const std = @import("std");
const model_provider = @import("../core/config/model_provider.zig");
const model_catalog = @import("../core/gateway/model_catalog.zig");
const gateway_provider = @import("../core/gateway/gateway_provider.zig");
const stream_provider = @import("../core/agent/stream_provider.zig");
const gateway = @import("gateway.zig");
const openai_codex = @import("../gateway/openai_codex.zig");
const openai_codex_models = @import("../gateway/openai_codex_models.zig");
const xai_grok = @import("../gateway/xai_grok.zig");
const xai_grok_models = @import("../gateway/xai_grok_models.zig");
const openai_compat = @import("../gateway/openai_compat.zig");
const openai_compat_models = @import("../gateway/openai_compat_models.zig");
const opencode_go = @import("../gateway/opencode_go.zig");
const opencode_go_models = @import("../gateway/opencode_go_models.zig");

pub const opencode_go_cli_model_catalog = gateway_provider.CliModelCatalogProvider{
    .fetch_fn = fetchOpenCodeGoCliModelCatalog,
};

fn fetchOpenCodeGoCliModelCatalog(
    _: ?*anyopaque,
    alloc: std.mem.Allocator,
    input: gateway_provider.CliModelCatalogInput,
) gateway_provider.CliModelCatalogResult {
    return switch (model_catalog.fetchWithPublicFallback(opencode_go_models.model_catalog_provider, alloc, .{
        .access = input.access,
        .endpoint = input.endpoint,
        .cancel_flag = input.cancel_flag,
        .view = .full,
    })) {
        .loaded => |loaded| blk: {
            var catalog = loaded.catalog;
            defer model_catalog.freeModelCatalog(alloc, &catalog);
            const ids = model_catalog.projectModelIds(alloc, catalog.items) catch return .{ .failure = .{
                .access = loaded.provenance.access,
                .anonymous_fallback_used = loaded.provenance.anonymous_fallback_used,
                .failure = .{ .category = .resource_exhausted },
            } };
            break :blk .{ .loaded = .{
                .ids = ids,
                .provenance = loaded.provenance,
            } };
        },
        .failed => |failure| .{ .failure = failure },
    };
}

pub fn agentStream(provider: model_provider.ProviderId) stream_provider.Provider {
    return switch (provider) {
        .gateway => gateway.agent_stream_provider,
        .codex => openai_codex.agent_stream_provider,
        .grok => xai_grok.agent_stream_provider,
        .openai_compatible => openai_compat.agent_stream_provider,
        .opencode_go => opencode_go.agent_stream_provider,
    };
}

pub fn modelCatalog(provider: model_provider.ProviderId) model_catalog.Provider {
    return switch (provider) {
        .gateway => gateway.model_catalog_provider,
        .codex => openai_codex_models.model_catalog_provider,
        .grok => xai_grok_models.model_catalog_provider,
        .openai_compatible => openai_compat_models.model_catalog_provider,
        .opencode_go => opencode_go_models.model_catalog_provider,
    };
}
