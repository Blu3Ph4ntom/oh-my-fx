Status: DONE_WITH_CONCERNS

Changed files: `src/core/auth/chatgpt_oauth.zig`, `src/gateway/openai_codex.zig`, `src/gateway/openai_codex_models.zig`, `src/test_root.zig`, `.github/workflows/windows.yml`.
Tests: Added the exact URL assertions and deterministic exactly-one originator header characterization tests; production originator literals remain unchanged.
Windows CI RED output: Not available in this environment; the two requested commands are wired into `.github/workflows/windows.yml`.
Local formatting: Not performed because `zig` is not installed; `git diff --check` passed.
Self-review: No production originator fix was implemented; both Codex request builders are covered; unrelated `omfx-windows-x86_64-f2d2869/` remains untouched.
Concerns: Windows CI must run the filters to capture the expected RED result; Zig compilation was intentionally not attempted per task constraint.
