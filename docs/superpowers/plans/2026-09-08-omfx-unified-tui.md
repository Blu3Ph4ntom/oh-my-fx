# omfx Unified TUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the omfx terminal UI feel like one deliberate Windows-native product: predictable focus and keyboard behavior, consistent Night Signal styling, stable rendering during transient surfaces, and explicit recovery for resize, narrow terminals, no-color output, and authentication failures.

**Architecture:** Keep product state in `src/core`, terminal rendering/input/lifecycle in `src/ui`, and transport/auth outside the UI. Extend the existing `interaction_contract`, `SurfaceFooterFrame`, `TerminalActionDecoder`, `RenderRequest`, and `AlternateScreenOwner` seams. Add only small shared presentation/state helpers; do not create a parallel renderer or move product state into UI code.

**Tech Stack:** Zig 0.16, `std.Io`, ANSI inline rendering, Windows Console/ConPTY support, existing Zig unit tests, Bun/tmux E2E fixtures, and GitHub Actions `windows-latest` as the build/test authority.

**Spec:** `docs/plans/2026-09-08-omfx-unified-tui-design.md`

## Global Constraints

- Do not run `zig build`, `zig build test`, or `zig test` on the developer machine. RAM is constrained; local Zig commands are limited to `zig fmt`/`zig fmt --check` and read-only inspection.
- Every implementation checkpoint must be pushed so Windows CI can run the focused unit filters and ReleaseSafe build. Inspect per-job conclusions, not only the workflow aggregate.
- Keep the existing `fx` compatibility contract for protocol identifiers and legacy `FX_*` environment variables while all user-facing product text says `omfx`.
- Preserve credential values and the current credential source on failed auth. No auth flow may silently replace a working credential or claim a provider is connected without a usable credential.
- Use the existing inline-first renderer and the existing alternate-screen ownership model. Do not introduce a second event loop, an always-on alternate buffer, or direct terminal writes from product-state modules.
- No generated `.fx`, `.zig-cache`, `zig-out`, or downloaded Windows artifact directories are committed. Do not delete the directory of the user’s currently running artifact; remove superseded downloaded artifacts only after the user process has exited.
- Every new or changed interaction needs a corporeal unit test in its owning Zig file and, when it is a real terminal workflow, a deterministic E2E assertion. Tests must cover semantic state without relying on color alone.
- Each task ends with `zig fmt` on touched Zig sources, `git diff --check`, a small checkpoint commit, and a Windows CI run before the next task changes the same seam.

## Current Code Map

| Concern | Existing owner | Planned change |
| --- | --- | --- |
| Product palette and modes | `src/core/shared/product_theme.zig`, `src/ui/render.zig` | Add one UI state-to-token mapping and wire all legacy style aliases to semantic roles. |
| Surface selection/status presentation | `src/ui/footer/*_presentation.zig`, `src/ui/footer/approval_ui.zig`, `src/ui/footer/question_ui.zig` | Use shared focus, disabled, loading, success, warning, and danger states with stable markers. |
| Footer layout and clipping | `src/ui/footer/surface_frame.zig`, `src/ui/footer/paint_plan.zig`, `src/ui/footer/input_presentation.zig`, `src/ui/footer/row_text.zig` | Make frame composition state-driven and width-safe at narrow sizes. |
| Keyboard contract | `src/ui/input/interaction_contract.zig`, `src/ui/input/terminal_action_decoder.zig`, `src/ui/input/runtime.zig` | Make normalized actions reach the owning surface exactly once, including Windows CR/CSI/Kitty input. |
| Product-state routing | `src/core/app/app_input_runtime.zig`, `src/core/app/app_lifecycle.zig` | Route through the common surface contract before domain-specific handlers and restore ownership on close/cancel/error. |
| Frame scheduling | `src/ui/event_loop.zig`, `src/ui/render_request.zig` | Coalesce input/resize/activity invalidations and avoid flicker or stale footer frames. |
| Alternate-screen lifecycle | `src/ui/shell_runtime.zig`, `src/ui/terminal/terminal.zig`, `src/ui/resize_runtime.zig` | Verify enter/leave symmetry and terminal mode restoration for every owner. |
| Regression proof | `src/test_root.zig`, `tests/e2e/tui-*.test.ts`, `.github/workflows/windows.yml` | Add focused filters and deterministic Windows/TUI coverage. |

---

## Task 1: Establish the shared Night Signal interaction-state contract

**Files:**

- Create `src/ui/surface_style.zig`.
- Modify `src/core/shared/product_theme.zig` only if a missing semantic role is exposed.
- Modify `src/ui/render.zig`.
- Modify `src/core/app/app_render_runtime.zig`.
- Modify `src/test_root.zig`.

### 1.1 Write the failing contract tests first

- [ ] Add `src/ui/surface_style.zig` tests for `default`, `hover`, `focus`, `active`, `disabled`, `loading`, `success`, `warning`, and `danger` state mapping.
- [ ] Assert focused rows have both a visible marker/weight distinction and a focus token; do not accept a color-only distinction.
- [ ] Assert status states map to `product_theme` semantic roles in dark, light, high-contrast, 256-color, and no-color modes.
- [ ] Assert status text remains intelligible when the terminal cannot emit color.
- [ ] Add the new module to `src/test_root.zig` so Windows package-root tests can discover it.

### 1.2 Implement the smallest shared helper

- [ ] Define a minimal `SurfaceState` enum and allocation-free helpers for row style, marker, status style, and hint style. Helpers return existing `render.zig`/theme tokens or values that can be passed into the existing row writers; they must not own product state.
- [ ] Keep marker text and status labels explicit so selection/loading/error are not conveyed by ANSI color alone.
- [ ] Reuse `product_theme.Palette` and its `Capabilities` fallback logic rather than duplicating RGB/256/no-color tables.

### 1.3 Wire the production theme

- [ ] Update `render.initTheme` so dark and light modes use the semantic warning/success/danger roles instead of the current neutral white aliases for `warning_style`, `green_style`, `red_style`, `diff_added_style`, and `diff_removed_style`.
- [ ] Preserve existing snapshot-compatible text/reset behavior and high-contrast/no-color guarantees.
- [ ] Build `transcript_blocks.Styles` from the same semantic tokens in `app_render_runtime.zig`; remove any duplicate status-color decisions encountered there.
- [ ] Keep the public `render` style variables stable for existing presentation modules while making their values semantically correct.

### 1.4 Verify and checkpoint

- [ ] Run `zig fmt` on touched Zig files and `git diff --check` locally.
- [ ] Push a checkpoint and require Windows filters for `Night Signal`, `initTheme`, and the new `surface_style` tests, followed by the ReleaseSafe build/smoke job.
- [ ] Commit as `feat: centralize omfx surface states`.

---

## Task 2: Apply one visual language to every transient surface

**Files:**

- Modify `src/ui/footer/picker_presentation.zig`.
- Modify `src/ui/footer/model_menu_presentation.zig`.
- Modify `src/ui/footer/settings_menu_presentation.zig`.
- Modify `src/ui/footer/appearance_menu_presentation.zig`.
- Modify `src/ui/footer/help_menu_presentation.zig`.
- Modify `src/ui/footer/resume_menu_presentation.zig`.
- Modify `src/ui/footer/skills_menu_presentation.zig`.
- Modify `src/ui/footer/compact_command_menu_presentation.zig`.
- Modify `src/ui/footer/approval_ui.zig`.
- Modify `src/ui/footer/question_ui.zig`.
- Modify `src/ui/footer/input_presentation.zig`.
- Modify `src/ui/footer/surface_frame.zig` and `src/ui/footer/paint_plan.zig`.
- Add focused tests in the owning files; extend `src/test_root.zig` only for newly imported test modules.

### 2.1 Capture the current failure modes with tests

- [ ] Add presenter tests that assert the selected item has one canonical marker, a stable active/focus token, and a readable label in every picker/menu.
- [ ] Add tests for disabled options and empty/loading/error rows. Error and failure rows must use an explicit status label plus the danger token; loading must use an explicit progress label and remain stable when motion is reduced.
- [ ] Add approval/question tests for selected choice, freeform editing, submit, cancel, and cursor movement. Assert that question freeform editing does not accidentally inherit approval selection semantics.
- [ ] Add width tests for long model/provider/auth labels and hyperlink rows, including the complete OSC8 target after visible text clipping.
- [ ] Add no-color and 256-color assertions for the same states.

### 2.2 Migrate presenters to the shared contract

- [ ] Replace duplicated selected/dim style decisions with `surface_style` helpers while retaining each module’s domain-specific row data.
- [ ] Standardize selection markers and spacing so arrow movement never causes horizontal jitter between selected and unselected rows.
- [ ] Give headings, hints, borders, and status messages the same semantic hierarchy: brand heading, focus marker, muted hint, explicit status label, and danger/warning/success token.
- [ ] Route picker status rows through the common state mapping instead of rendering all non-success states as neutral dim text.
- [ ] Ensure auth provider choices show availability/connected/error state as text and marker state, not color alone. Preserve the existing credential source and error copy.
- [ ] Keep approval/question controls keyboard-first and make disabled actions visibly unavailable without stealing focus.

### 2.3 Make the shared footer frame the sole composition boundary

- [ ] Have `paint_plan.zig` request row styles and status states from the shared helper, while `surface_frame.zig` remains responsible for measurement, placement, and commit order.
- [ ] Keep `row_text.zig` as the only clipping/ellipsizing owner. Verify that every styled row is clipped before ANSI/OSC8 output can corrupt width accounting.
- [ ] Make `input_presentation.zig` use the same hint/status tokens and preserve cursor/text-selection reverse video as an editing affordance only.
- [ ] Verify compact/narrow layouts omit optional hints before truncating the active input or selected label.

### 2.4 Verify and checkpoint

- [ ] Format, diff-check, push, and run focused Windows filters for picker/menu/approval/question/row clipping tests.
- [ ] Run the deterministic TUI menu, decision-prompt, auth-source, keybinding, narrow-terminal, and no-color E2E files in CI; keep any live-network/auth test classified as intentional exclusion.
- [ ] Commit as `feat: unify omfx transient surfaces`.

---

## Task 3: Make input ownership and frame lifecycle deterministic

**Files:**

- Modify `src/ui/input/interaction_contract.zig`.
- Modify `src/ui/input/terminal_action_decoder.zig` and `src/ui/input/runtime.zig`.
- Modify `src/core/app/app_input_runtime.zig`.
- Modify `src/core/app/app_lifecycle.zig`.
- Modify `src/ui/event_loop.zig` and `src/ui/render_request.zig`.
- Modify `src/ui/shell_runtime.zig`, `src/ui/terminal/terminal.zig`, and `src/ui/resize_runtime.zig` only where the lifecycle tests identify an ownership leak.

### 3.1 Add regression tests before routing changes

- [ ] Extend `interaction_contract` table tests to cover every declared `Surface`: arrows, page movement where supported, Enter, Escape/back, Tab/edit, Ctrl+C, and unsupported controls.
- [ ] Add decoder tests for Windows CR, LF, CRLF, CSI arrows, modified arrows, Kitty key forms, bare Escape, paste boundaries, and repeated input epochs. Assert exactly one logical action per physical key.
- [ ] Add app routing tests that prove Enter is handled once by the active auth/menu/approval/question surface and does not fall through to the composer; Escape closes only the current owner and restores the previous owner.
- [ ] Add event-loop tests for input bursts, resize-plus-input, activity-plus-input, and render-request coalescing. Assert no stale frame is committed after a surface closes.
- [ ] Add lifecycle tests for each `AlternateScreenOwner` that verify alternate buffer, cursor, mouse, paste, focus, and keyboard modes are restored after success, cancel, error, and EOF.

### 3.2 Normalize once, route once

- [ ] Make the decoder/runtime the only raw-byte-to-`TerminalInputEvent` boundary. Preserve replay/paste framing and do not let individual menu presenters inspect raw bytes.
- [ ] Add an explicit active-surface resolver in the existing app input path, using `interaction_contract.route` for common controls before invoking the domain handler. Keep domain handlers responsible for state transitions only.
- [ ] Define the precedence order in code and tests: terminal takeover/full transcript, approval/question, auth/catalog/menu, inline completion, composer, then global controls.
- [ ] Ensure `Enter` cannot be delivered both as a remapped carriage return and as a normal byte; ensure CRLF normalization does not swallow intentional composer newline input.
- [ ] Keep Ctrl+C cancellation and exit semantics separate from Escape clear/cancel behavior, including after a failed auth attempt.

### 3.3 Coalesce frame commits and restore ownership

- [ ] Use `RenderRequest` invalidation reasons to coalesce a burst into one frame transaction, while preserving an immediate frame for meaningful state changes.
- [ ] On surface close/error, clear transient selection/loading state before requesting the footer so the next frame cannot paint the old owner.
- [ ] On resize, recalculate available rows before painting hints/status and preserve the composer draft/cursor.
- [ ] Preserve reduced-motion behavior by removing time-based redraws that do not change state; loading remains visible through a stable text state.

### 3.4 Verify and checkpoint

- [ ] Format, diff-check, push, and require focused Windows decoder, interaction-contract, app-input, event-loop, and lifecycle filters.
- [ ] Run the deterministic TUI input-navigation, keybindings, interrupt-recovery, resize, native-clear-recovery, decision-prompt, and auth-source-selection tests in CI.
- [ ] Commit as `fix: make omfx surface ownership single-path`.

---

## Task 4: Finish responsive polish, regression coverage, and CI enforcement

**Files:**

- Modify `src/ui/render.zig`, `src/ui/footer/*` and `src/ui/input/*` only for issues found in the final matrix.
- Modify `tests/e2e/tui-keybindings.test.ts`, `tests/e2e/tui-resize.test.ts`, `tests/e2e/tui-auth-source-selection.test.ts`, and add `tests/e2e/tui-omfx-unified-surface.test.ts` if existing fixtures cannot express the complete matrix.
- Modify `scripts/pgso/corpus.json` if and only if a new E2E file is added; assign exactly one required classification.
- Modify `.github/workflows/windows.yml`.
- Update `README.md`, `CONTRIBUTING.md`, and `docs/customization.md` only for observable TUI controls or configuration exposed by this work.

### 4.1 Add the end-to-end interaction matrix

- [ ] Cover fresh startup, `/help`, picker open/move/select/cancel, `/setup` auth source selection, model/provider switching, approval/question submit/cancel, full transcript open/close, and `/quit`.
- [ ] Run the same matrix at normal width, narrow width, after resize, with `NO_COLOR`, with 256-color capability, and with reduced motion.
- [ ] Assert no mojibake in the omfx header, no duplicated footer rows, no flicker-inducing stale frame in captured grids, and no process abort on EOF or cancel.
- [ ] Assert browser auth URL output is a complete usable URL even when its visible label is clipped; auth failure leaves the previous credential/model state intact.
- [ ] Keep live provider chat smoke separate from deterministic TUI tests; the existing OpenCode Go CI smoke remains the credentialed provider proof.

### 4.2 Make Windows focused CI required

- [ ] Add the new exact test filters to the Windows test job and remove `continue-on-error` only after the new filters are green on the exact commit.
- [ ] Keep the build job’s formatting, ReleaseSafe build, `FX_BENCH=1` smoke, staged `omfx.exe` smoke, and OpenCode Go smoke intact.
- [ ] Add bounded TUI smoke commands that cannot hang a runner; record useful stderr/trace diagnostics on timeout.
- [ ] Download the artifact from the exact passing commit and verify its SHA/size before handing it to the user. Do not delete a currently running older artifact.

### 4.3 Final review and checkpoint

- [ ] Run local `zig fmt --check src/` and `git diff --check`; do not run local Zig build/test commands under the RAM constraint.
- [ ] Push the final checkpoint and wait for the exact commit’s required Windows jobs. If other workflows remain intentionally disabled, report that limitation rather than calling cross-platform Full CI green.
- [ ] Review the diff for raw terminal writes outside UI owners, new `@panic` paths for runtime conditions, accidental `fx`-only user copy, leaked allocations, and public API growth.
- [ ] Commit as `feat: finish the omfx unified TUI`.

## Handoff Gate

The implementation is not reported as ready until the Windows artifact has been run by the user (or can be run locally without violating the RAM constraint) and the happy-path interaction is confirmed. The final report must state exactly which build, focused tests, E2E checks, artifact, and interactive actions were verified, and must call out any remaining non-Windows CI limitation.
