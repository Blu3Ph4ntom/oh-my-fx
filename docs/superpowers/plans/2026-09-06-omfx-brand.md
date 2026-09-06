# omfx Public Identity and Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Replace the public fx identity with omfx, add Night Signal, and
preserve existing profiles, scripts, sessions, and wire compatibility.

**Architecture:** Put stable identity and environment compatibility in
src/core/shared. Put semantic terminal colors in a UI-owned brand theme module
and keep existing render names as a compatibility facade. Update public copy at
presentation boundaries while leaving protocol keys, storage paths, and
test-only controls stable.

**Tech Stack:** Zig 0.16, std.Io, existing ANSI/truecolor renderer, Windows
PowerShell workflow, and Markdown documentation.

**Spec:** docs/superpowers/specs/2026-09-06-omfx-brand.md

## Global Constraints

- Visible product name is omfx; FX_*, .fx, ACP _meta.fx, and provider wire names remain supported.
- OMFX_HOME and new user-facing OMFX_* aliases take precedence over FX_* counterparts.
- OpenAI protocol originators remain protocol values and never become omfx.
- Keep zig-out/bin/fx for development; publish omfx.exe primary and fx.exe compatibility.
- Do not use non-ASCII decorative branding bytes in banner or help.
- Do not run local Zig builds/tests; use local zig fmt only.
- Commit each independently testable task.

---

### Task 1: Add identity and compatibility contracts

**Files:**

- Create: src/core/shared/product_identity.zig
- Modify: src/core/shared/io.zig
- Modify: src/core/shared/profile_paths.zig
- Modify: src/test_root.zig
- Modify: .github/workflows/windows.yml

**Interfaces:**

- Consumes: io_mod.getenv and current profile path resolution.
- Produces: product_identity.name, command, compatibility_command, website,
  codex_protocol_originator, and io_mod.getenvProduct(primary, legacy).

- [ ] Add tests:

~~~zig
try std.testing.expectEqualStrings("omfx", product_identity.name);
try std.testing.expectEqualStrings("fx", product_identity.compatibility_command);
try std.testing.expectEqualStrings("codex_cli_rs", product_identity.codex_protocol_originator);
~~~

Use the existing test seam to prove OMFX_* wins over FX_* and FX_* works alone.
Prove OMFX_HOME selects an explicit root while absent variables retain .fx.

- [ ] Run on Windows Actions before implementation:

~~~powershell
zig test -lc src/test_root.zig --test-filter "omfx identity contract"
zig test -lc src/test_root.zig --test-filter "OMFX_HOME overrides legacy profile root"
~~~

Expected result: the new module and helper are not defined.

- [ ] Implement constants and the compatibility helper using io_mod.getenv.
Do not change the default profile root or test controls in this task.

- [ ] Format and commit:

~~~powershell
zig fmt src/core/shared/product_identity.zig src/core/shared/io.zig src/core/shared/profile_paths.zig
git add src/core/shared/product_identity.zig src/core/shared/io.zig src/core/shared/profile_paths.zig src/test_root.zig .github/workflows/windows.yml
git commit -m "feat: add omfx identity compatibility contract"
~~~

### Task 2: Introduce the Night Signal semantic theme

**Files:**

- Create: src/ui/brand_theme.zig
- Modify: src/ui/render.zig
- Modify: src/ui/footer/approval_ui.zig
- Modify: src/ui/footer/picker_presentation.zig
- Modify: src/ui/footer/model_menu_presentation.zig
- Modify: src/ui/terminal/theme_detection.zig
- Modify: src/test_root.zig
- Modify: .github/workflows/windows.yml

**Interfaces:**

- Consumes: truecolor and light/dark detection.
- Produces: semantic role styles for brand, focus, success, warning, error,
  text, muted, and border, with truecolor and 256-color values.

- [ ] Add pure tests proving every role has both color forms, light mode is
readable, and false truecolor support selects fallbacks.

- [ ] Run:

~~~powershell
zig test -lc src/test_root.zig --test-filter "Night Signal palette"
~~~

Expected result before implementation: the role module and values are missing.

- [ ] Define the exact role values from the spec in src/ui/brand_theme.zig.
Keep existing exported render styles as a compatibility facade and assign them
from semantic roles in initTheme. Replace component-local focus, success,
warning, and error literals in the listed footer files.

- [ ] Verify, format, and commit:

~~~powershell
zig fmt src/ui/brand_theme.zig src/ui/render.zig src/ui/footer/approval_ui.zig src/ui/footer/picker_presentation.zig src/ui/footer/model_menu_presentation.zig src/ui/terminal/theme_detection.zig
git add src/ui/brand_theme.zig src/ui/render.zig src/ui/footer/approval_ui.zig src/ui/footer/picker_presentation.zig src/ui/footer/model_menu_presentation.zig src/ui/terminal/theme_detection.zig src/test_root.zig .github/workflows/windows.yml
git commit -m "feat: add Night Signal terminal theme"
~~~

### Task 3: Rebrand visible copy and remove Windows mojibake

**Files:**

- Modify: src/ui/render.zig
- Modify: src/core/cli/cli_surface.zig
- Modify: src/builtins/commands.zig
- Modify: src/core/app/app_entry_runtime.zig
- Modify: src/core/app/app_auth_runtime.zig
- Modify: src/core/app/app_session_runtime.zig
- Modify: src/core/cli/doctor_runtime.zig
- Modify: src/core/output/output_contracts.zig
- Modify: src/acp/types.zig
- Modify: README.md
- Modify: CONTRIBUTING.md
- Modify: .github/workflows/windows.yml
- Modify: src/test_root.zig

**Interfaces:**

- Consumes: product_identity.name and existing public output contracts.
- Produces: ASCII-safe omfx startup/help/status/error copy, omfx ACP display
  metadata, and compatibility _meta.fx wire keys.

- [ ] Update existing startup/version/help tests to require an omfx v prefix,
no Unicode logotype, and ASCII-only branding bytes. Add an ACP assertion for
name omfx and title omfx while retaining _meta.fx.

- [ ] Run:

~~~powershell
zig test -lc src/test_root.zig --test-filter "version flags"
zig test -lc src/test_root.zig --test-filter "startup banner"
zig test -lc src/test_root.zig --test-filter "ACP agent info"
~~~

Expected result before implementation: current Unicode fx strings remain.

- [ ] Replace only user-facing strings with product_identity.name. Keep FX_*,
.fx, _meta.fx, internal fields, fixture paths, and test-only controls stable.
Replace the Unicode logotype with plain ASCII omfx.

- [ ] Update README and CONTRIBUTING examples and prose to omfx, retain a note
that fx remains a compatibility command, and keep valid https://fx.sh links.
Make omfx-windows-x86_64 primary and retain fx-windows-x86_64 compatibility.

- [ ] Format, run filters and help smoke, then commit:

~~~powershell
git add src/ui/render.zig src/core/cli/cli_surface.zig src/builtins/commands.zig src/core/app/app_entry_runtime.zig src/core/app/app_auth_runtime.zig src/core/app/app_session_runtime.zig src/core/cli/doctor_runtime.zig src/core/output/output_contracts.zig src/acp/types.zig README.md CONTRIBUTING.md .github/workflows/windows.yml src/test_root.zig
git commit -m "feat: rebrand public CLI surfaces as omfx"
~~~

### Task 4: Add product-prefixed environment aliases and artifact compatibility

**Files:**

- Modify: src/core/shared/io.zig
- Modify: src/core/config/config_runtime.zig
- Modify: src/ui/terminal/theme_detection.zig
- Modify: src/core/app/app_entry_runtime.zig
- Modify: src/core/workspace/record_tape.zig
- Modify: src/core/upgrade/upgrade_runtime.zig
- Modify: build.zig only if install alias does not duplicate compilation
- Modify: .github/workflows/windows.yml
- Modify: src/test_root.zig

**Interfaces:**

- Consumes: io_mod.getenvProduct and existing FX_MODEL, FX_THEME, FX_RECORD,
  FX_BENCH, FX_PERMISSION_MODE, and FX_MAX_AGENT_STEPS reads.
- Produces: OMFX_MODEL, OMFX_THEME, OMFX_RECORD, OMFX_BENCH,
  OMFX_PERMISSION_MODE, OMFX_MAX_AGENT_STEPS, and OMFX_HOME precedence.

- [ ] Add tests proving OMFX_* wins, FX_* works alone, absent values preserve
defaults, and FX_E2E_* controls remain unchanged.

- [ ] Run:

~~~powershell
zig test -lc src/test_root.zig --test-filter "OMFX environment aliases"
~~~

Expected result before implementation: only legacy names are recognized.

- [ ] Route only the listed user-facing reads through the helper. Leave
provider credential names, protocol headers, and internal test controls alone.
The helper checks OMFX_* first without allocating.

- [ ] Keep zig-out/bin/fx.exe, stage byte-identical omfx.exe, upload
omfx-windows-x86_64 primary, and upload fx-windows-x86_64 compatibility. Expose
a build alias only if Zig 0.16 supports it without recompiling.

- [ ] Run alias/build/smoke filters, launch both artifact names interactively,
check banner/help/status/theme/quit, and commit:

~~~powershell
git add src/core/shared/io.zig src/core/config/config_runtime.zig src/ui/terminal/theme_detection.zig src/core/app/app_entry_runtime.zig src/core/workspace/record_tape.zig src/core/upgrade/upgrade_runtime.zig build.zig .github/workflows/windows.yml src/test_root.zig
git commit -m "feat: support omfx environment aliases and artifacts"
~~~

