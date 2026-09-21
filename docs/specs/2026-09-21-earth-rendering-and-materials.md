# Earth rendering and material integration

Earth stays geographically recognizable in this pass. Ruins and scrap dressing
come later, as requested on 2026-09-21. The gameplay direction is
[the Astryx roadmap](2026-09-12-astryx-gameplay-layer-spec.md).

The Earth generator recipe carries `materials`, grouped by crust, ocean and
atmosphere. These are candidate material identities for gameplay, not surveyed
ore deposits, extraction yields, grades or automatically granted inventory.
`port_salvage_only` preserves the permanent graveyard-port rule. Material classes,
qualification grades and fabrication remain the roadmap's next gameplay layer;
crafting recipes must request class/amount/minimum grade rather than specific
Earth-only elements. The current visual terrain does not imply harvestability.

Streaming must not block a flight frame to join an unfinished terrain worker,
including atmosphere exit and body switches. A worker retains its sampler until
completion. Terrain prediction stays within the inner patch, and coverage grows
with tangential flight speed and measured build duration. Fine resolution returns
when flight slows. Individual ring anchors update only after their mesh uploads.
The globe remains the fallback when terrain cannot keep up. Coverage is bounded
by the existing maximum mesh spacing; arbitrary speeds cannot guarantee fine detail.

Vegetation uses mapped color, latitude and elevation to avoid forests on desert,
polar and alpine ground. Permanent ice receives no forest-kit props.

Snow uses irregular accumulation, exposed steep slopes and a rough highlight.
Frozen-moon fractures and volcanic noise execute only on applicable bodies.
Unresolved procedural relief fades to zero instead of becoming a negative height
bias at distant levels of detail.

Validation: `tools/test_earth_stream_budget.gd` exercises a deliberately slow
worker on exit, 10 km/s coverage/prediction, stopping, unresolved relief, and
material metadata isolation. Existing terrain, recipe, prop and streaming tests
cover shared behavior. `tools/render_terrain.tscn` captures Everest, Arctic and
Amazon views. Global elevation and color map resolution still limits close detail;
this pass does not provide photogrammetry or a finished destruction scenario.
