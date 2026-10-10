# scripts/core/

Orchestration + cross-cutting player state. `main.gd` is the game's entry point: it
spawns every other module and drives the frame loop by direct calls. The other files
here are state/logic extracted out of `main.gd` by responsibility (ADR-0001 Phase 2/3).

| File | Type | Role |
|---|---|---|
| `main.gd` | glue | Root orchestrator — spawns the world, owns the game loop, input, travel/teleport, nav-targeting |
| `black_hole_portal.gd` | feature area | Horizon cubic-mist cinematic and dinosaur arcade; suspends space, preserves state, restores the 2 AU orbit |
| `game_state.gd` | feature area (autoload) | Persisted player profile + economy (coins, claimed, visited, nav, onboarding, customization) |
| `music_director.gd` | feature area | Platform↔flight music state machine — docked-only platform loop vs. a sequential flight playlist — driven each frame by `main` |
| `onboarding.gd` | feature area | The GETTING STARTED beginner quest step list + advance loop |
