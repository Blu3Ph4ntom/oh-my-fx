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
    "deepseek-v4.1-flash",
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

fn chatModelUsesThinkingToggle(model: []const u8) bool {
    return std.mem.eql(u8, model, "longcat-2.0");
}

fn messagesModelUsesEffort(model: []const u8) bool {
    return std.mem.eql(u8, model, "qwen3.8-max") or
        std.mem.eql(u8, model, "qwen3.8-flash");
}

fn messagesModelUsesThinkingToggle(model: []const u8) bool {
    return std.mem.eql(u8, model, "minimax-m3") or
        std.mem.eql(u8, model, "minimax-m2.7") or
        std.mem.eql(u8, model, "minimax-m2.5") or
        std.mem.eql(u8, model, "qwen3.7-max") or
        std.mem.eql(u8, model, "qwen3.7-plus") or
        std.mem.eql(u8, model, "qwen3.6-plus");
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
        .chat_completions => openai.buildRequestBodyWithToolChoiceAndOptionsAndThinking(
            alloc,
            request.model,
            request.messages,
            request.serialized_tools,
            request.max_output_tokens,
            true,
            request.tool_choice,
            request.provider_options,
            chatModelUsesThinkingToggle(request.model) and
                request.provider_options.reasoning != null and
                std.mem.eql(u8, request.provider_options.reasoning.?.label(), "on"),
        ),
        .responses => buildResponsesBody(alloc, request),
        .messages => buildMessagesBody(alloc, request),
    };
}

fn writeJsonString(w: *std.Io.Writer, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, w);
}

fn writeNativeTools(w: *std.Io.Writer, alloc: Allocator, raw: []const u8, route: GoRoute) !void {
    if (raw.len == 0) return;
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, raw, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .array) return;
    var wrote = false;
    for (parsed.value.array.items) |tool| {
        if (tool != .object) continue;
        const name = tool.object.get("name") orelse continue;
        if (name != .string or name.string.len == 0) continue;
        const schema = tool.object.get("inputSchema") orelse tool.object.get("parameters") orelse continue;
        if (schema != .object) continue;
        if (!wrote) {
            try w.writeAll(",\"tools\":[");
            wrote = true;
        } else try w.writeByte(',');
        if (route == .responses) {
            try w.writeAll("{\"type\":\"function\",\"name\":");
            try writeJsonString(w, name.string);
            if (tool.object.get("description")) |description| if (description == .string) {
                try w.writeAll(",\"description\":");
                try writeJsonString(w, description.string);
            };
            try w.writeAll(",\"parameters\":");
        } else {
            try w.writeAll("{\"name\":");
            try writeJsonString(w, name.string);
            if (tool.object.get("description")) |description| if (description == .string) {
                try w.writeAll(",\"description\":");
                try writeJsonString(w, description.string);
            };
            try w.writeAll(",\"input_schema\":");
        }
        try std.json.Stringify.value(schema, .{}, w);
        try w.writeByte('}');
    }
    if (wrote) try w.writeByte(']');
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
            if (msg.role == .assistant) for (msg.tool_calls) |call| {
                try w.writeAll(",{\"type\":\"function_call\",\"call_id\":");
                try writeJsonString(w, call.id);
                try w.writeAll(",\"name\":");
                try writeJsonString(w, call.name);
                try w.writeAll(",\"arguments\":");
                try writeJsonString(w, call.arguments_json);
                try w.writeByte('}');
            };
        }
    }
    try w.writeAll("] ,\"stream\":true,\"store\":false");
    if (request.provider_options.reasoning) |effort| if (!effort.isDefault()) {
        try w.writeAll(",\"reasoning\":{\"effort\":");
        try writeJsonString(w, effort.label());
        try w.writeByte('}');
    };
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
    try writeNativeTools(w, alloc, request.serialized_tools, .responses);
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
    if (request.provider_options.reasoning) |effort| if (!effort.isDefault()) {
        if (messagesModelUsesEffort(request.model)) {
            if (std.mem.eql(u8, effort.label(), "none")) {
                try w.writeAll(",\"thinking\":{\"type\":\"disabled\"}");
            } else {
                try w.writeAll(",\"thinking\":{\"type\":\"enabled\"}");
                try w.writeAll(",\"output_config\":{\"effort\":");
                try writeJsonString(w, effort.label());
                try w.writeByte('}');
            }
        } else if (messagesModelUsesThinkingToggle(request.model) and
            std.mem.eql(u8, effort.label(), "on"))
        {
            try w.writeAll(",\"thinking\":{\"type\":\"enabled\",\"budget_tokens\":");
            const max_tokens = request.max_output_tokens orelse 32_768;
            const budget_tokens = if (max_tokens <= 1) 1 else if (max_tokens < 2_048) max_tokens - 1 else @min(max_tokens / 2, 32_768);
            try w.print("{d}", .{budget_tokens});
            try w.writeByte('}');
        }
    };
    if (request.max_output_tokens) |limit| try w.print(",\"max_tokens\":{d}", .{limit});
    for (request.messages) |msg| {
        if (msg.role == .system) if (msg.content) |content| {
            try w.writeAll(",\"system\":");
            try writeJsonString(w, content);
            break;
        };
    }
    try writeNativeTools(w, alloc, request.serialized_tools, .messages);
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

    const NativeTool = struct {
        id: []u8,
        name: []u8,
        arguments: std.ArrayList(u8) = .empty,
    };
    var native_tools: std.ArrayList(NativeTool) = .empty;
    defer {
        for (native_tools.items) |*tool| {
            alloc.free(tool.id);
            alloc.free(tool.name);
            tool.arguments.deinit(alloc);
        }
        native_tools.deinit(alloc);
    }
    var final_calls: std.ArrayList(types.ToolCall) = .empty;
    defer final_calls.deinit(alloc);

    var finish_reason: ?types.ProviderFinishReason = null;

    // Responses/Messages can carry large tool schemas or accumulated tool
    // arguments in a single SSE data line. Keep the line bounded, but large
    // enough for the same 4 MiB provider payload limit used by catalog fetches.
    var sse_buffer: [4 * 1024 * 1024]u8 = undefined;
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
                if (std.mem.eql(u8, event_type.string, "response.output_item.added")) {
                    if (object.get("item")) |item| if (item == .object) {
                        if (item.object.get("type")) |kind| if (kind == .string and std.mem.eql(u8, kind.string, "function_call")) {
                            const id_value = item.object.get("id") orelse item.object.get("call_id") orelse continue;
                            const name_value = item.object.get("name") orelse continue;
                            if (id_value == .string and name_value == .string) {
                                try native_tools.append(alloc, .{
                                    .id = try alloc.dupe(u8, id_value.string),
                                    .name = try alloc.dupe(u8, name_value.string),
                                });
                            }
                        };
                    };
                } else if (std.mem.eql(u8, event_type.string, "response.function_call_arguments.delta")) {
                    const item_id = object.get("item_id") orelse continue;
                    if (item_id == .string) for (native_tools.items) |*tool| {
                        if (std.mem.eql(u8, tool.id, item_id.string)) {
                            if (object.get("delta")) |delta| if (delta == .string) try tool.arguments.appendSlice(alloc, delta.string);
                            break;
                        }
                    };
                } else if (std.mem.eql(u8, event_type.string, "response.output_item.done")) {
                    if (object.get("item")) |item| if (item == .object) {
                        if (item.object.get("type")) |kind| if (kind == .string and std.mem.eql(u8, kind.string, "function_call")) {
                            const id_value = item.object.get("id") orelse item.object.get("call_id") orelse continue;
                            if (id_value == .string) for (native_tools.items, 0..) |*tool, index| {
                                if (std.mem.eql(u8, tool.id, id_value.string)) {
                                    if (tool.arguments.items.len == 0) if (item.object.get("arguments")) |args| if (args == .string) try tool.arguments.appendSlice(alloc, args.string);
                                    if (request.on_tool_start) |callback| callback(request.callback_ctx, tool.id, tool.name, null);
                                    try final_calls.append(alloc, .{
                                        .id = try alloc.dupe(u8, tool.id),
                                        .name = try alloc.dupe(u8, tool.name),
                                        .arguments_json = try alloc.dupe(u8, tool.arguments.items),
                                    });
                                    _ = index;
                                    break;
                                }
                            };
                        };
                    };
                } else if (std.mem.eql(u8, event_type.string, "response.output_text.delta")) {
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
            } else if (std.mem.eql(u8, event_type.string, "content_block_start")) {
                if (object.get("content_block")) |block| if (block == .object) {
                    if (block.object.get("type")) |kind| if (kind == .string and std.mem.eql(u8, kind.string, "tool_use")) {
                        const id = block.object.get("id") orelse continue;
                        const name = block.object.get("name") orelse continue;
                        if (id == .string and name == .string) try native_tools.append(alloc, .{
                            .id = try alloc.dupe(u8, id.string),
                            .name = try alloc.dupe(u8, name.string),
                        });
                    };
                };
            } else if (std.mem.eql(u8, event_type.string, "content_block_delta")) {
                if (object.get("delta")) |delta| if (delta == .object) {
                    if (delta.object.get("type")) |kind| if (kind == .string and std.mem.eql(u8, kind.string, "input_json_delta")) {
                        const index = object.get("index") orelse continue;
                        if (index == .integer) if (index.integer >= 0) if (delta.object.get("partial_json")) |args| if (args == .string) {
                            if (index.integer < native_tools.items.len) try native_tools.items[@intCast(index.integer)].arguments.appendSlice(alloc, args.string);
                        };
                    } else if (kind == .string and std.mem.eql(u8, kind.string, "text_delta")) {
                        if (delta.object.get("text")) |text| if (text == .string) {
                            const copied = try alloc.dupe(u8, text.string);
                            defer alloc.free(copied);
                            request.on_content_chunk(request.callback_ctx, copied);
                            try content_parts.appendSlice(alloc, copied);
                        };
                    };
                };
            } else if (std.mem.eql(u8, event_type.string, "content_block_stop")) {
                const index = object.get("index") orelse continue;
                if (index == .integer) if (index.integer >= 0 and index.integer < native_tools.items.len) {
                    const tool = native_tools.items[@intCast(index.integer)];
                    if (request.on_tool_start) |callback| callback(request.callback_ctx, tool.id, tool.name, null);
                    try final_calls.append(alloc, .{
                        .id = try alloc.dupe(u8, tool.id),
                        .name = try alloc.dupe(u8, tool.name),
                        .arguments_json = try alloc.dupe(u8, tool.arguments.items),
                    });
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
    try std.testing.expectEqual(GoRoute.chat_completions, routeForModel("deepseek-v4.1-flash").?);
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

    var continuation = request;
    continuation.messages = &[_]types.ChatMessage{.{
        .role = .assistant,
        .content = "",
        .tool_calls = &[_]types.ToolCall{.{
            .id = "fc_1",
            .name = "list_dir",
            .arguments_json = "{\"path\":\".\"}",
        }},
    }};
    const continuation_body = try buildRequest(null, std.testing.allocator, continuation);
    defer std.testing.allocator.free(continuation_body);
    try std.testing.expect(std.mem.indexOf(u8, continuation_body, "\"type\":\"function_call\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, continuation_body, "\"call_id\":\"fc_1\"") != null);
}

test "Go Chat Completions request forwards declared reasoning effort" {
    const request = stream_provider.BuildRequest{
        .model = "glm-5.2",
        .messages = &[_]types.ChatMessage{.{ .role = .user, .content = "hello" }},
        .serialized_tools = "[]",
        .tool_choice = .auto,
        .provider_options = .{ .reasoning = types.ReasoningEffort.literal("high") },
    };
    const body = try buildRequest(null, std.testing.allocator, request);
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoning_effort\":\"high\"") != null);
}

test "Go Responses request forwards declared reasoning effort" {
    const request = stream_provider.BuildRequest{
        .model = "gpt-5.6-luna",
        .messages = &[_]types.ChatMessage{.{ .role = .user, .content = "hello" }},
        .serialized_tools = "[]",
        .tool_choice = .auto,
        .provider_options = .{ .reasoning = types.ReasoningEffort.literal("xhigh") },
    };
    const body = try buildRequest(null, std.testing.allocator, request);
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoning\":{\"effort\":\"xhigh\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoning_effort\"") == null);
}

test "Go Messages request forwards native reasoning controls" {
    const request = stream_provider.BuildRequest{
        .model = "qwen3.8-max",
        .messages = &[_]types.ChatMessage{.{ .role = .user, .content = "hello" }},
        .serialized_tools = "[]",
        .tool_choice = .auto,
        .max_output_tokens = 8192,
        .provider_options = .{ .reasoning = types.ReasoningEffort.literal("xhigh") },
    };
    const body = try buildRequest(null, std.testing.allocator, request);
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"thinking\":{\"type\":\"enabled\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"output_config\":{\"effort\":\"xhigh\"}") != null);
}

test "Go toggle-only models expose a native thinking switch" {
    const request = stream_provider.BuildRequest{
        .model = "minimax-m3",
        .messages = &[_]types.ChatMessage{.{ .role = .user, .content = "hello" }},
        .serialized_tools = "[]",
        .tool_choice = .auto,
        .max_output_tokens = 8192,
        .provider_options = .{ .reasoning = types.ReasoningEffort.literal("on") },
    };
    const body = try buildRequest(null, std.testing.allocator, request);
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"thinking\":{\"type\":\"enabled\",\"budget_tokens\":4096}") != null);
}

test "Go Qwen toggle models do not receive an effort object" {
    const request = stream_provider.BuildRequest{
        .model = "qwen3.7-max",
        .messages = &[_]types.ChatMessage{.{ .role = .user, .content = "hello" }},
        .serialized_tools = "[]",
        .tool_choice = .auto,
        .provider_options = .{ .reasoning = types.ReasoningEffort.literal("on") },
    };
    const body = try buildRequest(null, std.testing.allocator, request);
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"thinking\":{\"type\":\"enabled\",\"budget_tokens\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"output_config\"") == null);
}
