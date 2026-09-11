const std = @import("std");
const Allocator = std.mem.Allocator;

const stream_provider = @import("../core/agent/stream_provider.zig");
const model_provider = @import("../core/config/model_provider.zig");
const io_mod = @import("../core/shared/io.zig");
const types = @import("../core/shared/types.zig");
const openai = @import("openai.zig");
const profiles = @import("openai_compat_profiles.zig");

pub const base_url_env = "OMFX_OPENAI_COMPATIBLE_BASE_URL";
pub const legacy_base_url_env = "FX_OPENAI_COMPATIBLE_BASE_URL";
pub const e2e_chat_url_env = "FX_E2E_OPENAI_COMPATIBLE_CHAT_URL";
pub const e2e_models_url_env = "FX_E2E_OPENAI_COMPATIBLE_MODELS_URL";
const chat_suffix = "/chat/completions";
const models_suffix = "/models";
const max_error_body_bytes: usize = 64 * 1024;

pub const agent_stream_provider = stream_provider.Provider{
    .build_fn = buildRequest,
    .stream_fn = streamCompletion,
};

pub fn agentStreamProvider(provider: model_provider.ProviderId) stream_provider.Provider {
    const profile = profiles.forProvider(provider) orelse return agent_stream_provider;
    return .{
        .context = @constCast(profile),
        .build_fn = buildRequest,
        .stream_fn = streamCompletion,
    };
}

pub fn isLoopbackHttpUrl(url: []const u8) bool {
    const uri = std.Uri.parse(url) catch return false;
    if (!std.ascii.eqlIgnoreCase(uri.scheme, "http") or
        uri.user != null or
        uri.password != null or
        uri.query != null or
        uri.fragment != null or
        uri.port == null)
    {
        return false;
    }
    const host = uri.host orelse return false;
    return isLoopbackHost(host);
}

test "loopback validation accepts valid and rejects host confusion" {
    try std.testing.expect(isLoopbackHttpUrl("http://127.0.0.1:43123"));
    try std.testing.expect(isLoopbackHttpUrl("http://127.0.0.1:43123/v1/chat/completions"));
    try std.testing.expect(isLoopbackHttpUrl("http://localhost:43123"));
    try std.testing.expect(isLoopbackHttpUrl("http://[::1]:43123"));
    try std.testing.expect(!isLoopbackHttpUrl("https://127.0.0.1:43123"));
    try std.testing.expect(!isLoopbackHttpUrl("http://evil.com:43123"));
    try std.testing.expect(!isLoopbackHttpUrl("http://localhost.evil.com:43123"));
    try std.testing.expect(!isLoopbackHttpUrl("http://127.0.0.1.evil.com:43123"));
    try std.testing.expect(!isLoopbackHttpUrl("http://127.0.0.1:43123@evil.com"));
    try std.testing.expect(!isLoopbackHttpUrl("http://user@127.0.0.1:43123"));
    try std.testing.expect(!isLoopbackHttpUrl("http://user:pass@localhost:43123"));
    try std.testing.expect(!isLoopbackHttpUrl("ftp://127.0.0.1:43123"));
}

test "OpenAI-compatible endpoints allow HTTPS and loopback HTTP only" {
    try std.testing.expect(isAllowedUrl("https://api.example.test/v1"));
    try std.testing.expect(isAllowedUrl("http://127.0.0.1:43123/v1"));
    try std.testing.expect(isAllowedUrl("http://localhost:43123/v1"));
    try std.testing.expect(!isAllowedUrl("http://api.example.test/v1"));
    try std.testing.expect(!isAllowedUrl("https://user:pass@api.example.test/v1"));
    try std.testing.expect(!isAllowedUrl("https://api.example.test/v1?key=secret"));
    try std.testing.expect(!isAllowedUrl("https://api.example.test/v1#fragment"));
}

test "OpenAI-compatible endpoint builder appends the OpenAI paths" {
    const alloc = std.testing.allocator;
    const chat = try endpointFromBase(alloc, "https://api.example.test/v1", chat_suffix);
    defer alloc.free(chat);
    try std.testing.expectEqualStrings("https://api.example.test/v1/chat/completions", chat);

    const models = try endpointFromBase(alloc, "https://api.example.test/v1/", models_suffix);
    defer alloc.free(models);
    try std.testing.expectEqualStrings("https://api.example.test/v1/models", models);

    const existing = try endpointFromBase(alloc, "https://api.example.test/v1/chat/completions", chat_suffix);
    defer alloc.free(existing);
    try std.testing.expectEqualStrings("https://api.example.test/v1/chat/completions", existing);
}

test "OpenAI-compatible request forwards declared reasoning effort" {
    const request = stream_provider.BuildRequest{
        .model = "reasoning-model",
        .messages = &[_]types.ChatMessage{.{ .role = .user, .content = "hello" }},
        .serialized_tools = "[]",
        .tool_choice = .auto,
        .provider_options = .{ .reasoning = types.ReasoningEffort.literal("high") },
    };
    const body = try buildRequest(null, std.testing.allocator, request);
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoning_effort\":\"high\"") != null);
}

fn isLoopbackHost(host: anytype) bool {
    var host_buf: [std.Io.net.HostName.max_len]u8 = undefined;
    const host_str = host.toRaw(&host_buf) catch return false;
    return std.mem.eql(u8, host_str, "127.0.0.1") or
        std.ascii.eqlIgnoreCase(host_str, "localhost") or
        std.mem.eql(u8, host_str, "[::1]");
}

pub fn isAllowedUrl(url: []const u8) bool {
    const uri = std.Uri.parse(url) catch return false;
    if (uri.user != null or uri.password != null or uri.query != null or uri.fragment != null) return false;
    const host = uri.host orelse return false;
    if (std.ascii.eqlIgnoreCase(uri.scheme, "https")) return true;
    return std.ascii.eqlIgnoreCase(uri.scheme, "http") and isLoopbackHost(host);
}

fn endpointFromBase(alloc: Allocator, base_url: []const u8, suffix: []const u8) ![]u8 {
    if (!isAllowedUrl(base_url)) return error.InvalidEndpoint;
    var root = std.mem.trimEnd(u8, base_url, "/");
    if (std.mem.endsWith(u8, root, chat_suffix)) root = root[0 .. root.len - chat_suffix.len];
    if (std.mem.endsWith(u8, root, models_suffix)) root = root[0 .. root.len - models_suffix.len];
    if (std.mem.endsWith(u8, root, suffix)) return alloc.dupe(u8, root);
    return std.fmt.allocPrint(alloc, "{s}{s}", .{ root, suffix });
}

fn resolveConfiguredEndpoint(alloc: Allocator, suffix: []const u8, override_env: []const u8) ![]u8 {
    if (io_mod.getenv(override_env)) |override| {
        if (isLoopbackHttpUrl(override)) return alloc.dupe(u8, override);
    }
    const base_url = io_mod.getenvProduct(base_url_env, legacy_base_url_env) orelse
        return error.MissingOpenAiCompatibleBaseUrl;
    return endpointFromBase(alloc, base_url, suffix);
}

pub fn resolveChatUrl(alloc: Allocator) ![]u8 {
    return resolveConfiguredEndpoint(alloc, chat_suffix, e2e_chat_url_env);
}

pub fn resolveModelsUrl(alloc: Allocator) ![]u8 {
    return resolveConfiguredEndpoint(alloc, models_suffix, e2e_models_url_env);
}

pub fn resolveModelsUrlForProfile(alloc: Allocator, profile: profiles.Profile) ![]u8 {
    return endpointFromBase(alloc, profile.base_url, models_suffix);
}

pub fn resolveChatUrlForProfile(alloc: Allocator, profile: profiles.Profile) ![]u8 {
    return endpointFromBase(alloc, profile.base_url, chat_suffix);
}

pub fn buildRequest(
    _: ?*anyopaque,
    alloc: Allocator,
    request: stream_provider.BuildRequest,
) ![]u8 {
    if (request.budget) |budget| {
        if (budget.cancel_flag) |flag| if (flag.load(.seq_cst)) return error.Cancelled;
    }
    return openai.buildRequestBodyWithToolChoiceAndOptions(
        alloc,
        request.model,
        request.messages,
        request.serialized_tools,
        request.max_output_tokens,
        true,
        request.tool_choice,
        request.provider_options,
    );
}

pub fn streamCompletion(
    context: ?*anyopaque,
    alloc: Allocator,
    request: stream_provider.Request,
) !stream_provider.Result {
    const profile: ?*const profiles.Profile = if (context) |raw|
        @ptrCast(@alignCast(raw))
    else
        null;
    if (profile) |selected| {
        if (request.credential_source != selected.credential_source)
            return error.CredentialSourceMismatch;
    }
    const url = if (profile) |selected|
        resolveChatUrlForProfile(alloc, selected.*)
    else
        resolveChatUrl(alloc) catch |err| switch (err) {
            error.MissingOpenAiCompatibleBaseUrl => if (isLoopbackHttpUrl(request.chat_url))
                try alloc.dupe(u8, request.chat_url)
            else
                return err,
            else => return err,
        };
    defer alloc.free(url);
    if (!isAllowedUrl(url)) return error.InvalidEndpoint;

    var client: std.http.Client = .{ .allocator = alloc, .io = io_mod.getIo() };
    defer client.deinit();

    const uri = try std.Uri.parse(url);

    var auth_header: ?[]u8 = null;
    defer if (auth_header) |v| alloc.free(v);
    var extra_headers_buf: [1]std.http.Header = undefined;
    var extra_len: usize = 0;
    if (request.api_key.len > 0) {
        auth_header = try std.fmt.allocPrint(alloc, "Bearer {s}", .{request.api_key});
        extra_headers_buf[extra_len] = .{ .name = "Authorization", .value = auth_header.? };
        extra_len += 1;
    }

    var req = try client.request(.POST, uri, .{
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .accept_encoding = .omit,
        },
        .extra_headers = extra_headers_buf[0..extra_len],
        .redirect_behavior = .unhandled,
    });
    defer req.deinit();

    if (request.cancel_flag.load(.seq_cst)) return error.Cancelled;

    req.transfer_encoding = .{ .content_length = request.payload.len };
    var send_buf: [8192]u8 = undefined;
    var body_writer = try req.sendBodyUnflushed(&send_buf);
    try body_writer.writer.writeAll(request.payload);
    try body_writer.end();
    try req.connection.?.flush();

    var response = try req.receiveHead(&.{});
    if (request.cancel_flag.load(.seq_cst)) return error.Cancelled;

    if (response.head.status != .ok) {
        var buf: [4096]u8 = undefined;
        const reader = response.reader(&buf);
        const body = try reader.allocRemaining(alloc, .limited(max_error_body_bytes));
        defer alloc.free(body);
        var err_body: ?[]u8 = null;
        if (body.len > 0) err_body = try alloc.dupe(u8, body);
        return .{
            .status = response.head.status,
            .err_body = err_body,
            .ownership = .owned,
        };
    }

    var parser = openai.StreamParser.init(alloc);
    defer parser.deinit();

    var content_parts: std.ArrayList(u8) = .empty;
    defer content_parts.deinit(alloc);

    var finish_reason: ?types.ProviderFinishReason = null;

    var sse_buffer: [32 * 1024]u8 = undefined;
    var reader = response.reader(&sse_buffer);

    while (true) {
        if (request.cancel_flag.load(.seq_cst)) return error.Cancelled;
        const line = (reader.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => return error.StreamTooLong,
            else => return err,
        }) orelse break;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (!std.mem.startsWith(u8, trimmed, "data:")) continue;
        const data = std.mem.trimStart(u8, trimmed["data:".len..], " ");

        const chunk = try parser.parseDataLine(data);
        if (chunk == null) continue;
        switch (chunk.?) {
            .done => break,
            .text_delta => |text| {
                defer alloc.free(text);
                request.on_content_chunk(request.callback_ctx, text);
                try content_parts.appendSlice(alloc, text);
            },
            .reasoning_delta => |reasoning| {
                defer alloc.free(reasoning);
                if (request.on_reasoning_chunk) |callback| callback(request.callback_ctx, reasoning);
            },
            .tool_call_delta => |tc| {
                defer {
                    if (tc.id) |v| alloc.free(v);
                    if (tc.function_name) |v| alloc.free(v);
                    if (tc.arguments_fragment) |v| alloc.free(v);
                }
                if (tc.id != null and tc.function_name != null) {
                    if (request.on_tool_start) |cb| cb(request.callback_ctx, tc.id.?, tc.function_name.?, null);
                }
            },
            .finish_reason => |fr| {
                defer alloc.free(fr);
                finish_reason = openai.parse_provider_finish_reason(fr);
            },
            .usage => {},
            .err => |e| {
                defer alloc.free(e);
                return .{ .status = .internal_server_error, .err_body = try alloc.dupe(u8, e), .ownership = .owned };
            },
        }
    }

    var final_calls: std.ArrayList(types.ToolCall) = .empty;
    defer final_calls.deinit(alloc);
    var it = parser.tool_arg_buffers.iterator();
    while (it.next()) |entry| {
        const idx = entry.key_ptr.*;
        const args = entry.value_ptr.items;
        const id = parser.tool_ids.get(idx) orelse continue;
        const name = parser.tool_names.get(idx) orelse continue;
        try final_calls.append(alloc, .{
            .id = try alloc.dupe(u8, id),
            .name = try alloc.dupe(u8, name),
            .arguments_json = try alloc.dupe(u8, args),
        });
    }

    const content_slice: ?[]const u8 = if (content_parts.items.len > 0)
        try alloc.dupe(u8, content_parts.items)
    else
        null;

    const calls_slice = if (final_calls.items.len > 0)
        try alloc.dupe(types.ToolCall, final_calls.items)
    else
        &[_]types.ToolCall{};

    return .{
        .status = .ok,
        .completion = .{
            .content = content_slice,
            .tool_calls = calls_slice,
            .finish_reason = finish_reason orelse if (final_calls.items.len > 0) .tool_calls else .stop,
        },
        .ownership = .owned,
    };
}

test "e2e openai_compatible tool loop with fixture" {
    try std.testing.expect(isLoopbackHttpUrl("http://127.0.0.1:1234/v1/chat/completions"));
    try std.testing.expect(isLoopbackHttpUrl("http://localhost:1234/v1/chat/completions"));
    try std.testing.expect(isLoopbackHttpUrl("http://[::1]:1234/v1/chat/completions"));
    try std.testing.expect(!isLoopbackHttpUrl("https://127.0.0.1:1234/v1/chat/completions"));
    try std.testing.expect(!isLoopbackHttpUrl("http://evil.com:1234/v1/chat/completions"));
    try std.testing.expect(!isLoopbackHttpUrl("http://localhost.evil.com:1234/v1/chat/completions"));
    try std.testing.expect(!isLoopbackHttpUrl("http://127.0.0.1.evil.com:1234/v1/chat/completions"));
    try std.testing.expect(!isLoopbackHttpUrl("http://user@127.0.0.1:1234/v1/chat/completions"));
    try std.testing.expect(!isLoopbackHttpUrl("http://user:pass@localhost:1234/v1/chat/completions"));
    try std.testing.expect(!isLoopbackHttpUrl("ftp://127.0.0.1:1234/v1/chat/completions"));
}
