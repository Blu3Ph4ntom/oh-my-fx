# omfx Public Identity and Design System Specification

**Status:** Approved design for implementation.

## Goal

Give the product a coherent omfx identity while keeping existing users,
scripts, sessions, and protocol clients working.

## Public identity

The visible product name is omfx in the startup banner, help, command
examples, status notices, terminal title, feedback copy, ACP display metadata,
release artifact names, and documentation. The logotype is ASCII-safe omfx;
decorative Unicode is not required for product recognition and must not become
mojibake on Windows.

The canonical public Windows artifact is omfx.exe. A byte-identical fx.exe
compatibility artifact remains available during the migration. The development
build may continue to expose zig-out/bin/fx because existing repository
verification and tooling depend on that path.

## Compatibility boundary

Preserve these names and meanings:

- existing FX_* environment variables;
- the default .fx profile, session, skill, and project configuration paths;
- the ACP _meta.fx compatibility namespace;
- provider wire identifiers and OpenAI's registered protocol originator.

Add OMFX_HOME as an explicit profile-root override and accept OMFX_* first
for new user-facing controls that currently have a product-specific FX_*
counterpart. If both are set, the OMFX_* value wins. Existing test-only
FX_E2E_* controls remain unchanged.

Do not silently move or delete an existing .fx directory. Diagnostics may offer
a migration path, but session data must remain recoverable.

## Visual system: Night Signal

Use semantic roles rather than component-specific colors:

| Role | Truecolor | 256-color fallback | Use |
| --- | --- | --- | --- |
| brand | 38;2;99;230;255 | 38;5;81 | omfx mark and primary identity |
| focus | 38;2;181;145;255 | 38;5;141 | selected item and active control |
| success | 38;2;95;220;160 | 38;5;78 | completed or safe state |
| warning | 38;2;255;190;92 | 38;5;180 | attention and pending state |
| error | 38;2;255;112;112 | 38;5;203 | failure and denial |
| text | 38;2;235;239;245 | 38;5;255 | primary content |
| muted | 38;2;145;154;170 | 38;5;245 | hints and secondary content |
| border | 38;2;65;76;95 | 38;5;240 | dividers and inactive chrome |

Light terminals use the same semantic roles with readable contrast values.
Color capability detection remains centralized. All screens use the same roles
for focus, status, notices, menus, approval controls, diffs, and the composer.

## Verification

Unit tests must prove public copy uses omfx, ASCII-safe banner output has no
non-ASCII branding bytes, compatibility FX_* and .fx behavior remains
available, OMFX_* overrides win, and ACP keeps _meta.fx while exposing omfx
display metadata. Windows CI must upload omfx.exe as the primary artifact and
fx.exe as the compatibility artifact. The real artifact must be run
interactively after the brand changes.

