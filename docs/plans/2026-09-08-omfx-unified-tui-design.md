# omfx Unified TUI Design

**Status:** Approved design; implementation follows in a separate plan.

## Goal

Make the Windows-native omfx terminal experience feel like one deliberate instrument: stable inline conversation, predictable keyboard behavior, consistent transient surfaces, clear state, and a distinctive Night Signal visual system.

This work is limited to the terminal UI. Website, documentation-site, and broader product marketing work are out of scope for this pass.

## Product outcomes

- The transcript and composer remain the permanent center of gravity.
- Menus, pickers, approvals, settings, help, questions, and subagent views share one frame, spacing system, focus treatment, and keyboard vocabulary.
- Enter, Escape, Up, Down, Left, Right, Tab, and Ctrl+C behave deterministically on Windows Terminal, ConPTY, and Unix terminals.
- Loading, success, warning, danger, and error states are readable without depending on color alone.
- Resize, narrow terminals, light mode, 256-color terminals, no-color output, and reduced motion remain usable.
- Terminal modes, cursor state, paste/mouse state, focus, and the main screen are restored after every modal, cancellation, error, and process exit path.
- `omfx` owns the visible identity while preserving `fx` protocol and compatibility behavior where required.

## Scope and non-goals

In scope:

- Main inline transcript/composer hierarchy and footer.
- Shared surface frame and spacing behavior.
- Shared focus, selection, disabled, loading, error, and success presentation.
- Input normalization and event routing across all interactive surfaces.
- Alternate-screen ownership and cleanup boundaries.
- Windows-specific rendering, browser-link, resize, and terminal-mode behavior.
- Deterministic unit, TUI, and Windows CI coverage for the changed paths.

Out of scope:

- Website or documentation-site redesign.
- New provider behavior unrelated to TUI presentation.
- A decorative dashboard, permanent sidebar, or browser-style shell.
- A second parallel execution path for any existing command or provider.

## Architecture

`src/core/` remains the owner of product state, commands, auth, providers, sessions, configuration, and persistence. `src/ui/` remains the owner of terminal rendering, input, layout, transcript presentation, and terminal lifecycle; it does not own product state.

The existing semantic theme, surface-frame, row-text, and interaction-contract modules become the shared presentation boundary. Each interactive surface provides semantic content and state to those primitives instead of inventing its own colors, borders, clipping, focus rules, or keyboard handling.

The event loop is the single owner of normalized input and redraw invalidation. Surface-specific timers, sleeps, competing readers, and ad-hoc redraw loops are not part of the design. Redraws are coalesced around state changes; reduced-motion mode removes nonessential transitional frames.

`AlternateScreenOwner` is the only owner allowed to enter the alternate buffer. It is used only for interactive permission review, full transcript, catalog menus, the Ctrl+X subagent manager, and hosted child-terminal takeover. Inline transcript rendering, question prompts, and command-output expansion stay in the main grid.

## Interaction contract

Input is normalized once at the terminal boundary for both Windows and Unix. Surface routing follows visible ownership:

1. The active modal or alternate-screen surface receives the event.
2. The composer receives text editing and history events.
3. Global shortcuts receive only events not consumed above.

The contract is:

- Enter confirms the focused action exactly once and never leaks an extra newline or filesystem action.
- Escape cancels the current layer and returns to the previous stable surface.
- Up and Down navigate lists and history.
- Left and Right change options where a row has alternatives.
- Tab cycles focus only where multiple controls exist.
- Ctrl+C cancels the active operation and restores terminal modes.
- Browser links are explicit actions and use the complete URL, independent of visible clipping.
- Failed auth keeps the previous credential unchanged and returns an actionable error to the same surface.
- Resize invalidates layout safely without losing focus, text, or scroll position.

Every surface exposes one focused element at a time, a visible focus treatment, a confirm action, a cancel action, and a stable status area. Disabled controls cannot consume confirmation. Loading controls cannot be activated twice.

## Visual system

Night Signal is the canonical omfx TUI language:

- Brand: cool cyan for omfx identity and primary active accents.
- Focus: violet with an additional marker or weight change so focus is not color-only.
- Success: green; warning: amber; danger: red.
- Text: cool near-white; muted: quiet blue-gray; border: restrained slate.
- Truecolor is preferred, with 256-color, ANSI, and no-color fallbacks.

The layout uses an inline transcript/composer with a stable three-row footer: divider, input, and status or hints. Density supports compact and comfortable modes. Spacing, borders, title placement, hint order, and action alignment are shared across surfaces. Long labels wrap or truncate visibly without removing the underlying action target.

Motion is state-only. No shimmer or decorative animation is required. Reduced-motion mode removes transitional frames and keeps only meaningful progress changes.

## Surface behavior

The main surface shows identity, workspace/model/auth state, transcript, composer, and contextual hints without overwhelming the conversation. Errors appear near the affected action and remain legible after the next redraw.

Transient surfaces use the same structure:

- title and context line;
- bounded content/list area;
- visible focus and selection;
- primary and cancel actions;
- status or error line;
- keyboard hints in a consistent order.

Surfaces must close transactionally. On normal close, Escape, Ctrl+C, resize failure, provider failure, and unexpected error, cleanup restores the prior buffer, cursor, paste/mouse, focus, keyboard modes, and terminal title state.

## Verification strategy

- Keep pure rendering, clipping, theme, key-normalization, focus, and surface-transition tests beside their owning Zig modules.
- Add regression coverage for duplicate Enter delivery, arrow decoding, Escape cancellation, Ctrl+C cleanup, browser-link completeness, resize, narrow width, and alternate-screen restoration.
- Exercise the real Windows binary through CI smoke paths and a PTY interaction covering help, navigation, cancellation, and exit.
- Keep local verification read-only or formatting-only because the development machine is RAM-constrained; Zig build and test authority is the Windows GitHub Actions runner for this phase.
- Do not call the feature ready until the repository’s required build, focused tests, exact-current-commit CI, and real binary interaction gates are satisfied.

## Acceptance criteria

The TUI is accepted when a user can launch the fresh Windows omfx artifact, see the omfx identity, navigate every primary interactive surface with the contract above, confirm and cancel actions without crashes or duplicate input, use auth/provider flows without clipped-link or filesystem detours, resize or interrupt safely, and return to a usable terminal with no stderr panic or leaked terminal mode.
