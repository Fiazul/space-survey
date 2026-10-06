# Astryx tree pass: local asset and budget review

The user selected reusing `/home/fiazul/Desktop/mmo-rpg` tree assets in Astryx.
This is the next step after the Sovereign polish. No tree rendering changes have
been made by this review.

## Available assets

Source: `/home/fiazul/Desktop/mmo-rpg/assets/nature_vale/manifest.json` and
`/home/fiazul/Desktop/mmo-rpg/docs/nature-kit.md`. Source assets have their base at
ground level and glTF Y-up. The set includes oaks, birch, pines and a dead tree.

| Asset | Full triangles | Medium triangles | Distant triangles | Authored height |
|---|---:|---:|---:|---:|
| oak_a | 1,940 | 551 | 4 | 9.5 m |
| oak_b | 1,940 | 552 | 4 | 8.2 m |
| birch_a | 1,760 | 552 | 4 | 9 m |
| pine_a | 1,366 | 552 | 4 | 13 m |
| pine_b | 1,346 | 552 | 4 | 10.5 m |

The source budget is 3,000 triangles and 1,024px textures per tree; leaf/needle
atlases are 512px. The assets fit those limits. Bark is textured with normal and
roughness maps; foliage uses alpha-masked cards. Distant versions have two crossed
quads with rendered views of the matching parent tree. Retain the texture source
credits from the source project's `docs/licenses.md` when importing the assets.

## Astryx constraints

`SurfacePatch` currently builds primitive cone and rounded-crown trees. The
`SurfaceForest` placement pass is deterministic, respects water/ice, terrain slope,
biomes and settlement exclusions, and already works in real scale. The recipe
defaults to 30 m; placement varies that by 0.72–1.28, producing roughly 22–38 m trees.

Keep `TerrainSampler` as the only height source. Preserve seeded placement and the
existing worker/main-thread separation. Rendering resources must be created on
the main thread. The present cap is 8,192 forest instances plus 400 ordinary props;
the current prop contract allows three MultiMesh batches. The third batch combines
a tree and boulder using per-instance selection. Imported bark/foliage surfaces
cannot be routed through the existing uniform vertex-color material unchanged.

Replacing all 8,192 trees with the 1,940-triangle oak would submit approximately
15.9 million triangles before other props. Per-asset compliance alone is insufficient.

## Proposed next step

Start with oak_a and pine_a. Use recipe-controlled mature sizes around 35–50 m,
with variation, while checking crown proportions and apparent leaf-cluster size
from the actual 100–300 m flight views. Merely enlarging the leaves can look worse.

Prototype a bounded detailed-tree population with the authored medium and distant
versions filling the rest of the forest. An illustrative ceiling of 64 full trees,
512 medium trees and 7,616 distant trees would total at most 437,248 tree triangles
using the maximum listed full/medium costs. This is a proposed geometry ceiling,
not a measured FPS result.

Resolve the existing three-batch contract before integrating the LOD partition;
do not silently multiply batches or create one scene node per tree. Share textures
across species/levels and preserve alpha cutouts, outward crown normals, sunlight,
local horizon blocking, atmosphere haze and streaming fade. Compare actual game
captures and geometry/memory/commit-time reports at the Amazon canopy site before
making performance claims.

Godot's automatic mesh LOD chooses one level for all instances in a MultiMesh;
individual instances also cannot be culled independently within one batch. The
forest therefore needs deliberate partitioning for mixed near/far detail rather
than assuming an imported full tree will automatically become cheap per instance.
See [mesh LOD](https://docs.godotengine.org/en/4.6/tutorials/3d/mesh_lod.html) and
[MultiMesh optimization](https://docs.godotengine.org/en/4.6/tutorials/performance/using_multimesh.html).
