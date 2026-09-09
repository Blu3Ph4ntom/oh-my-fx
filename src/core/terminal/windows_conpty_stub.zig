const std = @import("std");
const contracts = @import("contracts.zig");

pub const Pty = struct {
    pub fn spawn(
        _: std.mem.Allocator,
        _: []const []const u8,
        _: []const u8,
        _: contracts.Dimensions,
    ) !Pty {
        return error.TerminalHostUnsupported;
    }

    pub fn read(_: Pty, _: []u8) !usize {
        return error.TerminalHostUnsupported;
    }

    pub fn writeAll(_: Pty, _: []const u8) !void {
        return error.TerminalHostUnsupported;
    }

    pub fn pid(_: Pty) u32 {
        return 0;
    }

    pub fn resize(_: Pty, _: contracts.Dimensions) !void {
        return error.TerminalHostUnsupported;
    }

    pub fn kill(_: Pty) void {}

    pub fn waitBlocking(_: Pty) i32 {
        return -1;
    }

    pub fn close(_: Pty) void {}
};
