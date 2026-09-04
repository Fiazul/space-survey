# Needs your eyes

Things I cannot verify and you can. Everything here renders on **llvmpipe
software Vulkan** in my environment, so I can prove geometry, ranges, shared
rules and bounds — never appearance. Delete a line once you've judged it.

Fly to Earth, drop through **16.16 km**, and look. Band runs 0.03 → 16.16 km.

---

## 1. Three parameter judgments from slice A6 (light and air)

These are tuned to numbers I derived, not to a look. Each has a named lever.

| What to judge | If it's wrong | Lever |
|---|---|---|
| **Haze distance.** Does the far ground dissolve like kilometres of air, or like a grey fog a few hundred metres out? | too much / too little depth | `PlanetGenerator.HAZE_KM` (70.0). Higher = clearer. Measured: 95% at ring 3's 205 km rim, 25% at 20 km, 3% at 2 km |
| **Terminator curve.** Do ridges read, or does the lit/dark transition crush them into flat black and flat white? | ridges vanish near the terminator | `TERMINATOR_LO` / `TERMINATOR_HI` (−0.04, 0.28). Widen the gap for a softer roll-off. **Changing these changes the globe too — that sharing is deliberate** |
| **Air shell.** Is it a sky, or a blue wash over everything? | reads as a filter, not air | `air_shell_opacity()`'s `pow(depth, 1.5)`. Measured 0.78 at 15 km, 0.09 at 80 km |

Also worth a glance: **the night side.** `NIGHT_FILL` is 0.06, so the dark
hemisphere is 6% lit rather than pure black — pure black loses the horizon and
reads as a hole. If it looks milky, that number is why.

## 2. The pale diagonal band from the 22:57 screenshot

Still unexplained, and I would rather ask than guess. At `Alt 15 km Earth` there
was a large pale-blue straight-edged band across the sky and **no Earth globe
below you**, which is odd on its own — the crossfade maths says the globe should
be fully visible at 6386 km. Two answers would settle it:

- Does the band **move with the ship**, or stay fixed relative to the ground?
- Is there **ground below you at all**, or only that band and dark sky?

Candidates I can't separate from one frame: ring 3 seen at a grazing angle, the
water mesh, or a facet of Earth's own 192-segment sphere.

## 3. Ring seams

Never rendered. The maths says the skirts seal, but look for concentric **square**
boundaries where resolution changes (rings are squares, not circles), or gaps you
can see through. Haze should now hide the outer ones — that was part of why
`HAZE_KM` was chosen.

## 4. Does it still hitch?

Ring rebuild is **47.7 ms**, happening every 400 m of travel. At 230 m/s that's
one hitch every 1.7 seconds — 2.7% of the time, down from 123%. If that hitch is
visible, the next lever is inlining the noise (~27 GDScript calls per height
sample is the residual cost), or dropping `RING_SEGS` from 64 to 48.

## 5. The ship mesh looks yaw-rotated ~30°

Reported 2026-09-04, not diagnosed. Full note in `HANDOFF.md` under "Still open",
including the three candidate layers and why a counter-rotation is the wrong first
move.

---

## Known-not-fixed, so don't report these

- **Ground is still one flat colour.** The albedo spans under two texels across a
  whole ring — 0.51 on Earth. Slice A7 (the palette) is what fixes it.
- **No mountain ridges at 50 m scale.** `DETAIL_FREQ` gives a **44.5 km**
  wavelength, which is coarser than ring 0's entire 3.2 km width, so it adds broad
  undulation rather than ridges. Ridge-scale features need roughly 150× that
  frequency. I described this as "what makes 50 m triangles worth having" in an
  earlier commit; that was wrong in effect, and it is the #4 item on the
  reference-image gap list.
- **No cast shadows.** A mountain does not shade the valley behind it; dark sides
  are dark only from facing away from the sun. Named in the spec as the biggest
  remaining gap from your reference image.
- **Water is a dark plate**, not a surface. Slice C.
- **Trees only between 570 m and 5.2 km elevation** on dry ground, so most of
  Earth has no props at all. Slice D.
