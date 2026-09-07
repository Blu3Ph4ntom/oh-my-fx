const std = @import("std");

pub const Theme = enum { auto, dark, light, high_contrast };
pub const Density = enum { compact, comfortable };
pub const Motion = enum { full, reduced };

pub const Preferences = struct {
    theme: Theme = .auto,
    density: Density = .compact,
    motion: Motion = .full,
    show_key_hints: bool = true,
};

pub fn parseTheme(raw: []const u8) ?Theme {
    if (std.mem.eql(u8, raw, "auto")) return .auto;
    if (std.mem.eql(u8, raw, "dark")) return .dark;
    if (std.mem.eql(u8, raw, "light")) return .light;
    if (std.mem.eql(u8, raw, "high_contrast")) return .high_contrast;
    return null;
}

pub fn parseDensity(raw: []const u8) ?Density {
    if (std.mem.eql(u8, raw, "compact")) return .compact;
    if (std.mem.eql(u8, raw, "comfortable")) return .comfortable;
    return null;
}

pub fn parseMotion(raw: []const u8) ?Motion {
    if (std.mem.eql(u8, raw, "full")) return .full;
    if (std.mem.eql(u8, raw, "reduced")) return .reduced;
    return null;
}

pub fn themeLabel(value: Theme) []const u8 {
    return switch (value) {
        .auto => "Auto",
        .dark => "Dark",
        .light => "Light",
        .high_contrast => "High contrast",
    };
}

pub fn densityLabel(value: Density) []const u8 {
    return switch (value) {
        .compact => "Compact",
        .comfortable => "Comfortable",
    };
}

pub fn motionLabel(value: Motion) []const u8 {
    return switch (value) {
        .full => "Full",
        .reduced => "Reduced",
    };
}

test "ui preference parser accepts documented values" {
    try std.testing.expectEqual(Theme.auto, parseTheme("auto").?);
    try std.testing.expectEqual(Theme.dark, parseTheme("dark").?);
    try std.testing.expectEqual(Theme.light, parseTheme("light").?);
    try std.testing.expectEqual(Theme.high_contrast, parseTheme("high_contrast").?);
    try std.testing.expectEqual(Density.compact, parseDensity("compact").?);
    try std.testing.expectEqual(Density.comfortable, parseDensity("comfortable").?);
    try std.testing.expectEqual(Motion.full, parseMotion("full").?);
    try std.testing.expectEqual(Motion.reduced, parseMotion("reduced").?);
}

test "ui preference parser rejects unknown values" {
    try std.testing.expect(parseTheme("neon") == null);
    try std.testing.expect(parseDensity("spacious") == null);
    try std.testing.expect(parseMotion("cinematic") == null);
}

test "ui preference labels remain stable" {
    try std.testing.expectEqualStrings("Auto", themeLabel(.auto));
    try std.testing.expectEqualStrings("Dark", themeLabel(.dark));
    try std.testing.expectEqualStrings("Light", themeLabel(.light));
    try std.testing.expectEqualStrings("High contrast", themeLabel(.high_contrast));
    try std.testing.expectEqualStrings("Compact", densityLabel(.compact));
    try std.testing.expectEqualStrings("Comfortable", densityLabel(.comfortable));
    try std.testing.expectEqualStrings("Full", motionLabel(.full));
    try std.testing.expectEqualStrings("Reduced", motionLabel(.reduced));
}
