# omfx Brand Ownership Design

**Status:** Approved 2026-09-11  
**Scope:** Brand + surfaces + provider story (Identity first); selective product extras to satisfy upstream fx complainers.

## Relationship model

Like omp is to pi: community fork that owns identity and extends capability.  
Unlike omp: keep fx’s clean, minimal, premium, native aesthetic. No loud IDE marketing, no permanent full-screen chrome.

## Positioning

**omfx — tiny, native coding agent. Any model. Any provider. Any platform.**

- Community-owned (not Vercel-coupled)
- Provider-honest (Gateway is one option, not the brand)
- Windows-native first-class
- Still fx-clean: shell-first, inline, precise

Credit upstream once; own the public surface. Never advertise plugins or providers that are not shipped.

## Visual system

Extend Night Signal; do not replace with omp energy.

| Role | Direction |
| --- | --- |
| brand | Soft cool signal (refined cyan → slightly deeper signal blue); identity only |
| focus | Quiet violet for selection |
| success / warning / danger | Existing semantic meanings |
| text / muted / border | Neutral, high legibility |

Rules: ASCII `omfx` mark; inline transcript + composer primary; compact density; motion only for state; light / dark / high-contrast / 256-color share roles.

## Provider story + onboarding

Equal-citizen roster:

| Path | Stance |
| --- | --- |
| Vercel AI Gateway | Keep |
| Codex / Grok subscriptions | Keep |
| OpenCode Go | Keep |
| OpenAI-compatible (URL + key) | Own and finish as first-class |
| Direct OpenAI / Anthropic / Gemini keys | Phase C when transport is real; never fake |

`/setup` and first-run are a provider hub, not a Vercel funnel. Prefer OpenAI-compatible and direct keys in presentation order when available. Credentials stay profile-owned. `status` / `doctor` show provider + credential origin. Prefer `OMFX_*`; keep `FX_*`.

## Public site (GitHub Pages)

- URL: `https://blu3ph4ntom.github.io/oh-my-fx/`
- Static site under `docs/site/` or `site/`
- First viewport: brand, one line, one sentence, install CTAs (Unix + Windows), one quiet terminal still
- Below: providers, Windows-native, still fx-clean, upstream credit
- Own installers: `install.sh` and `install.ps1` on Pages; install to `~/.omfx/bin` (Windows) with PATH offer
- Binary `product_identity.website` points at Pages, not `fx.sh` as primary

## TUI chrome

Shell-first. Footer three-row contract. Semantic role sweep. Customization surfaces keep Night Signal naming under omfx. Windows exit/mode restoration is part of the contract. No sidebar, dashboard, or omp-style agent hub.

## Delivery phases

1. **A — Own the brand:** identity URLs, Pages, README/changelog/help, Night Signal sweep, install voice
2. **B — Provider complainers:** setup hub, finish OpenAI-compatible, status/doctor/docs truth
3. **C — Direct vendor keys:** OpenAI / Anthropic / Gemini when clean
4. **D — Windows harden:** install.ps1, MCP auth gap, ConPTY/exit regressions, CI artifacts

Deferred: Agent Plugins, Homebrew/XDG, attachments, Copilot sub, LSP/DAP/kernels, custom domain.

## Verification

Build, focused tests, run the real binary for the happy path, Pages/README/install match binary behavior, Windows CI for Windows-touching work, no marketing claim without a working path.

## Continuity constraints (from Codex session)

These are standing operating rules for this checkout, not optional:

- **No local Zig builds or tests.** Machine is RAM-constrained. Verification is Windows Actions (`windows.yml`) plus downloaded `omfx.exe` artifacts. Local `zig fmt` on touched files is allowed.
- **Poll CI until done.** Do not stop while a run for the exact commit is in progress; use `gh run view` per-job conclusions (test job truth matters).
- **Bump patch version** on every new public artifact (`src/main.zig` version + changelog markers).
- **Promote verified CI `omfx.exe` to** `%USERPROFILE%\.omfx\bin\omfx.exe` after interactive smoke; remove superseded in-repo artifact folders.
- **Other workflows stay disabled** until explicitly re-enabled (`# oh-my-fx: disabled`).
- Prior session already shipped Windows-native path, OpenCode Go provider, brand/TUI customization passes, terminal host fixes, and scrollback `0.0.7`. This design owns the remaining public brand + provider-honesty + Pages/install layer.

## Upstream gaps this design answers

From HN, GitHub issues, and reviews: provider lock-in (#112, #150, OpenAI-compatible PRs), no official Windows (#254, #330), marketing/product mismatch (#390 plugins), onboarding friction, secondary asks deferred.

## Prior user intent already on record

Session users asked for full rebrand/palette ownership earlier; at that time website was deferred for TUI-first. This design reopens website/install as Phase A now that TUI/Windows/`0.0.7` are green.
