const std = @import("std");
const builtin = @import("builtin");
const io_mod = @import("io.zig");

const Allocator = std.mem.Allocator;

pub const root_dir_name = ".fx";
pub const auth_file_name = "auth.json";
pub const chatgpt_auth_file_name = "chatgpt-auth.json";
pub const grok_auth_file_name = "grok-auth.json";
pub const api_key_file_name = "api-key";
pub const sessions_dir_name = "sessions";
pub const prompt_history_file_name = "history.jsonl";
pub const usage_file_name = "usage.jsonl";
pub const usage_recovery_dir_name = "usage-recovery";
pub const backups_dir_name = "backups";
pub const mcp_credentials_dir_name = "mcp-credentials";
pub const mcp_credentials_file_name = "credentials.json";

const settings_file_name = "settings.json";
const mcp_config_file_name = "mcp.json";
const managed_skills_dir_name = "skills";
const memories_file_name = "memories.json";
const logs_dir_name = "logs";
const trace_log_file_name = "trace.log";
const recordings_dir_name = "recordings";

fn rootDirWithOverride(alloc: Allocator, home: []const u8, override: ?[]const u8) ![]u8 {
    if (override) |path| {
        if (path.len == 0 or !std.fs.path.isAbsolute(path)) return error.InvalidPath;
        return alloc.dupe(u8, path);
    }
    return std.fs.path.join(alloc, &.{ home, root_dir_name });
}

pub fn rootDir(alloc: Allocator, home: []const u8) ![]u8 {
    return rootDirWithOverride(alloc, home, io_mod.getenv("OMFX_HOME"));
}

pub fn settingsPath(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, settings_file_name });
}

pub fn mcpConfigPath(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, mcp_config_file_name });
}

pub fn mcpCredentialsDir(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, mcp_credentials_dir_name });
}

pub fn mcpCredentialsPath(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, mcp_credentials_dir_name, mcp_credentials_file_name });
}

pub fn managedSkillsDir(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, managed_skills_dir_name });
}

pub fn authPath(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, auth_file_name });
}

pub fn chatgptAuthPath(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, chatgpt_auth_file_name });
}

pub fn apiKeyPath(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, api_key_file_name });
}

pub fn sessionsDir(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, sessions_dir_name });
}

pub fn promptHistoryPath(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, prompt_history_file_name });
}

pub fn memoriesPath(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, memories_file_name });
}

pub fn backupsDir(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, backups_dir_name });
}

pub fn logsDir(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, logs_dir_name });
}

pub fn traceLogPath(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, logs_dir_name, trace_log_file_name });
}

pub fn recordingsDir(alloc: Allocator, home: []const u8) ![]u8 {
    const root = try rootDir(alloc, home);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, recordings_dir_name });
}

test "profile path helpers preserve current default locations" {
    const alloc = std.testing.allocator;

    const root = try rootDir(alloc, "/tmp/fake-home");
    defer alloc.free(root);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx", root);

    const settings = try settingsPath(alloc, "/tmp/fake-home");
    defer alloc.free(settings);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx/settings.json", settings);

    const mcp = try mcpConfigPath(alloc, "/tmp/fake-home");
    defer alloc.free(mcp);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx/mcp.json", mcp);

    const mcp_credentials_dir = try mcpCredentialsDir(alloc, "/tmp/fake-home");
    defer alloc.free(mcp_credentials_dir);
    try std.testing.expectEqualStrings(
        "/tmp/fake-home/.fx/mcp-credentials",
        mcp_credentials_dir,
    );

    const mcp_credentials = try mcpCredentialsPath(alloc, "/tmp/fake-home");
    defer alloc.free(mcp_credentials);
    try std.testing.expectEqualStrings(
        "/tmp/fake-home/.fx/mcp-credentials/credentials.json",
        mcp_credentials,
    );

    const skills = try managedSkillsDir(alloc, "/tmp/fake-home");
    defer alloc.free(skills);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx/skills", skills);

    const auth = try authPath(alloc, "/tmp/fake-home");
    defer alloc.free(auth);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx/auth.json", auth);

    const chatgpt_auth = try chatgptAuthPath(alloc, "/tmp/fake-home");
    defer alloc.free(chatgpt_auth);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx/chatgpt-auth.json", chatgpt_auth);

    const api_key = try apiKeyPath(alloc, "/tmp/fake-home");
    defer alloc.free(api_key);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx/api-key", api_key);

    const sessions = try sessionsDir(alloc, "/tmp/fake-home");
    defer alloc.free(sessions);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx/sessions", sessions);

    const history = try promptHistoryPath(alloc, "/tmp/fake-home");
    defer alloc.free(history);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx/history.jsonl", history);

    const memories = try memoriesPath(alloc, "/tmp/fake-home");
    defer alloc.free(memories);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx/memories.json", memories);

    const backups = try backupsDir(alloc, "/tmp/fake-home");
    defer alloc.free(backups);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx/backups", backups);

    const logs = try logsDir(alloc, "/tmp/fake-home");
    defer alloc.free(logs);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx/logs", logs);

    const trace = try traceLogPath(alloc, "/tmp/fake-home");
    defer alloc.free(trace);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx/logs/trace.log", trace);

    const recordings = try recordingsDir(alloc, "/tmp/fake-home");
    defer alloc.free(recordings);
    try std.testing.expectEqualStrings("/tmp/fake-home/.fx/recordings", recordings);
}

test "OMFX_HOME overrides legacy profile root" {
    const alloc = std.testing.allocator;
    const override = if (builtin.os.tag == .windows)
        "C:\\omfx-profile"
    else
        "/tmp/omfx-profile";

    const root = try rootDirWithOverride(
        alloc,
        "/tmp/fake-home",
        override,
    );
    defer alloc.free(root);
    try std.testing.expectEqualStrings(override, root);
}
