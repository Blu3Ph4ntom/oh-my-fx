# Task 3 implementation report

## Scope and checkpoint

Implemented input ownership changes and regression coverage only in the seven primary Task 3 files. No changes to shell_runtime.zig, terminal.zig, resize_runtime.zig, presenters, product state ownership, renderer architecture, dependencies, or E2E corpus classification.

Started at 07cc218. Preserved Task 1/2 and the concurrent presenter checkpoints 74ed105 (compact resume width budgets) and 9f0f669 (explicit resume width casts). The two untracked omfx Windows distribution directories were untouched. This report belongs to the commit titled `fix: make omfx surface ownership single-path`.

## Implementation

- Added the app input surface resolver. Physical terminal takeover remains admitted outside Fx decoding; full transcript, decision prompts, subagent surface, auth, catalogs, and composer are classified before fallback routing. Inline completions remain composer editing so a standalone LF retains its newline meaning.
- Common Enter classification now precedes composer shortcut fallback. A menu's LF is Enter, while the composer's LF remains insert_newline. Auth Enter, Tab, navigation, Ctrl+C, and Escape are consumed before underlying catalogs/composer. Escape can pop auth and reveal an existing menu without closing that menu in the same event.
- Prevented auth action routing and visible picker navigation from intercepting decision-owned events. Moved full transcript routing before auth handling.
- Added UI-owned protocol alias normalization, reusing the existing typed approval/question/subagent decorators and control-feature mapper. The app ingress normalizes a remapped byte once rather than replaying that byte through terminal decoding. Legitimate bare-Escape replay remains intact.
- Added CRLF coalescing to the decoder within a delivery epoch. The existing delivery settlement clears the CR latch even when no paste is active. A later standalone LF and paste payload LF are retained. Paste still uses the existing framing owner.
- Kept existing event-loop batching, RenderRequest frame attempts, resize ownership, reduced-motion behavior, and alternate-screen restoration implementation. Added integration coverage instead of replacing those contracts.

## Regression coverage added

- Interaction contract table covers all 15 declared surfaces: CR/LF, Escape, navigation/page movement, and controls intentionally delegated to domain handlers (Ctrl+C, Tab, unsupported byte, paste).
- Decoder regression checks CRLF suppression, subsequent LF, epoch separation, and paste preservation. Existing CSI, modified/Kitty keys, bare Escape, mouse, and paste regressions remain unchanged.
- Protocol normalization regression asserts decision payloads for Enter/Ctrl+C and preservation of the Ctrl+O global action.
- App integration tests feed bytes through the existing decoder/routing helper for provider CR, LF, CRLF and Kitty Enter; full transcript over auth; question over auth; approval over auth; Escape revealing an underlying help menu; and a standalone LF in the next epoch. Composer submission counts and draft preservation are asserted.
- Resize integration invokes the existing resize implementation, then inserts at the preserved draft cursor and checks the updated footer layout and invalidation.
- Event-loop integration uses real auth state and RenderRequest state to combine resize/activity facts with multiple readable input chunks and a surface close. It checks that the single commit sees the closed owner and all bytes.
- RenderRequest regression checks that resize blocks attempts, coalesces repeated footer/modal/transcript requests, and leaves no redundant attempt after commit.
- Lifecycle regressions exercise shutdown dispatch for every alternate owner using file output and the shadow terminal. They check restoration/idempotence and preservation of ownership on output failure followed by a successful retry. Existing mode/keyboard restoration and terminal-takeover tests remain unchanged.

## Verification performed

Only the user-authorized local checks were run:

- Absolute `A:\zig-toolchain\zig-x86_64-windows-0.16.0\zig.exe fmt` on all seven changed Zig files: passed.
- `git diff --check`: passed.

No local build, unit-test execution, E2E execution, or binary interaction was attempted because of the explicit RAM constraint. New regressions have not been compiled or observed failing/passing. Formatting is not evidence of runtime correctness.

## Outstanding verification and concerns

- Require focused Windows decoder, interaction-contract, app-input, event-loop, render-request and lifecycle tests in CI. Then run TUI input-navigation, keybindings, interrupt-recovery, resize, native-clear-recovery, decision-prompt and auth-source-selection E2Es.
- Full CI on the exact integrated commit, all required native runners, the final ship gate, and a fresh built-binary happy-path interaction remain outstanding. No ready-for-review claim is made. No push/PR or remote CI was initiated in this shared implementer checkout.
- CRLF is intentionally coalesced only inside a delivery epoch. A CR and LF separated by epoch settlement are distinct input so intentional composer newlines cannot be swallowed. Verify this policy against native Windows input delivery and the existing burst limit.
- The added lifecycle tests cover shared shutdown and output-error recovery, not a separate real-TTY success/cancel/error/EOF matrix for every owner and every terminal mode. Existing terminal-mode tests and CI TUI coverage remain necessary.
- The new resolver retains the existing child/approval binding policy and completion handlers. Concurrent child takeover and approval handoff require the existing native TUI tests; no additional product state or renderer was introduced.
