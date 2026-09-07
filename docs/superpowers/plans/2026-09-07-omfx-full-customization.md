# omfx Full Customization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make omfx’s Night Signal identity, keyboard interaction model, profile customization, provider state, and Windows-native terminal behavior consistent across the product.

**Architecture:** Keep the inline transcript/composer as the primary surface and extend the existing typed terminal-input boundary instead of adding a parallel input path. Keep semantic theme and UI presentation at the existing rendering boundaries, persist user-owned UI preferences through the existing settings store, and leave `fx`/`.fx`/`FX_*`/`_meta.fx` compatibility untouched. The composition root wires state and callbacks; leaf modules own parsing, presentation, persistence, and terminal behavior.

**Tech Stack:** Zig 0.16.0, `std.Io`, existing ANSI/VT terminal engine, existing JSON settings store, Windows Terminal/ConPTY native path, GitHub Actions `windows-latest`, and Markdown documentation.

**Spec:** `docs/superpowers/specs/2026-09-07-omfx-full-customization.md`

## Global Constraints

- The visible product name is `omfx`; `fx` remains the compatibility command.
- Preserve `.fx`, `FX_*`, ACP `_meta.fx`, provider wire identifiers, and OpenAI’s registered protocol originator.
- Keep the inline transcript/composer primary; do not add a permanent dashboard or sidebar.
- All interactive surfaces must have deterministic Enter, Escape, Up/Down, and Tab behavior where advertised.
- Semantic roles are `brand`, `focus`, `success`, `warning`, `danger`, `text`, `muted`, and `border`; no component invents a private status color.
- `OMFX_*` aliases win over their documented `FX_*` counterparts; test-only `FX_E2E_*` names remain unchanged.
- Use Zig 0.16 APIs and existing allocator/I/O ownership patterns; do not add dependencies.
- Do not run `zig build`, `zig build test`, or `zig test` locally. Verification commands in this plan run on GitHub Actions Windows runners.
- `zig fmt` and read-only source inspection are allowed locally.
- Every implementation checkpoint ends with a focused Windows CI run, a small commit, and a clean-artifact check.

## File Map

| Area | Files | Responsibility |
| --- | --- | --- |
| Product context | `PRODUCT.md`, `DESIGN.md` | Strategic and visual design context already captured in the design checkpoint |
| UI preferences | `src/core/config/ui_preferences.zig`, `src/core/config/config_runtime.zig`, `src/core/config/settings_store.zig`, `src/core/config/settings_catalog.zig`, `src/core/shared/io.zig` | Typed values, precedence, persistence, and `/settings` catalog entries |
| Input | `src/core/input/input_action.zig`, `src/ui/input/escape_parser.zig`, `src/ui/input/terminal_action_decoder.zig`, `src/ui/input/shortcuts.zig`, `src/ui/input/runtime.zig` | One logical terminal event contract and surface-specific translation |
| Terminal lifecycle | `src/ui/terminal/terminal.zig`, `src/ui/shell_runtime.zig`, `src/ui/event_loop.zig` | Windows/ConPTY capability negotiation, polling, frame commits, and restoration |
| Surface interaction | `src/ui/input/interaction_contract.zig`, `src/ui/footer/interaction_state.zig`, `src/ui/footer/row_text.zig`, `src/ui/footer/*_menu_presentation.zig`, `src/ui/settings_screen.zig`, `src/main.zig` | Focus, hints, selection, and owner-scoped routing |
| Visual system | `src/core/shared/product_theme.zig`, `src/ui/render.zig`, `src/ui/assistant/user_message_card.zig`, `src/ui/approval_screen.zig`, `src/ui/footer/approval_ui.zig`, `src/ui/footer/picker_presentation.zig` | Night Signal semantic styles and all state treatments |
| Auth and links | `src/core/hosts/url_opener.zig`, `src/core/app/app_auth_runtime.zig`, `src/core/auth/auth_runtime.zig`, `src/builtins/commands.zig`, `src/core/cli/cli_surface.zig` | Browser activation, onboarding state, provider recovery, and public copy |
| Verification/docs | `src/test_root.zig`, `.github/workflows/windows.yml`, `README.md`, `CONTRIBUTING.md`, `docs/` | Focused Windows tests, artifacts, smoke checks, and user documentation |

---

### Task 1: Add typed UI preferences and profile persistence

**Files:**

- Create: `src/core/config/ui_preferences.zig`
- Modify: `src/core/shared/io.zig`
- Modify: `src/core/config/config_runtime.zig`
- Modify: `src/core/config/settings_store.zig`
- Modify: `src/core/config/settings_catalog.zig`
- Modify: `src/ui/terminal/theme_detection.zig`
- Modify: `src/test_root.zig`
- Modify: `.github/workflows/windows.yml`

**Interfaces:**

- Consumes: `io_mod.getenvProduct`, the existing `config_runtime.Settings`, and `settings_store.UserSettingsPatch`.
- Produces: `ui_preferences.Theme`, `ui_preferences.Density`, `ui_preferences.Motion`, `ui_preferences.Preferences`, parser/label functions, persisted settings keys, and `/settings` catalog entries.

- [ ] **Step 1: Define the typed preference contract and failing tests**

Create `src/core/config/ui_preferences.zig` with these public declarations:

```zig
pub const Theme = enum { auto, dark, light, high_contrast };
pub const Density = enum { compact, comfortable };
pub const Motion = enum { full, reduced };

pub const Preferences = struct {
    theme: Theme = .auto,
    density: Density = .compact,
    motion: Motion = .full,
    show_key_hints: bool = true,
};

pub fn parseTheme(raw: []const u8) ?Theme;
pub fn parseDensity(raw: []const u8) ?Density;
pub fn parseMotion(raw: []const u8) ?Motion;
pub fn themeLabel(value: Theme) []const u8;
pub fn densityLabel(value: Density) []const u8;
pub fn motionLabel(value: Motion) []const u8;
```

Add tests in the same file named `ui preference parser accepts documented values`, `ui preference parser rejects unknown values`, and `ui preference labels remain stable`. Assert the exact accepted values `auto`, `dark`, `light`, `high_contrast`, `compact`, `comfortable`, `full`, and `reduced`.

- [ ] **Step 2: Add the new module to the focused test root**

Add `_ = @import("core/config/ui_preferences.zig");` to `src/test_root.zig`. Add this Windows CI filter before any broad filter:

```powershell
zig test -lc src/test_root.zig --test-filter "ui preference parser"
```

Run the filter on `windows-latest`. It must fail only because the new declarations are not implemented yet if the test was written before implementation; after Step 1’s implementation it must report all matching tests passed.

- [ ] **Step 3: Extend settings precedence and persistence**

Add nullable fields to `config_runtime.Settings` and `ConfigSources`: `ui_theme`, `ui_density`, `ui_motion`, and `show_key_hints`. Add matching fields to `settings_store.UserSettingsPatch`, include them in `isEmpty`, validation, JSON parsing, root patching, merge precedence, and the existing `commit_first`/`runtime_first` accounting.

Use these serialized keys exactly:

```json
{
  "ui_theme": "auto",
  "ui_density": "compact",
  "ui_motion": "full",
  "show_key_hints": true
}
```

Add `OMFX_UI_THEME`, `OMFX_UI_DENSITY`, `OMFX_UI_MOTION`, and `OMFX_SHOW_KEY_HINTS` process overrides. Their legacy counterparts are `FX_UI_THEME`, `FX_UI_DENSITY`, `FX_UI_MOTION`, and `FX_SHOW_KEY_HINTS`. Keep the existing `OMFX_THEME`/`FX_THEME` light/dark override as a compatibility alias for terminal color detection, and let the explicit process override win over profile settings.

- [ ] **Step 4: Add settings catalog entries and deterministic option cycling**

Extend `settings_catalog.SettingId`, `Snapshot`, `Spec`, `optionCount`, `optionAt`, `selectedOptionIndex`, and `changeAt` with `ui_theme`, `ui_density`, `ui_motion`, and `show_key_hints`. Put the new entries in the `interface` category in this order: Theme, Density, Motion, Key hints.

Use these labels and values:

```text
Theme       Auto · Dark · Light · High contrast
Density     Compact · Comfortable
Motion      Full · Reduced
Key hints   On · Off
```

Add tests named `settings catalog exposes UI preference controls` and `settings catalog cycles UI preferences without skipping values`. Assert that every option is reachable exactly once with positive and negative deltas.

- [ ] **Step 5: Connect theme detection to the typed preference**

Keep `theme_detection.explicitThemeOverride() ?bool` as the low-level compatibility function. Add a typed resolver that maps `ui_preferences.Theme.auto` to terminal probing, `.dark` to `false`, `.light` to `true`, and `.high_contrast` to the dark high-contrast palette while retaining the explicit `OMFX_THEME`/`FX_THEME` behavior.

- [ ] **Step 6: Format, verify, and commit**

Run locally only:

```powershell
zig fmt src/core/config/ui_preferences.zig src/core/shared/io.zig src/core/config/config_runtime.zig src/core/config/settings_store.zig src/core/config/settings_catalog.zig src/ui/terminal/theme_detection.zig src/test_root.zig
git diff --check
```

Push the checkpoint and require the focused Windows filters `ui preference parser`, `settings catalog exposes UI preference controls`, and `settings catalog cycles UI preferences`. Commit as:

```powershell
git add src/core/config/ui_preferences.zig src/core/shared/io.zig src/core/config/config_runtime.zig src/core/config/settings_store.zig src/core/config/settings_catalog.zig src/ui/terminal/theme_detection.zig src/test_root.zig .github/workflows/windows.yml
git commit -m "feat: add omfx UI preference contract"
```

### Task 2: Normalize Windows terminal input and frame delivery

**Files:**

- Modify: `src/core/input/input_action.zig`
- Modify: `src/ui/input/escape_parser.zig`
- Modify: `src/ui/input/terminal_action_decoder.zig`
- Modify: `src/ui/input/shortcuts.zig`
- Modify: `src/ui/input/runtime.zig`
- Modify: `src/ui/terminal/terminal.zig`
- Modify: `src/ui/shell_runtime.zig`
- Modify: `src/ui/event_loop.zig`
- Modify: `src/test_root.zig`
- Modify: `.github/workflows/windows.yml`

**Interfaces:**

- Consumes: `input_action.TerminalDecodeContext`, `TerminalInputIngress`, existing raw/decoded action unions, and the current `TerminalState` polling methods.
- Produces: one-event-per-byte decoder behavior for Windows/ConPTY and VT terminals, complete common-key coverage, safe bare-Escape handling, and one settled frame per input delivery epoch.

- [ ] **Step 1: Add the decoder regression matrix before changing routing**

Extend tests in `src/ui/input/terminal_action_decoder.zig` with the exact matrix below:

```zig
try expectDecodedAction("\x1b[A", .cursor_up);
try expectDecodedAction("\x1b[B", .cursor_down);
try expectDecodedAction("\x1b[C", .cursor_right);
try expectDecodedAction("\x1b[D", .cursor_left);
try expectDecodedAction("\x1b[H", .home);
try expectDecodedAction("\x1b[F", .end);
try expectDecodedAction("\x1b[3~", .delete_next);
try expectDecodedAction("\x1b[200~", .paste_start);
try expectDecodedAction("\x1b[201~", .paste_end);
```

Add tests named `terminal decoder preserves CR and LF as surface input`, `terminal decoder key matrix does not emit duplicate events`, and `bare Escape emits once after quiet timeout`. Assert that a CR and LF each produce one raw ingress event, that a complete escape sequence produces exactly one decoded action, and that feeding `0x1b` followed by `flush(now + timeout)` emits one `.escape` action and no second event.

- [ ] **Step 2: Cover Windows modifier and keyboard protocol forms**

Extend `escape_parser.consumeInputEscapeByteWithMouse` and its tests for the common modifier forms emitted by Windows Terminal and ConPTY: `CSI 1;5A/B/C/D` for Ctrl arrows, `CSI 1;2A/B/C/D` for Shift arrows, `CSI 1;3A/B/C/D` for Alt arrows, `CSI 1;5H/F` for Ctrl Home/End, and Kitty `CSI <code>;<modifier>u` forms for Enter, Escape, Tab, and arrows.

Map each supported variant to the existing `input_action.Action` values (`cursor_up`, `cursor_down`, `cursor_left`, `cursor_right`, `home`, `end`, `insert_newline`, or `escape`). Do not add a second decoder. Unsupported modifier values must finish in `.ignore` and must not replay their payload as text.

- [ ] **Step 3: Make CR/LF, Escape, and surface fallbacks explicit**

Keep `approvalActionFromByte`, `questionActionFromByte`, and the composer shortcut table as the only surface translators. Add tests in `src/ui/input/runtime.zig` proving:

```zig
try std.testing.expectEqual(approval_decision.Action.submit, approvalActionFromByte('\r').?);
try std.testing.expectEqual(approval_decision.Action.submit, approvalActionFromByte('\n').?);
try std.testing.expectEqual(question_prompt.Action.submit, questionActionFromByte('\r', true).?);
try std.testing.expectEqual(question_prompt.Action.submit, questionActionFromByte('\n', false).?);
```

Verify that a bare Escape closes the current higher-priority surface before it reaches the composer, while a completed CSI sequence never triggers the bare-Escape path.

- [ ] **Step 4: Harden Windows terminal mode ownership**

In `src/ui/terminal/terminal.zig` and `src/ui/shell_runtime.zig`, keep the existing `interactiveModeEnableSequence`, but make the selected keyboard protocol explicit in `TerminalState`. On Windows, enable the VT/raw input path only after the native console handle is validated; when protocol negotiation is unavailable, use the legacy CSI decoder path. Ensure `disableRawMode`, alternate-screen restoration, and keyboard/paste/mouse cleanup run from one idempotent cleanup function on normal exit, input close, and error exit.

Add or extend the `Windows raw input mode` test to assert that cleanup can be called twice and still emits each restoration sequence at most once.

- [ ] **Step 5: Coalesce input frame commits**

In `src/ui/event_loop.zig`, preserve `max_input_reads_per_fact_collection = 32`, route every byte through `handle_byte`, call `settle_delivery_epoch` once after the current readable batch, and call `commit_frame` once for that batch. Extend the fake-terminal tests with a burst containing `Enter`, `Escape`, and an arrow sequence; assert the callback trace has one settle/commit pair after the batch and no commit from a partial escape sequence.

- [ ] **Step 6: Format, verify, and commit**

Run locally only:

```powershell
zig fmt src/core/input/input_action.zig src/ui/input/escape_parser.zig src/ui/input/terminal_action_decoder.zig src/ui/input/shortcuts.zig src/ui/input/runtime.zig src/ui/terminal/terminal.zig src/ui/shell_runtime.zig src/ui/event_loop.zig src/test_root.zig
git diff --check
```

Require these Windows filters: `terminal decoder key matrix`, `terminal decoder preserves CR and LF`, `bare Escape emits once`, `Windows raw input mode`, and `event loop commits once`. Commit as:

```powershell
git add src/core/input/input_action.zig src/ui/input/escape_parser.zig src/ui/input/terminal_action_decoder.zig src/ui/input/shortcuts.zig src/ui/input/runtime.zig src/ui/terminal/terminal.zig src/ui/shell_runtime.zig src/ui/event_loop.zig src/test_root.zig .github/workflows/windows.yml
git commit -m "fix: normalize Windows terminal input delivery"
```

### Task 3: Make surface focus, hints, and selection deterministic

**Files:**

- Create: `src/ui/input/interaction_contract.zig`
- Modify: `src/ui/input/runtime.zig`
- Modify: `src/ui/footer/interaction_state.zig`
- Modify: `src/ui/footer/row_text.zig`
- Modify: `src/ui/footer/render_input.zig`
- Modify: `src/ui/footer/settings_menu_presentation.zig`
- Modify: `src/ui/footer/appearance_menu_presentation.zig`
- Modify: `src/ui/footer/model_menu_presentation.zig`
- Modify: `src/ui/footer/picker_presentation.zig`
- Modify: `src/ui/settings_screen.zig`
- Modify: `src/ui/shell_runtime.zig`
- Modify: `src/main.zig`
- Modify: `src/test_root.zig`
- Modify: `.github/workflows/windows.yml`

**Interfaces:**

- Consumes: `input_action.TerminalInputEvent`, existing menu state types, and `shell_runtime.AlternateScreenOwner`.
- Produces: `interaction_contract.Surface`, `interaction_contract.Command`, `interaction_contract.route`, and one shared hint vocabulary used by every picker/approval/question surface.

- [ ] **Step 1: Define a pure surface-command contract and failing tests**

Create `src/ui/input/interaction_contract.zig` with:

```zig
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
    resume,
    skills,
    subagent_manager,
    terminal_takeover,
    auth,
};

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

pub fn route(surface: Surface, event: input_action.TerminalInputEvent) ?Command;
pub fn hint(surface: Surface, narrow: bool) []const u8;
```

Add tests named `interaction contract maps common navigation keys` and `interaction contract keeps surface-specific cancel behavior`. Assert that decoded Up/Down/Enter/Escape map to the expected commands for command/model/settings/approval/question surfaces, while a raw printable byte maps to `.edit` only for `composer`, `question`, and amendment-capable `approval` routing.

- [ ] **Step 2: Use one hint vocabulary**

Move the shared wording currently spread across `interaction_state.zig` into `interaction_contract.hint`. Keep the widest and compact forms:

```text
↑↓ Move    Enter Select    Esc Cancel
↑↓ Move    Tab Edit       Enter Confirm    Esc Cancel
Enter Confirm    Esc Cancel
```

Make `narrow` select a form that fits the measured width. Add tests for widths 18, 40, and 80 through the existing row composition helpers; every returned row must remain one line and fit its width.

- [ ] **Step 3: Route surface events without leaking ownership**

In `src/ui/input/runtime.zig` and the existing app input runtime, classify the active owner before applying a decoded event. Route auth, approval, question, picker, full-transcript, subagent, and terminal-takeover events before composer shortcuts. On `.cancel`, close only the active surface; on `.submit`, invoke only that surface’s existing commit action. Keep state mutation in the existing owning runtime and use `interaction_contract.route` only for classification.

Update `src/main.zig` only to wire the new contract and callbacks; do not add menu or provider logic to the composition root.

- [ ] **Step 4: Make selected rows visibly focused and width-safe**

Update each `*_menu_presentation.zig` row builder so the selected row uses `focus` styling, the current option uses `success` or `brand` styling only when it communicates state, and inactive options use `muted`. Preserve one-line clipping through `row_text.appendSingleLineEllipsized` and do not put OSC 8 targets through a clipped label.

Add focused tests named `settings menu Enter commits selected option`, `settings menu Escape restores previous surface`, `provider picker arrows move selection`, and `question freeform Enter submits`. Assert both state change and returned surface ownership.

- [ ] **Step 5: Verify alternate-screen restoration at every owner boundary**

Extend `shell_runtime` and screen tests so opening and closing each `AlternateScreenOwner` leaves the same `TerminalState` flags, cursor visibility, paste mode, mouse mode, keyboard protocol, and footer reservation as before entry. Add a failure-path test for an owner whose frame composition returns an error; cleanup must still execute.

- [ ] **Step 6: Format, verify, and commit**

Run locally only:

```powershell
zig fmt src/ui/input/interaction_contract.zig src/ui/input/runtime.zig src/ui/footer/interaction_state.zig src/ui/footer/row_text.zig src/ui/footer/render_input.zig src/ui/footer/settings_menu_presentation.zig src/ui/footer/appearance_menu_presentation.zig src/ui/footer/model_menu_presentation.zig src/ui/footer/picker_presentation.zig src/ui/settings_screen.zig src/ui/shell_runtime.zig src/main.zig src/test_root.zig
git diff --check
```

Require Windows filters for the four named interaction tests plus `alternate screen` and `footer tiny widths`. Commit as:

```powershell
git add src/ui/input/interaction_contract.zig src/ui/input/runtime.zig src/ui/footer/interaction_state.zig src/ui/footer/row_text.zig src/ui/footer/render_input.zig src/ui/footer/settings_menu_presentation.zig src/ui/footer/appearance_menu_presentation.zig src/ui/footer/model_menu_presentation.zig src/ui/footer/picker_presentation.zig src/ui/settings_screen.zig src/ui/shell_runtime.zig src/main.zig src/test_root.zig .github/workflows/windows.yml
git commit -m "fix: make omfx surface interactions deterministic"
```

### Task 4: Apply Night Signal semantic styling and accessibility modes

**Files:**

- Modify: `src/core/shared/product_theme.zig`
- Modify: `src/ui/render.zig`
- Modify: `src/ui/assistant/user_message_card.zig`
- Modify: `src/ui/approval_screen.zig`
- Modify: `src/ui/footer/approval_ui.zig`
- Modify: `src/ui/footer/picker_presentation.zig`
- Modify: `src/ui/footer/model_menu_presentation.zig`
- Modify: `src/ui/footer/settings_menu_presentation.zig`
- Modify: `src/ui/full_transcript_screen.zig`
- Modify: `src/ui/help_screen.zig`
- Modify: `src/ui/models_screen.zig`
- Modify: `src/ui/resume_screen.zig`
- Modify: `src/ui/skills_screen.zig`
- Modify: `src/test_root.zig`
- Modify: `.github/workflows/windows.yml`

**Interfaces:**

- Consumes: `ui_preferences.Preferences`, terminal truecolor detection, and existing compatibility style globals in `src/ui/render.zig`.
- Produces: `product_theme.Variant`, `product_theme.PaletteOptions`, `product_theme.paletteFor`, consistent role assignment, high-contrast fallback, and reduced-motion rendering decisions.

- [ ] **Step 1: Add palette variants and complete semantic-role tests**

Extend `product_theme.zig` with:

```zig
pub const Variant = enum { dark, light, high_contrast };

pub const PaletteOptions = struct {
    truecolor: bool,
    variant: Variant,
};

pub fn paletteFor(options: PaletteOptions) Palette;
```

Keep `palette(truecolor, light)` as a compatibility wrapper. Add tests named `Night Signal palette exposes every semantic role`, `Night Signal high contrast palette separates focus and text`, and `Night Signal fallback palette stays 256 color`. Assert every role is nonempty in truecolor and fallback variants, high contrast focus differs from text, and fallback strings contain only `38;5;` foreground sequences.

- [ ] **Step 2: Route all render globals through the palette**

Update `render.initTheme`, `setTruecolorSupport`, and the preference application path so `brand_style`, `focus_style`, `success_style`, `danger_style`, `border_style`, `divider_style`, `hint_style`, `statusline_style`, `warning_style`, `green_style`, `red_style`, approval styles, completion styles, and diff marker styles are assigned from the semantic palette or documented derived roles.

Do not change protocol or storage strings. Keep `reset_style` and structural ANSI sequences separate from color roles. Add a render test that initializes dark, light, high-contrast, and fallback modes in sequence and asserts no mode retains a previous mode’s color.

- [ ] **Step 3: Replace component-local status colors**

Search the listed UI files for hardcoded foreground/background color sequences. Replace status/focus/error/success literals with the render semantic style fields. Keep syntax-highlighting language colors owned by the code-highlighting module and keep diff marker colors as the documented derived roles.

For every replaced component, add a string-level test that checks selected/failure/success output contains the expected semantic style and reset sequence. Do not add background fills to inactive rows.

- [ ] **Step 4: Add no-color, narrow, and reduced-motion behavior**

When color is disabled, emit readable text and structural markers without ANSI styles. When `Preferences.motion == .reduced`, suppress shimmer and nonessential animated frame updates while keeping textual loading/status changes. When the terminal is narrower than the hint row, use the compact hint variants from Task 3.

Add tests named `no color keeps approval decisions distinguishable`, `reduced motion removes shimmer frames`, and `light palette keeps primary text readable`.

- [ ] **Step 5: Format, verify, and commit**

Run locally only:

```powershell
zig fmt src/core/shared/product_theme.zig src/ui/render.zig src/ui/assistant/user_message_card.zig src/ui/approval_screen.zig src/ui/footer/approval_ui.zig src/ui/footer/picker_presentation.zig src/ui/footer/model_menu_presentation.zig src/ui/footer/settings_menu_presentation.zig src/ui/full_transcript_screen.zig src/ui/help_screen.zig src/ui/models_screen.zig src/ui/resume_screen.zig src/ui/skills_screen.zig src/test_root.zig
git diff --check
```

Require Windows filters `Night Signal palette`, `Night Signal high contrast`, `no color keeps approval decisions`, `reduced motion removes shimmer`, and `light palette`. Commit as:

```powershell
git add src/core/shared/product_theme.zig src/ui/render.zig src/ui/assistant/user_message_card.zig src/ui/approval_screen.zig src/ui/footer/approval_ui.zig src/ui/footer/picker_presentation.zig src/ui/footer/model_menu_presentation.zig src/ui/footer/settings_menu_presentation.zig src/ui/full_transcript_screen.zig src/ui/help_screen.zig src/ui/models_screen.zig src/ui/resume_screen.zig src/ui/skills_screen.zig src/test_root.zig .github/workflows/windows.yml
git commit -m "feat: apply Night Signal semantic styling"
```

### Task 5: Harden provider/auth state and Windows browser activation

**Files:**

- Modify: `src/core/hosts/url_opener.zig`
- Modify: `src/ui/footer/row_text.zig`
- Modify: `src/core/app/app_auth_runtime.zig`
- Modify: `src/core/auth/auth_runtime.zig`
- Modify: `src/core/auth/credentials.zig`
- Modify: `src/core/config/model_provider.zig`
- Modify: `src/builtins/commands.zig`
- Modify: `src/core/cli/cli_surface.zig`
- Modify: `src/core/output/output_contracts.zig`
- Modify: `src/test_root.zig`
- Modify: `.github/workflows/windows.yml`

**Interfaces:**

- Consumes: `host.UrlOpener`, auth source inventory, provider activation, catalog access, and existing `openSignInBrowser`/`openChatGptSignInPickerForProviderSwitch` seams.
- Produces: full-target hyperlink rendering, Windows one-argument URL launching, explicit authenticated-provider status, and recovery copy that never replaces a working credential on failed auth.

- [ ] **Step 1: Preserve full OAuth targets independently from visible labels**

Keep `row_text.appendHyperlinkClipped`’s contract that `url` is written in full and only `label` is clipped. Add a regression test with a URL containing `redirect_uri`, `code`, and `state`; feed the output through the VT emulator and assert the stored hyperlink target equals the original URL byte-for-byte while the visible label fits the requested width.

- [ ] **Step 2: Verify and harden the Windows launcher**

Keep the Windows argv exactly as:

```text
rundll32.exe url.dll,FileProtocolHandler <complete-url>
```

Update `url_opener` tests to assert query strings containing `&`, `%2F`, `=`, and `+` remain one argument. Add a failure message path that tells the user to open the displayed complete URL manually when the launcher returns a nonzero exit code.

- [ ] **Step 3: Make auth state drive onboarding and provider availability**

In `app_auth_runtime` and `auth_runtime`, after successful Vercel or Codex sign-in, refresh source inventory, activate the selected provider, fetch its catalog when available, and persist the provider/model selection only after activation succeeds. On failure, preserve the current source, current provider, and current model. Ensure a signed-in Codex source exposes the Codex model catalog in `/models`, `/status`, and the provider picker without reopening the root onboarding screen.

For OpenCode Go, keep `OPENCODE_GO_API_KEY` as the credential name and show the exact recovery instruction `set OPENCODE_GO_API_KEY first`. Do not rename provider wire identifiers.

- [ ] **Step 4: Make browser opening automatic but explicit**

Keep `FX_NO_OPEN_BROWSER` behavior and add `OMFX_NO_OPEN_BROWSER` precedence. When a sign-in code becomes ready, open the complete URL once unless either override is present. Enter reopens the same complete URL; Escape cancels without changing credentials. The visible auth screen may ellipsize the line, but its hyperlink target and manual-copy value must remain complete.

Add tests named `ChatGPT browser authorization URL keeps redirect URI`, `auth success activates the selected provider`, `auth failure preserves the current credential`, and `browser login cancellation releases callback listener`.

- [ ] **Step 5: Align public recovery copy**

Update command/help/status output so the active provider, credential source, catalog availability, and recovery command are named consistently. Preserve `fx` only in compatibility explanations and preserve protocol originator values in transport headers.

- [ ] **Step 6: Format, verify, and commit**

Run locally only:

```powershell
zig fmt src/core/hosts/url_opener.zig src/ui/footer/row_text.zig src/core/app/app_auth_runtime.zig src/core/auth/auth_runtime.zig src/core/auth/credentials.zig src/core/config/model_provider.zig src/builtins/commands.zig src/core/cli/cli_surface.zig src/core/output/output_contracts.zig src/test_root.zig
git diff --check
```

Require Windows filters `ChatGPT browser authorization URL`, `auth success activates`, `auth failure preserves`, `provider credential guidance`, `auth status snapshot`, `Windows browser callback readiness`, and `clipped footer hyperlinks preserve`. Commit as:

```powershell
git add src/core/hosts/url_opener.zig src/ui/footer/row_text.zig src/core/app/app_auth_runtime.zig src/core/auth/auth_runtime.zig src/core/auth/credentials.zig src/core/config/model_provider.zig src/builtins/commands.zig src/core/cli/cli_surface.zig src/core/output/output_contracts.zig src/test_root.zig .github/workflows/windows.yml
git commit -m "fix: make provider onboarding state explicit"
```

### Task 6: Finish public customization, CI enforcement, and artifact verification

**Files:**

- Modify: `src/builtins/commands.zig`
- Modify: `src/core/cli/cli_surface.zig`
- Modify: `src/ui/render.zig`
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`
- Create: `docs/customization.md`
- Modify: `.github/workflows/windows.yml`
- Modify: `src/test_root.zig`

**Interfaces:**

- Consumes: all preference, input, surface, theme, and auth contracts from Tasks 1–5.
- Produces: documented omfx customization controls, required Windows unit checks, primary `omfx.exe` and compatibility `fx.exe` artifacts, and a reproducible handoff for interactive verification.

- [ ] **Step 1: Add the user-facing customization command surface**

Update `/settings` help and the top-level help registry to list Theme, Density, Motion, Key hints, Status line, Input appearance, and Presentation. Keep command parsing in `src/core/slash_commands/command_specs.zig` and dispatch in the existing CLI surface; do not scatter new help strings into `main.zig`.

Add `docs/customization.md` with exact examples:

```json
{
  "ui_theme": "high_contrast",
  "ui_density": "comfortable",
  "ui_motion": "reduced",
  "show_key_hints": true
}
```

```powershell
$env:OMFX_UI_THEME = "dark"
$env:OMFX_UI_DENSITY = "comfortable"
$env:OMFX_UI_MOTION = "reduced"
$env:OMFX_SHOW_KEY_HINTS = "true"
```

Document that `OMFX_*` wins over `FX_*`, settings live under the existing `.fx` profile, and `fx` remains a compatibility command.

- [ ] **Step 2: Update README and contribution guidance**

Describe Night Signal, keyboard behavior, light/high-contrast/no-color modes, reduced motion, Windows Terminal/ConPTY support, provider status, and the `omfx.exe`/`fx.exe` artifact relationship. Keep the canonical upstream repository and `https://fx.sh` links required by `AGENTS.md`.

- [ ] **Step 3: Remove masked broad unit filters**

Replace the current broad `--test-filter "provider"` line in `.github/workflows/windows.yml` with the named filters from Tasks 1–5. Remove `continue-on-error: true` from the Windows unit-test job only after every named filter passes on the exact commit. Keep the full suite out of the Windows job until a separate sharded parity job exists; do not re-enable the disabled workflows.

- [ ] **Step 4: Make the Windows build artifact gate explicit**

Keep the ReleaseSafe build, `zig fmt --check src/`, `FX_BENCH=1` smoke, staged `omfx.exe`, OpenCode Go catalog/chat smoke, and both artifact uploads. Add checks that `fx.exe` and `omfx.exe` have identical byte lengths and that both `help` outputs begin with ASCII `omfx v` and contain no mojibake branding bytes.

- [ ] **Step 5: Run the complete focused Windows verification**

Push the final checkpoint and wait for the Windows workflow. Inspect job conclusions, not only the run-level conclusion:

```powershell
gh run list --repo blu3ph4ntom/oh-my-fx --workflow windows.yml --limit 5
gh run view <run-id> --repo blu3ph4ntom/oh-my-fx --json jobs --jq '.jobs[] | "\(.status) \(.conclusion) \(.name)"'
gh run view <run-id> --repo blu3ph4ntom/oh-my-fx --log-failed
```

The build and required unit-test jobs must be green for the exact final commit. Download the `omfx-windows-x86_64` artifact into a fresh local artifact directory and run only the downloaded binary, never a bare PATH command:

```powershell
.\omfx-windows-x86_64\omfx.exe help
.\omfx-windows-x86_64\omfx.exe status --json
.\omfx-windows-x86_64\omfx.exe models --json
```

Then drive one real interactive session in Windows Terminal: launch `omfx.exe`, use `/help`, Down, Up, Enter, Escape, `/settings`, change one UI preference, return to the composer, type a prompt, and exit with `/quit`. Record exit code, stderr, terminal cursor/mouse/paste state, and the exact CI run ID.

- [ ] **Step 6: Format, verify repository state, and commit**

Run locally only:

```powershell
zig fmt src/builtins/commands.zig src/core/cli/cli_surface.zig src/ui/render.zig src/test_root.zig
git diff --check
git status --short
```

Do not stage downloaded artifact directories, `.zig-cache`, `zig-out`, `.fx`, or `.env.local`. Commit as:

```powershell
git add src/builtins/commands.zig src/core/cli/cli_surface.zig src/ui/render.zig README.md CONTRIBUTING.md docs/customization.md .github/workflows/windows.yml src/test_root.zig
git commit -m "docs: document omfx customization and enforce Windows gates"
```

## Final Self-Review Checklist

- [ ] Every requirement in `docs/superpowers/specs/2026-09-07-omfx-full-customization.md` maps to at least one task above.
- [ ] No new input path bypasses `input_action.TerminalInputEvent`.
- [ ] No settings mutation changes the default `.fx` root or removes legacy `FX_*` behavior.
- [ ] No UI state uses a color without a readable text or structural fallback.
- [ ] Every new public declaration has a focused unit test in its owning source file.
- [ ] The Windows unit job is required and contains only finite named filters.
- [ ] The exact final commit has green Windows build and unit-test jobs.
- [ ] The downloaded `omfx.exe` has been run interactively and restored the terminal cleanly.
