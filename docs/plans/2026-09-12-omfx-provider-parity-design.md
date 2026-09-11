# omfx Provider Parity and Reasoning Design

## Goal

Make the Windows-native `omfx` provider surface broad enough to cover the
provider families currently exposed by OpenCode and pi, while preserving
source-specific authentication, live model catalogs, tool streaming, and
reasoning controls. The product remains `omfx`; upstream behavior is a
compatibility reference, not a reason to copy upstream branding or unsafe
fallbacks.

## Scope

The provider platform covers these families:

- Existing subscription routes: Vercel AI Gateway, Codex, and OpenCode Go.
- OpenAI-compatible routes: OpenAI, OpenRouter, xAI, DeepSeek, Groq,
  Cerebras, Fireworks, Together, Mistral, custom endpoints, Azure OpenAI, and
  Cloudflare AI Gateway where their endpoint exposes the compatible contract.
- Native protocol routes: OpenAI Responses, Anthropic Messages, and Google
  Gemini.
- Protocol/auth adapters: Amazon Bedrock and GitHub Copilot, using their
  provider-specific authentication rather than treating them as plain API
  keys.

The provider registry, catalog model, request options, stream events, CLI/TUI
surfaces, ACP, and documentation are in scope. Website work, SDK parity, and
provider-specific billing UX are out of scope.

## Design principles

1. A provider profile owns protocol, endpoint, credential source, catalog
   endpoint, model capability defaults, and option encoding.
2. A model catalog is authoritative when live; fallback entries are marked
   stale and never silently override a successful live response.
3. Credentials are source-specific. A key or OAuth token for one provider is
   never sent to another provider because both happen to use similar HTTP.
4. Reasoning is a typed capability and stream event, not an ignored UI value.
5. Native protocol differences stay in gateway modules. Product state remains
   in `src/core`, rendering remains in `src/ui`, and `src/main.zig` remains a
   composition root.
6. Every network path has a deterministic loopback fixture for request and
   response tests. Live credentialed smoke tests remain CI-only.

## Architecture

Introduce a provider-profile contract below the existing `ProviderId` and
`CredentialSource` enums. The profile describes:

- stable provider identity and display copy;
- credential source and environment-variable names;
- base URL and live catalog URL resolution;
- protocol (`openai_chat`, `openai_responses`, `anthropic_messages`,
  `gemini`, `bedrock_converse`, or `copilot`);
- supported tool, vision, file, cache, web-search, context, and output limits;
- supported reasoning levels and their provider wire mapping.

The existing `BuildRequest.provider_options` and stream callbacks remain the
typed boundary. Provider modules consume those options and emit normal text,
reasoning, tool, usage, and error events. No provider-specific state is added
to the UI.

Compatibility profiles share request construction and SSE parsing only when
their wire contract is actually compatible. A named profile may override
headers, URL construction, model discovery, request fields, or error parsing.
This avoids a generic adapter that appears to support a feature but drops it.

## Reasoning contract

The user-facing setting is one normalized effort value:

`auto`, `none`, `minimal`, `low`, `medium`, `high`, and `xhigh`.

Catalog metadata declares the levels supported by each model. The request
mapper then applies the provider-specific representation:

- OpenAI and OpenAI-compatible reasoning models use `reasoning_effort`.
- Anthropic uses enabled/disabled thinking plus a bounded token budget.
- Gemini uses its thinking configuration and budget field.
- Codex preserves its existing effort mapping.
- OpenCode Go uses the live model capability when available and a conservative
  model-family mapping otherwise.
- Providers without reasoning omit reasoning fields and report that fact in
  status/model information.

Unsupported values are never sent. `auto` means provider default; `none`
means disabled only for a provider/model that explicitly supports disabling.
Budget conversion is deterministic, bounded by model output limits, and
covered by unit tests.

Streaming parsers recognize provider-specific reasoning deltas and route them
through `on_reasoning_chunk`. Reasoning is rendered distinctly from answer
text, retained in structured output where the output contract supports it, and
never mistaken for tool-call arguments.

## Authentication and UX

`/login`, `/provider`, `/models`, `/status`, and `/doctor` all read the same
provider registry. Login rows show the actual credential method:

- API key providers identify their environment variable and masked input flow.
- OAuth providers show the browser/callback requirement and preserve the
  current credential on failure.
- AWS and Copilot providers show their required setup instead of exposing a
  misleading generic API-key form.

Provider activation validates the selected model against the selected
provider's catalog. A provider switch does not inherit an incompatible model
or credential. Catalog failures preserve the previous valid state and expose a
stale/fallback notice.

## Provider rollout order

1. Complete the shared profile and reasoning contracts; upgrade OpenCode Go
   and OpenAI-compatible profiles to preserve live capability metadata and
   reasoning streams.
2. Add the high-value compatible profiles: OpenAI, OpenRouter, xAI, DeepSeek,
   Groq, Cerebras, Fireworks, Together, Mistral, Azure, and Cloudflare.
3. Add native OpenAI Responses, Anthropic Messages, and Gemini transports.
4. Add Bedrock and GitHub Copilot adapters with their real authentication and
   protocol rules.
5. Expose the full matrix consistently through CLI, TUI, ACP, docs, and
   Windows smoke coverage.

Each step is independently buildable and keeps the prior provider paths
working.

## Verification

- Source-local unit tests cover profile resolution, credential isolation,
  model catalog parsing, request bodies, reasoning mapping, stream parsing,
  tool calls, usage, and errors.
- Windows CI runs focused filters and bounded ConPTY smoke tests. The existing
  uncapped full-suite invocation is not restored.
- The exact artifact for the current commit is downloaded and exercised in an
  attached terminal. Interactive tests cover Enter, Escape, arrows, scrolling,
  provider/model selection, one tool call, one reasoning response, and clean
  exit.
- Every public artifact-producing commit increments the patch version.
- Only the exact verified artifact is promoted to the global `omfx` location.

## Upstream references

- OpenCode provider and protocol packages:
  https://github.com/anomalyco/opencode/tree/dev/packages/llm/src
- pi model and reasoning configuration:
  https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/models.md
- OpenCode Go documentation:
  https://opencode.ai/docs/go/
- Upstream fx reasoning-effort issue:
  https://github.com/vercel-labs/fx/issues/276
