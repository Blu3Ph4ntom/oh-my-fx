const std = @import("std");
const Allocator = std.mem.Allocator;

const stream_provider = @import("../core/agent/stream_provider.zig");
const io_mod = @import("../core/shared/io.zig");
const types = @import("../core/shared/types.zig");
const gateway_client = @import("client.zig");
const openai = @import("openai.zig");

/// OpenCode Go subscription provider (first parity with Codex subscription).
/// OpenAI-compatible chat-completions transport against the fixed Go base URL.
/// Auth is `Bearer <OPENCODE_GO_API_KEY>`; the credential source gate mirrors
/// the Codex subscription check.
pub const default_base_url = "https://opencode.ai/zen/go/v1";
pub const default_chat_url = "https://opencode.ai/zen/go/v1/chat/completions";
pub const default_models_url = "https://opencode.ai/zen/go/v1/models";
pub const e2e_chat_url_env = "FX_E2E_OPENCODE_GO_CHAT_URL";
pub const e2e_models_url_env = "FX_E2E_OPENCODE_GO_MODELS_URL";

// OpenCode Go exposes different models through Chat Completions, Responses,
// and Anthropic Messages. Keep the route map explicit: the live catalog is
// intentionally broader than any single wire protocol.
pub const GoRoute = enum {
    chat_completions,
    responses,
    messages,
};
const chat_completions_model_ids = [_][]const u8{
    "glm-5.3-flash",
    "glm-5.3",
    "glm-5.2",
    "glm-5.1",
    "kimi-k3",
    "kimi-k2.7-code",
    "kimi-k2.6",
    "longcat-2.0",
    "deepseek-v4-pro",
    "deepseek-v4-flash",
    "deepseek-v4-flash-vision-exp",
    "mimo-v2.5",
    "mimo-v2.5-pro",
    "hy4-preview",
    "hy3",
    "omen-alpha",
};

const responses_model_ids = [_][]const u8{
    "grok-4.6",
    "gpt-5.6-luna",
    "muse-spark-1.3-contributor",
    "muse-spark-1.2-contributor",
};

const messages_model_ids = [_][]const u8{
    "minimax-m3",
    "minimax-m2.7",
    "minimax-m2.5",
    "qwen3.8-max",
    "qwen3.8-flash",
    "qwen3.7-max",
    "qwen3.7-plus",
    "qwen3.6-plus",
};

const max_error_body_bytes: usize = 64 * 1024;

pub const agent_stream_provider = stream_provider.Provider{
    .build_fn = buildRequest,
    .stream_fn = streamCompletion,
};

/// Structural endpoint check: fixed Go host over https, or a loopback http
/// override for E2E fixtures. Rejects userinfo and non-Go hosts.
pub fn isGoChatUrl(url: []const u8) bool {
    if (gateway_client.isLoopbackHttpUrl(url)) return true;
    const uri = std.Uri.parse(url) catch return false;
    if (!std.mem.eql(u8, uri.scheme, "https")) return false;
    if (uri.user != null) return false;
    if (uri.password != null) return false;
    const host = uri.host orelse return false;
    const host_str = switch (host) {
        .raw => |raw| raw,
        .percent_encoded => |raw| raw,
    };
    if (!std.mem.eql(u8, host_str, "opencode.ai")) return false;
    const path = switch (uri.path) {
        .raw => |raw| raw,
        .percent_encoded => |raw| raw,
    };
    return std.mem.startsWith(u8, path, "/zen/go/v1/");
}

pub fn resolveChatUrl() []const u8 {
    if (io_mod.getenv(e2e_chat_url_env)) |override| {
        if (gateway_client.isLoopbackHttpUrl(override)) return override;
    }
    return default_chat_url;
}

pub fn resolveModelsUrl() []const u8 {
    if (io_mod.getenv(e2e_models_url_env)) |override| {
        if (gateway_client.isLoopbackHttpUrl(override)) return override;
    }
    return default_models_url;
}

pub fn resolveRouteUrl(route: GoRoute) []const u8 {
    if (io_mod.getenv(e2e_chat_url_env)) |override| {
        if (gateway_client.isLoopbackHttpUrl(override)) {
            // E2E servers commonly multiplex all route fixtures on one URL.
            return override;
        }
    }
    return switch (route) {
        .chat_completions => default_chat_url,
        .responses => default_base_url ++ "/responses",
        .messages => default_base_url ++ "/messages",
    };
}

pub fn supportsChatCompletionsModel(model: []const u8) bool {
    for (chat_completions_model_ids) |supported| {
        if (std.mem.eql(u8, model, supported)) return true;
    }
    return false;
}

pub fn routeForModel(model: []const u8) ?GoRoute {
    if (supportsChatCompletionsModel(model)) return .chat_completions;
    for (responses_model_ids) |supported| {
        if (std.mem.eql(u8, model, supported)) return .responses;
    }
    for (messages_model_ids) |supported| {
        if (std.mem.eql(u8, model, supported)) return .messages;
    }
    return null;
}

pub fn buildRequest(
    _: ?*anyopaque,
    alloc: Allocator,
    request: stream_provider.BuildRequest,
) ![]u8 {
    if (request.budget) |budget| {
        if (budget.cancel_flag) |flag| if (flag.load(.seq_cst)) return error.Cancelled;
    }
    return switch (routeForModel(request.model) orelse .chat_completions) {
        .chat_completions => openai.buildRequestBodyWithToolChoice(
            alloc,
            request.model,
            request.messages,
            request.serialized_tools,
            request.max_output_tokens,
            true,
            request.tool_choice,
        ),
        .responses => buildResponsesBody(alloc, request),
        .messages => buildMessagesBody(alloc, request),
    };
}

fn writeJsonString(w: *std.Io.Writer, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, w);
}

fn buildResponsesBody(alloc: Allocator, request: stream_provider.BuildRequest) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    const w = &out.writer;
    try w.writeAll("{\"model\":");
    try writeJsonString(w, request.model);
    try w.writeAll(",\"input\":[");
    var first = true;
    for (request.messages) |msg| {
        if (msg.role == .system) continue;
        if (!first) try w.writeByte(',');
        first = false;
        if (msg.role == .tool) {
            try w.writeAll("{\"type\":\"function_call_output\",\"call_id\":");
            try writeJsonString(w, msg.tool_call_id orelse "unknown");
            try w.writeAll(",\"output\":");
            try writeJsonString(w, msg.content orelse "");
            try w.writeByte('}');
        } else {
            try w.writeAll("{\"type\":\"message\",\"role\":");
            try writeJsonString(w, @tagName(msg.role));
            try w.writeAll(",\"content\":");
            try writeJsonString(w, msg.content orelse "");
            try w.writeByte('}');
        }
    }
    try w.writeAll("] ,\"stream\":true,\"store\":false");
    if (request.max_output_tokens) |limit| {
        try w.print(",\"max_output_tokens\":{d}", .{limit});
    }
    for (request.messages) |msg| {
        if (msg.role == .system) {
            if (msg.content) |content| {
                try w.writeAll(",\"instructions\":");
                try writeJsonString(w, content);
                break;
            }
        }
    }
    try w.writeByte('}');
    return out.toOwnedSlice();
}

fn buildMessagesBody(alloc: Allocator, request: stream_provider.BuildRequest) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    const w = &out.writer;
    try w.writeAll("{\"model\":");
    try writeJsonString(w, request.model);
    try w.writeAll(",\"messages\":[");
    var first = true;
    for (request.messages) |msg| {
        if (msg.role == .system) continue;
        if (!first) try w.writeByte(',');
        first = false;
        try w.writeAll("{\"role\":");
        try writeJsonString(w, if (msg.role == .tool) "user" else @tagName(msg.role));
        try w.writeAll(",\"content\":");
        try writeJsonString(w, msg.content orelse "");
        try w.writeByte('}');
    }
    try w.writeAll("] ,\"stream\":true");
    if (request.max_output_tokens) |limit| try w.print(",\"max_tokens\":{d}", .{limit});
    for (request.messages) |msg| {
        if (msg.role == .system) if (msg.content) |content| {
            try w.writeAll(",\"system\":");
            try writeJsonString(w, content);
            break;
        };
    }
    try w.writeByte('}');
    return out.toOwnedSlice();
}

pub fn streamCompletion(
    _: ?*anyopaque,
    alloc: Allocator,
    request: stream_provider.Request,
) !stream_provider.Result {
    if (request.cancel_flag.load(.seq_cst)) return error.Cancelled;
    if (request.credential_source != .opencode_go_subscription) {
        return error.OpenCodeGoSubscriptionCredentialRequired;
    }
    const route = routeForModel(request.model) orelse return error.OpenCodeGoModelRequiresDifferentEndpoint;
    const url = resolveRouteUrl(route);
    if (!isGoChatUrl(url)) return error.InvalidEndpoint;

    var client: std.http.Client = .{ .allocator = alloc, .io = io_mod.getIo() };
    defer client.deinit();

    const uri = try std.Uri.parse(url);

    var auth_header: ?[]u8 = null;
    defer if (auth_header) |v| alloc.free(v);
    var generated_session_id: [64]u8 = undefined;
    const session_id = if (request.session_id) |value| blk: {
        if (value.len > 0) break :blk value;
        break :blk try std.fmt.bufPrint(
            &generated_session_id,
            "omfx-{d}-{d}",
            .{ request.trace_ctx.turn_id, request.trace_ctx.step_id },
        );
    } else try std.fmt.bufPrint(
        &generated_session_id,
        "omfx-{d}-{d}",
        .{ request.trace_ctx.turn_id, request.trace_ctx.step_id },
    );
    var extra_headers_buf: [3]std.http.Header = undefined;
    var extra_len: usize = 0;
    if (request.api_key.len > 0 and route != .messages) {
        auth_header = try std.fmt.allocPrint(alloc, "Bearer {s}", .{request.api_key});
        extra_headers_buf[extra_len] = .{ .name = "Authorization", .value = auth_header.? };
        extra_len += 1;
    }
    if (request.api_key.len > 0 and route == .messages) {
        extra_headers_buf[extra_len] = .{ .name = "x-api-key", .value = request.api_key };
        extra_len += 1;
    }
    extra_headers_buf[extra_len] = .{ .name = "Accept", .value = "text/event-stream" };
    extra_len += 1;
    extra_headers_buf[extra_len] = .{ .name = "x-opencode-session", .value = session_id };
    extra_len += 1;

    var req = try client.request(.POST, uri, .{
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .accept_encoding = .omit,
            .user_agent = .{ .override = gateway_client.user_agent },
        },
        .extra_headers = extra_headers_buf[0..extra_len],
        .keep_alive = false,
        .redirect_behavior = .unhandled,
    });
    defer req.deinit();
    if (request.cancel_flag.load(.seq_cst)) return error.Cancelled;

    req.transfer_encoding = .{ .content_length = request.payload.len };
    var send_buf: [8192]u8 = undefined;
    request.delivery.markPossiblySent();
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

        if (route != .chat_completions) {
            const parsed = std.json.parseFromSlice(std.json.Value, alloc, data, .{}) catch continue;
            defer parsed.deinit();
            if (parsed.value != .object) continue;
            const object = parsed.value.object;
            const event_type = object.get("type") orelse continue;
            if (event_type != .string) continue;
            if (route == .responses) {
                if (std.mem.eql(u8, event_type.string, "response.output_text.delta")) {
                    if (object.get("delta")) |delta| if (delta == .string) {
                        const text = try alloc.dupe(u8, delta.string);
                        defer alloc.free(text);
                        request.on_content_chunk(request.callback_ctx, text);
                        try content_parts.appendSlice(alloc, text);
                    };
                } else if (std.mem.eql(u8, event_type.string, "response.reasoning_text.delta") or
                    std.mem.eql(u8, event_type.string, "response.reasoning_summary_text.delta"))
                {
                    if (object.get("delta")) |delta| if (delta == .string) {
                        if (request.on_reasoning_chunk) |callback| callback(request.callback_ctx, delta.string);
                    };
                } else if (std.mem.eql(u8, event_type.string, "response.incomplete")) {
                    finish_reason = .length;
                }
            } else if (std.mem.eql(u8, event_type.string, "content_block_delta")) {
                if (object.get("delta")) |delta| if (delta == .object) {
                    if (delta.object.get("type")) |kind| if (kind == .string and std.mem.eql(u8, kind.string, "text_delta")) {
                        if (delta.object.get("text")) |text| if (text == .string) {
                            const copied = try alloc.dupe(u8, text.string);
                            defer alloc.free(copied);
                            request.on_content_chunk(request.callback_ctx, copied);
                            try content_parts.appendSlice(alloc, copied);
                        };
                    };
                };
            } else if (std.mem.eql(u8, event_type.string, "message_delta")) {
                if (object.get("delta")) |delta| if (delta == .object) {
                    if (delta.object.get("stop_reason")) |reason| if (reason == .string) {
                        finish_reason = if (std.mem.eql(u8, reason.string, "max_tokens")) .length else .stop;
                    };
                };
            }
            continue;
        }

        const chunk = try parser.parseDataLine(data);
        if (chunk == null) continue;
        switch (chunk.?) {
            .done => break,
            .text_delta => |text| {
                defer alloc.free(text);
                request.on_content_chunk(request.callback_ctx, text);
                try content_parts.appendSlice(alloc, text);
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

test "go endpoint accepts fixed host and loopback, rejects impostors" {
    try std.testing.expect(isGoChatUrl("https://opencode.ai/zen/go/v1/chat/completions"));
    try std.testing.expect(isGoChatUrl("http://127.0.0.1:43123/v1/chat/completions"));
    try std.testing.expect(!isGoChatUrl("http://evil.com:43123"));
    try std.testing.expect(!isGoChatUrl("https://opencode.ai.evil.com/zen/go/v1/chat/completions"));
    try std.testing.expect(!isGoChatUrl("https://evil-opencode.ai/zen/go/v1/chat/completions"));
    try std.testing.expect(!isGoChatUrl("http://opencode.ai/zen/go/v1/chat/completions"));
    try std.testing.expect(!isGoChatUrl("https://opencode.ai/zen/v1/chat/completions"));
    try std.testing.expect(!isGoChatUrl("https://user@opencode.ai/zen/go/v1/chat/completions"));
}

test "Go route guard distinguishes Chat Completions models" {
    try std.testing.expect(supportsChatCompletionsModel("glm-5.2"));
    try std.testing.expect(supportsChatCompletionsModel("omen-alpha"));
    try std.testing.expect(!supportsChatCompletionsModel("minimax-m3"));
    try std.testing.expect(!supportsChatCompletionsModel("gpt-5.6-luna"));
}

test "Go model routes cover every documented endpoint family" {
    try std.testing.expectEqual(GoRoute.chat_completions, routeForModel("glm-5.2").?);
    try std.testing.expectEqual(GoRoute.responses, routeForModel("gpt-5.6-luna").?);
    try std.testing.expectEqual(GoRoute.responses, routeForModel("muse-spark-1.3-contributor").?);
    try std.testing.expectEqual(GoRoute.messages, routeForModel("minimax-m3").?);
    try std.testing.expectEqual(GoRoute.messages, routeForModel("qwen3.8-max").?);
    try std.testing.expect(routeForModel("future-model") == null);
}

test "Go route request bodies use their native token fields" {
    const request = stream_provider.BuildRequest{
        .model = "gpt-5.6-luna",
        .messages = &[_]types.ChatMessage{.{ .role = .user, .content = "hello" }},
        .serialized_tools = "[]",
        .tool_choice = .auto,
        .max_output_tokens = 123,
        .provider_options = .{},
    };
    const responses = try buildRequest(null, std.testing.allocator, request);
    defer std.testing.allocator.free(responses);
    try std.testing.expect(std.mem.indexOf(u8, responses, "\"input\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, responses, "\"max_output_tokens\":123") != null);
    try std.testing.expect(std.mem.indexOf(u8, responses, "\"messages\"") == null);

    var messages_request = request;
    messages_request.model = "minimax-m3";
    const messages = try buildRequest(null, std.testing.allocator, messages_request);
    defer std.testing.allocator.free(messages);
    try std.testing.expect(std.mem.indexOf(u8, messages, "\"messages\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, messages, "\"max_tokens\":123") != null);
}
