# Temperature-based star previews

The gallery and close views use the same PlanetGenerator recipes and shaders as
gameplay. Photosphere colors integrate a visible blackbody continuum through CIE
1931 and map to sRGB; exposure is compressed for display. Hot/cool surface variations,
granulation, giant convection and optical corona are procedural approximations.

Captured with compatibility rendering. Rendered palette checks pass for blue stars,
the warm-white Sun, warmer M dwarfs and dim brown dwarfs. These images are neither
observations of individual stars nor device performance benchmarks.

`ingame_sol.png`, `ingame_sirius.png` and `ingame_proxima.png` show the actual game
camera and travel flow. Far-side sphere faces are culled to remove the large
depth-conflict triangles found in these views. The shared pixel regression passes
for both warm-white and blue-white discs at real scene scale.
