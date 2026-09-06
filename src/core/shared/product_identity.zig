/// Stable public identity for the omfx command-line product.
///
/// Compatibility names are intentionally kept next to the public values so
/// presentation code cannot accidentally turn a migration into a storage or
/// protocol change.
pub const name = "omfx";
pub const command = "omfx";
pub const compatibility_command = "fx";
pub const website = "https://fx.sh";
pub const docs_url = "https://fx.sh/docs";
pub const codex_protocol_originator = "codex_cli_rs";

test "omfx identity contract" {
    const std = @import("std");

    try std.testing.expectEqualStrings("omfx", name);
    try std.testing.expectEqualStrings("omfx", command);
    try std.testing.expectEqualStrings("fx", compatibility_command);
    try std.testing.expectEqualStrings("codex_cli_rs", codex_protocol_originator);
}
