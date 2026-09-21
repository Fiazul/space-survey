# Surface contact and gameplay readiness

User direction: death off; terrain must stop ships, with a slight impact bounce.
Build the foundation for ships landing later, without player landing controls now.
Earth remains recognizable; ruins and scrap dressing come later.

## Implemented

- Death is disabled by default through `FlightMode.death_enabled`. Developer
  no-death toggles do not bypass physical contact.
- Solid physical Sol worlds resolve swept movement against the same TerrainSampler
  used by ground geometry. Buried positions are lifted out, first contact blocks
  further travel, and inward normal velocity becomes an 8% rebound capped at 5 m/s.
  Low-speed contact is supported without gravity-driven repeated bouncing.
- A sphere enclosing the fitted ship bounds supplies clearance. This is deliberately
  conservative: it prevents hull penetration but is not landing-gear contact and
  can leave visible space under a ship's belly. Slopes can still allow sliding.
- The sweep samples at 25 m spacing and refines detected impacts. At extreme
  speed/timewarp it stops at the last verified point when its sample budget runs out,
  rather than increasing spacing and allowing tunnelling. It is a sampled heightfield
  collision, not an exact continuous mesh intersection for arbitrarily tiny features.
- Teleports invalidate previous contact positions. Render positions refresh after
  correction. Stars and gas giants have no solid floor.
- MaterialClass has the ten roadmap classes. ElementDef, RecipeSlot and RecipeDef
  are Resource types; qualification/grade checks support substitution.
- Earth lists crust/ocean/atmosphere identities and recoverable scrap identities.
  Its starter recipes are hull_patch, survival_module and survey_scanner.
  Recipes require class, amount and minimum grade. Definitions grant no inventory,
  unlocks or outputs. Earth docking remains designated scrap-only.

## Next playable slice: materials to fabrication

1. Add a versioned inventory/save model with material identity, source body, grade
   and quantity. Preserve the existing flight/save data and migration behavior.
2. Derive environment modifiers from available planet parameters. The current grade
   helper accepts a modifier but does not yet derive it. Set missing-data defaults
   explicitly; tune grade distributions so exploration improves component stats.
3. Implement one acquisition loop: Earth salvage plus a Moon resource/probe target.
   Define quantities and sources, not rewards for merely seeing a surface prop.
4. Build the fabricator: allocate qualifying stacks across class slots, prevent
   double spending, show substitutions/grades, consume atomically, persist outputs.
   Survival module is the first end-to-end recipe; hull patch and scanner follow.
5. Add component stats driven by grade and material mass. Density and stat mappings
   are not implemented in the starter catalog.

These are sufficient to begin the gameplay roadmap now; more Earth cosmetic polish
is not a prerequisite for inventory/fabrication work.

## Following slices

- Unlimited free probes, persistent 2–10 minute relay jobs, completion notifications.
- Station upgrades, storage, fuel-cost fast travel and cargo-mass limits.
- Survey archive value, unlock progression, then three world-state quest shapes.
- Map filters/network visibility, then author the spine beats over working systems.

Before ship landing presentation, add per-hull support/gear points, surface-relative
rest/rotation, grounded/takeoff state and a landing-site slope policy. Player landing
controls, walking and docking interactions are outside this pass.

Before extending close-surface gameplay beyond Sol, convert the remaining authored
arcade systems to consistent physical units or define their own collider matching
rendered globe displacement. They currently do not use the physical terrain band;
this pass must not interpret their coordinate units as kilometres.

## Verification and remaining issues

Contact tests cover Earth/Moon/Mars/Europa, Everest crossed between clear endpoints,
buried starts, capped bounce, stable rest, takeoff, extreme-speed budget handling,
scene integration and no-death
solidity. Crafting tests cover recipe/material references, substitutions, wrong
classes, minimum grades and environment quality scaling.

The broader anchor-frame suite reports four failures in anchor precision/drag
assertions; those are tracked separately from the passing contact checks. The
scene test also reports shutdown resource leaks. These remain to investigate.
