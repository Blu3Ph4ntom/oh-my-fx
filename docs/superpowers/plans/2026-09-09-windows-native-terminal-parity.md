# Windows-Native Terminal Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable the complete existing terminal and background-process contract on Windows using named-pipe IPC and ConPTY.

**Architecture:** Keep protocol, registry, screen engine, permissions, and app lifecycle shared. Add a Windows named-pipe transport beside the Unix socket transport and a Windows ConPTY child launcher behind the existing native-session boundary; switch capability dispatch only after focused tests pass.

**Tech Stack:** Zig 0.16, Windows kernel32 APIs, ConPTY, existing terminal protocol and process-tree code, GitHub Actions `windows-latest`.

**Spec:** `docs/superpowers/specs/2026-09-09-windows-native-terminal-parity.md`

## Global Constraints

- No local `zig build`, `zig build test`, or `zig test`; all compile/test verification runs on GitHub Actions Windows runners.
- Local `zig fmt` is permitted for touched Zig files.
- No third-party dependencies.
- Preserve Unix behavior and the permission system.
- Use explicit allocator and handle ownership; every Windows handle closes on success and error paths.
- Do not claim completion until exact-commit CI and a real Windows binary interaction pass.

---

### Task 1: Lock the platform contracts

**Files:**
- Modify: `src/core/hosts/host.zig`
- Modify: `src/core/terminal/identity.zig`
- Test: inline tests in both files

**Interfaces:**
- Produce `terminalSupportForOs(.windows) == .supported`.
- Produce a non-null Windows profile identity stable for the process lifetime.

- [ ] **Step 1: Add failing contract tests** for Windows support and identity shape, retaining Linux/macOS assertions.
- [ ] **Step 2: Push this focused checkpoint** and run the two filtered tests on Windows CI; verify the old implementation fails for the expected assertions.
- [ ] **Step 3: Implement Windows identity** from the current user/profile environment plus process-safe fallback, without using `std.c.getuid`.
- [ ] **Step 4: Make Windows terminal and background capabilities report supported** while leaving WASI unsupported.
- [ ] **Step 5: Run `zig fmt` locally, push, and poll the filtered Windows CI job to completion.**
- [ ] **Step 6: Commit** with `feat(windows): enable terminal capability contracts`.

### Task 2: Add the Windows named-pipe transport

**Files:**
- Create: `src/core/terminal/windows_transport.zig`
- Modify: `src/core/terminal/host.zig`
- Modify: `src/core/terminal/client.zig`
- Modify: `src/core/terminal/identity.zig` if endpoint naming helpers belong there
- Test: inline transport tests plus host/client focused tests

**Interfaces:**
- `WindowsTransport.Server.listen(alloc, io, endpoint_name, token)` creates a private named pipe and accepts one authenticated client.
- `WindowsTransport.Client.connect(alloc, io, endpoint_name, token)` returns the same framed stream contract consumed by terminal protocol code.
- `WindowsTransport.close()` closes handles and invalidates the endpoint.

- [ ] **Step 1: Write transport tests** for deterministic UTF-16 pipe naming, successful token handshake, wrong-token rejection, reconnect after a failed first connect, and close cleanup.
- [ ] **Step 2: Define a narrow handle-owning stream adapter** with read, write, flush, and close operations matching the host/client framing call sites; map Win32 failures to existing terminal errors.
- [ ] **Step 3: Implement named-pipe creation** with `CreateNamedPipeW` using duplex byte mode, one instance, overlapped-safe connection handling, and a restrictive security descriptor or current-user-only access flag.
- [ ] **Step 4: Implement client open/connect** with `CreateFileW` and `WaitNamedPipeW`, then exchange a fixed handshake containing protocol version, nonce/token length, and token bytes before accepting frames.
- [ ] **Step 5: Route `host.Paths`, `host.listen`, `host.wait`, and `client.tryConnect` through the Windows adapter under `comptime builtin.os.tag == .windows`; leave POSIX socket code untouched.
- [ ] **Step 6: Store and remove Windows endpoint metadata** using the existing host record lifecycle, and reject stale/malformed records before connection.
- [ ] **Step 7: Run focused transport/host/client tests on Windows CI, inspect failed-job logs, then commit** `feat(windows): add authenticated terminal host transport`.

### Task 3: Implement ConPTY session creation

**Files:**
- Create: `src/core/terminal/windows_conpty.zig`
- Modify: `src/core/terminal/native_session.zig`
- Test: inline ConPTY lifecycle tests

**Interfaces:**
- `WindowsConPty.start(alloc, io, command, cwd, cols, rows)` returns a session owning input/output pipe handles, pseudoconsole handle, and process handle.
- `WindowsConPty.read`, `write`, `resize`, `terminate`, and `wait` are non-panicking and release all owned handles.

- [ ] **Step 1: Add Windows-only lifecycle tests** that start `cmd.exe /c echo ...`, capture output, write a command to an interactive shell, resize, terminate, and verify process exit.
- [ ] **Step 2: Add UTF-16 command/cwd conversion** and a small Windows API declaration block for `CreatePseudoConsole`, `ResizePseudoConsole`, `ClosePseudoConsole`, `CreateProcessW`, attribute-list setup, and handle cleanup.
- [ ] **Step 3: Create overlapped-capable input/output pipes** and initialize ConPTY with the requested dimensions.
- [ ] **Step 4: Start the child with `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`** and an inherited environment/cwd consistent with the existing native-session request.
- [ ] **Step 5: Implement bounded reads and writes** through the existing I/O abstraction, returning EOF on closed output and preserving partial writes.
- [ ] **Step 6: Implement resize and graceful termination**, falling back to the existing Windows process-tree termination helper after the configured timeout.
- [ ] **Step 7: Connect the backend to `native_session`** without changing the shared session state machine or screen-engine parser.
- [ ] **Step 8: Run focused ConPTY tests on Windows CI and commit** `feat(windows): host sessions with ConPTY`.

### Task 4: Wire terminal actions and lifecycle parity

**Files:**
- Modify: `src/core/terminal/host.zig`
- Modify: `src/core/terminal/client.zig`
- Modify: `src/core/app/app_terminal_runtime.zig`
- Modify: `src/core/execution/background_process_provider.zig`
- Modify: `src/core/hosts/host.zig`
- Test: terminal protocol/session/background tests

**Interfaces:**
- Existing actions `start`, `write`, `resize`, `signal`, `snapshot`, `close`, `recover`, and background list/inspect/signal use the Windows transport/backend without new product commands.

- [ ] **Step 1: Add regression tests** for direct-terminal startup, command output, input, resize, interrupt, child exit, host restart, and recovery on Windows.
- [ ] **Step 2: Replace compile-time Windows unsupported branches** in host/client action paths with the Windows transport and ConPTY calls.
- [ ] **Step 3: Enable the existing background process provider** on Windows and route spawn/capture/match/signal through the already implemented Windows process-tree functions.
- [ ] **Step 4: Verify permission checks remain before every write, signal, spawn, and cleanup action.**
- [ ] **Step 5: Run focused terminal/background CI filters and commit** `feat(windows): wire terminal lifecycle parity`.

### Task 5: Add Windows end-to-end smoke coverage

**Files:**
- Modify: `.github/workflows/windows.yml`
- Create or modify: `scripts/windows/omfx-terminal-smoke.ps1`
- Modify: `README.md`
- Modify: `CONTRIBUTING.md` if Windows verification instructions change

**Interfaces:**
- The smoke script starts the exact staged `omfx.exe`, sends a terminal command through the interactive path, checks output and clean exit, and returns nonzero on timeout/crash.

- [ ] **Step 1: Write the smoke script** with a temporary workspace, redirected stdin/stdout/stderr, timeout cleanup, and assertions for command output and absence of crash text.
- [ ] **Step 2: Add the script after artifact staging** in `windows.yml`, retaining the existing help smoke and artifact uploads.
- [ ] **Step 3: Update user docs** to describe Windows terminal support and the exact artifact/binary verification command.
- [ ] **Step 4: Run formatting and all focused Windows filters, then push.**
- [ ] **Step 5: Poll the exact run until build, unit tests, terminal smoke, and artifact upload conclude successfully.**
- [ ] **Step 6: Commit** `test(windows): cover terminal parity smoke`.

### Task 6: Final parity gate and release checkpoint

**Files:**
- Modify: `src/main.zig` only if version or Windows internal-mode dispatch requires it
- Modify: `CHANGELOG.md` only if the project release process requests a release note
- Modify: `.github/workflows/windows.yml` to remove `continue-on-error` only after green proof

- [ ] **Step 1: Run `zig fmt --check src/` in CI for the exact commit.**
- [ ] **Step 2: Run every Windows focused test shard and the ConPTY smoke on that exact commit.**
- [ ] **Step 3: Remove `continue-on-error` from the Windows test job only after all required filters pass.**
- [ ] **Step 4: Download the exact artifact, run the interactive happy path, exercise input plus `/quit`, and confirm clean stderr.**
- [ ] **Step 5: Delete only superseded downloaded artifact directories after confirming their absolute paths are under the repository; preserve source and user files.**
- [ ] **Step 6: Report remaining upstream parity gaps, if any, with evidence instead of calling them complete.**

## Self-review

- Capability, identity, transport, ConPTY, action routing, background processes, recovery, docs, CI, and live binary verification are all covered.
- No step relies on a placeholder or an unspecified test command.
- The transport and ConPTY interfaces are explicitly defined before later wiring tasks consume them.
- Unix socket and Unix launcher paths remain unchanged behind compile-time Windows branches.
