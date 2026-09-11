```
 ⠀⠀⠀⠀⠀⠀⣠⣾⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀
 ⠀⠀⠀⠀⠀⢰⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
 ⠀⠀⠀⣠⣶⣿⣿⣷⣶⡶⣶⣶⣆⠀⠀⠀⣴⣶⣶⠆
 ⠀⠀⠀⠉⢹⣿⣿⠉⠉⠀⠘⢿⣿⣧⣀⣾⣿⡿⠃⠀             omfx — tiny, open, embeddable, native coding agent.
 ⠀⠀⠀⠀⣼⣿⡏⠀⠀⠀⠀⠀⠻⣿⣿⣿⠟⠀⠀⠀
 ⠀⠀⠀⢀⣿⣿⠃⠀⠀⠀⠀⢠⣦⠘⢿⣿⣷⡀⠀⠀             irm https://blu3ph4ntom.github.io/oh-my-fx/install.ps1 | iex
 ⠀⠀⠀⣸⣿⡟⠀⠀⠀⠀⣰⣿⣿⠗⠀⠻⣿⣿⣄⠀
 ⠀⠀⠀⣿⣿⠇⠀⠀⠀⠾⠿⠿⠋⠀⠀⠀⠘⠿⠿⠦             ⚠ Status: Experimental. Use at your own risk.
  ⠀⣸⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
 ⣿⣿⣿⠟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
```

omfx is a coding agent harness and CLI written in Zig, optimized for research and embeddability as part of larger systems. The historical `fx` command remains available as a compatibility name. Product home: [blu3ph4ntom.github.io/oh-my-fx](https://blu3ph4ntom.github.io/oh-my-fx/).

It focuses on minimalism and performance across the board, from system prompt design to its tools, feature set, and 7.8 MiB binary.

For end users, its CLI output style and form factor aim to be closer to a Unix shell than a heavy "IDE in the terminal" TUI.

It's open source (Apache-2.0), model-agnostic, and suitable for both local and cloud inference.

## Install

**Windows (PowerShell):**

```powershell
irm https://blu3ph4ntom.github.io/oh-my-fx/install.ps1 | iex
```

**macOS / Linux:**

```bash
curl -fsSL https://blu3ph4ntom.github.io/oh-my-fx/install.sh | sh
```

Product home: [blu3ph4ntom.github.io/oh-my-fx](https://blu3ph4ntom.github.io/oh-my-fx/). Upstream `fx` install remains at `https://fx.sh/setup.sh` for the Vercel-owned binary.

## Run omfx

Sign in with Vercel AI Gateway:

```bash
omfx login
```

Or use an eligible ChatGPT subscription through OpenAI Codex OAuth:

```bash
omfx login codex
omfx
```

Inside omfx, `/provider` switches between Gateway, Codex, OpenCode Go, and named OpenAI-compatible providers. The named profiles are OpenAI, OpenRouter, xAI, DeepSeek, Groq, Cerebras, Fireworks, Together, and Mistral. `/model` lists the active provider's fetched models. Codex model IDs are the raw IDs returned by its authenticated catalog. Use `/logout codex` to remove the Codex session without affecting Vercel access.

The OpenAI Codex route uses ChatGPT subscription access directly and never sends its OAuth token to Vercel AI Gateway. The session is stored privately at `~/.fx/chatgpt-auth.json` and refreshed when needed. On supported Codex models, `/fast` requests OpenAI's priority service tier and consumes ChatGPT credits at the higher Fast mode rate.

OpenCode Go uses the OpenAI-compatible transport and the fixed OpenCode Go service. Set `OPENCODE_GO_API_KEY`, then choose it with `/provider opencode_go` or `omfx provider opencode_go`:

```bash
export OPENCODE_GO_API_KEY=your-key
omfx provider opencode_go
omfx models
```

On Windows PowerShell, use `$env:OPENCODE_GO_API_KEY = "your-key"` for the current shell. OpenCode Go model IDs come from its authenticated `/v1/models` catalog. Models with native reasoning controls expose them in the effort picker; omfx sends the correct Chat Completions, Responses, or Anthropic Messages fields for the selected Go model.

OpenAI-compatible providers use any HTTPS OpenAI-compatible service, or an HTTP loopback service for local development. Set the base URL and key, then select the provider:

```bash
export OMFX_OPENAI_COMPATIBLE_BASE_URL=https://api.example.com/v1
export CUSTOM_PROVIDER_API_KEY=your-key
omfx provider openai_compatible
omfx models
```

On Windows PowerShell:

```powershell
$env:OMFX_OPENAI_COMPATIBLE_BASE_URL = "https://api.example.com/v1"
$env:CUSTOM_PROVIDER_API_KEY = "your-key"
omfx provider openai_compatible
```

omfx fetches `/models` live and sends chat requests to `/chat/completions`. When a model advertises reasoning, the effort picker forwards the selected value and streamed reasoning is kept separate from the answer. The base URL must not include credentials, a query, or a fragment. `FX_OPENAI_COMPATIBLE_BASE_URL` remains accepted as a legacy environment name.

Named profiles use their provider's fixed HTTPS endpoint and dedicated environment variable. For example:

```powershell
$env:OPENROUTER_API_KEY = "your-key"
omfx provider openrouter
omfx models
```

The other profiles use `OPENAI_API_KEY`, `XAI_API_KEY`, `DEEPSEEK_API_KEY`, `GROQ_API_KEY`, `CEREBRAS_API_KEY`, `FIREWORKS_API_KEY`, `TOGETHER_API_KEY`, and `MISTRAL_API_KEY` respectively. Their model catalogs and reasoning metadata are kept separate from the custom endpoint profile.

To use an AI Gateway API key instead:

```bash
omfx setup
```

Run omfx from a project:

```bash
cd your_project
omfx
```

The current directory becomes the primary workspace. Enter a prompt, or run `/help` to browse interactive commands. On Windows, use the native `omfx.exe` artifact; the byte-identical `fx.exe` name remains available for older scripts.

The status line hides the workspace path and Git branch by default. Enable the `Status line workspace` option in `/settings`, run `/statusline workspace`, or set it in `~/.fx/settings.json`:

```json
{
  "statusLine": {
    "workspace": true
  }
}
```

List saved sessions with `omfx sessions`. Resume the latest session for the current workspace, or select an exact session ID, through the same command group:

```bash
omfx session resume last
omfx session resume --id <id>
```

Each interactive session names its terminal tab. The title prefers the session name, falls back to the workspace name, and keeps the active model as secondary context. Renaming or resuming a session updates the tab, and exiting clears the omfx-owned title. Noninteractive commands do not emit terminal-title controls.

Run `/feedback` to open the feedback form at `fx.sh/feedback`. It does not create a diagnostic or change the clipboard.

Run `/trace` to create a private Markdown diagnostic with logs, session context, runtime state, permissions, and recent activity. On macOS, omfx copies the `.md` file to the clipboard; on other platforms, it saves the file and prints its path. Review and redact the trace before sharing it.

Use `omfx ask` for a single request:

```bash
omfx ask "explain the changes in this repository"
```

omfx starts in `auto` permission mode. Routine understood development actions run directly; unresolved sensitive actions receive one bounded automatic review. A blocked action may return an exact approval request that the agent can send to omfx's real permission screen. Ordinary question text never grants permission. See [Permissions](https://fx.sh/docs/configure-fx/permissions) for other modes and persistent rules.

Use `omfx ask --full-access "..."` or `/permissions full-access` when you explicitly want unrestricted tool execution and no command sandbox. The legacy `--yolo` and `/permissions yolo` spellings remain accepted as aliases.

JSON and quiet requests stay noninteractive by default. Add `--prompt-permissions` to allow the existing Y/N approval prompt when stdin is a TTY. Prompt text is written to stderr, so JSON stdout stays parseable and quiet stdout stays empty. Piped or redirected stdin remains noninteractive and fails instead of waiting for approval.

Inside a saved session, `/permissions remember <allow|deny> <tool-name> <arguments-json>` stores an exact confirmed rule without running the action. `/permissions` lists stable rule IDs, and `/permissions revoke <rule-id>` removes a stored rule even when its original workspace or file state has changed.

## Embed omfx

omfx builds as a native binary or WebAssembly. Applications embedding omfx can provide network transport, session storage, configuration, permission handling, and terminal I/O.

| Surface | Use |
| --- | --- |
| `omfx acp` | Connect the native agent to editors and other Agent Client Protocol clients. |
| `createFxAgent()` | Embed the agent core in a JavaScript host with `fx-core.wasm`. |
| `createFxTerminal()` | Embed the interactive terminal with `fx-term.wasm`. |

The WebAssembly SDK is experimental. See the [WebAssembly SDK](sdk/README.md) and [ACP documentation](https://fx.sh/docs/using-fx/acp).

## Extend omfx

Add reusable instructions with [skills](https://fx.sh/docs/capabilities/skills), connect external tools through [MCP](https://fx.sh/docs/capabilities/mcp), or delegate independent work to [subagents](https://fx.sh/docs/capabilities/subagents). Project instruction files may link within their scope, and read-only workspace or compatibility skill directories may link within their owning workspace or home; managed skills, `SKILL.md` files, resources, and escaping links remain no-follow. Skills installed via symlinks that resolve outside home or workspace (e.g. Nix store paths) are loaded when their resolved target is inside a directory listed in the `FX_SKILL_SYMLINK_AUTHORITIES` environment variable (colon-separated absolute paths). `omfx status` and `omfx doctor` report an invalid trusted MCP profile without starting its servers.

## Documentation

Read the [omfx site](https://blu3ph4ntom.github.io/oh-my-fx/) for product identity and install.
Shared upstream harness docs remain at [fx.sh/docs](https://fx.sh/docs). For local UI
controls, see the [customization guide](docs/customization.md).

## Build from source

Building omfx requires [Zig 0.16.0+](https://ziglang.org/download/):

```bash
git clone https://github.com/vercel-labs/fx.git
cd fx
zig build -Doptimize=ReleaseSafe
./zig-out/bin/fx
```

Run the test suite with `zig build test`. See [CONTRIBUTING.md](CONTRIBUTING.md) for development and contribution guidelines.

## License

[Apache-2.0](LICENSE)

Third-party licenses and attributions are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Credits

Interface sounds by [cuelume](https://github.com/Danilaa1/cuelume).
