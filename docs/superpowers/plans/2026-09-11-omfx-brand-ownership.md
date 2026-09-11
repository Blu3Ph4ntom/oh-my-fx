# omfx Brand Ownership Implementation Plan

> **For agentic workers:** Execute task-by-task. Respect the Continuity constraints in the design doc. No local `zig build` / `zig test`; Windows Actions + artifact smoke only. Local `zig fmt` OK.

**Goal:** Own omfx as the community fx — clean premium brand, GH Pages + install, equal-citizen providers, Windows-first — and close the loudest upstream complainers without omp energy.

**Architecture:** Identity constants and website URL in `src/core/shared/product_identity.zig`. Semantic theme remains UI-owned. Setup/onboarding presentation in auth/app runtimes. Static site under `docs/site/` published via GitHub Pages. Install scripts fetch release/CI artifacts into `~/.omfx/bin` on Windows.

**Tech stack:** Zig 0.16, existing TUI/theme, static HTML/CSS, PowerShell + POSIX install scripts, `windows.yml`.

**Spec:** `docs/plans/2026-09-11-omfx-brand-ownership-design.md`

## Global constraints

- Visible name `omfx`; keep `fx`, `.fx`, `FX_*`, `_meta.fx`, protocol originators.
- Prefer `OMFX_*`; Pages URL is primary website.
- No local Zig compile/test; push → poll Windows CI → download artifact → interactive smoke → global install → bump was already in commit.
- Patch-bump version for every shippable artifact.
- Never advertise plugins or unshipped providers.
- Aesthetic: fx-clean, not omp-loud; inline-first TUI.

---

### Task 1: Point identity at Pages and freeze copy contracts

**Files:**

- Modify: `src/core/shared/product_identity.zig`
- Modify: README.md, CONTRIBUTING.md, PRODUCT.md, DESIGN.md, `docs/customization.md` as needed for website/install pointers
- Modify: `src/test_root.zig` / identity tests if present
- Modify: `.github/workflows/windows.yml` only if a filter name changes

- [ ] Set `website` (and docs entry if present) to `https://blu3ph4ntom.github.io/oh-my-fx/`
- [ ] Update help/learn-more strings that hardcode `fx.sh` as primary product home; keep upstream credit where appropriate
- [ ] Add/adjust test: identity website is Pages URL; name remains `omfx`
- [ ] `zig fmt` touched Zig; commit; push; poll Windows CI; do not ship site yet

~~~powershell
# after push
gh run list --repo blu3ph4ntom/oh-my-fx --workflow windows.yml --limit 3
gh run view <id> --repo blu3ph4ntom/oh-my-fx --json jobs --jq '.jobs[] | "\(.name) \(.status) \(.conclusion)"'
~~~

---

### Task 2: GH Pages site (static, premium, one composition)

**Files:**

- Create: `docs/site/index.html`, `docs/site/styles.css`, `docs/site/install.sh`, `docs/site/install.ps1`
- Create: `.github/workflows/pages.yml` (or enable Pages from `docs/site`)
- Optional: `docs/site/og.png` later — defer if it blocks

- [ ] Hero: brand `omfx`, one line, one sentence, Unix + Windows install CTAs, GitHub link, one quiet terminal still
- [ ] Sections: providers (honest roster), Windows-native, still fx-clean, upstream credit
- [ ] Install scripts install `omfx` to `%USERPROFILE%\.omfx\bin` (Windows) / documented Unix path; never print secrets
- [ ] Enable GitHub Pages; verify URL loads
- [ ] Commit site + workflow; no Zig required

---

### Task 3: Night Signal ownership sweep + README install voice

**Files:**

- Modify: UI theme/render/footer files still carrying hard-coded accents
- Modify: README install block to Pages installers (not `fx.sh/setup.sh` as primary)
- Modify: CHANGELOG + `src/main.zig` version when shipping the public artifact for this phase

- [ ] Semantic role sweep for remaining private colors
- [ ] README/PRODUCT/DESIGN align with approved positioning
- [ ] Patch-bump, push, CI, download artifact, interactive smoke (banner shows omfx + Pages learn-more if exposed), promote global, remove old in-repo artifact folder

---

### Task 4: Provider hub honesty (Phase B)

**Files:**

- Modify: setup/onboarding/auth presentation (`app_auth_runtime.zig`, `auth_runtime.zig`, related UI)
- Modify: doctor/status output contracts
- Modify: README provider docs; Pages provider section

- [ ] `/setup` and first-run list equal citizens; do not funnel to Vercel-only
- [ ] Surface OpenAI-compatible as first-class when credential/URL configured
- [ ] `omfx provider` / help usage lists all real providers
- [ ] `status`/`doctor` show provider + credential origin
- [ ] Tests on Windows CI filters for setup copy / provider parse / status fields
- [ ] Patch-bump + artifact smoke: open `/setup`, confirm roster order and OpenAI-compatible path discoverable

---

### Task 5: Finish OpenAI-compatible path (complainer #1)

**Files:**

- Inspect/extend: `openai_compat` / custom_provider credential storage, setup actions, catalog, stream wiring already partially present
- Docs: customization + Pages + README

- [ ] Document exact setup: base URL + API key (env + `/setup`)
- [ ] Prove catalog + one `ask`/interactive turn on Windows CI or artifact with a loopback or real compatible endpoint
- [ ] Explicit degrade messages for unsupported capabilities
- [ ] Patch-bump + promote global only after smoke

---

### Task 6: Direct vendor keys (Phase C, if clean)

**Files:** new/extended gateway transports for OpenAI / Anthropic / Gemini direct keys

- [ ] Only start if Task 5 is green and transports can reuse existing stream contracts
- [ ] Profile-owned secrets; never from project config
- [ ] Same agent loop: stream, tools, ACP where supported
- [ ] Site/README gain these rows only after CI smoke proves them
- [ ] Otherwise leave “next” on the site without claiming shipped

---

### Task 7: Windows install + harden leftovers (Phase D)

**Files:** install.ps1 refinements, MCP interactive auth gap notes/fix if in scope, windows.yml artifact naming

- [ ] Pages `install.ps1` is the documented Windows path
- [ ] Global PATH guidance matches `%USERPROFILE%\.omfx\bin`
- [ ] Track MCP interactive auth unsupported on Windows as known gap or fix if small
- [ ] Keep polling discipline; delete superseded local artifact dirs after promote

---

## Definition of done (full redesign pass)

- Pages live with matching install scripts
- Binary website/help/README agree
- Setup is not a Vercel funnel
- OpenAI-compatible path documented and proven
- Global `omfx` matches latest CI artifact version
- No omp-energy visuals; no fake plugins
