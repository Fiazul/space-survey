# Crafting definitions

`crafting_catalog.gd` supplies fresh Resource definitions for the initial Earth
material pool and three starter recipes. `planet_generator.gd` links Earth to
material IDs and recipe IDs. `RecipeSlot.accepts()` checks class qualification and
minimum grade; recipes never require a specific element.

Amounts are gameplay units and quality values are tuning constants. This module
contains no inventory, extraction, crafting transaction, persistence, unlock UI or
component-stat calculation. Environment modifiers are supplied by the caller;
planet-derived modifiers are the next roadmap step. Probes remain free and unlimited.

See ../../docs/specs/2026-09-21-surface-contact-and-gameplay-readiness.md.
