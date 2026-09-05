const std = @import("std");
const types = @import("../shared/types.zig");

pub const ProviderId = enum {
    gateway,
    codex,
    grok,
    openai_compatible,
    opencode_go,
};

pub const ProviderSelection = struct {
    provider: ProviderId,
    model: []const u8,
};

pub fn parse(value: []const u8) ?ProviderId {
    if (std.ascii.eqlIgnoreCase(value, "gateway")) return .gateway;
    if (std.ascii.eqlIgnoreCase(value, "codex")) return .codex;
    if (std.ascii.eqlIgnoreCase(value, "grok")) return .grok;
    if (std.ascii.eqlIgnoreCase(value, "openai_compatible")) return .openai_compatible;
    if (std.ascii.eqlIgnoreCase(value, "openai-compatible")) return .openai_compatible;
    if (std.ascii.eqlIgnoreCase(value, "opencode_go")) return .opencode_go;
    if (std.ascii.eqlIgnoreCase(value, "opencode-go")) return .opencode_go;
    return null;
}

pub fn label(provider: ProviderId) []const u8 {
    return switch (provider) {
        .gateway => "Vercel AI Gateway",
        .codex => "Codex subscription",
        .grok => "Grok subscription",
        .openai_compatible => "OpenAI-compatible",
        .opencode_go => "OpenCode Go subscription",
    };
}

pub fn authorizesCredential(provider: ProviderId, source: ?types.CredentialSource) bool {
    const selected = source orelse return false;
    return switch (provider) {
        .gateway => selected == .ai_gateway_api_key or selected == .fx_login or selected == .vercel_oidc_token or selected == .stored_key,
        .codex => selected == .chatgpt_subscription,
        .grok => selected == .grok_subscription,
        .openai_compatible => selected == .custom_provider,
        .opencode_go => selected == .opencode_go_subscription,
    };
}

pub fn usesGatewayAuxiliaries(provider: ProviderId) bool {
    return provider == .gateway;
}

test "explicit providers authorize only their own credential origins" {
    try std.testing.expect(authorizesCredential(.gateway, .ai_gateway_api_key));
    try std.testing.expect(authorizesCredential(.gateway, .fx_login));
    try std.testing.expect(!authorizesCredential(.gateway, .chatgpt_subscription));
    try std.testing.expect(authorizesCredential(.codex, .chatgpt_subscription));
    try std.testing.expect(!authorizesCredential(.codex, .ai_gateway_api_key));
    try std.testing.expect(!authorizesCredential(.codex, null));
}

test "provider parsing exposes only gateway and codex" {
    try std.testing.expectEqual(ProviderId.gateway, parse("gateway").?);
    try std.testing.expectEqual(ProviderId.codex, parse("CODEX").?);
    try std.testing.expectEqual(ProviderId.grok, parse("GROK").?);
    try std.testing.expectEqual(ProviderId.openai_compatible, parse("openai_compatible").?);
    try std.testing.expectEqual(ProviderId.openai_compatible, parse("openai-compatible").?);
    try std.testing.expectEqual(ProviderId.opencode_go, parse("opencode_go").?);
    try std.testing.expectEqual(ProviderId.opencode_go, parse("opencode-go").?);
    try std.testing.expect(parse("openai-codex") == null);
    try std.testing.expect(parse("") == null);
}
