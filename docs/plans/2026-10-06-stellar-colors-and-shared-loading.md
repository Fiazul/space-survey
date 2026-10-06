# Stellar appearance and shared loading

User request: investigate delayed rendering beyond Earth and make stellar recipes
closer to real temperatures instead of universal orange/yellow plasma.

Design: preserve anchored physical distances, shared recipe/cook materials, fixed
star geometry, vacuum black, hazards and existing mesh/sky handoffs. Integrate a
visible blackbody continuum using the CIE 1931 observer, provide hot/cool surface
colors, scale convection by stellar family and filter unresolved texture. Separate
display exposure from physical luminosity. Avoid new textures or particle systems.

Evidence: G/K/M shader branches overwrote recipe colors with saturated orange, and
corona tint applied a second orange multiplier. A minimal GDScript experiment proved
callback assignment to a captured Array does not persist between calls. The actual
staggered-texture regression confirmed completed map flags were subsequently reset.

Implementation: cached continuum colors and explicit surface-temperature colors;
350 solar cells (approximately 994 km spacing), subdued hot-star convection,
white-biased optical halo, ordinary photosphere exposure for the Sun, derivative
filtering with skipped subpixel noise and skipped stellar terrain height samples.
Shared map polling retains remaining keys in a mutable dictionary and disconnects
and clears its closure after completion.

Validation: color/scale regression, physical recipes/hazards, planet-generator
checks, Sun mesh/sky transition, every catalogue star destination, staggered loads,
actual rendered twelve-family gallery and close views. Spaceflight physics and
physical luminosity are unchanged. Blackbody colors are continuum approximations,
not individual atmosphere/spectral simulations. GPU frame rate remains unmeasured.

Actual in-game captures exposed large triangular patches on distant photospheres.
The opaque cook shader drew both sphere hemispheres; far-side faces competed in the
depth buffer at large scale. Culling those faces fixes the shared sphere draw path.
A pixel regression deliberately restores the old mode: approximately 51% of the
Sun core and 46% of Sirius's core are corrupt. Production mode measures 0% for both
and all six in-game star captures pass. Vacuum background is black.

User follow-up: many destinations still appear orange/white because the nearby
travel catalogue has no O/B stars. Sirius is pale blue-white; gallery O/B examples
show stronger blue-white support. No spectral types were invented for existing
real destinations to force arbitrary color variety.
