# Astryx — Gameplay Layer Spec

Target: Godot 4 / GDScript. This spec covers the progression, crafting, station, and quest systems that sit on top of the existing flight model and procedural planet generator.

**Design thesis:** give players the joy of flying between stars without Elite's punishment curve. Nothing in this spec should ever cost a player their progress. Difficulty comes from scale and distance, never from loss.

---

## 1. Progression Spine

Hand-authored beats. Everything else is procedural.

| # | Beat | Purpose |
|---|---|---|
| 1 | Earth destruction, emergency launch | Cinematic opening, teaches basic flight |
| 2 | Reach orbit, build survival module | Tutorial for fabrication and docking |
| 3 | Return to Earth surface | Emotional beat: no humanity, ruins, little sign of civilization |
| 4 | Prompt: head to the Moon | First real objective |
| 5 | Moon: fire first probe (scripted) | Teaches the probe/relay loop |
| 6 | Inner Sol bodies | Gathering, crafting, first ship upgrades |
| 7 | Outer Sol / gas giants | Introduces gas skimming |
| 8 | First interstellar jump (Proxima) | Ship tier gate, marks end of hand-authored content |

After beat 8, all content is generated. Keep 4-6 more spine beats in reserve for later star systems so there is a narrative thread at long range.

### Earth as permanent graveyard port
Earth is always reachable and never improves. Docking there yields only scrap. Every other system gets better as the player progresses; Earth does not. This single asymmetry carries the game's identity — do not soften it with a rebuilt colony later.

---

## 2. Material Class System

The core abstraction. Planet gen outputs real elements and gases. Recipes never reference them directly.

### Layer structure

```
Planet gen  ->  Elements/gases (with tags)  ->  Material classes  ->  Recipes
```

### Material classes (~10)

`STRUCTURAL_ALLOY`, `SUPERCONDUCTOR`, `COOLANT`, `VOLATILE_FUEL`, `RADIATION_SHIELDING`, `SEMICONDUCTOR`, `OPTICS`, `PROPELLANT`, `CATALYST`, `POLYMER`

Recipes request a class and a minimum grade. Any qualifying element can fill the slot.

### Element definition

```gdscript
# res://data/elements/titanium.tres  (Resource)
class_name ElementDef
extends Resource

@export var id: StringName            # &"titanium"
@export var display_name: String
@export var phase: Phase              # SOLID / LIQUID / GAS
@export var qualifies: Dictionary     # { class_id: base_quality (0.0-1.0) }
@export var density: float
@export var abundance_curve: Curve    # sampled against planet params
```

Example: titanium qualifies as `STRUCTURAL_ALLOY` at 0.85 and `RADIATION_SHIELDING` at 0.3. Aluminium qualifies as `STRUCTURAL_ALLOY` at 0.5. Same recipe slot, different resulting mass and durability.

### Grades

Exploration must always pay, so quality is not fixed per element. Final grade is modified by where it was gathered:

```
grade = base_quality * environment_modifier
```

Environment modifier draws on planet gen params already available: stellar metallicity, surface temperature, stellar age, tectonic activity, atmospheric pressure. A superconductor refined from a hot metal-rich world near a young star should measurably beat one made from Earth scrap.

Grade feeds directly into component stats. Same recipe, better numbers. This is what keeps players hunting new worlds after they have already unlocked every recipe.

### Recipe definition

```gdscript
class_name RecipeDef
extends Resource

@export var id: StringName
@export var output: StringName          # component id
@export var inputs: Array[RecipeSlot]   # class_id, amount, min_grade
@export var unlock_tier: int
```

### Gas skimming
Gas giants and thick atmospheres are a distinct gathering activity, harvested in flight rather than on foot. This gives the three atmospheric/speed modes a mechanical purpose beyond flavour. `VOLATILE_FUEL`, `COOLANT`, and `PROPELLANT` should be sourced primarily from gas.

---

## 3. Probes, Relays, Stations

Landing on any large celestial body unlocks a deploy prompt. The player fires a builder probe; it descends and constructs a relay while the player flies elsewhere.

### Rules
- **Probes are unlimited and cannot fail.** No scarcity, no loss, no rebuild grind.
- Build window of roughly 2-10 minutes of real time so there is a sense of work happening. Completion fires a notification.
- Build duration scales with hostility (gravity, heat, pressure). This quietly teaches players to read planet stats without punishing them.
- Progress persists while the player is out of the system.

### Tiers

| Tier | Cost | Provides |
|---|---|---|
| Relay | Free | Refuel, fast travel node, data upload |
| Station | Materials | Fabricator, quest board, storage |

Relays are free and spammable. The meaningful choice is which systems get upgraded to full stations. Players who ignore the system entirely still get a playable game; players who engage get a network with real structure.

### Fast travel gating
Flying between stars is the core fun, so teleport must not replace it.
- Station-to-station only, both endpoints must be built
- Costs fuel
- Cargo mass cap, so real hauling still needs the ship

Teleport handles boring repeat trips. It never handles the interesting first one.

### Lore consistency
Humanity is gone, so no pre-existing infrastructure anywhere. Every station in the galaxy was placed by the player. The relay network *is* the progress map.

---

## 4. Data Archive and Economy

Selling planetary survey data is the infinite reward channel. Value never runs out because it scales on axes that never repeat.

```
data_value = f(distance_from_sol, body_rarity, first_discovery_bonus, scan_completeness)
```

### Who buys it
Primary sink is the player's own archive at their home station. Uploading data unlocks recipe tiers, better scanners, and longer jump range. This needs no surviving civilisation to justify it.

For a material currency, introduce a **remnant faction**: a few thousand survivors on a generation ship or a buried Mars colony. They pay in materials they cannot gather themselves. This gives a trade partner without repopulating the galaxy. Keep them small, keep them singular.

---

## 5. Procedural Quest Generation

Millions of stars cannot be hand-written. Template-driven generation dies fast because it degenerates into "fetch 20 iron" forever. Generate from world state instead.

### Inputs to the quest composer
- What the player's ship is currently missing or under-tiered on
- What this system actually contains (from planet gen params)
- What the player has and has not visited
- Current relay/station network shape
- Remnant faction needs

### Composition
```gdscript
func compose_quest(system: SystemData, player: PlayerState) -> Quest:
    # score candidate quest shapes against world state,
    # pick weighted-random from the top N to avoid determinism
```

Quest shapes worth having: survey an unscanned body, source a specific material class at a target grade, skim a named gas, extend the relay network toward a distant marker, deliver to the remnant faction, investigate a generator anomaly (unusual planet params).

Always tag quests with *why* they were generated so reward and text can be written from that reason. A quest that exists because the player's hull is two tiers behind should say so.

---

## 6. Map UI

Free relays create clutter. This is a UI problem, not a design one.

- Relays collapse into faint network lines, no named icons
- Named icons only for tiered stations
- Filter toggles: fuel, materials, quests, unscanned
- The map must answer "where do I go next" rather than showing 400 undifferentiated dots

---

## 7. Implementation Order

1. `MaterialClass` enum, `ElementDef` and `RecipeDef` resources, and the element-to-class qualification table
2. Grade calculation hooked into existing planet gen params
3. Inventory and fabricator, with class-slot resolution and substitution
4. Probe deploy, async build timer, relay persistence
5. Station tier upgrade and fast travel with fuel and mass constraints
6. Data scan, value formula, archive unlock tree
7. Quest composer, starting with three shapes and expanding
8. Map filtering and relay collapse
9. Hand-authored spine beats 1-8 as scripted sequences over the finished systems

Build systems before scripting the spine. The Moon probe deploy in particular should be authored last, once the probe loop actually works, because it is a showcase of the system rather than a special case.
