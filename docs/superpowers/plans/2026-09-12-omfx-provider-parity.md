# omfx Provider Parity and Reasoning Implementation Plan

> Execute in small checkpoints. Zig builds and tests run only on the Windows
> GitHub Actions runner; local work is limited to inspection and formatting.

**Goal:** Extend `omfx` from OpenCode Go plus one generic OpenAI-compatible route
to a provider platform with live model metadata, correct reasoning controls,
native protocols where necessary, and consistent CLI/TUI/ACP behavior.

**Spec:** `docs/plans/2026-09-12-omfx-provider-parity-design.md`

## Constraints

- Preserve `omfx` identity and existing Windows-native terminal behavior.
- Never reuse a credential across provider sources.
- Do not send unsupported reasoning or tool fields.
- Keep `src/main.zig` composition-only and keep provider transport in
  `src/gateway/`.
- Do not run `zig build`, `zig build test`, or `zig test` locally.
- Use loopback fixtures for deterministic tests and bounded filtered Windows CI.
- Do not restore the uncapped full-suite Windows invocation.
- Bump the patch version for each artifact handoff and verify the exact
  downloaded artifact before global promotion.

## Current ownership map

- Provider identity/auth: `src/core/config/model_provider.zig`,
  `src/core/auth/credentials.zig`, `src/core/app/*auth*`.
- Model contracts/catalogs: `src/core/gateway/model_catalog.zig`,
  `src/core/gateway/model_catalog_metadata.zig`,
  `src/core/config/model_capabilities.zig`, `src/core/app/model_cache_runtime.zig`.
- Agent request boundary: `src/core/agent/stream_provider.zig` and
  `src/core/agent/runtime/*`.
- Transports: `src/gateway/openai.zig`, `openai_compat.zig`,
  `opencode_go.zig`, and new protocol modules.
- Dispatch: `src/builtins/providers.zig` plus exhaustive provider switches in
  `src/main.zig`, `src/core/`, `src/acp/`, and `src/ui/`.
- Presentation: `src/ui/footer/*`, `src/core/output/output_contracts.zig`,
  command and setup surfaces.
- Windows proof: `.github/workflows/windows.yml` and existing ConPTY smoke.

## Task 1: Introduce the profile and reasoning contracts

**Files:**

- Add `src/core/config/provider_profile.zig`.
- Modify `src/core/config/model_capabilities.zig` and
  `src/core/gateway/model_catalog.zig`.
- Modify `src/core/agent/stream_provider.zig` only if a typed protocol/options
  boundary is required.
- Add source-local tests in these modules.

**Contract:** A profile exposes provider identity, credential source, protocol,
URL policy, catalog access, tool/vision/cache capability defaults, and a
model-specific reasoning map. `ResolvedProviderOptions` carries only options
that the chosen model declared as supported.

- [ ] Add protocol and profile enums without changing behavior for existing
  providers.
- [ ] Add model metadata for reasoning levels, reasoning wire family, and
  optional budget mapping while preserving existing catalog ownership/freeing.
- [ ] Add deterministic normalization for `auto`, `none`, `minimal`, `low`,
  `medium`, `high`, and `xhigh`.
- [ ] Add tests for unknown efforts, stale catalog efforts, unsupported
  disablement, bounded budgets, and profile credential isolation.
- [ ] Run only the new focused Windows filters and inspect the job conclusion.
- [ ] Commit `feat: add omfx provider profile contracts`.

## Task 2: Make OpenCode Go and compatible routes capability-complete

**Files:**

- Modify `src/gateway/openai.zig`, `src/gateway/openai_compat.zig`,
  `src/gateway/opencode_go.zig`.
- Modify `src/gateway/openai_compat_models.zig` and
  `src/gateway/opencode_go_models.zig`.
- Modify `src/core/config/model_capabilities.zig` and dispatch as needed.

- [ ] Add request-body tests proving `reasoning_effort` is emitted only for a
  declared compatible reasoning model.
- [ ] Add SSE fixture tests for `reasoning_content`, `reasoning`, tool-call
  deltas, usage, finish reasons, and malformed chunks.
- [ ] Populate live catalog entries from supported metadata fields when
  present; preserve safe defaults for plain OpenAI-list responses.
- [ ] Add conservative model-family defaults for OpenCode Go, including the
  current Muse/Spark and other live Go models without hardcoding a stale list
  as the only source of truth.
- [ ] Ensure Go model URL validation remains fixed-host plus loopback E2E only.
- [ ] Expose the selected effort in the existing model/settings picker and
  render streamed reasoning through `on_reasoning_chunk`.
- [ ] Run filtered Windows tests and a credentialed OpenCode Go CI smoke if the
  configured Actions secret is available.
- [ ] Commit `feat: wire reasoning through compatible providers`.

## Task 3: Add named compatible provider profiles

**Files:**

- Modify `src/core/config/model_provider.zig`, `src/core/shared/types.zig`,
  `src/core/auth/credentials.zig`, `src/builtins/providers.zig`.
- Add profile/config modules under `src/core/config/` and model catalog helpers
  under `src/gateway/` where the existing generic route cannot express a
  provider-specific endpoint or header.
- Update every exhaustive provider switch.

**Profiles:** OpenAI, OpenRouter, xAI, DeepSeek, Groq, Cerebras, Fireworks,
Together, Mistral, Azure OpenAI, and Cloudflare AI Gateway. Use a shared
OpenAI-compatible protocol only when the provider’s request and stream shape
matches; use profile-specific URL/header rules otherwise.

- [ ] Add one credential source and environment variable per profile, with
  aliases only for documented upstream-compatible names.
- [ ] Add HTTPS endpoint allowlists/defaults and deployment/path validation for
  Azure; keep custom endpoints explicit and secure.
- [ ] Add live `/models` resolution with provider-specific authentication and
  catalog metadata preservation.
- [ ] Add reasoning mappings for providers that expose effort controls and
  omit them for providers/models that do not.
- [ ] Add CLI/TUI/ACP provider labels, setup copy, status, doctor output, and
  model selection without duplicating feature logic.
- [ ] Add focused loopback tests for each profile family, grouping identical
  contracts into table-driven cases.
- [ ] Run Windows filtered tests and build smoke; bump the patch version for
  the artifact checkpoint.
- [ ] Commit `feat: add first-class compatible provider profiles`.

## Task 4: Add native OpenAI Responses, Anthropic, and Gemini

**Files:**

- Add `src/gateway/openai_responses.zig`, `anthropic_messages.zig`, and
  `gemini.zig` plus model catalog modules.
- Modify `src/core/agent/stream_provider.zig` only for shared typed events.
- Update provider/auth/dispatch/presentation switch sites.

- [ ] Write request fixtures for text, images/files where the current tool
  contract supports them, tools, structured output, effort/thinking options,
  and cancellation.
- [ ] Write stream fixtures for answer text, reasoning/thinking blocks,
  tool-call lifecycle, usage, provider errors, and incomplete streams.
- [ ] Map normalized effort to OpenAI `reasoning_effort`, Anthropic thinking
  budget, and Gemini thinking configuration with explicit bounds.
- [ ] Add live catalog parsing and safe defaults for each native endpoint.
- [ ] Verify native credentials are never accepted by a different provider.
- [ ] Add CLI JSON and ACP snapshots from the same completion contract.
- [ ] Run focused Windows filters and non-credentialed loopback E2E fixtures.
- [ ] Commit `feat: add native reasoning provider transports`.

## Task 5: Add Bedrock and GitHub Copilot adapters

**Files:**

- Add `src/gateway/bedrock_converse.zig` and `src/gateway/github_copilot.zig`
  with catalog helpers.
- Modify credential/OAuth/config modules for AWS signing and Copilot token
  exchange, following existing secure storage and browser callback seams.
- Update all dispatch and UI surfaces.

- [ ] Define the minimum supported AWS credential forms and region/model
  resolution; reject ambiguous or incomplete signing configuration clearly.
- [ ] Implement SigV4 signing and event-stream decoding behind loopback
  fixtures; do not substitute bearer auth.
- [ ] Implement Copilot OAuth/token refresh and preserve existing credentials
  on callback failure.
- [ ] Map native reasoning controls where the model advertises them.
- [ ] Add tests for signing canonicalization, token isolation, expiry, stream
  parsing, and error redaction.
- [ ] Run bounded Windows CI filters; live auth smoke remains optional and
  secret-gated.
- [ ] Commit `feat: add Bedrock and Copilot provider adapters`.

## Task 6: Finish shared UX and output parity

**Files:**

- Modify `src/core/app/app_auth_runtime.zig`, `src/core/app/model_cache_runtime.zig`,
  `src/ui/footer/model_menu_presentation.zig`, `src/ui/footer/*`,
  `src/core/output/output_contracts.zig`, `src/core/cli/*`, and `src/acp/*`.
- Update `README.md`, `CONTRIBUTING.md`, and `CHANGELOG.md` for the public
  artifact version.

- [ ] Make `/login` show every supported auth method with provider-specific
  copy and OpenCode Go first among API-key providers.
- [ ] Make `/models` visibly distinguish live, stale, authenticated, and
  public-fallback catalogs.
- [ ] Show reasoning availability and current effort in status/footer/model
  menus; do not show an enabled toggle for unsupported models.
- [ ] Preserve reasoning in JSON/text snapshots consistently while keeping
  secrets and provider internals out of output.
- [ ] Test arrow navigation, Enter, Escape, scroll, provider switching, and
  alternate-screen restoration through the existing ConPTY script.
- [ ] Update docs for every new environment variable, protocol limitation, and
  setup command. Do not claim a provider is live unless implemented.
- [ ] Commit `docs: document omfx provider parity and reasoning controls`.

## Task 7: CI, artifact, and global handoff

**Files:**

- Modify `.github/workflows/windows.yml`.
- Modify `scripts/windows/omfx-conpty-smoke.ps1` only for deterministic new
  interactions.

- [ ] Keep build, format, filtered unit tests, CLI smoke, ConPTY smoke, and
  artifact upload as separate bounded steps.
- [ ] Remove `continue-on-error` from the test job only after the filtered
  matrix is green on the exact commit.
- [ ] Push the clean checkpoint and poll `gh run view <id> --json jobs` until
  every required job reaches a terminal success conclusion.
- [ ] Download the exact artifact into a fresh commit-named directory and
  verify version plus SHA-256.
- [ ] Run interactive attached-terminal checks with the downloaded binary,
  including `/login`, `/models`, provider selection, reasoning selection,
  arrows, Enter, Escape, scroll, one real request, and clean `/quit`.
- [ ] Confirm no `fx`, `omfx`, `zig`, `test`, or `build` process remains.
- [ ] Move superseded in-repo artifacts to a recoverable temp directory and
  promote only the verified executable to `%USERPROFILE%\\.omfx\\bin\\omfx.exe`.
- [ ] Start a fresh PowerShell, resolve `omfx`, run `omfx help`, and capture
  clean stderr and the new patch version.

## Final review gate

- [ ] `git diff --check` and formatting gate pass in Windows CI.
- [ ] Every provider has a source-specific credential path and focused tests.
- [ ] Every supported reasoning path reaches the wire and returns through the
  reasoning callback; unsupported paths are omitted and visible.
- [ ] Exact current-commit Windows build/tests/smoke/artifact checks pass.
- [ ] Global `omfx` points to the exact verified artifact.
- [ ] Disabled cross-platform upstream workflows are reported honestly; no
  claim of Linux/macOS parity is made without their required CI evidence.
