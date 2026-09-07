const product_theme = @import("../core/shared/product_theme.zig");

/// Visual state shared by inline rows and alternate-screen surfaces.
pub const State = enum {
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

pub const Row = struct {
    style: []const u8,
    marker: []const u8,
    status_label: []const u8,
};

/// Returns allocation-free presentation tokens for one row. `marker` and
/// `status_label` intentionally retain their meaning when ANSI colors are
/// disabled, so state is never communicated by color alone.
pub fn row(palette: product_theme.Palette, state: State, color_enabled: bool) Row {
    const result = switch (state) {
        .normal => Row{ .style = palette.text, .marker = "  ", .status_label = "" },
        .hover => Row{ .style = palette.text, .marker = "> ", .status_label = "" },
        .focus => Row{ .style = palette.focus, .marker = "> ", .status_label = "selected" },
        .active => Row{ .style = palette.focus, .marker = "> ", .status_label = "active" },
        .disabled => Row{ .style = palette.muted, .marker = "  ", .status_label = "disabled" },
        .loading => Row{ .style = palette.warning, .marker = "  ", .status_label = "loading" },
        .success => Row{ .style = palette.success, .marker = "  ", .status_label = "success" },
        .warning => Row{ .style = palette.warning, .marker = "! ", .status_label = "warning" },
        .danger => Row{ .style = palette.danger, .marker = "! ", .status_label = "error" },
    };
    if (!color_enabled) return .{ .style = "", .marker = result.marker, .status_label = result.status_label };
    return result;
}
