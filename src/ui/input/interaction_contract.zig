const std = @import("std");
const input_action = @import("../../core/input/input_action.zig");

/// Logical surfaces that may own a terminal event before the composer does.
pub const Surface = enum {
    composer,
    command_picker,
    model_picker,
    provider_picker,
    settings,
    appearance,
    statusline,
    approval,
    question,
    full_transcript,
    @"resume",
    skills,
    subagent_manager,
    terminal_takeover,
    auth,
};

/// Classification only. The owning runtime remains responsible for changing
/// state after it receives the command.
pub const Command = union(enum) {
    move_previous,
    move_next,
    move_page_up,
    move_page_down,
    submit,
    cancel,
    back,
    edit: input_action.ShortcutAction,
    ignore,
};

pub fn route(surface: Surface, event: input_action.TerminalInputEvent) ?Command {
    return switch (event) {
        .paste_byte => null,
        .raw => |raw| routeRaw(surface, raw),
        .action => |decoded| routeAction(surface, decoded.action, decoded.composer_shortcut),
    };
}

pub fn hint(surface: Surface, narrow: bool) []const u8 {
    if (narrow) return "Enter Confirm    Esc Cancel";

    return switch (surface) {
        .composer, .approval, .question => "↑↓ Move    Tab Edit       Enter Confirm    Esc Cancel",
        .command_picker,
        .model_picker,
        .provider_picker,
        .settings,
        .appearance,
        .statusline,
        .@"resume",
        .skills,
        .auth,
        => "↑↓ Move    Enter Select    Esc Cancel",
        .full_transcript, .subagent_manager, .terminal_takeover => "↑↓ Move    Esc Close",
    };
}

fn routeRaw(surface: Surface, raw: input_action.RawTerminalInput) ?Command {
    // LF is a newline only in the composer. Decide ownership before considering
    // its composer fallback, or a menu receives an editor shortcut for Enter.
    if (raw.byte == '\n' and surface != .composer) return submitFor(surface);
    if (raw.composer_shortcut) |shortcut| {
        if (surfaceAcceptsEdit(surface)) return .{ .edit = shortcut };
        return .ignore;
    }

    return switch (raw.byte) {
        '\r' => submitFor(surface),
        '\n' => if (surface == .composer)
            .{ .edit = .insert_newline }
        else
            submitFor(surface),
        else => null,
    };
}

fn routeAction(
    surface: Surface,
    action: input_action.Action,
    composer_shortcut: ?input_action.ShortcutAction,
) ?Command {
    return switch (action) {
        .history_up, .cursor_up => if (surface == .composer)
            if (composer_shortcut) |shortcut| .{ .edit = shortcut } else null
        else if (surfaceAcceptsNavigation(surface))
            .move_previous
        else
            null,
        .history_down, .cursor_down => if (surface == .composer)
            if (composer_shortcut) |shortcut| .{ .edit = shortcut } else null
        else if (surfaceAcceptsNavigation(surface))
            .move_next
        else
            null,
        .page_up => if (surfaceAcceptsNavigation(surface)) .move_page_up else null,
        .page_down => if (surfaceAcceptsNavigation(surface)) .move_page_down else null,
        .remapped_byte => |byte| routeRemappedByte(surface, byte),
        .escape => escapeFor(surface),
        .composer_shortcut => |shortcut| if (surfaceAcceptsEdit(surface))
            .{ .edit = shortcut }
        else
            .ignore,
        .insert_newline => if (surface == .composer or surface == .question)
            .{ .edit = .insert_newline }
        else
            submitFor(surface),
        else => null,
    };
}

fn routeRemappedByte(surface: Surface, byte: u8) ?Command {
    return switch (byte) {
        '\r' => submitFor(surface),
        '\n' => if (surface == .composer)
            .{ .edit = .insert_newline }
        else
            submitFor(surface),
        else => null,
    };
}

fn surfaceAcceptsEdit(surface: Surface) bool {
    return switch (surface) {
        .composer, .approval, .question => true,
        else => false,
    };
}

fn surfaceAcceptsNavigation(surface: Surface) bool {
    return switch (surface) {
        .command_picker,
        .model_picker,
        .provider_picker,
        .settings,
        .appearance,
        .statusline,
        .approval,
        .question,
        .full_transcript,
        .@"resume",
        .skills,
        .subagent_manager,
        .terminal_takeover,
        .auth,
        => true,
        .composer => false,
    };
}

fn submitFor(surface: Surface) ?Command {
    return switch (surface) {
        .composer,
        .command_picker,
        .model_picker,
        .provider_picker,
        .settings,
        .appearance,
        .statusline,
        .approval,
        .question,
        .@"resume",
        .skills,
        .auth,
        => .submit,
        .full_transcript, .subagent_manager, .terminal_takeover => .ignore,
    };
}

fn escapeFor(surface: Surface) ?Command {
    return switch (surface) {
        .command_picker,
        .model_picker,
        .provider_picker,
        .settings,
        .appearance,
        .statusline,
        .@"resume",
        .skills,
        .auth,
        => .back,
        .composer,
        .approval,
        .question,
        .full_transcript,
        .subagent_manager,
        .terminal_takeover,
        => .cancel,
    };
}

test "interaction contract maps common navigation keys" {
    const up: input_action.TerminalInputEvent = .{ .action = .{ .action = .cursor_up } };
    const down: input_action.TerminalInputEvent = .{ .action = .{ .action = .cursor_down } };
    const enter: input_action.TerminalInputEvent = .{ .action = .{ .action = .{ .remapped_byte = '\r' } } };
    const escape: input_action.TerminalInputEvent = .{ .action = .{ .action = .escape } };

    for ([_]Surface{ .command_picker, .model_picker, .settings }) |surface| {
        try std.testing.expectEqual(Command.move_previous, route(surface, up).?);
        try std.testing.expectEqual(Command.move_next, route(surface, down).?);
        try std.testing.expectEqual(Command.submit, route(surface, enter).?);
        try std.testing.expectEqual(Command.back, route(surface, escape).?);
    }

    try std.testing.expectEqual(Command.move_previous, route(.approval, up).?);
    try std.testing.expectEqual(Command.move_next, route(.question, down).?);
    try std.testing.expectEqual(Command.submit, route(.approval, enter).?);
    try std.testing.expectEqual(Command.submit, route(.question, enter).?);
}

test "interaction contract keeps surface-specific cancel behavior" {
    const escape: input_action.TerminalInputEvent = .{ .action = .{ .action = .escape } };
    try std.testing.expectEqual(Command.cancel, route(.composer, escape).?);
    try std.testing.expectEqual(Command.cancel, route(.approval, escape).?);
    try std.testing.expectEqual(Command.cancel, route(.question, escape).?);
    try std.testing.expectEqual(Command.back, route(.provider_picker, escape).?);

    const edit: input_action.ShortcutAction = .delete_backward;
    const raw: input_action.TerminalInputEvent = .{ .raw = .{
        .byte = 0x7f,
        .composer_shortcut = edit,
    } };
    try std.testing.expectEqual(
        Command{ .edit = edit },
        route(.composer, raw).?,
    );
    try std.testing.expectEqual(
        Command{ .edit = edit },
        route(.question, raw).?,
    );
    try std.testing.expectEqual(
        Command{ .edit = edit },
        route(.approval, raw).?,
    );
    try std.testing.expectEqual(Command.ignore, route(.settings, raw).?);
}

test "settings menu Enter commits selected option" {
    const enter: input_action.TerminalInputEvent = .{ .action = .{ .action = .{ .remapped_byte = '\r' } } };
    try std.testing.expectEqual(Command.submit, route(.settings, enter).?);
}

test "settings menu Escape restores previous surface" {
    const escape: input_action.TerminalInputEvent = .{ .action = .{ .action = .escape } };
    try std.testing.expectEqual(Command.back, route(.settings, escape).?);
}

test "provider picker arrows move selection" {
    const up: input_action.TerminalInputEvent = .{ .action = .{ .action = .cursor_up } };
    const down: input_action.TerminalInputEvent = .{ .action = .{ .action = .cursor_down } };
    try std.testing.expectEqual(Command.move_previous, route(.provider_picker, up).?);
    try std.testing.expectEqual(Command.move_next, route(.provider_picker, down).?);
}

test "question freeform Enter submits" {
    const enter: input_action.TerminalInputEvent = .{ .raw = .{ .byte = '\r' } };
    try std.testing.expectEqual(Command.submit, route(.question, enter).?);
}

test "interaction contract keeps hint rows compact" {
    try std.testing.expectEqualStrings("Enter Confirm    Esc Cancel", hint(.settings, true));
    try std.testing.expect(std.mem.find(u8, hint(.provider_picker, false), "Enter Select") != null);
    try std.testing.expect(std.mem.find(u8, hint(.question, false), "Tab Edit") != null);
}

test "interaction contract covers every surface without stealing domain controls" {
    const Case = struct { surface: Surface, submit: Command, escape: Command };
    const cases = [_]Case{
        .{ .surface = .composer, .submit = .submit, .escape = .cancel },
        .{ .surface = .command_picker, .submit = .submit, .escape = .back },
        .{ .surface = .model_picker, .submit = .submit, .escape = .back },
        .{ .surface = .provider_picker, .submit = .submit, .escape = .back },
        .{ .surface = .settings, .submit = .submit, .escape = .back },
        .{ .surface = .appearance, .submit = .submit, .escape = .back },
        .{ .surface = .statusline, .submit = .submit, .escape = .back },
        .{ .surface = .approval, .submit = .submit, .escape = .cancel },
        .{ .surface = .question, .submit = .submit, .escape = .cancel },
        .{ .surface = .full_transcript, .submit = .ignore, .escape = .cancel },
        .{ .surface = .@"resume", .submit = .submit, .escape = .back },
        .{ .surface = .skills, .submit = .submit, .escape = .back },
        .{ .surface = .subagent_manager, .submit = .ignore, .escape = .cancel },
        .{ .surface = .terminal_takeover, .submit = .ignore, .escape = .cancel },
        .{ .surface = .auth, .submit = .submit, .escape = .back },
    };
    try std.testing.expectEqual(@typeInfo(Surface).@"enum".fields.len, cases.len);
    for (cases) |case| {
        try std.testing.expectEqual(case.submit, route(case.surface, .{ .raw = .{ .byte = '\r' } }).?);
        try std.testing.expectEqual(case.escape, route(case.surface, .{ .action = .{ .action = .escape } }).?);
        for ([_]u8{ 3, '\t', 0 }) |byte| {
            try std.testing.expect(route(case.surface, .{ .raw = .{ .byte = byte } }) == null);
        }
        try std.testing.expect(route(case.surface, .{ .paste_byte = '\r' }) == null);
        if (case.surface == .composer) {
            try std.testing.expectEqual(Command{ .edit = .insert_newline }, route(case.surface, .{ .raw = .{ .byte = '\n', .composer_shortcut = .insert_newline } }).?);
            continue;
        }
        try std.testing.expectEqual(case.submit, route(case.surface, .{ .raw = .{ .byte = '\n', .composer_shortcut = .insert_newline } }).?);
        try std.testing.expectEqual(Command.move_previous, route(case.surface, .{ .action = .{ .action = .cursor_up } }).?);
        try std.testing.expectEqual(Command.move_next, route(case.surface, .{ .action = .{ .action = .cursor_down } }).?);
        try std.testing.expectEqual(Command.move_page_up, route(case.surface, .{ .action = .{ .action = .page_up } }).?);
        try std.testing.expectEqual(Command.move_page_down, route(case.surface, .{ .action = .{ .action = .page_down } }).?);
    }
}
