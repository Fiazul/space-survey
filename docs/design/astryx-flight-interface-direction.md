# Astryx flight interface — proposed direction

## Intent

A serious third-person spaceflight and exploration game. The interface should make
physical flight, distance, momentum and the player's next decision legible without
crowding out the ship or world. The user explicitly permits replacing the existing
visual design. No cockpit imitation is required. Earth remains recognizable and
future material/crafting progression must fit into the interaction model.

## Diagnosis from the current implementation

- The navigation panel mixes speed, altitude, orbital reference speeds, scan progress,
  objective text and developer renderer diagnostics. These have different priorities.
- Its default scale is 0.76 and several critical lines use a 10px reference font,
  leaving speed and flight state difficult to read at the 1280×720 design size.
- Flight mode and zone are repeated in the speed line and instrument text.
- Labels use a metallic gradient shader. Readability over variable terrain needs
  consistent glyph contrast rather than decorative shading.
- Persistent combat totals, navigation controls, prompts and onboarding text create
  multiple competing focal points. The gameplay roadmap is exploration-first.

## Visual audit of the running desktop screen

Inspected an isolated fresh-profile capture on 2026-09-21. The navigation block
and hull bars overlap at top left; small telemetry and strong cyan panel edges
compete for attention. A bare XYZ orientation gizmo appears at right. The docking
prompt can read “Press F to dock at” without a destination. Combat totals and the
Earth teleport button occupy persistent corners despite ordinary exploration.
The ship below the selected planet is the strongest part of the composition and
should remain visible. The capture used a virtual display; existing player saves
and HUD positions were not modified.

## Recommended visual identity: expedition instruments

Near-white readouts, graphite local backplates where contrast requires them,
muted warm-gray labels, sea-green navigation cues, amber caution and red critical
warnings. Color indicates function, not a different theme for each widget.

Provisional colors: ink #E8EEE9, secondary #AAB8B4, plate #10191D,
navigation #8EDCC1, caution #E8B66B, critical #F17D72.
One readable sans family for UI, tabular numerals for instrumentation. Ordinary
readouts should start around 14–16px at 720p and support player scaling; critical
speed/clearance values can be larger. Test contrast against bright clouds, snow,
planetary night and black space. Outlines and subtle local backplates are functional.

## Composition

The center remains a view of the world, with a small projected nose marker and a
separate velocity-vector marker. The difference communicates drift immediately.
Selected destinations receive a restrained world-space bracket and an offscreen cue.

Top left: system/body/location, compact and stable.
Top center: one current objective or actionable caution, not a stack of banners.
Top right: a small session/system access point; most menu controls belong in a
consistent command screen, available through keyboard and controller.

Lower left: speed, flight mode, throttle/acceleration and relevant local flight data.
Lower right: selected destination, range, approach information, one contextual action.
Bottom periphery: compact ship condition. Expand damage and power detail on demand
or when a condition requires attention. Keep notifications in a single timed queue.

The signature is an approach instrument connecting velocity, destination and braking:
players should understand whether they are drifting sideways, closing too fast, or
ready to transition out of cruise. Compute it from live state and the actual drive
model; no decorative trajectory lines or invented braking precision.

## Contexts, not unrelated layouts

Surface flight: terrain clearance, vertical speed, velocity direction and terrain
warning. Distinguish AGL from sea-level altitude. Critical warnings use text and shape
as well as color. Support future grounded/takeoff states without claiming they exist.

Local space: body-relative velocity and useful orbital context. Advanced telemetry
can expand; instantaneous circular/escape speed need not occupy the default HUD.

Supercruise: drive state, destination distance, approach rate and exit/deceleration
information. Name the frame of reference and preserve real units. Do not call
scripted/visual travel rates physical velocity.

Survey: selected body, scan state and one clear action. Discovery detail appears in
a brief result and the archive, not in a permanent wall of flight text.

Combat: aiming, target state, weapon state and damage become prominent. Hide irrelevant
survey prompts. Instruments retain their locations so muscle memory survives.

## Interaction and implementation boundaries

Build a single command interface for navigation, ship systems, inventory, fabrication
and archive as those systems become available. Disabled future features must not be
presented as working actions. Keep the in-flight view focused on piloting.

Preserve current input bindings and live data integrations while replacing visual
components. Respect user HUD scale/accessibility; saved positions from the old layout
need an explicit version/migration rather than quietly mangling the new arrangement.
Developer diagnostics belong behind F3. Include reduced motion and alert prioritization.

## Review and rollout

First review the visual composition against real flight captures: Earth surface,
orbital limb and deep-space cruise. Then build one working flight-HUD slice in Godot,
validate on light and dark backgrounds at 720p/1080p/ultrawide, and expand the shared
system to command screens. This file is a proposed design, not an implemented HUD.
