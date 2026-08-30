const std = @import("std");
const test_support = @import("support.zig");
const types = @import("../../../shared/types.zig");
const io_mod = @import("../../../shared/io.zig");

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
    std.debug.print("tmp_path={s}\n", .{tmp_path});

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
    var job = fixture.job();
    job.prompt = @constCast("Read fixture.txt and tell me its contents.");
    job.model = @constCast("company/coder-v1");
    job.api_key = @constCast("COMPATIBLE-SECRET-EXPECTED");

    std.debug.print("before runFakePrompt\n", .{});
    test_support.runFakePrompt(&gateway, &hooks, config, job) catch |err| {
        std.debug.print("runFakePrompt failed: {s}\n", .{@errorName(err)});
        if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
        return err;
    };
    std.debug.print("after runFakePrompt, bodies={d}\n", .{gateway.request_bodies.items.len});

    try std.testing.expectEqual(@as(usize, 2), gateway.request_bodies.items.len);
}
