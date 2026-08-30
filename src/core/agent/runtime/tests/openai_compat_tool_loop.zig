const std = @import("std");
const test_support = @import("support.zig");
const types = @import("../../../shared/types.zig");

const FakeGateway = test_support.FakeGateway;
const FakeCompletion = test_support.FakeCompletion;
const ToolCall = types.ToolCall;

fn toolCall(id: []const u8, name: []const u8, args: []const u8) ToolCall {
    return .{ .id = id, .name = name, .arguments_json = args };
}

test "openai_compatible tool loop via orchestrator with real read_file" {
    const alloc = std.testing.allocator;
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

    var hooks = test_support.FakeAgentRuntimeDeps.init(alloc);
    defer hooks.deinit();

    var fixture = test_support.PromptFixture{};
    var config = fixture.config();
    var job = fixture.job();
    job.prompt = @constCast("Read fixture.txt");
    job.model = @constCast("company/coder-v1");
    job.api_key = @constCast("COMPATIBLE-SECRET-EXPECTED");

    try test_support.runFakePrompt(&gateway, &hooks, config, job);

    try std.testing.expectEqual(@as(usize, 2), gateway.request_bodies.items.len);
    try std.testing.expectEqualStrings("COMPATIBLE-SECRET-EXPECTED", gateway.request_api_keys.items[0]);
}
