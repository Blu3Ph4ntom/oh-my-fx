# Windows-Native Terminal Parity Design

## Problem

Windows currently compiles and runs the main omfx UI, but the direct terminal
feature is hard-disabled. `src/core/hosts/host.zig` reports Windows as
unsupported, `identity.profileUser` returns null, and the terminal host/client
only use Unix-domain sockets. The Windows process helpers already present in
the repository are therefore unreachable. This causes the visible
`Direct terminal was not started: unsupported host` failure and prevents the
Windows build from matching the Linux/macOS feature set.

## Goal

Make Windows a first-class terminal host with the same product contract as
Linux/macOS: foreground command execution, persistent hosted sessions,
screen capture, input/write, resize, interrupt/termination, background
process monitoring, recovery, and deterministic cleanup. Preserve the existing
Unix implementation and keep the shared protocol, session, registry, and
screen-engine contracts unchanged wherever possible.

## Architecture

### Shared layers

The existing terminal protocol, action dispatch, session registry, recovery
records, screen engine, and app lifecycle remain the platform-neutral product
layers. Platform code is isolated behind the endpoint transport and native
child-process launcher boundaries.

### Windows endpoint transport

Use a per-profile Windows named pipe with a cryptographically unpredictable
endpoint suffix. The host writes its endpoint metadata and one-time
authentication token into the existing profile-private host record. The client
reads that record, opens the named pipe, and authenticates before sending
protocol frames. The server rejects unknown clients and stale records are
removed during startup/recovery. No TCP listener is exposed.

The transport adapter presents the same framed reader/writer operations used by
the Unix socket path. Windows API calls are contained in a small module using
UTF-16 conversion and explicit handle ownership. Handle closure, failed
connects, and server shutdown map to the existing terminal errors.

### Windows child backend

Use Windows ConPTY for hosted shells and commands. The launcher creates input
and output pipes, creates a pseudoconsole, starts the child with an extended
startup attribute list, and retains the process and pseudoconsole handles in
the native session object. Output is fed into the existing terminal engine.

Resize calls `ResizePseudoConsole`; input writes to the ConPTY input pipe;
interrupt/termination uses the existing process-tree and Windows termination
helpers with graceful close first and forceful cleanup on timeout. The
launcher has no Unix-only calls on the Windows branch.

### Lifecycle

The host remains a separate internal process. The parent starts it, waits for
the authenticated endpoint, and reconnects after transient startup races.
Session ownership, background monitoring, recovery, and host shutdown use the
same lifecycle notices as Unix. Every Windows handle is owned by exactly one
object and closed on all error paths; host shutdown removes the endpoint and
registry record.

## Security and compatibility

- Keep profile state under the existing omfx profile directory.
- Authenticate every named-pipe connection before decoding actions.
- Use restrictive pipe access and reject unauthenticated/stale endpoint data.
- Do not weaken the permission system or add a second product execution path.
- Keep Unix behavior unchanged and compile Windows-specific code only on
  Windows.
- Do not add third-party dependencies.

## Tests and rollout

1. Add focused Windows capability and identity tests.
2. Add transport tests for endpoint creation, authentication, reconnect, and
   cleanup.
3. Add ConPTY lifecycle tests covering output, input, resize, termination,
   EOF, and child exit.
4. Enable Windows terminal/background capability and run only filtered tests
   in GitHub Actions while iterating.
5. Add a CI ConPTY smoke that starts the built binary, enters the terminal
   path, performs one command, and exits cleanly.
6. Remove the Windows `continue-on-error` test exception only after the
   focused shards pass.

## Acceptance criteria

- `host.isSupported()` and terminal capability report supported on Windows.
- `omfx` can start a direct terminal, execute a command, display its output,
  accept input, resize, interrupt/terminate, and return to the agent UI.
- A hosted session can be inspected, resumed, recovered, and cleaned up after
  host or child failure.
- Background process listing and lifecycle actions work on Windows.
- Windows ReleaseSafe build, focused unit tests, ConPTY smoke, formatting, and
  stderr-clean binary execution pass in GitHub Actions for the exact commit.
