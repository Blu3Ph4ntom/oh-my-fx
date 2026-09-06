test {
    _ = @import("core/auth/auth_runtime.zig");
    _ = @import("core/app/app_auth_runtime.zig");
    _ = @import("core/shared/io.zig");
    _ = @import("gateway/openai.zig");
    _ = @import("gateway/opencode_go.zig");
    _ = @import("gateway/opencode_go_models.zig");
    _ = @import("gateway/openai_codex.zig");
    _ = @import("gateway/openai_codex_models.zig");
    _ = @import("core/config/model_provider.zig");
    _ = @import("ui/input/terminal_action_decoder.zig");
}
