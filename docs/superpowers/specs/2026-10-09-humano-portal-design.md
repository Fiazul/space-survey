# Sagittarius A* → Humano

Crossing Sagittarius A* should become a playful portal, preserving the ship and
progress. The user clarified that this is the Chrome dinosaur joke reversed:
the player sees a dinosaur from behind, playing an endless runner whose character
is a little human on a physical screen.

## Experience

The horizon starts a five-second cinematic. The ship continues coasting instead
of losing its hull or stopping; drifting 3D cubic frames and an increasing mist
fill the camera. A brief loading card covers the swap. Then the whole space view
and its HUD disappear, revealing a third-person dinosaur at an arcade cabinet.
This fictional interior effect applies only during the portal.

Humano is a small endless runner: Space, Up, click or a touch button starts/jumps;
obstacles arrive with safe spacing, the score increases, a hit offers a restart.
The dinosaur taps the controls when the player jumps. Esc or a visible Return to
ship button exits at any stage and restores a circular orbit at exactly 2 AU
from Sagittarius A*, facing the hole. Hull, customization and discovery remain.

## Design and ownership

`BlackHolePortal` owns the cinematic, loading, room and temporary suspension of
space rendering, processing, inputs and audio. Its own viewport contains the
cubic effect and room, so unrelated worlds do not contribute to the arcade view.
`HumanoRunner` owns the human's jump physics, scoring, obstacles and pixel drawing.
The existing root orchestrator starts the portal and performs anchored return;
no rewrite of ship gravity or ordinary surfaces is needed.

The horizon's swept-crossing flag remains the trigger, including fast crossings.
Beyond it the interior motion is cinematic coasting, not integration through the
pseudo-Newtonian potential's singularity. The screenshot follow-up adds a fictional
0.6 AU capture boundary: radial infall overrides arbitrary velocity/thrust and
developer no-death, reaches the horizon within four simulation seconds, and then
opens the portal. Swept crossings cannot skip the capture region.
Repeated triggers cannot create another portal. Saved locations during the
portal point to the safe 2 AU orbit, so quitting cannot trap a player inside.

## Visual direction

The room uses midnight blue `#182637`, warm cream `#f1dfb5`, dinosaur green
`#62ab80`, dusty pink `#dc7f9b` and ink `#263541`. Quiet sans-serif room labels
and a monospaced screen contrast the chunky dinosaur and cabinet. The signature
is the playable human screen inside the dinosaur's third-person view. Geometry
and art come from primitives and drawing code; no downloaded assets or shaders
with costly full-screen ray marching are needed.

## Validation

Headless runner checks cover jumping/landing, collision/restart, scoring and
large frame deltas. A scene test checks swept horizon entry, preserved velocity
and hull, continued interior displacement, one portal, loading/play stages,
suspended world controls and audio, safe saves, Esc/button exit and repeated use.
Retain relevant core/plunge regression checks. Capture the cinematic, loading
and dinosaur room sequentially with software rendering and inspect the images.
