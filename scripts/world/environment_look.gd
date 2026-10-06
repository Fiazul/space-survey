class_name EnvironmentLook
extends RefCounted
## Shared restrained color grade for gameplay and review captures.
static func apply(environment: Environment) -> void:
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.04
	environment.adjustment_saturation = 1.18
	environment.adjustment_brightness = 1.0
