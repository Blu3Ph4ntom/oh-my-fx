const std = @import("std");
const Allocator = std.mem.Allocator;

const model_catalog = @import("../core/gateway/model_catalog.zig");
const io_mod = @import("../core/shared/io.zig");
const secret = @import("../core/auth/secret.zig");
const gateway_client = @import("client.zig");
const opencode_go = @import("opencode_go.zig");

const max_catalog_models: usize = 256;
const max_model_id_bytes: usize = 1024;
const max_catalog_bytes: usize = 4 * 1024 * 1024;

pub const model_catalog_provider = model_catalog.Provider{
    .fetch_fn = fetchCatalogForProvider,
};

fn fetchCatalogForProvider(
    _: ?*anyopaque,
    alloc: Allocator,
    input: model_catalog.FetchInput,
) Allocator.Error!model_catalog.ProviderResult {
    if (input.access.credentialSource() != .opencode_go_subscription) {
        return .{ .failure = .{ .category = .authentication, .http_status = .unauthorized } };
    }
    const credential = input.access.authorizationCredential() orelse
        return .{ .failure = .{ .category = .authentication, .http_status = .unauthorized } };

    const request_url = opencode_go.resolveModelsUrl();
    if (!opencode_go.isGoChatUrl(request_url) and !gateway_client.isLoopbackHttpUrl(request_url)) {
        return .{ .failure = .{ .category = .runtime } };
    }

    var fallback_cancel = std.atomic.Value(bool).init(false);
    const cancel_flag = input.cancel_flag orelse &fallback_cancel;
    if (cancel_flag.load(.seq_cst)) {
        return .{ .failure = .{ .category = .cancellation } };
    }

    var client: std.http.Client = .{ .allocator = alloc, .io = io_mod.getIo() };
    defer client.deinit();
    const auth_header = std.fmt.allocPrint(alloc, "Bearer {s}", .{credential}) catch
        return error.OutOfMemory;
    defer secret.zeroAndFree(alloc, auth_header);
    const body_buffer = alloc.alloc(u8, max_catalog_bytes + 1) catch
        return error.OutOfMemory;
    defer secret.zeroAndFree(alloc, body_buffer);
    var response_writer = std.Io.Writer.fixed(body_buffer);
    const result = client.fetch(.{
        .location = .{ .url = request_url },
        .method = .GET,
        .headers = .{
            .authorization = .{ .override = auth_header },
            .accept_encoding = .omit,
            .user_agent = .{ .override = gateway_client.user_agent },
        },
        .extra_headers = &.{
            .{ .name = "accept", .value = "application/json" },
        },
        .response_writer = &response_writer,
        .redirect_behavior = .unhandled,
    }) catch {
        return .{ .failure = .{ .category = .transport, .retryable = true } };
    };
    if (cancel_flag.load(.seq_cst)) {
        return .{ .failure = .{ .category = .cancellation } };
    }
    if (result.status != .ok) {
        return .{ .failure = model_catalog.failureForHttpStatus(result.status) };
    }
    const catalog = parseCatalog(alloc, response_writer.buffered()) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .failure = .{ .category = .malformed_response, .http_status = .ok } };
    };
    return .{ .catalog = catalog };
}

/// Parses the OpenAI model list shape `{"data": [{"id": "..."}]}`.
/// Go's list includes models for several wire protocols; this provider keeps
/// only entries documented for its Chat Completions transport.
fn parseCatalog(
    alloc: Allocator,
    json_text: []const u8,
) !std.ArrayList(model_catalog.ModelCatalogEntry) {
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json_text, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidOpenCodeGoModelCatalog;
    const data_value = parsed.value.object.get("data") orelse
        return error.InvalidOpenCodeGoModelCatalog;
    if (data_value != .array or data_value.array.items.len > max_catalog_models) {
        return error.InvalidOpenCodeGoModelCatalog;
    }

    var catalog: std.ArrayList(model_catalog.ModelCatalogEntry) = .empty;
    errdefer model_catalog.freeModelCatalog(alloc, &catalog);
    for (data_value.array.items) |value| {
        if (value != .object) return error.InvalidOpenCodeGoModelCatalog;
        const id_value = value.object.get("id") orelse
            return error.InvalidOpenCodeGoModelCatalog;
        if (id_value != .string) return error.InvalidOpenCodeGoModelCatalog;
        try validateModelId(id_value.string);
        if (!opencode_go.supportsChatCompletionsModel(id_value.string)) continue;
        const id = try alloc.dupe(u8, id_value.string);
        errdefer alloc.free(id);
        const model_type = try alloc.dupe(u8, "language");
        errdefer alloc.free(model_type);
        try catalog.append(alloc, .{
            .id = id,
            .model_type = model_type,
            .has_tool_use = true,
            .has_implicit_caching = true,
        });
    }
    return catalog;
}

fn validateModelId(id: []const u8) !void {
    if (id.len == 0 or id.len > max_model_id_bytes) return error.InvalidOpenCodeGoModelCatalog;
    for (id) |byte| {
        if (byte <= 0x20 or byte == 0x7f) return error.InvalidOpenCodeGoModelCatalog;
    }
}

test "Go catalog parser keeps OpenAI list ids with safe defaults" {
    const alloc = std.testing.allocator;
    const json =
        \\{"data":[
        \\  {"id":"glm-5.2","object":"model"},
        \\  {"id":"kimi-k3","object":"model"}
        \\]}
    ;
    var catalog = try parseCatalog(alloc, json);
    defer model_catalog.freeModelCatalog(alloc, &catalog);

    try std.testing.expectEqual(@as(usize, 2), catalog.items.len);
    try std.testing.expectEqualStrings("glm-5.2", catalog.items[0].id);
    try std.testing.expectEqualStrings("kimi-k3", catalog.items[1].id);
    try std.testing.expect(catalog.items[0].has_tool_use);
    try std.testing.expect(!catalog.items[0].has_reasoning);
    try std.testing.expectEqual(@as(u32, 0), catalog.items[0].context_window);
}

test "Go catalog parser filters models without a Chat Completions route" {
    const alloc = std.testing.allocator;
    const json =
        \\{"data":[
        \\  {"id":"minimax-m3","object":"model"},
        \\  {"id":"glm-5.2","object":"model"},
        \\  {"id":"qwen3.7-max","object":"model"},
        \\  {"id":"omen-alpha","object":"model"}
        \\]}
    ;
    var catalog = try parseCatalog(alloc, json);
    defer model_catalog.freeModelCatalog(alloc, &catalog);

    try std.testing.expectEqual(@as(usize, 2), catalog.items.len);
    try std.testing.expectEqualStrings("glm-5.2", catalog.items[0].id);
    try std.testing.expectEqualStrings("omen-alpha", catalog.items[1].id);
}

test "Go catalog parser rejects malformed lists" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(
        error.InvalidOpenCodeGoModelCatalog,
        parseCatalog(alloc, "{}"),
    );
    try std.testing.expectError(
        error.InvalidOpenCodeGoModelCatalog,
        parseCatalog(alloc, "{\"data\":{}}"),
    );
}
