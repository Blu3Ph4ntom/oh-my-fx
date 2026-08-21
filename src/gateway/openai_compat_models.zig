const std = @import("std");
const Allocator = std.mem.Allocator;

const model_catalog = @import("../core/gateway/model_catalog.zig");

/// OpenAI-compatible provider does not require a remote model catalog.
/// We return an empty catalog; the provider works with arbitrary model IDs.
/// The model is passed through unchanged, and capabilities are default-safe.
pub const model_catalog_provider = model_catalog.Provider{
    .fetch_fn = fetchCatalog,
};

fn fetchCatalog(
    _: ?*anyopaque,
    alloc: Allocator,
    input: model_catalog.FetchInput,
) Allocator.Error!model_catalog.ProviderResult {
    _ = input;
    _ = alloc;
    // Return an empty catalog — the provider works with any model ID.
    // This satisfies the catalog contract without requiring a Vercel catalog.
    const entries: std.ArrayList(model_catalog.ModelCatalogEntry) = .empty;
    return .{ .catalog = entries };
}
