Status: DONE_WITH_CONCERNS

Changed files: `src/core/auth/chatgpt_oauth.zig`, `src/gateway/openai_codex.zig`, `src/gateway/openai_codex_models.zig`, `src/test_root.zig`, `.github/workflows/windows.yml`.
Tests: Added the exact URL assertions and deterministic exactly-one originator header characterization tests; production originator literals remain unchanged.
Windows CI RED output: Not available in this environment; the two requested commands are wired into `.github/workflows/windows.yml`.
Local formatting: Not performed because `zig` is not installed; `git diff --check` passed.
Self-review: No production originator fix was implemented; both Codex request builders are covered; unrelated `omfx-windows-x86_64-f2d2869/` remains untouched.
Concerns: Windows CI must run the filters to capture the expected RED result; Zig compilation was intentionally not attempted per task constraint.

Fix round 1
Status: DONE_WITH_CONCERNS
Changed files: `src/gateway/openai_codex.zig`, this report.
Change: Added the streaming request originator characterization test using a nonempty session ID; production `originator: fx` literals were not changed.
Windows run `34057370061`, job `Windows unit tests` (`101551607586`): completed `failure` at step `Run unit tests`.
Command results: `zig test -lc src/test_root.zig --test-filter "ChatGPT browser authorization URL"` passed; `zig test -lc src/test_root.zig --test-filter "Codex request originator"` failed as expected in the catalog test: expected `codex_cli_rs`, found `fx`.
The run’s `Windows native build (ReleaseSafe)` job was still in progress when recorded; no local Zig build/test was run, and local `zig fmt` remains unavailable.
