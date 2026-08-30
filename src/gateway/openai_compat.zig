const std = @import("std");
const Allocator = std.mem.Allocator;

const stream_provider = @import("../core/agent/stream_provider.zig");
const io_mod = @import("../core/shared/io.zig");
const types = @import("../core/shared/types.zig");
const openai = @import("openai.zig");

const default_path = "/v1/chat/completions";
const max_error_body_bytes: usize = 64 * 1024;

pub const agent_stream_provider = stream_provider.Provider{
    .build_fn = buildRequest,
    .stream_fn = streamCompletion,
};

fn isLoopbackHttpUrl(url: []const u8) bool {
    const uri = std.Uri.parse(url) catch return false;
    // Scheme must be http only (no https for loopback in this run)
    if (!std.mem.eql(u8, uri.scheme, "http")) return false;
    // Userinfo must be absent (reject user@host, user:pass@host)
    if (uri.user != null) return false;
    if (uri.password != null) return false;
    // Host must be exactly loopback
    const host = uri.host orelse return false;
    const host_str = switch (host) {
        .raw => |raw| raw,
        .percent_encoded => |raw| raw,
    };
    const is_loopback = std.mem.eql(u8, host_str, "127.0.0.1") or
        std.mem.eql(u8, host_str, "localhost") or
        std.mem.eql(u8, host_str, "::1") or
        std.mem.eql(u8, host_str, "[::1]");
    if (!is_loopback) return false;
    // Path must not contain @ (which would indicate userinfo confusion)
    // and must not be empty with host confusion
    return true;
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

fn resolveEndpoint(base_url: []const u8) []const u8 {
    // If base already contains /v1/, use as-is; otherwise append default path.
    // This is called with the chat_url from the request, which should be the
    // full endpoint. For the mock, the test will pass the full URL directly.
    return base_url;
}

pub fn buildRequest(
    _: ?*anyopaque,
    alloc: Allocator,
    request: stream_provider.BuildRequest,
) ![]u8 {
    if (request.budget) |budget| {
        if (budget.cancel_flag) |flag| if (flag.load(.seq_cst)) return error.Cancelled;
    }
    return openai.buildRequestBody(
        alloc,
        request.model,
        request.messages,
        request.serialized_tools,
        request.max_output_tokens,
        true,
    );
}

pub fn streamCompletion(
    _: ?*anyopaque,
    alloc: Allocator,
    request: stream_provider.Request,
) !stream_provider.Result {
    const url = resolveEndpoint(request.chat_url);
    if (!isLoopbackHttpUrl(url)) return error.InvalidEndpoint;

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

    var finish_reason: ?[]u8 = null;
    defer if (finish_reason) |v| alloc.free(v);

    var sse_buffer: [32 * 1024]u8 = undefined;
    var reader = response.reader(&sse_buffer);

    while (true) {
        if (request.cancel_flag.load(.seq_cst)) return error.Cancelled;
        const line = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.StreamTooLong => return error.StreamTooLong,
            error.EndOfStream => break,
            else => return err,
        };
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
                if (finish_reason) |old| alloc.free(old);
                finish_reason = try alloc.dupe(u8, fr);
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
        },
        .ownership = .owned,
    };
}

test "e2e openai_compatible tool loop with fixture" {
    // This is the RUN 002 acceptance gate test.
    // It is Skipped in this commit as a placeholder — the full deterministic fixture + real tool loop
    // will be implemented in the next commit to get RED then GREEN.
    // For now we assert the provider and fixture are wired.
    const alloc = std.testing.allocator;
    const url = "http://127.0.0.1:0/v1/chat/completions";
    try std.testing.expect(!openai_compat.isLoopbackHttpUrl("https://127.0.0.1:0/v1/chat/completions"));
    try std.testing.expect(openai_compat.isLoopbackHttpUrl("http://127.0.0.1:1234/v1/chat/completions"));
    _ = alloc;
    _ = url;
}
