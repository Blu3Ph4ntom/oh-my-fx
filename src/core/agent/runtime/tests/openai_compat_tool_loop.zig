const std = @import("std");
const test_support = @import("support.zig");
const types = @import("../../../shared/types.zig");
const io_mod = @import("../../../shared/io.zig");

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

    const tmp_path = try io_mod.dirRealpathAlloc(alloc, tmp.dir, ".");
    defer alloc.free(tmp_path);

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

    var fixture = test_support.PromptFixture{
        .workspace_root = tmp_path,
    };
    var config = fixture.config();
    config.workspace_root = tmp_path;
    // Override to use openai_compatible
    // Note: PromptFixture config does not have provider/model/api_key, those are in QueuedPrompt
    // We need to set them via hooks or via config? Let's check Config fields
    // Actually Config in runtime_config does not have provider; provider is via gateway
    // The job's api_key and model are used
    var job = fixture.job();
    job.prompt = @constCast("Read fixture.txt and tell me its contents.");
    job.model = @constCast("company/coder-v1");
    job.api_key = @constCast("COMPATIBLE-SECRET-EXPECTED");

    try test_support.runFakePrompt(&gateway, &hooks, config, job);

    try std.testing.expectEqual(@as(usize, 2), gateway.request_bodies.items.len);
    try std.testing.expectEqual(@as(usize, 2), gateway.request_models.items.len);
    try std.testing.expectEqualStrings("company/coder-v1", gateway.request_models.items[0]);
    try std.testing.expectEqualStrings("company/coder-v1", gateway.request_models.items[1]);

    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[0], "read_file") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[0], "GATEWAY-SECRET-MUST-NOT-LEAK") == null);
    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[0], "CODEX-SECRET-MUST-NOT-LEAK") == null);
    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[0], "GROK-SECRET-MUST-NOT-LEAK") == null);

    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[1], "call_abc123") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway.request_bodies.items[1], "OH_MY_FX_TOOL_LOOP_PROOF") != null);

    try std.testing.expectEqual(@as(usize, 2), gateway.index);
    try std.testing.expectEqualStrings("COMPATIBLE-SECRET-EXPECTED", gateway.request_api_keys.items[0]);
    try std.testing.expectEqualStrings("COMPATIBLE-SECRET-EXPECTED", gateway.request_api_keys.items[1]);
}
