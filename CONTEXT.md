# Astryx

Space survey game. Sol is becoming a 1:1 physical world; other systems stay authored arenas for now.

## Language

**Scene unit**:
One kilometre. Every `true_pos` and body radius is stored in these units.
_Avoid_: Godot unit, meter (not yet), old 0.1 AU unit

**True position**:
A body's absolute position in scene units. The ship stays at the render origin; bodies draw at true position minus the ship's true position.
_Avoid_: world position, global transform

**Physical body**:
A Sol body whose radius and separation are real. Past the camera far plane it is a sky disc with the real angular size. The cut is the near face, not the centre — a star bigger than the far plane still becomes a cook ball when you close in.
_Avoid_: scaled planet, fat planet, star forced to sky disc forever

**Opaque world**:
A celestial body hides everything behind it. Sky impostors sit behind every in-range mesh. Stars and the Sun corona test depth. You never see the Sun or other stars through a planet, moon, or star.
_Avoid_: depth-test-off starfield, sky shell in front of the Moon, additive sun through a world

**Geostationary spawn**:
The Sol start: 42,157 km from Earth's centre on the anti-Sun ray. Parked — no circular speed — so you fall.
_Avoid_: start pad, hangar origin

**Newton**:
Sol inverse-square pull from the live bodies. Vacuum has no damping. Arcade idle-release is off. A mouse or key turn carries speed with the hull so the nose and the path match.
_Avoid_: arcade well, safe-zone pull, leftover “I turned but still fall in”

**Earth atmosphere**:
A 100 km skin. Drag only. No blue shell. Inside it the ship turns with Earth — you do not watch the ground race.
_Avoid_: fat air shell, Kerbal bubble, arcade planet spin

**Flight zone**:
CENTER / INSIDE / SKIN / AIR / SPACE vs the nearest body. Tape says the word. Same shells for a planet, moon, or star. Star corona is a look, not air.
_Avoid_: mystery altitude, Sun as a unique object

**Flight mode**:
LOCAL / CRUISE / AIR. Zone is where. Mode is how. Cruise is Sol time warp outside a body's exclusion (Elite EZ, real size). Earth 100 km. Venus 250. Mars 80. Titan 600. Giants a few hundred km above the 1-bar skin. Airless +10 km. Stars +2500 km chromosphere. Hitting EZ from cruise or fat engines is DROP — sit on the shell, dump speed, short tape cue, not a white blink. Air is still drag after that. You do not skip the air into a skin kill.
_Avoid_: Elite white flash as the trick, arcade FTL in Sol, cruise through a world

**Sol speed**:
Earth-relative. m/s when slow, km/s when fast. Engines are a few g. No arcade 550 cap in Sol.
Time warp: period faster, comma slower. Dies in air or on burn.
_Avoid_: u/s, warp-as-local-flight

**Planet generator**:
One cook. Catalog row → true position → recipe. Real map when we have evidence. Spectral/size when we do not. Sky is HYG points; you only cook a ball when the player is there. EZ is high bird-eye on that ball. Tape Cook/Look is the render log. Pacman voids in mosaics fill with recipe crust. You will not land.
_Avoid_: Earth texture hack, landing game, Elite clone, one mesh per planet, hand-authoring every star, unique GLB per world

**Skin kill / no landing**:
Every body uses the same swept terrain-contact test (`Ephemeris.surface_kill_km`, a 20 m margin above the sampled ground, in the body's own rotating frame), not a fixed altitude bubble. Death is a short tumble, then a snap to the nearest sweet park (GEO for Earth).
_Avoid_: landing gear, silent hitch, 8 s home ritual for a skin kill

**Recipe**:
Per-body look data. A real map path when we have one. Kind, colors, and heat when we do not. Features (volcano at a real spot) live here later.
_Avoid_: one mesh per planet, shared random noise with no data

## Standing rule

Every Sol feature we just landed is a **first pass**. We will come back to each one and make it right. Do not treat any of this as finished.

Needs a perfection pass later: naked sky, Newton pull, Earth air (drag, no fake shell), speedo, engines, time warp, Sol worlds / sky discs, labels, flight feel, planet-generator paint.

Debug (Sol only): F6 circularize at this height. F7 park at GEO. F9 fat engines so the 42,000 km GEO gap is testable. F10 point the nose at the nearest body and kill leftover speed. S is a brake. F4 dumps a 15s flight footprint. Tape in/out/alt is vs that nearest body, not always Earth.

## Later (do not build now)

- **No special Sun sky path** — start next session here. `_sun_sky` is still a unique impostor. A star should be one physical body: cook mesh when the near face is in range, sky disc when it is not. Recreate with F9 into the Sun; mesh must be on inside ~1.64 R, disc off.
- **Plane band** — done: the m/s flyover with one local height tile + low-poly kit now runs on every physical body, Earth included (35 km ceiling, no fixed kill altitude). See `PLANET_GENERATOR.md`.
- Richer 101 m assets (real tree kits, volcanoes). Skin kill and the first ground patch are in. The 36 km stamp must not show at 100 km AIR.
- Remaining moon mosaics in the same albedo slot (Deimos; Ganymede gridless USGS/NASA swap)
- USGS / NASA / ESA 8k swap in the recipe albedo slot
- **Vacuum RCS / empty-space spin**
- **Flight feel / units / leftover arcade**

The generator is why we stop on a planet’s skin and do not build a landing game.
