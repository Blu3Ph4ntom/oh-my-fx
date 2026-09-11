const std = @import("std");
const Allocator = std.mem.Allocator;

const model_catalog = @import("../core/gateway/model_catalog.zig");
const io_mod = @import("../core/shared/io.zig");
const secret = @import("../core/auth/secret.zig");
const gateway_client = @import("client.zig");
const opencode_go = @import("opencode_go.zig");
const types = @import("../core/shared/types.zig");

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
/// The endpoint is the source of truth: Go advertises models backed by
/// Chat Completions, Responses, and Anthropic Messages, so listing must not
/// discard models merely because the transport route is different.
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
        const id = try alloc.dupe(u8, id_value.string);
        errdefer alloc.free(id);
        const model_type = try alloc.dupe(u8, "language");
        errdefer alloc.free(model_type);
        var reasoning_efforts: std.ArrayList(types.ReasoningEffort) = .empty;
        errdefer reasoning_efforts.deinit(alloc);
        try appendKnownReasoningEfforts(alloc, &reasoning_efforts, id_value.string);
        try catalog.append(alloc, .{
            .id = id,
            .model_type = model_type,
            .has_tool_use = true,
            .has_reasoning = reasoning_efforts.items.len > 0,
            .reasoning_efforts = reasoning_efforts,
            .has_implicit_caching = true,
        });
    }
    return catalog;
}

fn appendKnownReasoningEfforts(
    alloc: Allocator,
    out: *std.ArrayList(types.ReasoningEffort),
    model_id: []const u8,
) !void {
    const efforts = if (std.mem.eql(u8, model_id, "glm-5.3-flash") or
        std.mem.eql(u8, model_id, "glm-5.3"))
        &[_]types.ReasoningEffort{
            types.ReasoningEffort.literal("low"),
            types.ReasoningEffort.literal("high"),
            types.ReasoningEffort.literal("max"),
        }
    else if (std.mem.eql(u8, model_id, "glm-5.2") or
        std.mem.eql(u8, model_id, "deepseek-v4-pro"))
        &[_]types.ReasoningEffort{
            types.ReasoningEffort.literal("high"),
            types.ReasoningEffort.literal("max"),
        }
    else if (std.mem.eql(u8, model_id, "kimi-k3"))
        &[_]types.ReasoningEffort{types.ReasoningEffort.literal("max")}
    else if (std.mem.eql(u8, model_id, "gpt-5.6-luna"))
        &[_]types.ReasoningEffort{
            types.ReasoningEffort.literal("none"),
            types.ReasoningEffort.literal("low"),
            types.ReasoningEffort.literal("medium"),
            types.ReasoningEffort.literal("high"),
            types.ReasoningEffort.literal("xhigh"),
            types.ReasoningEffort.literal("max"),
        }
    else if (std.mem.eql(u8, model_id, "grok-4.6"))
        &[_]types.ReasoningEffort{
            types.ReasoningEffort.literal("low"),
            types.ReasoningEffort.literal("medium"),
            types.ReasoningEffort.literal("high"),
            types.ReasoningEffort.literal("xhigh"),
        }
    else if (std.mem.eql(u8, model_id, "muse-spark-1.3-contributor") or
        std.mem.eql(u8, model_id, "muse-spark-1.2-contributor"))
        &[_]types.ReasoningEffort{
            types.ReasoningEffort.literal("minimal"),
            types.ReasoningEffort.literal("low"),
            types.ReasoningEffort.literal("medium"),
            types.ReasoningEffort.literal("high"),
            types.ReasoningEffort.literal("xhigh"),
        }
    else if (std.mem.eql(u8, model_id, "deepseek-v4.1-flash") or
        std.mem.eql(u8, model_id, "deepseek-v4-flash") or
        std.mem.eql(u8, model_id, "deepseek-v4-flash-vision-exp"))
        &[_]types.ReasoningEffort{
            types.ReasoningEffort.literal("low"),
            types.ReasoningEffort.literal("high"),
            types.ReasoningEffort.literal("max"),
        }
    else if (std.mem.eql(u8, model_id, "hy4-preview"))
        &[_]types.ReasoningEffort{
            types.ReasoningEffort.literal("none"),
            types.ReasoningEffort.literal("high"),
        }
    else if (std.mem.eql(u8, model_id, "hy3"))
        &[_]types.ReasoningEffort{
            types.ReasoningEffort.literal("none"),
            types.ReasoningEffort.literal("low"),
            types.ReasoningEffort.literal("high"),
        }
    else if (std.mem.eql(u8, model_id, "omen-alpha"))
        &[_]types.ReasoningEffort{
            types.ReasoningEffort.literal("low"),
            types.ReasoningEffort.literal("high"),
        }
    else if (std.mem.eql(u8, model_id, "qwen3.8-max") or
        std.mem.eql(u8, model_id, "qwen3.8-flash"))
        &[_]types.ReasoningEffort{
            types.ReasoningEffort.literal("low"),
            types.ReasoningEffort.literal("medium"),
            types.ReasoningEffort.literal("xhigh"),
        }
    else if (std.mem.eql(u8, model_id, "minimax-m3") or
        std.mem.eql(u8, model_id, "minimax-m2.7") or
        std.mem.eql(u8, model_id, "minimax-m2.5") or
        std.mem.eql(u8, model_id, "longcat-2.0") or
        std.mem.eql(u8, model_id, "qwen3.7-max") or
        std.mem.eql(u8, model_id, "qwen3.7-plus") or
        std.mem.eql(u8, model_id, "qwen3.6-plus"))
        &[_]types.ReasoningEffort{types.ReasoningEffort.literal("on")}
    else
        &[_]types.ReasoningEffort{};
    try out.appendSlice(alloc, efforts);
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
    try std.testing.expect(catalog.items[0].has_reasoning);
    try std.testing.expectEqual(@as(usize, 2), catalog.items[0].reasoning_efforts.items.len);
    try std.testing.expectEqualStrings("high", catalog.items[0].reasoning_efforts.items[0].label());
    try std.testing.expectEqual(@as(u32, 0), catalog.items[0].context_window);
}

test "Go catalog parser enriches live ids with route capabilities" {
    const alloc = std.testing.allocator;
    const json =
        \\{"data":[
        \\  {"id":"gpt-5.6-luna"},
        \\  {"id":"qwen3.8-max"},
        \\  {"id":"deepseek-v4.1-flash"},
        \\  {"id":"minimax-m3"}
        \\]}
    ;
    var catalog = try parseCatalog(alloc, json);
    defer model_catalog.freeModelCatalog(alloc, &catalog);

    try std.testing.expect(catalog.items[0].has_reasoning);
    try std.testing.expectEqual(@as(usize, 6), catalog.items[0].reasoning_efforts.items.len);
    try std.testing.expectEqual(@as(usize, 3), catalog.items[1].reasoning_efforts.items.len);
    try std.testing.expectEqualStrings("low", catalog.items[2].reasoning_efforts.items[0].label());
    try std.testing.expectEqualStrings("on", catalog.items[3].reasoning_efforts.items[0].label());
}

test "Go catalog parser keeps models from every advertised route" {
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

    try std.testing.expectEqual(@as(usize, 4), catalog.items.len);
    try std.testing.expectEqualStrings("minimax-m3", catalog.items[0].id);
    try std.testing.expectEqualStrings("glm-5.2", catalog.items[1].id);
    try std.testing.expectEqualStrings("qwen3.7-max", catalog.items[2].id);
    try std.testing.expectEqualStrings("omen-alpha", catalog.items[3].id);
}

test "Go catalog parser keeps every model advertised by the live catalog" {
    const alloc = std.testing.allocator;
    const json =
        \\{"data":[
        \\  {"id":"minimax-m3"},
        \\  {"id":"qwen3.8-max"},
        \\  {"id":"gpt-5.6-luna"},
        \\  {"id":"glm-5.3"}
        \\]}
    ;
    var catalog = try parseCatalog(alloc, json);
    defer model_catalog.freeModelCatalog(alloc, &catalog);

    try std.testing.expectEqual(@as(usize, 4), catalog.items.len);
    try std.testing.expectEqualStrings("minimax-m3", catalog.items[0].id);
    try std.testing.expectEqualStrings("qwen3.8-max", catalog.items[1].id);
    try std.testing.expectEqualStrings("gpt-5.6-luna", catalog.items[2].id);
    try std.testing.expectEqualStrings("glm-5.3", catalog.items[3].id);
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
