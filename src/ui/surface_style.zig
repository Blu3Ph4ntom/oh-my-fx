const product_theme = @import("../core/shared/product_theme.zig");

/// Visual state shared by inline rows and alternate-screen surfaces.
pub const SurfaceState = enum {
    normal,
    hover,
    focus,
    active,
    disabled,
    loading,
    success,
    warning,
    danger,
};

/// Backwards-compatible name retained for early Night Signal callers.
pub const State = SurfaceState;

pub const Row = struct {
    style: []const u8,
    marker: []const u8,
    status_label: []const u8,
};

/// Returns allocation-free presentation tokens for one row. `marker` and
/// `status_label` intentionally retain their meaning when ANSI colors are
/// disabled, so state is never communicated by color alone.
pub fn rowStyle(palette: product_theme.Palette, state: SurfaceState, color_enabled: bool) []const u8 {
    if (!color_enabled) return "";
    return palette.style(styleRole(state));
}

pub fn marker(state: SurfaceState) []const u8 {
    return switch (state) {
        .normal, .disabled, .loading, .success => "  ",
        .hover, .focus, .active => "> ",
        .warning, .danger => "! ",
    };
}

pub fn statusStyle(palette: product_theme.Palette, state: SurfaceState, color_enabled: bool) []const u8 {
    return rowStyle(palette, state, color_enabled);
}

pub fn statusLabel(state: SurfaceState) []const u8 {
    return switch (state) {
        .normal, .hover => "",
        .focus => "selected",
        .active => "active",
        .disabled => "disabled",
        .loading => "loading",
        .success => "success",
        .warning => "warning",
        .danger => "error",
    };
}

pub fn hintStyle(palette: product_theme.Palette, state: SurfaceState, color_enabled: bool) []const u8 {
    if (!color_enabled) return "";
    return palette.style(switch (state) {
        .normal, .hover, .disabled => .muted,
        .focus, .active => .focus,
        .loading, .warning => .warning,
        .success => .success,
        .danger => .danger,
    });
}

/// Returns allocation-free presentation tokens for one row. `marker` and
/// `status_label` intentionally retain their meaning when ANSI colors are
/// disabled, so state is never communicated by color alone.
pub fn row(palette: product_theme.Palette, state: SurfaceState, color_enabled: bool) Row {
    return .{
        .style = rowStyle(palette, state, color_enabled),
        .marker = marker(state),
        .status_label = statusLabel(state),
    };
}

fn styleRole(state: SurfaceState) product_theme.Role {
    return switch (state) {
        .normal => .text,
        .hover, .focus, .active => .focus,
        .disabled => .muted,
        .loading, .warning => .warning,
        .success => .success,
        .danger => .danger,
    };
}
