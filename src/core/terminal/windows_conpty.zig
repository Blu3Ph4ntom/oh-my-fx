const std = @import("std");
const builtin = @import("builtin");
const contracts = @import("contracts.zig");

const Allocator = std.mem.Allocator;
const is_windows = builtin.os.tag == .windows;

const pipe_buffer_bytes: u32 = 128 * 1024;
const max_command_line_bytes: usize = contracts.max_command_bytes * 2 +
    contracts.max_shell_path_bytes +
    4096;

/// A Windows-native pseudoterminal. ConPTY owns the console state and
/// exposes UTF-8 VT bytes through the two parent-side pipe handles.
pub const Pty = struct {
    state: *State,

    pub fn spawn(
        alloc: Allocator,
        argv: []const []const u8,
        cwd: []const u8,
        dimensions: contracts.Dimensions,
    ) !Pty {
        if (comptime !is_windows) return error.TerminalHostUnsupported;
        if (argv.len == 0) return error.InvalidCommand;
        for (argv) |arg| {
            if (std.mem.findScalar(u8, arg, 0) != null) {
                return error.InvalidCommand;
            }
        }
        try dimensions.validate();

        var arena_state = std.heap.ArenaAllocator.init(alloc);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const command_line = try commandLineW(arena, argv);
        const application = try wideSentinel(arena, argv[0]);
        const directory = try wideSentinel(arena, cwd);

        var input_read: win.HANDLE = undefined;
        var input_write: win.HANDLE = undefined;
        if (win.CreatePipe(&input_read, &input_write, null, pipe_buffer_bytes) == 0) {
            return error.PipeUnavailable;
        }
        errdefer {
            _ = win.CloseHandle(input_read);
            _ = win.CloseHandle(input_write);
        }

        var output_read: win.HANDLE = undefined;
        var output_write: win.HANDLE = undefined;
        if (win.CreatePipe(&output_read, &output_write, null, pipe_buffer_bytes) == 0) {
            return error.PipeUnavailable;
        }
        errdefer {
            _ = win.CloseHandle(output_read);
            _ = win.CloseHandle(output_write);
        }

        var hpc: win.HPCON = undefined;
        const size = win.COORD{
            .X = @intCast(@min(dimensions.columns, 32767)),
            .Y = @intCast(@min(dimensions.rows, 32767)),
        };
        const create_result = win.CreatePseudoConsole(
            size,
            input_read,
            output_write,
            0,
            &hpc,
        );
        _ = win.CloseHandle(input_read);
        input_read = win.INVALID_HANDLE_VALUE;
        _ = win.CloseHandle(output_write);
        output_write = win.INVALID_HANDLE_VALUE;
        if (create_result < 0) return error.PseudoConsoleUnavailable;
        var console_open = true;
        errdefer if (console_open) win.ClosePseudoConsole(hpc);

        var attribute_bytes: usize = 0;
        _ = win.InitializeProcThreadAttributeList(null, 1, 0, &attribute_bytes);
        const attribute_list = try arena.alignedAlloc(
            u8,
            .of(usize),
            attribute_bytes,
        );
        if (win.InitializeProcThreadAttributeList(
            attribute_list.ptr,
            1,
            0,
            &attribute_bytes,
        ) == 0) return error.AttributeListUnavailable;
        defer win.DeleteProcThreadAttributeList(attribute_list.ptr);
        if (win.UpdateProcThreadAttribute(
            attribute_list.ptr,
            0,
            win.PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
            @ptrCast(&hpc),
            @sizeOf(win.HPCON),
            null,
            null,
        ) == 0) return error.AttributeListUnavailable;

        var startup = std.mem.zeroes(win.STARTUPINFOEXW);
        startup.StartupInfo.cb = @sizeOf(win.STARTUPINFOEXW);
        startup.lpAttributeList = attribute_list.ptr;
        var process_info = std.mem.zeroes(win.PROCESS_INFORMATION);
        if (win.CreateProcessW(
            application,
            command_line.ptr,
            null,
            null,
            0,
            win.EXTENDED_STARTUPINFO_PRESENT | win.CREATE_UNICODE_ENVIRONMENT,
            null,
            directory.ptr,
            &startup.StartupInfo,
            &process_info,
        ) == 0) {
            return mapCreateProcessError(lastError());
        }
        _ = win.CloseHandle(process_info.hThread);

        const state = try std.heap.page_allocator.create(State);
        state.* = .{
            .hpc = hpc,
            .process = process_info.hProcess,
            .process_id = process_info.dwProcessId,
            .out_read = output_read,
            .in_write = input_write,
        };
        console_open = false;
        output_read = win.INVALID_HANDLE_VALUE;
        input_write = win.INVALID_HANDLE_VALUE;
        return .{ .state = state };
    }

    /// Blocks until ConPTY produces bytes or teardown breaks its pipe.
    pub fn read(self: Pty, destination: []u8) !usize {
        if (comptime !is_windows) return error.TerminalHostUnsupported;
        if (destination.len == 0) return 0;
        var count: win.DWORD = 0;
        if (win.ReadFile(
            self.state.out_read,
            destination.ptr,
            @intCast(@min(destination.len, std.math.maxInt(win.DWORD))),
            &count,
            null,
        ) != 0) return @intCast(count);
        return switch (lastError()) {
            win.ERROR_BROKEN_PIPE,
            win.ERROR_PIPE_NOT_CONNECTED,
            win.ERROR_HANDLE_EOF,
            => 0,
            else => error.ReadFailed,
        };
    }

    pub fn writeAll(self: Pty, bytes: []const u8) !void {
        if (comptime !is_windows) return error.TerminalHostUnsupported;
        var offset: usize = 0;
        while (offset < bytes.len) {
            const take = @min(bytes.len - offset, 16 * 1024);
            var written: win.DWORD = 0;
            if (win.WriteFile(
                self.state.in_write,
                bytes[offset .. offset + take].ptr,
                @intCast(take),
                &written,
                null,
            ) == 0) return error.WriteFailed;
            if (written == 0) return error.WriteFailed;
            offset += @intCast(written);
        }
    }

    pub fn pid(self: Pty) u32 {
        return self.state.process_id;
    }

    pub fn resize(self: Pty, dimensions: contracts.Dimensions) !void {
        if (comptime !is_windows) return error.TerminalHostUnsupported;
        try dimensions.validate();
        const size = win.COORD{
            .X = @intCast(@min(dimensions.columns, 32767)),
            .Y = @intCast(@min(dimensions.rows, 32767)),
        };
        self.state.lock.lock();
        defer self.state.lock.unlock();
        if (self.state.console_closed) return;
        if (win.ResizePseudoConsole(self.state.hpc, size) < 0) {
            return error.ResizeFailed;
        }
    }

    pub fn kill(self: Pty) void {
        if (comptime !is_windows) return;
        _ = win.TerminateProcess(self.state.process, 1);
    }

    /// The process handle is the authoritative Windows lifecycle signal.
    /// Closing the pseudoconsole after it exits manufactures EOF for the
    /// reader and also tears down console-attached descendants.
    pub fn waitBlocking(self: Pty) u32 {
        if (comptime !is_windows) return 1;
        _ = win.WaitForSingleObject(self.state.process, win.INFINITE);
        var code: win.DWORD = 1;
        if (win.GetExitCodeProcess(self.state.process, &code) == 0) code = 1;
        self.closeConsole();
        return code;
    }

    pub fn close(self: Pty) void {
        if (comptime !is_windows) return;
        const state = self.state;
        self.closeConsole();
        if (state.out_read != win.INVALID_HANDLE_VALUE) {
            _ = win.CloseHandle(state.out_read);
            state.out_read = win.INVALID_HANDLE_VALUE;
        }
        if (state.in_write != win.INVALID_HANDLE_VALUE) {
            _ = win.CloseHandle(state.in_write);
            state.in_write = win.INVALID_HANDLE_VALUE;
        }
        if (state.process != win.INVALID_HANDLE_VALUE) {
            _ = win.CloseHandle(state.process);
            state.process = win.INVALID_HANDLE_VALUE;
        }
        std.heap.page_allocator.destroy(state);
    }

    fn closeConsole(self: Pty) void {
        self.state.lock.lock();
        if (self.state.console_closed) {
            self.state.lock.unlock();
            return;
        }
        self.state.console_closed = true;
        const hpc = self.state.hpc;
        self.state.lock.unlock();
        win.ClosePseudoConsole(hpc);
    }
};

const State = struct {
    hpc: win.HPCON,
    process: win.HANDLE,
    process_id: u32,
    out_read: win.HANDLE,
    in_write: win.HANDLE,
    lock: SpinLock = .{},
    console_closed: bool = false,
};

const SpinLock = struct {
    locked: std.atomic.Value(bool) = .init(false),

    fn lock(self: *SpinLock) void {
        while (self.locked.swap(true, .acquire)) std.atomic.spinLoopHint();
    }

    fn unlock(self: *SpinLock) void {
        self.locked.store(false, .release);
    }
};

fn commandLineW(arena: Allocator, argv: []const []const u8) ![:0]u16 {
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(arena);
    for (argv, 0..) |arg, index| {
        if (index != 0) try line.append(arena, ' ');
        try appendQuotedArg(arena, &line, arg);
    }
    if (line.items.len > max_command_line_bytes) return error.CommandLineTooLong;
    return try wideSentinel(arena, line.items);
}

fn appendQuotedArg(
    arena: Allocator,
    line: *std.ArrayList(u8),
    arg: []const u8,
) !void {
    try line.append(arena, '"');
    var backslashes: usize = 0;
    for (arg) |byte| {
        if (byte == '\\') {
            backslashes += 1;
            continue;
        }
        if (byte == '"') {
            try appendRepeated(arena, line, '\\', backslashes * 2 + 1);
            try line.append(arena, '"');
            backslashes = 0;
            continue;
        }
        try appendRepeated(arena, line, '\\', backslashes);
        backslashes = 0;
        try line.append(arena, byte);
    }
    try appendRepeated(arena, line, '\\', backslashes * 2);
    try line.append(arena, '"');
}

fn appendRepeated(
    arena: Allocator,
    line: *std.ArrayList(u8),
    byte: u8,
    count: usize,
) !void {
    try line.appendNTimes(arena, byte, count);
}

fn wideSentinel(arena: Allocator, value: []const u8) ![:0]u16 {
    const length = std.unicode.calcWtf16LeLen(value) catch return error.InvalidCommand;
    const result = try arena.allocSentinel(u16, length, 0);
    _ = std.unicode.wtf8ToWtf16Le(result, value) catch return error.InvalidCommand;
    return result;
}

fn mapCreateProcessError(code: u32) anyerror {
    return switch (code) {
        win.ERROR_FILE_NOT_FOUND,
        win.ERROR_PATH_NOT_FOUND,
        win.ERROR_ACCESS_DENIED,
        win.ERROR_BAD_EXE_FORMAT,
        win.ERROR_INVALID_NAME,
        win.ERROR_DIRECTORY,
        => error.CommandNotFound,
        else => error.ProcessUnavailable,
    };
}

fn lastError() u32 {
    return @intFromEnum(std.os.windows.GetLastError());
}

const win = struct {
    const HANDLE = std.os.windows.HANDLE;
    const HPCON = *anyopaque;
    const DWORD = u32;
    const BOOL = i32;
    const HRESULT = i32;
    const COORD = extern struct { X: i16, Y: i16 };
    const SECURITY_ATTRIBUTES = std.os.windows.SECURITY_ATTRIBUTES;
    const STARTUPINFOW = std.os.windows.STARTUPINFOW;
    const STARTUPINFOEXW = extern struct {
        StartupInfo: STARTUPINFOW,
        lpAttributeList: ?*anyopaque,
    };
    const PROCESS_INFORMATION = extern struct {
        hProcess: HANDLE,
        hThread: HANDLE,
        dwProcessId: DWORD,
        dwThreadId: DWORD,
    };

    const INVALID_HANDLE_VALUE = std.os.windows.INVALID_HANDLE_VALUE;
    const GENERIC_READ: DWORD = 0x8000_0000;
    const GENERIC_WRITE: DWORD = 0x4000_0000;
    const EXTENDED_STARTUPINFO_PRESENT: DWORD = 0x0008_0000;
    const CREATE_UNICODE_ENVIRONMENT: DWORD = 0x0000_0400;
    const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: usize = 0x0002_0016;
    const STARTF_USESTDHANDLES: DWORD = 0x100;
    const INFINITE: DWORD = 0xFFFF_FFFF;
    const ERROR_FILE_NOT_FOUND: u32 = 2;
    const ERROR_PATH_NOT_FOUND: u32 = 3;
    const ERROR_ACCESS_DENIED: u32 = 5;
    const ERROR_HANDLE_EOF: u32 = 38;
    const ERROR_BROKEN_PIPE: u32 = 109;
    const ERROR_INVALID_NAME: u32 = 123;
    const ERROR_BAD_EXE_FORMAT: u32 = 193;
    const ERROR_PIPE_NOT_CONNECTED: u32 = 233;
    const ERROR_DIRECTORY: u32 = 267;

    extern "kernel32" fn CreatePipe(
        hReadPipe: *HANDLE,
        hWritePipe: *HANDLE,
        lpPipeAttributes: ?*SECURITY_ATTRIBUTES,
        nSize: DWORD,
    ) callconv(.winapi) BOOL;
    extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;
    extern "kernel32" fn ReadFile(
        hFile: HANDLE,
        lpBuffer: [*]u8,
        nNumberOfBytesToRead: DWORD,
        lpNumberOfBytesRead: ?*DWORD,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) BOOL;
    extern "kernel32" fn WriteFile(
        hFile: HANDLE,
        lpBuffer: [*]const u8,
        nNumberOfBytesToWrite: DWORD,
        lpNumberOfBytesWritten: ?*DWORD,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) BOOL;
    extern "kernel32" fn WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD) callconv(.winapi) DWORD;
    extern "kernel32" fn TerminateProcess(hProcess: HANDLE, uExitCode: DWORD) callconv(.winapi) BOOL;
    extern "kernel32" fn GetExitCodeProcess(hProcess: HANDLE, lpExitCode: *DWORD) callconv(.winapi) BOOL;
    extern "kernel32" fn InitializeProcThreadAttributeList(
        lpAttributeList: ?*anyopaque,
        dwAttributeCount: DWORD,
        dwFlags: DWORD,
        lpSize: *usize,
    ) callconv(.winapi) BOOL;
    extern "kernel32" fn UpdateProcThreadAttribute(
        lpAttributeList: *anyopaque,
        dwFlags: DWORD,
        Attribute: usize,
        lpValue: ?*anyopaque,
        cbSize: usize,
        lpPreviousValue: ?*anyopaque,
        lpReturnSize: ?*usize,
    ) callconv(.winapi) BOOL;
    extern "kernel32" fn DeleteProcThreadAttributeList(lpAttributeList: *anyopaque) callconv(.winapi) void;
    extern "kernel32" fn CreateProcessW(
        lpApplicationName: ?[*:0]const u16,
        lpCommandLine: ?[*:0]u16,
        lpProcessAttributes: ?*SECURITY_ATTRIBUTES,
        lpThreadAttributes: ?*SECURITY_ATTRIBUTES,
        bInheritHandles: BOOL,
        dwCreationFlags: DWORD,
        lpEnvironment: ?[*:0]u16,
        lpCurrentDirectory: ?[*:0]const u16,
        lpStartupInfo: *STARTUPINFOW,
        lpProcessInformation: *PROCESS_INFORMATION,
    ) callconv(.winapi) BOOL;
    extern "kernel32" fn CreatePseudoConsole(
        size: COORD,
        hInput: HANDLE,
        hOutput: HANDLE,
        dwFlags: DWORD,
        phPC: *HPCON,
    ) callconv(.winapi) HRESULT;
    extern "kernel32" fn ResizePseudoConsole(hPC: HPCON, size: COORD) callconv(.winapi) HRESULT;
    extern "kernel32" fn ClosePseudoConsole(hPC: HPCON) callconv(.winapi) void;
};
