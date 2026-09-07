const std = @import("std");
const product_theme = @import("../core/shared/product_theme.zig");
const surface_style = @import("surface_style.zig");

test "omfx surface states keep focus visible without color" {
    const palette = product_theme.paletteFor(.{ .truecolor = false, .variant = .dark });
    const focused = surface_style.row(palette, .focus, true);
    const focused_no_color = surface_style.row(palette, .focus, false);

    try std.testing.expectEqualStrings("> ", focused.marker);
    try std.testing.expectEqualStrings(palette.focus, focused.style);
    try std.testing.expectEqualStrings("selected", focused.status_label);
    try std.testing.expectEqualStrings("> ", focused_no_color.marker);
    try std.testing.expectEqualStrings("", focused_no_color.style);
    try std.testing.expectEqualStrings("selected", focused_no_color.status_label);
}

test "omfx surface states map status feedback to semantic roles" {
    const palette = product_theme.paletteFor(.{ .truecolor = true, .variant = .dark });

    const normal = surface_style.row(palette, .normal, true);
    const disabled = surface_style.row(palette, .disabled, true);
    const loading = surface_style.row(palette, .loading, true);
    const success = surface_style.row(palette, .success, true);
    const warning = surface_style.row(palette, .warning, true);
    const danger = surface_style.row(palette, .danger, true);

    try std.testing.expectEqualStrings("  ", normal.marker);
    try std.testing.expectEqualStrings(palette.text, normal.style);
    try std.testing.expectEqualStrings("", normal.status_label);
    try std.testing.expectEqualStrings(palette.muted, disabled.style);
    try std.testing.expectEqualStrings("disabled", disabled.status_label);
    try std.testing.expectEqualStrings(palette.warning, loading.style);
    try std.testing.expectEqualStrings("loading", loading.status_label);
    try std.testing.expectEqualStrings(palette.success, success.style);
    try std.testing.expectEqualStrings("success", success.status_label);
    try std.testing.expectEqualStrings(palette.warning, warning.style);
    try std.testing.expectEqualStrings("warning", warning.status_label);
    try std.testing.expectEqualStrings(palette.danger, danger.style);
    try std.testing.expectEqualStrings("error", danger.status_label);
}

test "omfx surface state styles support every palette variant" {
    const variants = [_]product_theme.Variant{ .dark, .light, .high_contrast };
    for (variants) |variant| {
        const palette = product_theme.paletteFor(.{ .truecolor = false, .variant = variant });
        const states = [_]surface_style.State{ .normal, .focus, .disabled, .loading, .success, .warning, .danger };
        for (states) |state| {
            const row = surface_style.row(palette, state, true);
            try std.testing.expect(row.style.len > 0);
            if (state != .normal) try std.testing.expect(row.status_label.len > 0);
        }
    }
}
