# omfx Design System

## Visual Theme

Night Signal is a restrained, terminal-native system with a cool cyan brand
signal and a violet focus signal against the user's own terminal surface. The
physical scene is a developer working in Windows Terminal or a Unix terminal
after dark, moving quickly between code, approvals, and model responses. The
screen should feel like a precise instrument: quiet at rest, expressive only
when state changes.

## Color Palette

Semantic roles are shared by every screen. Truecolor is preferred; the listed
256-color value is the fallback. Light terminals use the readable light values
defined by the implementation's palette module.

| Role | Truecolor | 256-color fallback | Meaning |
| --- | --- | --- | --- |
| brand | `rgb(99,230,255)` | `81` | omfx identity and primary mark |
| focus | `rgb(181,145,255)` | `141` | selected item and active control |
| success | `rgb(95,220,160)` | `78` | completed or safe state |
| warning | `rgb(255,190,92)` | `180` | pending or attention state |
| danger | `rgb(255,112,112)` | `203` | failure, denial, or destructive state |
| text | `rgb(235,239,245)` | `255` | primary content |
| muted | `rgb(145,154,170)` | `245` | hints and secondary content |
| border | `rgb(65,76,95)` | `240` | dividers and inactive chrome |

Accent color is reserved for identity, focus, and state. Inactive content
stays neutral. No component invents a private status color.

## Typography and Density

Use the terminal's native monospace font and a compact, stable scale. Strong
weight contrast distinguishes the product mark, headings, active controls, and
body text; decorative type is not introduced into the terminal UI. The default
density is compact, with a comfortable option for users who want more spacing.

## Layout

The inline transcript and composer are the primary surface. A three-row footer
contract keeps the divider, input, and hint/status rows stable. Transient
alternate-screen surfaces are limited to menus, approvals, full transcript,
subagent management, and terminal takeover. They share the same semantic
roles, frame spacing, title treatment, and exit restoration rules.

The interface does not add a permanent sidebar or dashboard grid. Hierarchy is
created with alignment, whitespace, borders, and state color rather than cards.

## Interaction States

Every interactive control has default, hover where supported, keyboard focus,
active/pressed, disabled, loading, error, and success treatments. Focus is
never represented only by a color change. Every transient surface states its
available keys in a compact hint row and keeps Enter to confirm and Escape to
cancel unless a destructive action explicitly requires a second confirmation.

## Motion

Motion communicates only loading, reveal, and state change. Frames are
coalesced after an input delivery epoch to avoid flicker. Reduced-motion mode
removes shimmer and nonessential transitions while preserving textual feedback.

## Customization Surface

Profile-owned settings expose automatic, dark, light, and high-contrast theme
behavior; compact or comfortable density; full or reduced motion; key-hint
visibility; and status-line contents. New `OMFX_*` environment aliases take
precedence over legacy `FX_*` names, while existing `.fx` profile and session
paths remain authoritative by default.

## Windows Rules

The native binary must use ASCII-safe public branding, handle Windows Terminal
and ConPTY input consistently, open authentication links through the Windows
default browser without treating a filesystem association as a URL, and
restore cursor, paste, mouse, keyboard, and screen modes on every exit path.
