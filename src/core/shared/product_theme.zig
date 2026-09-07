const std = @import("std");

pub const Role = enum {
    brand,
    focus,
    success,
    warning,
    danger,
    text,
    muted,
    border,
};

pub const Variant = enum { dark, light, high_contrast };

pub const PaletteOptions = struct {
    truecolor: bool,
    variant: Variant,
};

pub const Palette = struct {
    brand: []const u8,
    focus: []const u8,
    success: []const u8,
    warning: []const u8,
    danger: []const u8,
    text: []const u8,
    muted: []const u8,
    border: []const u8,

    pub fn style(self: Palette, role: Role) []const u8 {
        return switch (role) {
            .brand => self.brand,
            .focus => self.focus,
            .success => self.success,
            .warning => self.warning,
            .danger => self.danger,
            .text => self.text,
            .muted => self.muted,
            .border => self.border,
        };
    }
};

const dark_truecolor = Palette{
    .brand = "\x1b[38;2;99;230;255m",
    .focus = "\x1b[38;2;181;145;255m",
    .success = "\x1b[38;2;95;220;160m",
    .warning = "\x1b[38;2;255;190;92m",
    .danger = "\x1b[38;2;255;112;112m",
    .text = "\x1b[38;2;235;239;245m",
    .muted = "\x1b[38;2;145;154;170m",
    .border = "\x1b[38;2;65;76;95m",
};

const dark_fallback = Palette{
    .brand = "\x1b[38;5;81m",
    .focus = "\x1b[38;5;141m",
    .success = "\x1b[38;5;78m",
    .warning = "\x1b[38;5;180m",
    .danger = "\x1b[38;5;203m",
    .text = "\x1b[38;5;255m",
    .muted = "\x1b[38;5;245m",
    .border = "\x1b[38;5;240m",
};

const light_truecolor = Palette{
    .brand = "\x1b[38;2;0;118;150m",
    .focus = "\x1b[38;2;105;64;175m",
    .success = "\x1b[38;2;20;125;75m",
    .warning = "\x1b[38;2;160;90;0m",
    .danger = "\x1b[38;2;190;40;40m",
    .text = "\x1b[38;2;26;32;44m",
    .muted = "\x1b[38;2;74;85;104m",
    .border = "\x1b[38;2;176;185;199m",
};

const light_fallback = Palette{
    .brand = "\x1b[38;5;30m",
    .focus = "\x1b[38;5;99m",
    .success = "\x1b[38;5;29m",
    .warning = "\x1b[38;5;136m",
    .danger = "\x1b[38;5;160m",
    .text = "\x1b[38;5;16m",
    .muted = "\x1b[38;5;238m",
    .border = "\x1b[38;5;250m",
};

const high_contrast_truecolor = Palette{
    .brand = "\x1b[1;38;2;0;220;255m",
    .focus = "\x1b[1;38;2;255;255;0m",
    .success = "\x1b[1;38;2;0;255;128m",
    .warning = "\x1b[1;38;2;255;210;0m",
    .danger = "\x1b[1;38;2;255;80;80m",
    .text = "\x1b[38;2;255;255;255m",
    .muted = "\x1b[38;2;220;220;220m",
    .border = "\x1b[1;38;2;255;255;255m",
};

const high_contrast_fallback = Palette{
    .brand = "\x1b[1;38;5;51m",
    .focus = "\x1b[1;38;5;226m",
    .success = "\x1b[1;38;5;118m",
    .warning = "\x1b[1;38;5;220m",
    .danger = "\x1b[1;38;5;196m",
    .text = "\x1b[38;5;15m",
    .muted = "\x1b[38;5;253m",
    .border = "\x1b[1;38;5;15m",
};

pub fn paletteFor(options: PaletteOptions) Palette {
    return switch (options.variant) {
        .dark => if (options.truecolor) dark_truecolor else dark_fallback,
        .light => if (options.truecolor) light_truecolor else light_fallback,
        .high_contrast => if (options.truecolor) high_contrast_truecolor else high_contrast_fallback,
    };
}

pub fn palette(truecolor: bool, light: bool) Palette {
    return paletteFor(.{
        .truecolor = truecolor,
        .variant = if (light) .light else .dark,
    });
}

pub fn style(role: Role, truecolor: bool, light: bool) []const u8 {
    return palette(truecolor, light).style(role);
}

test "Night Signal palette keeps truecolor and fallback roles stable" {
    const dark = palette(true, false);
    try std.testing.expectEqualStrings("\x1b[38;2;99;230;255m", dark.style(.brand));
    try std.testing.expectEqualStrings("\x1b[38;2;181;145;255m", dark.style(.focus));
    try std.testing.expectEqualStrings("\x1b[38;2;255;112;112m", dark.style(.danger));

    const fallback = palette(false, false);
    try std.testing.expectEqualStrings("\x1b[38;5;81m", fallback.style(.brand));
    try std.testing.expectEqualStrings("\x1b[38;5;141m", fallback.style(.focus));
    try std.testing.expectEqualStrings("\x1b[38;5;203m", fallback.style(.danger));
}

test "Night Signal light palette uses dark readable foregrounds" {
    const light = palette(true, true);
    try std.testing.expectEqualStrings("\x1b[38;2;26;32;44m", light.text);
    try std.testing.expectEqualStrings("\x1b[38;2;0;118;150m", light.brand);
    try std.testing.expectEqualStrings("\x1b[38;2;176;185;199m", light.border);
}

test "Night Signal palette exposes every semantic role" {
    const roles = [_]Role{ .brand, .focus, .success, .warning, .danger, .text, .muted, .border };
    const variants = [_]Variant{ .dark, .light, .high_contrast };
    for (variants) |variant| {
        for ([_]bool{ true, false }) |truecolor| {
            const colors = paletteFor(.{ .truecolor = truecolor, .variant = variant });
            for (roles) |role| {
                try std.testing.expect(colors.style(role).len > 0);
            }
        }
    }
}

test "Night Signal high contrast palette separates focus and text" {
    const truecolor = paletteFor(.{ .truecolor = true, .variant = .high_contrast });
    const fallback = paletteFor(.{ .truecolor = false, .variant = .high_contrast });
    try std.testing.expect(!std.mem.eql(u8, truecolor.focus, truecolor.text));
    try std.testing.expect(!std.mem.eql(u8, fallback.focus, fallback.text));
}

test "Night Signal fallback palette stays 256 color" {
    const variants = [_]Variant{ .dark, .light, .high_contrast };
    const roles = [_]Role{ .brand, .focus, .success, .warning, .danger, .text, .muted, .border };
    for (variants) |variant| {
        const colors = paletteFor(.{ .truecolor = false, .variant = variant });
        for (roles) |role| {
            const value = colors.style(role);
            try std.testing.expect(std.mem.find(u8, value, "38;2;") == null);
            try std.testing.expect(std.mem.find(u8, value, "38;5;") != null);
        }
    }
}

test "light palette keeps primary text readable" {
    const light = paletteFor(.{ .truecolor = true, .variant = .light });
    const fallback = paletteFor(.{ .truecolor = false, .variant = .light });
    try std.testing.expect(!std.mem.eql(u8, light.text, light.muted));
    try std.testing.expect(!std.mem.eql(u8, fallback.text, fallback.muted));
}
