const std = @import("std");
const Allocator = std.mem.Allocator;

const model_catalog = @import("../core/gateway/model_catalog.zig");
const model_provider = @import("../core/config/model_provider.zig");
const io_mod = @import("../core/shared/io.zig");
const secret = @import("../core/auth/secret.zig");
const gateway_client = @import("client.zig");
const openai_compat = @import("openai_compat.zig");
const profiles = @import("openai_compat_profiles.zig");

const max_catalog_models: usize = 512;
const max_model_id_bytes: usize = 1024;
const max_catalog_bytes: usize = 4 * 1024 * 1024;

pub const model_catalog_provider = model_catalog.Provider{
    .fetch_fn = fetchCatalog,
};

pub fn modelCatalogProvider(provider: model_provider.ProviderId) model_catalog.Provider {
    const profile = profiles.forProvider(provider) orelse return model_catalog_provider;
    return .{
        .context = @constCast(profile),
        .fetch_fn = fetchCatalog,
    };
}

fn fetchCatalog(
    context: ?*anyopaque,
    alloc: Allocator,
    input: model_catalog.FetchInput,
) Allocator.Error!model_catalog.ProviderResult {
    const profile: ?*const profiles.Profile = if (context) |raw|
        @ptrCast(@alignCast(raw))
    else
        null;
    const expected_source = if (profile) |selected| selected.credential_source else .custom_provider;
    if (input.access.credentialSource() != expected_source) {
        return .{ .failure = .{ .category = .authentication, .http_status = .unauthorized } };
    }
    const credential = input.access.authorizationCredential() orelse
        return .{ .failure = .{ .category = .authentication, .http_status = .unauthorized } };

    const request_url = if (profile) |selected|
        openai_compat.resolveModelsUrlForProfile(alloc, selected.*) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return .{ .failure = .{ .category = .runtime } },
        }
    else
        openai_compat.resolveModelsUrl(alloc) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return .{ .failure = .{ .category = .runtime } },
        };
    defer alloc.free(request_url);

    var fallback_cancel = std.atomic.Value(bool).init(false);
    const cancel_flag = input.cancel_flag orelse &fallback_cancel;
    if (cancel_flag.load(.seq_cst)) return .{ .failure = .{ .category = .cancellation } };

    var client: std.http.Client = .{ .allocator = alloc, .io = io_mod.getIo() };
    defer client.deinit();
    const bearer = std.fmt.allocPrint(alloc, "Bearer {s}", .{credential}) catch return error.OutOfMemory;
    defer secret.zeroAndFree(alloc, bearer);

    const body_buffer = alloc.alloc(u8, max_catalog_bytes + 1) catch return error.OutOfMemory;
    defer secret.zeroAndFree(alloc, body_buffer);
    var response_writer = std.Io.Writer.fixed(body_buffer);
    const result = client.fetch(.{
        .location = .{ .url = request_url },
        .method = .GET,
        .headers = .{
            .authorization = .{ .override = bearer },
            .accept_encoding = .omit,
            .user_agent = .{ .override = gateway_client.user_agent },
        },
        .extra_headers = &.{.{ .name = "accept", .value = "application/json" }},
        .response_writer = &response_writer,
        .redirect_behavior = .unhandled,
    }) catch {
        return .{ .failure = .{ .category = .transport, .retryable = true } };
    };
    if (cancel_flag.load(.seq_cst)) return .{ .failure = .{ .category = .cancellation } };
    if (result.status != .ok) return .{ .failure = model_catalog.failureForHttpStatus(result.status) };

    const catalog = parseCatalog(alloc, response_writer.buffered()) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .failure = .{ .category = .malformed_response, .http_status = .ok } };
    };
    return .{ .catalog = catalog };
}

fn parseCatalog(alloc: Allocator, json_text: []const u8) !std.ArrayList(model_catalog.ModelCatalogEntry) {
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json_text, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidOpenAiCompatibleModelCatalog;
    const data = parsed.value.object.get("data") orelse return error.InvalidOpenAiCompatibleModelCatalog;
    if (data != .array or data.array.items.len > max_catalog_models) return error.InvalidOpenAiCompatibleModelCatalog;

    var catalog: std.ArrayList(model_catalog.ModelCatalogEntry) = .empty;
    errdefer model_catalog.freeModelCatalog(alloc, &catalog);
    for (data.array.items) |value| {
        if (value != .object) return error.InvalidOpenAiCompatibleModelCatalog;
        const id_value = value.object.get("id") orelse return error.InvalidOpenAiCompatibleModelCatalog;
        if (id_value != .string) return error.InvalidOpenAiCompatibleModelCatalog;
        try validateModelId(id_value.string);
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
    if (id.len == 0 or id.len > max_model_id_bytes) return error.InvalidOpenAiCompatibleModelCatalog;
    for (id) |byte| if (byte <= 0x20 or byte == 0x7f) return error.InvalidOpenAiCompatibleModelCatalog;
}

test "OpenAI-compatible catalog parser keeps live OpenAI list ids" {
    const alloc = std.testing.allocator;
    var catalog = try parseCatalog(alloc, "{\"data\":[{\"id\":\"local-model\"},{\"id\":\"provider/model\"}]}");
    defer model_catalog.freeModelCatalog(alloc, &catalog);
    try std.testing.expectEqual(@as(usize, 2), catalog.items.len);
    try std.testing.expectEqualStrings("local-model", catalog.items[0].id);
    try std.testing.expect(catalog.items[0].has_tool_use);
    try std.testing.expectEqualStrings("provider/model", catalog.items[1].id);
}

test "OpenAI-compatible catalog parser rejects malformed lists" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(error.InvalidOpenAiCompatibleModelCatalog, parseCatalog(alloc, "{}"));
    try std.testing.expectError(error.InvalidOpenAiCompatibleModelCatalog, parseCatalog(alloc, "{\"data\":{}}"));
    try std.testing.expectError(error.InvalidOpenAiCompatibleModelCatalog, parseCatalog(alloc, "{\"data\":[{\"id\":\"\"}]}"));
}
