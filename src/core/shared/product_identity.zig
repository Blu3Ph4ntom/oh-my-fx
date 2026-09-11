/// Stable public identity for the omfx command-line product.
///
/// Compatibility names are intentionally kept next to the public values so
/// presentation code cannot accidentally turn a migration into a storage or
/// protocol change.
pub const name = "omfx";
pub const command = "omfx";
pub const compatibility_command = "fx";
pub const website = "https://blu3ph4ntom.github.io/oh-my-fx/";
pub const docs_url = website;
pub const upstream_website = "https://fx.sh";
pub const upstream_docs_url = "https://fx.sh/docs";
pub const upstream_llms_txt = "https://fx.sh/llms.txt";
pub const codex_protocol_originator = "fx";

test "omfx identity contract" {
    const std = @import("std");

    try std.testing.expectEqualStrings("omfx", name);
    try std.testing.expectEqualStrings("omfx", command);
    try std.testing.expectEqualStrings("fx", compatibility_command);
    try std.testing.expectEqualStrings("https://blu3ph4ntom.github.io/oh-my-fx/", website);
    try std.testing.expectEqualStrings(website, docs_url);
    try std.testing.expectEqualStrings("https://fx.sh", upstream_website);
    try std.testing.expectEqualStrings("https://fx.sh/docs", upstream_docs_url);
    try std.testing.expectEqualStrings("https://fx.sh/llms.txt", upstream_llms_txt);
    try std.testing.expectEqualStrings("fx", codex_protocol_originator);
}
