const std = @import("std");
const builtin = @import("builtin");

/// Stable local profile identity used only inside private terminal authority.
pub fn profileUser(buffer: *[64]u8) ?[]const u8 {
    if (comptime builtin.os.tag == .macos or builtin.os.tag == .linux) {
        return std.fmt.bufPrint(buffer, "uid-{d}", .{std.c.getuid()}) catch null;
    }
    if (comptime builtin.os.tag == .windows) {
        return std.fmt.bufPrint(buffer, "win-pid-{d}", .{std.os.windows.GetCurrentProcessId()}) catch null;
    }
    return null;
}

test "profile identity is available exactly on supported terminal hosts" {
    var buffer: [64]u8 = undefined;
    const value = profileUser(&buffer);
    if (comptime builtin.os.tag == .macos or builtin.os.tag == .linux) {
        try std.testing.expect(value != null);
        try std.testing.expect(std.mem.startsWith(u8, value.?, "uid-"));
    } else if (comptime builtin.os.tag == .windows) {
        try std.testing.expect(value != null);
        try std.testing.expect(std.mem.startsWith(u8, value.?, "win-pid-"));
    } else {
        try std.testing.expect(value == null);
    }
}
