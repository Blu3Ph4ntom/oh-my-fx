const std = @import("std");
const product_theme = @import("../core/shared/product_theme.zig");
const surface_style = @import("surface_style.zig");

test "omfx surface states map every role across palette capabilities" {
    const Contract = struct {
        state: surface_style.SurfaceState,
        row_role: product_theme.Role,
        hint_role: product_theme.Role,
        marker: []const u8,
        status_label: []const u8,
    };
    const contracts = [_]Contract{
        .{ .state = .normal, .row_role = .text, .hint_role = .muted, .marker = "  ", .status_label = "" },
        .{ .state = .hover, .row_role = .focus, .hint_role = .muted, .marker = "> ", .status_label = "" },
        .{ .state = .focus, .row_role = .focus, .hint_role = .focus, .marker = "> ", .status_label = "selected" },
        .{ .state = .active, .row_role = .focus, .hint_role = .focus, .marker = "> ", .status_label = "active" },
        .{ .state = .disabled, .row_role = .muted, .hint_role = .muted, .marker = "  ", .status_label = "disabled" },
        .{ .state = .loading, .row_role = .warning, .hint_role = .warning, .marker = "  ", .status_label = "loading" },
        .{ .state = .success, .row_role = .success, .hint_role = .success, .marker = "  ", .status_label = "success" },
        .{ .state = .warning, .row_role = .warning, .hint_role = .warning, .marker = "! ", .status_label = "warning" },
        .{ .state = .danger, .row_role = .danger, .hint_role = .danger, .marker = "! ", .status_label = "error" },
    };
    const variants = [_]product_theme.Variant{ .dark, .light, .high_contrast };
    for (variants) |variant| {
        for ([_]bool{ true, false }) |truecolor| {
            const palette = product_theme.paletteFor(.{ .truecolor = truecolor, .variant = variant });
            for (contracts) |contract| {
                try std.testing.expectEqualStrings(palette.style(contract.row_role), surface_style.rowStyle(palette, contract.state, true));
                try std.testing.expectEqualStrings(palette.style(contract.row_role), surface_style.statusStyle(palette, contract.state, true));
                try std.testing.expectEqualStrings(palette.style(contract.hint_role), surface_style.hintStyle(palette, contract.state, true));
                try std.testing.expectEqualStrings(contract.marker, surface_style.marker(contract.state));
                try std.testing.expectEqualStrings(contract.status_label, surface_style.statusLabel(contract.state));
            }
        }
    }
}

test "omfx surface states retain visible markers and labels without color" {
    const palette = product_theme.paletteFor(.{ .truecolor = false, .variant = .dark });
    const states = [_]surface_style.SurfaceState{ .normal, .hover, .focus, .active, .disabled, .loading, .success, .warning, .danger };
    for (states) |state| {
        const styled_row = surface_style.row(palette, state, false);
        try std.testing.expectEqualStrings("", surface_style.rowStyle(palette, state, false));
        try std.testing.expectEqualStrings("", surface_style.statusStyle(palette, state, false));
        try std.testing.expectEqualStrings("", surface_style.hintStyle(palette, state, false));
        try std.testing.expectEqualStrings(surface_style.marker(state), styled_row.marker);
        try std.testing.expectEqualStrings(surface_style.statusLabel(state), styled_row.status_label);
        if (state != .normal) {
            try std.testing.expect(surface_style.marker(state).len > 0 or surface_style.statusLabel(state).len > 0);
        }
    }
}
