const model_provider = @import("../core/config/model_provider.zig");
const std = @import("std");
const types = @import("../core/shared/types.zig");

pub const Profile = struct {
    provider: model_provider.ProviderId,
    label: []const u8,
    api_key_env: []const u8,
    base_url: []const u8,
    credential_source: types.CredentialSource,
    missing_message: []const u8,
    missing_interactive_message: []const u8,
};

const openai = Profile{
    .provider = .openai,
    .label = "OpenAI",
    .api_key_env = "OPENAI_API_KEY",
    .base_url = "https://api.openai.com/v1",
    .credential_source = .openai_api_key,
    .missing_message = "omfx needs an OpenAI API key for this model. Set OPENAI_API_KEY.",
    .missing_interactive_message = "OpenAI needs an API key. Set OPENAI_API_KEY.",
};
const openrouter = Profile{
    .provider = .openrouter,
    .label = "OpenRouter",
    .api_key_env = "OPENROUTER_API_KEY",
    .base_url = "https://openrouter.ai/api/v1",
    .credential_source = .openrouter_api_key,
    .missing_message = "omfx needs an OpenRouter API key for this model. Set OPENROUTER_API_KEY.",
    .missing_interactive_message = "OpenRouter needs an API key. Set OPENROUTER_API_KEY.",
};
const xai = Profile{
    .provider = .xai,
    .label = "xAI",
    .api_key_env = "XAI_API_KEY",
    .base_url = "https://api.x.ai/v1",
    .credential_source = .xai_api_key,
    .missing_message = "omfx needs an xAI API key for this model. Set XAI_API_KEY.",
    .missing_interactive_message = "xAI needs an API key. Set XAI_API_KEY.",
};
const deepseek = Profile{
    .provider = .deepseek,
    .label = "DeepSeek",
    .api_key_env = "DEEPSEEK_API_KEY",
    .base_url = "https://api.deepseek.com/v1",
    .credential_source = .deepseek_api_key,
    .missing_message = "omfx needs a DeepSeek API key for this model. Set DEEPSEEK_API_KEY.",
    .missing_interactive_message = "DeepSeek needs an API key. Set DEEPSEEK_API_KEY.",
};
const groq = Profile{
    .provider = .groq,
    .label = "Groq",
    .api_key_env = "GROQ_API_KEY",
    .base_url = "https://api.groq.com/openai/v1",
    .credential_source = .groq_api_key,
    .missing_message = "omfx needs a Groq API key for this model. Set GROQ_API_KEY.",
    .missing_interactive_message = "Groq needs an API key. Set GROQ_API_KEY.",
};
const cerebras = Profile{
    .provider = .cerebras,
    .label = "Cerebras",
    .api_key_env = "CEREBRAS_API_KEY",
    .base_url = "https://api.cerebras.ai/v1",
    .credential_source = .cerebras_api_key,
    .missing_message = "omfx needs a Cerebras API key for this model. Set CEREBRAS_API_KEY.",
    .missing_interactive_message = "Cerebras needs an API key. Set CEREBRAS_API_KEY.",
};
const fireworks = Profile{
    .provider = .fireworks,
    .label = "Fireworks",
    .api_key_env = "FIREWORKS_API_KEY",
    .base_url = "https://api.fireworks.ai/inference/v1",
    .credential_source = .fireworks_api_key,
    .missing_message = "omfx needs a Fireworks API key for this model. Set FIREWORKS_API_KEY.",
    .missing_interactive_message = "Fireworks needs an API key. Set FIREWORKS_API_KEY.",
};
const together = Profile{
    .provider = .together,
    .label = "Together",
    .api_key_env = "TOGETHER_API_KEY",
    .base_url = "https://api.together.xyz/v1",
    .credential_source = .together_api_key,
    .missing_message = "omfx needs a Together API key for this model. Set TOGETHER_API_KEY.",
    .missing_interactive_message = "Together needs an API key. Set TOGETHER_API_KEY.",
};
const mistral = Profile{
    .provider = .mistral,
    .label = "Mistral",
    .api_key_env = "MISTRAL_API_KEY",
    .base_url = "https://api.mistral.ai/v1",
    .credential_source = .mistral_api_key,
    .missing_message = "omfx needs a Mistral API key for this model. Set MISTRAL_API_KEY.",
    .missing_interactive_message = "Mistral needs an API key. Set MISTRAL_API_KEY.",
};
const google = Profile{
    .provider = .google,
    .label = "Google Gemini",
    .api_key_env = "GOOGLE_API_KEY",
    .base_url = "https://generativelanguage.googleapis.com/v1beta/openai",
    .credential_source = .google_api_key,
    .missing_message = "omfx needs a Google Gemini API key for this model. Set GOOGLE_API_KEY.",
    .missing_interactive_message = "Google Gemini needs an API key. Set GOOGLE_API_KEY.",
};

pub fn forProvider(provider: model_provider.ProviderId) ?*const Profile {
    return switch (provider) {
        .openai => &openai,
        .openrouter => &openrouter,
        .xai => &xai,
        .deepseek => &deepseek,
        .groq => &groq,
        .cerebras => &cerebras,
        .fireworks => &fireworks,
        .together => &together,
        .mistral => &mistral,
        .google => &google,
        else => null,
    };
}

pub fn isNamed(provider: model_provider.ProviderId) bool {
    return forProvider(provider) != null;
}

test "named OpenAI-compatible profiles keep fixed endpoints and isolated keys" {
    const cases = [_]struct {
        provider: model_provider.ProviderId,
        base_url: []const u8,
        env: []const u8,
        source: types.CredentialSource,
    }{
        .{ .provider = .openai, .base_url = "https://api.openai.com/v1", .env = "OPENAI_API_KEY", .source = .openai_api_key },
        .{ .provider = .openrouter, .base_url = "https://openrouter.ai/api/v1", .env = "OPENROUTER_API_KEY", .source = .openrouter_api_key },
        .{ .provider = .xai, .base_url = "https://api.x.ai/v1", .env = "XAI_API_KEY", .source = .xai_api_key },
        .{ .provider = .deepseek, .base_url = "https://api.deepseek.com/v1", .env = "DEEPSEEK_API_KEY", .source = .deepseek_api_key },
        .{ .provider = .groq, .base_url = "https://api.groq.com/openai/v1", .env = "GROQ_API_KEY", .source = .groq_api_key },
        .{ .provider = .cerebras, .base_url = "https://api.cerebras.ai/v1", .env = "CEREBRAS_API_KEY", .source = .cerebras_api_key },
        .{ .provider = .fireworks, .base_url = "https://api.fireworks.ai/inference/v1", .env = "FIREWORKS_API_KEY", .source = .fireworks_api_key },
        .{ .provider = .together, .base_url = "https://api.together.xyz/v1", .env = "TOGETHER_API_KEY", .source = .together_api_key },
        .{ .provider = .mistral, .base_url = "https://api.mistral.ai/v1", .env = "MISTRAL_API_KEY", .source = .mistral_api_key },
        .{ .provider = .google, .base_url = "https://generativelanguage.googleapis.com/v1beta/openai", .env = "GOOGLE_API_KEY", .source = .google_api_key },
    };
    for (cases) |case| {
        const profile = forProvider(case.provider).?;
        try std.testing.expectEqualStrings(case.base_url, profile.base_url);
        try std.testing.expectEqualStrings(case.env, profile.api_key_env);
        try std.testing.expectEqual(case.source, profile.credential_source);
    }
}
