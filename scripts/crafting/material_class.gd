extends RefCounted
## Stable class IDs; recipes depend on these, never a particular planet's elements.
enum Kind {
	STRUCTURAL_ALLOY, SUPERCONDUCTOR, COOLANT, VOLATILE_FUEL,
	RADIATION_SHIELDING, SEMICONDUCTOR, OPTICS, PROPELLANT, CATALYST, POLYMER
}
