const std = @import("std");
const types = @import("../core/shared/types.zig");

const Allocator = std.mem.Allocator;

/// Minimal OpenAI Chat Completions request shape for the agent loop.
/// Only fields required by current fx semantics are modeled.
pub const ChoiceDelta = struct {
    content: ?[]const u8 = null,
    tool_calls: ?[]const ToolCallDelta = null,
};

pub const ToolCallDelta = struct {
    index: u32,
    id: ?[]const u8 = null,
    function_name: ?[]const u8 = null,
    arguments_fragment: ?[]const u8 = null,
};

pub const StreamChunk = union(enum) {
    text_delta: []const u8,
    tool_call_delta: ToolCallDelta,
    finish_reason: []const u8,
    usage: struct {
        prompt_tokens: ?u32 = null,
        completion_tokens: ?u32 = null,
        total_tokens: ?u32 = null,
    },
    done,
    err: []const u8,
};

/// Builds an OpenAI-compatible Chat Completions request body.
/// The caller owns the returned slice.
pub fn buildRequestBody(
    alloc: Allocator,
    model: []const u8,
    messages: []const types.ChatMessage,
    serialized_tools: []const u8,
    max_output_tokens: ?u32,
    stream: bool,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    var w = &out.writer;

    try w.writeAll("{\"model\":");
    try writeJsonString(w, model);
    try w.writeAll(",\"stream\":");
    try w.writeAll(if (stream) "true" else "false");

    if (max_output_tokens) |limit| {
        try w.writeAll(",\"max_tokens\":");
        try w.print("{d}", .{limit});
    }

    // Messages
    try w.writeAll(",\"messages\":[");
    for (messages, 0..) |msg, i| {
        if (i > 0) try w.writeAll(",");
        try writeMessage(w, msg);
    }
    try w.writeAll("]");

    // Tools (if any)
    if (serialized_tools.len > 0 and !std.mem.eql(u8, serialized_tools, "[]")) {
        try w.writeAll(",\"tools\":");
        try w.writeAll(serialized_tools);
        try w.writeAll(",\"tool_choice\":\"auto\"");
    }

    try w.writeAll("}");
    return out.toOwnedSlice();
}

fn writeMessage(w: *std.Io.Writer, msg: types.ChatMessage) !void {
    try w.writeAll("{\"role\":");
    try writeJsonString(w, @tagName(msg.role));
    try w.writeAll(",\"content\":");

    if (msg.content) |content| {
        if (content.len == 0) {
            try w.writeAll("null");
        } else {
            try writeJsonString(w, content);
        }
    } else {
        try w.writeAll("null");
    }

    // Tool calls (assistant)
    if (msg.tool_calls.len > 0) {
        const calls = msg.tool_calls;
        try w.writeAll(",\"tool_calls\":[");
        for (calls, 0..) |call, j| {
            if (j > 0) try w.writeAll(",");
            try w.writeAll("{\"id\":");
            try writeJsonString(w, call.id);
            try w.writeAll(",\"type\":\"function\",\"function\":{\"name\":");
            try writeJsonString(w, call.name);
            try w.writeAll(",\"arguments\":");
            try writeJsonString(w, call.arguments_json);
            try w.writeAll("}}");
        }
        try w.writeAll("]");
    }

    // Tool result (tool role)
    if (msg.tool_call_id) |id| {
        try w.writeAll(",\"tool_call_id\":");
        try writeJsonString(w, id);
    }
    if (msg.tool_name) |name| {
        try w.writeAll(",\"name\":");
        try writeJsonString(w, name);
    }

    try w.writeAll("}");
}

fn writeJsonString(w: *std.Io.Writer, s: []const u8) !void {
    try w.writeAll("\"");
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0x08 => try w.writeAll("\\b"),
            0x0C => try w.writeAll("\\f"),
            else => {
                if (c < 0x20) {
                    try w.print("\\u{x:0>4}", .{c});
                } else {
                    try w.writeAll(&[_]u8{c});
                }
            },
        }
    }
    try w.writeAll("\"");
}

// ---------------------------------------------------------------------------
// SSE stream decoding for OpenAI Chat Completions
// ---------------------------------------------------------------------------

pub const StreamParser = struct {
    alloc: Allocator,
    // Accumulates fragmented tool call arguments per index
    tool_arg_buffers: std.AutoHashMap(u32, std.ArrayList(u8)),
    // Tracks tool call ids/names per index
    tool_ids: std.AutoHashMap(u32, []u8),
    tool_names: std.AutoHashMap(u32, []u8),

    pub fn init(alloc: Allocator) StreamParser {
        return .{
            .alloc = alloc,
            .tool_arg_buffers = std.AutoHashMap(u32, std.ArrayList(u8)).init(alloc),
            .tool_ids = std.AutoHashMap(u32, []u8).init(alloc),
            .tool_names = std.AutoHashMap(u32, []u8).init(alloc),
        };
    }

    pub fn deinit(self: *StreamParser) void {
        var it = self.tool_arg_buffers.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(self.alloc);
        self.tool_arg_buffers.deinit();
        var it2 = self.tool_ids.iterator();
        while (it2.next()) |entry| self.alloc.free(entry.value_ptr.*);
        self.tool_ids.deinit();
        var it3 = self.tool_names.iterator();
        while (it3.next()) |entry| self.alloc.free(entry.value_ptr.*);
        self.tool_names.deinit();
    }

    /// Parses a single SSE data line (without the "data: " prefix).
    /// Returns null for "[DONE]" or empty, otherwise a parsed chunk.
    pub fn parseDataLine(self: *StreamParser, data: []const u8) !?StreamChunk {
        const trimmed = std.mem.trim(u8, data, " \t\r\n");
        if (trimmed.len == 0) return null;
        if (std.mem.eql(u8, trimmed, "[DONE]")) return .done;

        // Parse JSON
        const parsed = std.json.parseFromSlice(std.json.Value, self.alloc, trimmed, .{}) catch {
            return StreamChunk{ .err = try self.alloc.dupe(u8, trimmed) };
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return null;
        const obj = root.object;

        // Check for error object
        if (obj.get("error")) |err_val| {
            _ = err_val;
            return StreamChunk{ .err = try self.alloc.dupe(u8, trimmed) };
        }

        // Usage (may appear in final chunk)
        if (obj.get("usage")) |usage| {
            if (usage == .object) {
                return StreamChunk{ .usage = .{
                    .prompt_tokens = if (usage.object.get("prompt_tokens")) |v| @as(?u32, if (v == .integer) @intCast(v.integer) else null) else null,
                    .completion_tokens = if (usage.object.get("completion_tokens")) |v| @as(?u32, if (v == .integer) @intCast(v.integer) else null) else null,
                    .total_tokens = if (usage.object.get("total_tokens")) |v| @as(?u32, if (v == .integer) @intCast(v.integer) else null) else null,
                } };
            }
        }

        const choices_val = obj.get("choices") orelse return null;
        if (choices_val != .array or choices_val.array.items.len == 0) return null;
        const choice = choices_val.array.items[0];
        if (choice != .object) return null;

        // Finish reason
        if (choice.object.get("finish_reason")) |fr| {
            if (fr != .null) {
                if (fr == .string) {
                    return StreamChunk{ .finish_reason = try self.alloc.dupe(u8, fr.string) };
                }
            }
        }

        const delta_val = choice.object.get("delta") orelse return null;
        if (delta_val != .object) return null;
        const delta = delta_val.object;

        // Text content
        if (delta.get("content")) |content| {
            if (content == .string and content.string.len > 0) {
                return StreamChunk{ .text_delta = try self.alloc.dupe(u8, content.string) };
            }
        }

        // Tool calls
        if (delta.get("tool_calls")) |tc_val| {
            if (tc_val == .array and tc_val.array.items.len > 0) {
                const tc = tc_val.array.items[0];
                if (tc == .object) {
                    const idx: u32 = if (tc.object.get("index")) |v| @as(u32, if (v == .integer) @intCast(v.integer) else 0) else 0;
                    var id: ?[]const u8 = null;
                    var name: ?[]const u8 = null;
                    var args: ?[]const u8 = null;
                    if (tc.object.get("id")) |v| {
                        if (v == .string) id = v.string;
                    }
                    if (tc.object.get("function")) |fn_obj| {
                        if (fn_obj == .object) {
                            if (fn_obj.object.get("name")) |v| {
                                if (v == .string) name = v.string;
                            }
                            if (fn_obj.object.get("arguments")) |v| {
                                if (v == .string) args = v.string;
                            }
                        }
                    }

                    // Persist id/name
                    if (id) |v| {
                        const gop = try self.tool_ids.getOrPut(idx);
                        if (!gop.found_existing) {
                            gop.value_ptr.* = try self.alloc.dupe(u8, v);
                        } else {
                            self.alloc.free(gop.value_ptr.*);
                            gop.value_ptr.* = try self.alloc.dupe(u8, v);
                        }
                    }
                    if (name) |v| {
                        const gop = try self.tool_names.getOrPut(idx);
                        if (!gop.found_existing) {
                            gop.value_ptr.* = try self.alloc.dupe(u8, v);
                        } else {
                            self.alloc.free(gop.value_ptr.*);
                            gop.value_ptr.* = try self.alloc.dupe(u8, v);
                        }
                    }
                    if (args) |fragment| {
                        const gop = try self.tool_arg_buffers.getOrPut(idx);
                        if (!gop.found_existing) gop.value_ptr.* = .empty;
                        try gop.value_ptr.appendSlice(self.alloc, fragment);
                    }

                    // Return delta for this chunk
                    const stored_id = self.tool_ids.get(idx);
                    const stored_name = self.tool_names.get(idx);
                    return StreamChunk{ .tool_call_delta = .{
                        .index = idx,
                        .id = if (stored_id) |v| try self.alloc.dupe(u8, v) else null,
                        .function_name = if (stored_name) |v| try self.alloc.dupe(u8, v) else null,
                        .arguments_fragment = if (args) |v| try self.alloc.dupe(u8, v) else null,
                    } };
                }
            }
        }

        return null;
    }

    /// Returns the fully assembled tool call arguments for a given index, if any.
    pub fn assembledArguments(self: *StreamParser, index: u32) ?[]const u8 {
        const entry = self.tool_arg_buffers.get(index) orelse return null;
        return entry.items;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "buildRequestBody includes model and stream" {
    const alloc = std.testing.allocator;
    const body = try buildRequestBody(alloc, "company/coder-v1", &[_]types.ChatMessage{
        .{ .role = .user, .content = "hello" },
    }, "[]", null, true);
    defer alloc.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"model\":\"company/coder-v1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"stream\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"role\":\"user\"") != null);
}

test "buildRequestBody passes arbitrary model id unchanged" {
    const alloc = std.testing.allocator;
    const body = try buildRequestBody(alloc, "my-org/my-model-123", &[_]types.ChatMessage{}, "[]", null, true);
    defer alloc.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "my-org/my-model-123") != null);
}

test "buildRequestBody serializes tool calls and tool results" {
    const alloc = std.testing.allocator;
    const body = try buildRequestBody(alloc, "test/model", &[_]types.ChatMessage{
        .{ .role = .assistant, .content = null, .tool_calls = &[_]types.ToolCall{
            .{ .id = "call_1", .name = "read_file", .arguments_json = "{\"path\":\"a.txt\"}" },
        } },
        .{ .role = .tool, .content = "file content", .tool_call_id = "call_1" },
    }, "[{\"type\":\"function\",\"function\":{\"name\":\"read_file\"}}]", null, true);
    defer alloc.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "call_1") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "tool_call_id") != null);
}

test "parseDataLine handles text delta" {
    var p = StreamParser.init(std.testing.allocator);
    defer p.deinit();
    const chunk = try p.parseDataLine("{\"choices\":[{\"delta\":{\"content\":\"hello\"},\"finish_reason\":null}]}");
    try std.testing.expect(chunk != null);
    try std.testing.expect(chunk.? == .text_delta);
    try std.testing.expectEqualStrings("hello", chunk.?.text_delta);
    std.testing.allocator.free(chunk.?.text_delta);
}

test "parseDataLine handles [DONE]" {
    var p = StreamParser.init(std.testing.allocator);
    defer p.deinit();
    const chunk = try p.parseDataLine("[DONE]");
    try std.testing.expect(chunk != null);
    try std.testing.expect(chunk.? == .done);
}

test "parseDataLine handles tool call fragmented arguments" {
    var p = StreamParser.init(std.testing.allocator);
    defer p.deinit();
    // First chunk: id + name + partial args
    const c1 = try p.parseDataLine("{\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_abc\",\"function\":{\"name\":\"read_file\",\"arguments\":\"{\\\"path\\\":\\\"\"}}]},\"finish_reason\":null}]}");
    try std.testing.expect(c1 != null);
    if (c1) |ch| {
        try std.testing.expect(ch == .tool_call_delta);
        if (ch.tool_call_delta.id) |v| std.testing.allocator.free(v);
        if (ch.tool_call_delta.function_name) |v| std.testing.allocator.free(v);
        if (ch.tool_call_delta.arguments_fragment) |v| std.testing.allocator.free(v);
    }
    // Second chunk: remaining args
    const c2 = try p.parseDataLine("{\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"a.txt\\\"}\"}}]},\"finish_reason\":null}]}");
    try std.testing.expect(c2 != null);
    if (c2) |ch| {
        if (ch.tool_call_delta.arguments_fragment) |v| std.testing.allocator.free(v);
        if (ch.tool_call_delta.id) |v| std.testing.allocator.free(v);
        if (ch.tool_call_delta.function_name) |v| std.testing.allocator.free(v);
    }
    const assembled = p.assembledArguments(0);
    try std.testing.expect(assembled != null);
    try std.testing.expectEqualStrings("{\"path\":\"a.txt\"}", assembled.?);
}

test "parseDataLine handles finish reason" {
    var p = StreamParser.init(std.testing.allocator);
    defer p.deinit();
    const chunk = try p.parseDataLine("{\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}");
    try std.testing.expect(chunk != null);
    try std.testing.expect(chunk.? == .finish_reason);
    try std.testing.expectEqualStrings("tool_calls", chunk.?.finish_reason);
    std.testing.allocator.free(chunk.?.finish_reason);
}
