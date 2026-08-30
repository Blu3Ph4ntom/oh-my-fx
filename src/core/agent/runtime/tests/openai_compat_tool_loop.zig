const std = @import("std");
const test_support = @import("support.zig");
const types = @import("../../../shared/types.zig");

const Allocator = std.mem.Allocator;
const FakeGateway = test_support.FakeGateway;
const FakeCompletion = test_support.FakeCompletion;
const ToolCall = types.ToolCall;

fn toolCall(id: []const u8, name: []const u8, args: []const u8) ToolCall {
    return .{ .id = id, .name = name, .arguments_json = args };
}

test "openai_compatible tool loop via orchestrator with real read_file" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const content = "OH_MY_FX_TOOL_LOOP_PROOF";
    var f = try tmp.dir.createFile(std.testing.io, "fixture.txt", .{});
    try f.writeStreamingAll(std.testing.io, content);
    f.close(std.testing.io);

    // FakeGateway with two completions: first returns read_file tool call, second returns final answer
    const completions = [_]FakeCompletion{
        .{
            .tool_calls = &[_]ToolCall{toolCall("call_abc123", "read_file", "{\"path\":\"fixture.txt\"}")},
        },
        .{
            .chunks = &[_][]const u8{"done"},
        },
    };
    var gateway = FakeGateway.init(alloc, &completions);
    defer gateway.deinit();

    var hooks = test_support.FakeAgentRuntimeDeps.init(alloc, tmp.dir, &gateway);
    defer hooks.deinit();

    const config = test_support.Config{
        .workspace_root = hooks.workspace_root,
        .provider = .openai_compatible,
        .model = "company/coder-v1",
        .api_key = "COMPATIBLE-SECRET-EXPECTED",
    };

    const job = test_support.QueuedPrompt{
        .id = "test-job",
        .prompt = "Read fixture.txt and tell me its contents.",
    };

    try test_support.runFakePrompt(&gateway, &hooks, config, job);

    // Assertions: 2 gateway requests, 1 real read_file execution, no leaked secrets
    try std.testing.expectEqual(@as(usize, 2), gateway.request_bodies.items.len);
    try std.testing.expectEqual(@as(usize, 2), gateway.request_models.items.len);
    try std.testing.expectEqualStrings("company/coder-v1", gateway.request_models.items[0]);
    try std.testing.expectEqualStrings("company/coder-v1", gateway.request_models.items[1]);

    // Verify first request contains tool schema and not leaked secrets
    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[0], "read_file") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[0], "GATEWAY-SECRET-MUST-NOT-LEAK") == null);
    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[0], "CODEX-SECRET-MUST-NOT-LEAK") == null);
    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[0], "GROK-SECRET-MUST-NOT-LEAK") == null);
    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[0], "COMPATIBLE-SECRET-EXPECTED") == null);

    // Verify second request contains tool result with expected content and matching id
    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[1], "call_abc123") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[1], "OH_MY_FX_TOOL_LOOP_PROOF") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[1], "fixture.txt") != null);

    // Verify no third request
    try std.testing.expectEqual(@as(usize, 2), gateway.index);

    // Verify API key was correctly sent
    try std.testing.expectEqualStrings("COMPATIBLE-SECRET-EXPECTED", gateway.request_api_keys.items[0]);
    try std.testing.expectEqualStrings("COMPATIBLE-SECRET-EXPECTED", gateway.request_api_keys.items[1]);

    // Verify tool was executed via hooks
    const history = hooks.history.items;
    var found_tool_result = false;
    for (history) |msg| {
        if (msg.role == .tool) {
            if (msg.content) |c| {
                if (std.mem.indexOf(u8, c, "OH_MY_FX_TOOL_LOOP_PROOF") != null) {
                    found_tool_result = true;
                    try std.testing.expectEqualStrings("call_abc123", msg.tool_call_id.?);
                }
            }
        }
    }
    try std.testing.expect(found_tool_result);
}
