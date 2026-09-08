# omfx Upstream Parity and OpenCode Go Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add first-class OpenCode Go API-key login and port the highest-value upstream `fx` v0.0.5–v0.0.8 native CLI/TUI/runtime behavior into Windows-native `omfx` without losing its custom identity.

**Architecture:** Keep provider activation in the existing auth/provider runtime, tool behavior in the tool contracts and dispatch layers, and interaction/rendering in the UI input/event layers. Each task is a narrow contract change with source-local tests and a filtered Windows CI proof; the global install happens only after the exact artifact for the final commit passes.

**Tech Stack:** Zig 0.16.0, Windows `windows-latest` GitHub Actions, PowerShell ConPTY smoke, existing stdlib-only runtime, GitHub Actions artifact download.

**Spec:** `docs/plans/2026-09-09-omfx-upstream-parity-design.md`

## Global Constraints

- Scope covers the native CLI, agent runtime, authentication, MCP, sessions, tools, and terminal UI; the `libfx` SDK/API surface is deferred.
- OpenCode Go is API-key-only and uses `OPENCODE_GO_API_KEY`; it must be first in `/login` and must activate a catalog-valid model after entry.
- Preserve omfx branding, Night Signal styling, Windows-native behavior, OpenCode Go, and existing credential safety.
- Local verification is limited to read-only inspection, formatting, static checks, and the exact downloaded Windows artifact; no local Zig build/test commands.
- Every production change has a focused test written first, observed failing on a Windows runner, then made green by the smallest implementation.
- Do not use external dependencies or add leaf feature logic to `src/main.zig`.

## File Map

- `src/core/app/app_auth_runtime.zig`, `src/core/auth/credentials.zig`, `src/core/config/model_provider.zig`: provider login, credential source, and activation contracts.
- `src/builtins/commands.zig`, `src/ui/footer/picker_presentation.zig`, `src/ui/footer/settings_menu_presentation.zig`: ordered login/setup rows and selection presentation.
- `src/builtins/tools.zig`, `src/core/tooling/tool_admission.zig`, `src/core/agent/runtime/*`: upstream shell/capability/subagent contracts and execution admission.
- `src/ui/input/*`, `src/ui/event_loop.zig`, `src/ui/footer/*`: steering, key normalization, surface ownership, and frame commits.
- `src/builtins/mcp.zig`, `src/core/mcp/*`, `src/core/output/output_contracts.zig`, `src/core/cli/cli_ask.zig`: MCP management and structured output.
- `src/core/config/*`, `src/core/session/*`, `src/core/permissions/*`: obsolete-setting migration, session recovery, and current permission naming.
- `.github/workflows/windows.yml`, `scripts/windows/omfx-conpty-smoke.ps1`: bounded CI proof and exact artifact verification.
- `README.md`, `CONTRIBUTING.md`: user-facing command and configuration documentation.

### Task 1: Put OpenCode Go first in `/login`

**Files:**
- Modify: `src/builtins/commands.zig`
- Modify: `src/core/app/app_auth_runtime.zig`
- Modify: `src/core/auth/credentials.zig`
- Modify: `src/core/config/model_provider.zig`
- Modify: the existing login/setup picker presenter and its source-local tests

**Interfaces:**
- Consumes: `ProviderId.opencode_go`, `CredentialSource.opencode_go_subscription`, `OPENCODE_GO_API_KEY`, the existing masked API-key input state, and the existing model-catalog activation path.
- Produces: an ordered `/login` registry whose first actionable provider row is OpenCode Go; selecting it enters the API-key flow, saves the source-specific key, selects a valid Go model, and returns to the provider picker with `connected` status.

- [ ] Write the failing tests:
  - `test "login provider picker places OpenCode Go first"` asserts the first provider row is `.opencode_go` and its copy names `OPENCODE_GO_API_KEY`.
  - `test "OpenCode Go API key submission activates provider"` supplies a non-empty key through the existing key-submit seam and asserts provider `.opencode_go`, source `.opencode_go_subscription`, and the selected catalog model.
  - `test "OpenCode Go login rejects empty key without changing credential"` asserts the existing provider/source remain unchanged and the notice gives the variable name.
- [ ] Push the test-only commit and run the three exact filters on `windows-latest` through `.github/workflows/windows.yml`; confirm each fails for the missing ordering/activation behavior rather than a compile error.
- [ ] Implement only the row ordering and API-key activation path, reusing the existing masked input, credential persistence, and catalog activation helpers.
- [ ] Run the same filters in Windows CI; require zero failures and clean stderr.
- [ ] Run the Windows CLI and ConPTY smoke after the focused tests; confirm `/login` renders OpenCode Go first and Escape restores the composer.
- [ ] Commit as `feat: prioritize OpenCode Go API-key login`.

### Task 2: Port the upstream shell and capability contracts

**Files:**
- Modify: `src/builtins/tools.zig`
- Modify: `src/core/tooling/tool_admission.zig`
- Modify: `src/core/terminal/contracts.zig`, `src/core/terminal/*` as required by the typed contract
- Modify: `src/core/agent/runtime/*` only where dispatch/admission consumes the new contract
- Test: existing tool-admission and runtime tool-flow test files

**Interfaces:**
- Consumes: existing terminal execution/session ownership, permission admission, MCP dispatch, and skill loading.
- Produces: the upstream-shaped `shell` contract with run/interact/stop actions, bounded live executions, terminal-safe output handles, and `capability_search` for combined skills/MCP discovery.

- [ ] Write failing tests for exact shell action decoding, owned session interaction, stop behavior, and capability-search result selection.
- [ ] Run the focused Windows filters and record the expected missing-symbol or wrong-tool-contract failures.
- [ ] Add the smallest typed schemas/dispatch adapters; preserve the existing terminal implementation until every call site consumes the new contract.
- [ ] Add compatibility decoding only where saved sessions or old provider tool records require it; do not advertise both old and new tools to models.
- [ ] Run focused Windows filters plus the OpenCode Go live smoke; verify tool output remains permission-gated and bounded.
- [ ] Commit as `feat: align omfx execution and capability tools`.

### Task 3: Port steering and current keyboard semantics

**Files:**
- Modify: `src/ui/input/terminal_action_decoder.zig`
- Modify: `src/ui/input/interaction_contract.zig`
- Modify: `src/ui/input/runtime.zig`, `src/ui/event_loop.zig`
- Modify: `src/core/app/*` only for the typed steering event and turn boundary
- Test: existing decoder, interaction-contract, event-loop, and resize test files

**Interfaces:**
- Consumes: normalized CR/LF, Kitty/Windows key decoding, active turn state, and existing surface owner cleanup.
- Produces: Enter/Ctrl+Enter steering behavior matching upstream, with queued follow-ups only when the turn boundary requires them; all alternate-screen owners still restore cursor, mouse, paste, keyboard, and main-screen state.

- [ ] Write failing tests for Enter while a turn is active, Ctrl+Enter steering, unknown escape completion, and Escape behavior in login/provider/setup surfaces.
- [ ] Run each focused Windows filter and confirm the old queue/no-op result is observed.
- [ ] Implement one normalized event path; keep product state out of render code and keep frame coalescing in the event loop.
- [ ] Run the filters and the exact ConPTY sequence with `/login`, `/help`, arrows, Enter, Escape, and `/quit`.
- [ ] Commit as `feat: add upstream steering semantics to omfx`.

### Task 4: Modernize subagents and MCP management

**Files:**
- Modify: `src/builtins/tools.zig`, `src/core/subagent/*`
- Modify: `src/builtins/commands.zig`, `src/core/cli/*`, `src/core/app/*`
- Modify: `src/builtins/mcp.zig`, `src/core/mcp/*`
- Test: existing subagent, MCP, command registry, and session tests

**Interfaces:**
- Consumes: existing parent-owned child sessions, MCP config persistence, permission gates, and omfx picker surfaces.
- Produces: two-action direct subagent delegation, top-level `mcp` management with project trust boundaries, passive listing versus explicit connection, and stable child-session visibility.

- [ ] Write failing tests for subagent `run`/`message`, top-level `mcp` command registration, passive listing, project trust refusal, and parent-private child sessions.
- [ ] Run focused Windows filters and confirm the old Ctrl+X-manager/tool contract is what fails.
- [ ] Implement typed adapters and command dispatch without duplicating session ownership or MCP persistence.
- [ ] Run focused Windows filters and ConPTY menu navigation; confirm provider and MCP pickers do not steal each other’s alternate screen.
- [ ] Commit as `feat: align subagent and MCP controls`.

### Task 5: Align output, permissions, and obsolete settings

**Files:**
- Modify: `src/core/output/output_contracts.zig`, `src/core/cli/cli_ask.zig`
- Modify: `src/core/config/*`, `src/core/permissions/*`, `src/core/session/*`
- Modify: `src/builtins/commands.zig`, `src/ui/footer/*`
- Test: output, config migration, permission, and session recovery tests

**Interfaces:**
- Consumes: current snapshot/text/JSON rendering, saved settings, session codecs, and exact-action permission review.
- Produces: `ask --json.final_output`, current `--full-access`/permission wording with old aliases handled intentionally, safe migration away from memory/record/sandbox/appearance settings, and upstream recovery/fallback behavior without credential-source mixing.

- [ ] Write failing tests for `final_output`, full-access aliases, obsolete-setting migration, unchanged credentials after login failure, and source-specific provider fallback.
- [ ] Run focused Windows filters and confirm each failure is behavioral.
- [ ] Implement the shared snapshot fields and migration rules at their owning boundaries; keep compatibility data readable without re-advertising retired features.
- [ ] Run focused Windows filters, JSON CLI smoke, and exact artifact smoke.
- [ ] Commit as `feat: align omfx output and compatibility contracts`.

### Task 6: Documentation, CI parity gate, and global handoff

**Files:**
- Modify: `.github/workflows/windows.yml`
- Modify: `scripts/windows/omfx-conpty-smoke.ps1` only for new deterministic coverage
- Modify: `README.md`, `CONTRIBUTING.md`
- Test: Windows workflow and exact artifact run

**Interfaces:**
- Consumes: all prior task contracts and the user-provided `OPENCODE_GO_API_KEY` Actions secret.
- Produces: documented omfx commands/provider setup, required Windows build/test/ConPTY/OpenCode Go checks, and a verified global `omfx.exe` installation.

- [ ] Add only stable user-visible commands and environment names to docs; document that `.env.local` is not loaded by the native binary.
- [ ] Add focused filters for each new contract and keep the test job required; never restore the uncapped full-suite invocation.
- [ ] Push the final commit and inspect per-job conclusions for the exact SHA; require build, filtered tests, CLI smoke, ConPTY, OpenCode Go, artifact upload, and artifact download/hash verification.
- [ ] Download `omfx-windows-x86_64` into a fresh commit-named directory and run its ConPTY and attached-terminal happy paths locally.
- [ ] Confirm no `fx`/`omfx` process is running, then copy only that verified executable to `%USERPROFILE%\\.omfx\\bin\\omfx.exe`; add that directory to the user PATH only if absent.
- [ ] Start a fresh PowerShell process, resolve `omfx`, run `omfx help`, and confirm version/help output and stderr are clean.
- [ ] Commit docs/CI changes as `docs: document omfx upstream parity surface`.

## Final Review Checklist

- [ ] `git diff --check` is clean and only intended source/docs/CI files are tracked.
- [ ] Every new test was observed failing on Windows before its production implementation.
- [ ] Exact current-commit Windows build, filtered tests, ConPTY, OpenCode Go, and artifact hash checks pass.
- [ ] Exact downloaded artifact runs locally through an attached terminal and exits cleanly.
- [ ] Global `omfx` resolves to the verified artifact; no old artifact or process is used.
- [ ] Cross-platform upstream Full CI is explicitly reported as unavailable if its workflows remain disabled.
