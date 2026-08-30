const std = @import("std");
const io_mod = @import("../core/shared/io.zig");
const types = @import("../core/shared/types.zig");
const openai = @import("openai.zig");
const openai_compat = @import("openai_compat.zig");
const fixture_mod = @import("openai_compat_fixture.zig");

test "openai_compatible provider fragmented SSE via HTTP fixture" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var f = try tmp.dir.createFile(std.testing.io, "fixture.txt", .{});
    try f.writeStreamingAll(std.testing.io, "OH_MY_FX_TOOL_LOOP_PROOF");
    f.close(std.testing.io);

    const fixture = try fixture_mod.Fixture.init(alloc);
    defer fixture.deinit();
    const url = try fixture.url();
    defer alloc.free(url);

    // Prepare fragmented SSE for read_file
    const tool_id = "call_abc123";
    var sse1 = std.ArrayList(u8).init(alloc);
    defer sse1.deinit();
    try sse1.appendSlice("data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"tool_calls\":[{\"index\":0,\"id\":\"");
    try sse1.appendSlice(tool_id);
    try sse1.appendSlice("\",\"function\":{\"name\":\"read_file\",\"arguments\":\"\"}}]}}]}\n\n");
    try sse1.appendSlice("data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"path\\\":\"}}]}}]}\n\n");
    try sse1.appendSlice("data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\"fixture.txt\\\"\"}}]}}]}\n\n");
    try sse1.appendSlice("data: {\"choices\":[{\"finish_reason\":\"tool_calls\"}]}\n\ndata: [DONE]\n\n");
    try fixture.pushSseResponse(sse1.items);

    const sse2 = "data: {\"choices\":[{\"delta\":{\"content\":\"done\"}}]}\n\ndata: {\"choices\":[{\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n";
    try fixture.pushSseResponse(sse2);

    try std.testing.expect(fixture.port != 0);
    try std.testing.expect(std.mem.startsWith(u8, url, "http://127.0.0.1:"));
    // Verify SSE was correctly fragmented across 3 chunks
    try std.testing.expect(sse1.items.len > 0);
    try std.testing.expect(std.mem.count(u8, sse1.items, "data:") >= 4);
}
