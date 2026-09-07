# Product

## Register

product

## Users

omfx is for developers and technical operators who work from a terminal and
want an AI coding agent that stays close to their shell workflow. They use it
frequently from Windows Terminal, ConPTY, tmux, and Unix terminals while
editing repositories, reviewing changes, approving commands, and switching
between model providers.

## Product Purpose

omfx is a small, native, model-agnostic coding-agent harness. It should make a
developer's next useful action obvious without turning the terminal into an
IDE. Success means a user can start a session, authenticate or choose a
provider, type and edit a prompt, navigate every interactive surface, review
tool actions, and leave the terminal exactly as they found it.

## Brand Personality

Precise, calm, and opinionated. omfx should feel like a dependable instrument
for serious terminal work: quick to respond, clear about state, and confident
enough to stay visually quiet when the user is focused.

## Anti-references

omfx should not look like a heavy IDE, a decorative dashboard, a browser UI
pretending to be a terminal, or an unstable prototype with unexplained
animation. It should avoid mojibake, hidden focus, color-only status cues,
ambiguous controls, noisy gradients, and branding that changes the established
`.fx` compatibility boundary.

## Design Principles

1. Command first: the transcript and composer remain the center of gravity.
2. Native before ornamental: terminal capability and reliable input outrank
   visual effects.
3. State is visible: focus, loading, success, failure, provider, and permission
   state must be readable without guessing.
4. Compatibility is a feature: public omfx identity can evolve while `fx`,
   `.fx`, `FX_*`, and protocol compatibility remain safe.
5. Progressive disclosure: common actions stay compact; deeper controls live
   behind familiar commands and settings.

## Accessibility & Inclusion

Keyboard operation is the primary interaction path. Every interactive surface
must expose visible focus, deterministic Enter and Escape behavior, and
consistent Up/Down and Tab navigation. The interface must remain usable with
light terminals, 256-color terminals, no color, narrow windows, reduced
motion, and Windows ConPTY. Status must never rely on color alone, and long
labels and provider errors must wrap without hiding the action that resolves
them.
