const std = @import("std");
const types = @import("../shared/types.zig");

pub const ProviderId = enum {
    gateway,
    codex,
    grok,
    openai,
    openrouter,
    xai,
    deepseek,
    groq,
    cerebras,
    fireworks,
    together,
    mistral,
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
    if (std.ascii.eqlIgnoreCase(value, "openai")) return .openai;
    if (std.ascii.eqlIgnoreCase(value, "openrouter")) return .openrouter;
    if (std.ascii.eqlIgnoreCase(value, "xai")) return .xai;
    if (std.ascii.eqlIgnoreCase(value, "deepseek")) return .deepseek;
    if (std.ascii.eqlIgnoreCase(value, "groq")) return .groq;
    if (std.ascii.eqlIgnoreCase(value, "cerebras")) return .cerebras;
    if (std.ascii.eqlIgnoreCase(value, "fireworks")) return .fireworks;
    if (std.ascii.eqlIgnoreCase(value, "together")) return .together;
    if (std.ascii.eqlIgnoreCase(value, "mistral")) return .mistral;
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
        .openai => "OpenAI",
        .openrouter => "OpenRouter",
        .xai => "xAI",
        .deepseek => "DeepSeek",
        .groq => "Groq",
        .cerebras => "Cerebras",
        .fireworks => "Fireworks",
        .together => "Together",
        .mistral => "Mistral",
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
        .openai => selected == .openai_api_key,
        .openrouter => selected == .openrouter_api_key,
        .xai => selected == .xai_api_key,
        .deepseek => selected == .deepseek_api_key,
        .groq => selected == .groq_api_key,
        .cerebras => selected == .cerebras_api_key,
        .fireworks => selected == .fireworks_api_key,
        .together => selected == .together_api_key,
        .mistral => selected == .mistral_api_key,
        .openai_compatible => selected == .custom_provider,
        .opencode_go => selected == .opencode_go_subscription,
    };
}

pub fn usesGatewayAuxiliaries(provider: ProviderId) bool {
    return provider == .gateway;
}

pub fn isNamedCompatible(provider: ProviderId) bool {
    return switch (provider) {
        .openai,
        .openrouter,
        .xai,
        .deepseek,
        .groq,
        .cerebras,
        .fireworks,
        .together,
        .mistral,
        => true,
        else => false,
    };
}

test "explicit providers authorize only their own credential origins" {
    try std.testing.expect(authorizesCredential(.gateway, .ai_gateway_api_key));
    try std.testing.expect(authorizesCredential(.gateway, .fx_login));
    try std.testing.expect(!authorizesCredential(.gateway, .chatgpt_subscription));
    try std.testing.expect(authorizesCredential(.codex, .chatgpt_subscription));
    try std.testing.expect(!authorizesCredential(.codex, .ai_gateway_api_key));
    try std.testing.expect(!authorizesCredential(.codex, null));
    try std.testing.expect(authorizesCredential(.openai, .openai_api_key));
    try std.testing.expect(!authorizesCredential(.openai, .openrouter_api_key));
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

test "provider parsing exposes named compatible providers" {
    for ([_][]const u8{
        "openai",
        "openrouter",
        "xai",
        "deepseek",
        "groq",
        "cerebras",
        "fireworks",
        "together",
        "mistral",
    }) |name| {
        try std.testing.expect(parse(name) != null);
    }
}
