# Customize omfx

omfx uses a terminal-native design system called Night Signal. It keeps the
interface quiet by default, gives focus a violet accent, and reserves distinct
semantic colors for success, warning, danger, muted text, and borders. The
same roles are used by the dark, light, high-contrast, and 256-color fallback
palettes.

## Fast controls

Inside an interactive session:

```text
/settings
/appearance input lines
/appearance input tint
/appearance presentation normal
/appearance presentation minimal
/statusline workspace
/statusline session
/sound off
```

`/settings` opens the complete settings catalog. In menus, use Up and Down to
move, Enter to apply, and Escape to return without applying the current
surface. `/help` shows the complete command list and completes command
arguments as you type.

The interface settings are:

| Setting | Values | Effect |
| --- | --- | --- |
| Theme | `auto`, `dark`, `light`, `high_contrast` | Select the Night Signal palette. `auto` follows the terminal. |
| Density | `compact`, `comfortable` | Adjust spacing in interactive surfaces. |
| Motion | `full`, `reduced` | Keep or reduce animated status updates. |
| Key hints | `on`, `off` | Show keyboard hints in menus and prompts. |
| Input appearance | `lines`, `tint` | Choose the composer and submitted-prompt treatment. |
| Presentation | `minimal`, `legacy` | Choose the transcript presentation. |

The status line can independently show sandbox, context, session, workspace,
and Git information. Each `/statusline <item>` command toggles one item and
persists the choice.

## Persistent profile settings

Profile-owned preferences belong in `~/.fx/settings.json`. The project
`.fx.json` file is intentionally limited to shareable workspace defaults and
does not override personal appearance or credential settings.

Example:

```json
{
  "ui_theme": "high_contrast",
  "ui_density": "comfortable",
  "ui_motion": "reduced",
  "show_key_hints": true,
  "statusLine": {
    "workspace": true,
    "session": true,
    "context": false,
    "sandbox": false
  },
  "startup_scrollback": false,
  "prompt_history": {
    "enabled": true
  }
}
```

Environment variables take precedence over profile settings. The `OMFX_`
names are preferred; the matching `FX_` names remain supported for scripts
and existing installations:

```powershell
$env:OMFX_UI_THEME = "high_contrast"
$env:OMFX_UI_DENSITY = "comfortable"
$env:OMFX_UI_MOTION = "reduced"
$env:OMFX_SHOW_KEY_HINTS = "false"
$env:OMFX_MODEL = "gpt-5.6-luna"
$env:OMFX_NO_OPEN_BROWSER = "1"
```

On Windows, `OMFX_NO_OPEN_BROWSER=1` is useful in SSH sessions, CI, or when
you want to copy the complete authorization URL into a browser yourself.

## Providers and model identity

The active provider is deliberately visible in `omfx status --json` and can be
changed without deleting credentials:

```powershell
omfx provider codex
omfx models
omfx provider opencode_go
omfx models --json
```

Codex sign-in activates the Codex provider only after the authenticated model
catalog loads successfully. If catalog loading fails, the previous provider
and credential remain selected. OpenCode Go uses its own credential source:

```powershell
$env:OPENCODE_GO_API_KEY = "your-key"
omfx provider opencode_go
```

The OpenCode Go API key is never used for another provider. Likewise, a Codex
subscription credential is not sent through the AI Gateway route.

## Windows-native use

Use the downloaded `omfx.exe` artifact directly from PowerShell:

```powershell
.\omfx-windows-x86_64-<commit>\omfx.exe status --json
.\omfx-windows-x86_64-<commit>\omfx.exe
```

The Windows callback listener binds IPv4 loopback and advertises that same
address in the OAuth redirect. This avoids browser resolution differences
between `localhost` and IPv6 loopback. The authorization link keeps the full
redirect target even when its visible terminal label is clipped.

## Compatibility and diagnostics

`omfx` is the product identity. The historical `fx` command, `FX_*`
environment aliases, and `.fx` profile paths remain compatibility surfaces so
existing sessions and scripts continue to work. Use these commands when
diagnosing a setup:

```powershell
omfx status --json
omfx doctor
omfx models --json
```

For a rendering bug, run with `FX_RECORD=<path>` and replay the tape with
`omfx replay <path> --json`. Redact private paths, prompts, and credentials
before sharing diagnostics.
