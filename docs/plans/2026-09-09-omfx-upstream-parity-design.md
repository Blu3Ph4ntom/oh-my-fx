# omfx Upstream Parity and OpenCode Go Login Design

## Goal

Bring the Windows-native `omfx` CLI/TUI/runtime toward feature parity with upstream `fx` through `v0.0.8`, while preserving omfx branding, Night Signal styling, Windows-native behavior, and the OpenCode Go provider.

## Scope

This phase covers the native CLI, agent runtime, authentication, MCP, sessions, tools, and terminal UI. The `libfx` SDK/API surface is explicitly deferred to a separate phase.

The first deliverable is provider activation: `/login` presents OpenCode Go first, accepts a masked API key, persists the selected provider and credential source, and keeps Codex/Vercel/API-key flows available.

The parity pass then addresses the highest-impact upstream `v0.0.5`–`v0.0.8` changes: the shell tool contract, active-turn steering, direct subagent actions, capability search, top-level MCP management, structured JSON output, current permission naming, and removal or migration of obsolete memory, record, sandbox, and legacy appearance paths.

## Architecture

Provider login remains owned by `src/core/app/app_auth_runtime.zig` and the existing credential/provider contracts. OpenCode Go is an API-key-only provider: its login row enters the existing masked key flow, stores the key under its own credential source, and immediately activates a catalog-valid model.

Parity changes stay in their owning modules: tool schemas and dispatch in `src/builtins/` and `src/core/tooling/`, provider/session behavior in `src/core/`, and rendering/input in `src/ui/`. `src/main.zig` remains composition-only. The omfx presentation layer is retained and receives upstream behavior through existing typed contracts.

## Interaction and copy

- `/login` ordering: OpenCode Go, Codex, Vercel, API key, then credential switching where applicable.
- OpenCode Go labels identify `OPENCODE_GO_API_KEY` and never imply OAuth.
- The selected provider and credential source are visible in setup/status surfaces.
- Existing omfx product name, palette, `omfx` executable identity, and Windows-safe terminal behavior remain authoritative.
- Deprecated upstream surfaces either migrate existing settings safely or produce a concise compatibility message; they do not silently change provider or permission state.

## Error handling and security

Credential writes are atomic and source-specific. Missing or invalid OpenCode Go keys return actionable guidance without altering a working credential. Provider switches must not fall back to another provider's credential. API keys remain masked in UI and diagnostics. OAuth callback state and browser failures keep the existing credential unchanged.

Tool and MCP changes continue through the permission gate. Exact-action review, session ownership, sensitive-output masking, and bounded response sizes remain enforced on Windows and other supported hosts.

## Verification

Local verification is limited to read-only inspection, formatting, static checks, and running the exact downloaded Windows artifact. All Zig builds and tests run on GitHub Actions `windows-latest` because the development machine is RAM-constrained. Each slice adds a focused test, observes the expected failure before implementation, passes the Windows filtered test job, and exercises the relevant CLI/TUI path through ConPTY.

The global install is the final handoff only after an exact-commit Windows artifact passes build, filtered tests, CLI smoke, ConPTY smoke, and provider smoke. It installs the verified `omfx.exe` under `%USERPROFILE%\\.omfx\\bin` and does not overwrite unrelated binaries.

## Upstream reference

- https://fx.sh/changelog
- https://github.com/vercel-labs/fx
