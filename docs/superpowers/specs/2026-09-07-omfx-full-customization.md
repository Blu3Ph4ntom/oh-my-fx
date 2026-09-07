# omfx Full Customization and Windows Interaction Design Brief

**Status:** Approved direction; implementation plan follows.

## 1. Feature Summary

This is a product-wide omfx customization pass for the existing terminal
coding-agent product. It deepens the approved Night Signal identity across
rendering, interaction, onboarding, provider/auth state, profile settings,
Windows-native behavior, and public documentation while preserving the
existing `fx` compatibility boundary.

The work is production-oriented and must make the interactive shell reliable
on Windows Terminal and ConPTY. Visual polish is valuable only when it makes
state and action clearer; input ownership and terminal restoration are part of
the design, not follow-up work.

## 2. Primary User Action

The user should be able to type a prompt, navigate a picker or approval screen,
confirm or cancel it, and immediately understand what omfx is doing without
lost keys, stale frames, flicker, or unexplained mode changes.

## 3. Design Direction

Color strategy: restrained product palette with semantic accents for identity,
focus, status, and errors.

Theme scene: a developer works in Windows Terminal or a Unix terminal after
dark, moving rapidly between code, approvals, and model responses; omfx is a
quiet, precise instrument that becomes expressive only when state changes.

Named anchor references:

- Raycast for keyboard-first command surfaces and compact affordances.
- Linear for clear state communication and restrained product hierarchy.
- Windows Terminal for native terminal behavior and capability-aware fallback.

The existing Night Signal palette and shell-like form factor are the baseline.
No permanent dashboard or decorative full-screen redesign is intended.

## 4. Scope

- Fidelity: production-ready.
- Breadth: the interactive shell, transient UI surfaces, CLI onboarding and
  status/help output, profile customization, Windows behavior, and docs.
- Interactivity: shipped keyboard-first behavior, with pointer support only
  where the terminal can report it safely.
- Time intent: polish until the Windows artifact is reliable and observable.

The implementation is split into small, independently testable checkpoints:
input/event reliability; semantic visual system; provider/auth and onboarding
state; profile customization; and docs/CI/artifact verification.

## 5. Layout Strategy

The inline transcript and composer remain the primary surface. The footer keeps
its stable divider, input, and hint/status rows so the terminal does not jump
when state changes. The transcript receives the largest visual area; the
composer receives the strongest focus treatment; status and hints stay muted
until they carry an actionable state.

Transient surfaces use the existing alternate-screen owner model. Menus,
approvals, questions, full transcript, subagent management, and terminal
takeover must share frame spacing, title placement, semantic colors, and a
single exit path that restores the main terminal grid and input modes.

No permanent sidebar, card grid, or decorative background is added. Hierarchy
comes from alignment, compact spacing, borders, and deliberate state color.

## 6. Key States

- Startup with no credential: explain the available sign-in/API-key paths and
  keep the composer usable for deferred setup.
- Authenticated provider: show the active provider and model source; do not
  reopen onboarding merely because another provider is unavailable.
- Credential expired or missing: name the exact provider and recovery command;
  preserve the current credential until a replacement succeeds.
- Model catalog loading, empty, and failed: show progress, a useful empty
  explanation, or a bounded retry/recovery action.
- Composer default, multiline, completion, history, paste, and cursor-editing:
  keep the cursor visible and preserve text on every navigation action.
- Command/model picker: show a selected row, visible focus, loading/no-match
  state, and deterministic Enter/Escape behavior.
- Approval and amendment: show the selected decision, amendment focus, exact
  key hints, and a clear success/denial result.
- Question prompt: support choice movement, freeform editing, submit, and
  cancel without routing keys to the parent composer.
- Full transcript, resume, subagent manager, and terminal takeover: each owns
  its input until it closes and restores the previous surface.
- Resize and too-small terminal: remeasure, wrap or compact hints, and never
  hide the only submit/cancel action.
- Light terminal, 256-color terminal, no-color mode, and reduced motion: retain
  contrast, state meaning, and usable keyboard feedback.
- Clean exit and failure exit: restore cursor visibility, paste, mouse,
  keyboard protocol, alternate screen, and terminal title state.

## 7. Interaction Model

Raw terminal bytes are normalized once at the input boundary into logical
events. The normalized contract covers CR/LF Enter, bare Escape timeout,
arrows, Home/End, Delete/Backspace, Tab, Ctrl+C, Ctrl+D, Ctrl+L, paste, mouse
reports, Kitty/CSI variants, and Windows ConPTY behavior.

Each surface declares its input owner and maps only the events it understands:

- Enter confirms or submits.
- Escape cancels or closes the current surface.
- Up/Down moves a selection or navigates the composer according to focus.
- Tab cycles choices or enters amendment/freeform mode according to the
  surface contract.
- Ctrl+C cancels the active operation; it never inserts or disappears silently.
- Unsupported sequences are discarded safely and cannot leak a partial event
  into the next surface.

Accepted input settles one delivery epoch and produces one deterministic frame
commit. Terminal mode negotiation and restoration remain centralized. Browser
links are explicit actions: Enter activates the selected URL through the native
Windows default-browser path, the displayed URL may wrap for readability, and
the underlying URL is never truncated or passed to a filesystem association.

## 8. Content Requirements

- Public name: `omfx`.
- Compatibility name: `fx`; preserve `.fx`, `FX_*`, and `_meta.fx` contracts.
- Startup/help/status copy is ASCII-safe and uses omfx consistently.
- Hints use one vocabulary: `↑↓ Move`, `Enter Select`, `Esc Cancel`, and
  `Tab Edit` where relevant.
- Auth/provider messages name the provider, credential source, and recovery
  command without claiming success before persistence and activation finish.
- Empty and error states explain what the user can do next.
- No emoji is added to code, output, or documentation. Unicode control symbols
  remain optional and must have a readable ASCII fallback.

## 9. Recommended References

- `interaction-design.md` for the complete interactive-state matrix and focus
  behavior.
- `color-and-contrast.md` for semantic contrast and light-terminal checks.
- `motion-design.md` for reduced-motion and frame-coalescing rules.
- `spatial-design.md` for footer, transient-surface, and narrow-terminal
  hierarchy.
- `ux-writing.md` for auth, catalog, permission, and recovery copy.

## 10. Open Questions

1. Keep arbitrary user-defined ANSI themes out of the first reliability pass;
   ship named semantic variants first so invalid colors cannot make controls
   unreadable. Revisit a theme file after the state contract is stable.
2. Keep the default keymap stable in this pass. Add remapping only if the
   normalized logical-event contract proves sufficient and a concrete user
   workflow requires it.
3. Live provider authentication remains credentialed user verification. CI
   should prove deterministic auth seams and provider routing; the user must
   run the downloaded Windows artifact for a real browser and subscription
   round trip.

## Acceptance Criteria

1. Every interactive surface has deterministic Enter, Escape, Up/Down, and Tab
   behavior where the surface advertises those keys.
2. Windows Terminal and ConPTY no longer lose common control sequences or leave
   stale cursor, mouse, paste, keyboard, title, or alternate-screen state.
3. Night Signal semantic roles are used consistently in dark, light,
   256-color, no-color, and reduced-motion modes.
4. Provider/auth state is reflected in onboarding, status, model catalogs, and
   recovery copy without overwriting a working credential on failure.
5. Profile settings and `OMFX_*` aliases customize the documented controls;
   legacy `FX_*` behavior remains compatible.
6. Focused tests and the Windows CI artifact prove the changed paths. No local
   Zig build or test is required under the RAM constraint; the final claim must
   include the exact CI run and an interactive `omfx.exe` check.
