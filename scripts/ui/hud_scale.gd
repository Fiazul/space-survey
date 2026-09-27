class_name HudScale
extends RefCounted
# Touch-UI sizing shared by hud.gd and TouchControls. The canvas is pinned to 720 short
# (canvas_items + expand), so on a high-dpi phone one canvas unit is ~0.1 mm and a 48-unit
# button lands under a fingertip at ~4.5 mm. touch_scale() is how much larger touch targets
# must grow for REF_TARGET canvas units to span TARGET_MM (Android's 48 dp minimum),
# clamped; always 1.0 off-mobile so desktop never changes. safe_insets() converts the
# display cutout safe area to canvas units. The pure compute_*/fit_* functions are
# unit-tested in tools/test_touch_controls.gd.
# TOUCH_SCALE / SAFE_INSET ("l,t,r,b" canvas units) env overrides exist so desktop
# `--touch` screenshots can preview a phone (xvfb reports 96 dpi, no cutout).

const MIN_SCALE := 1.0
const MAX_SCALE := 1.6
const TARGET_MM := 7.6
const REF_TARGET := 48.0
const BASE := Vector2(1280.0, 720.0)


static func is_touch() -> bool:
	return OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()


static func touch_scale() -> float:
	if OS.has_environment("TOUCH_SCALE"):
		return clampf(float(OS.get_environment("TOUCH_SCALE")), MIN_SCALE, MAX_SCALE)
	var screen := DisplayServer.screen_get_size()
	return compute_scale(float(DisplayServer.screen_get_dpi()), Vector2(screen), OS.has_feature("mobile"))


static func compute_scale(dpi: float, screen_px: Vector2, mobile: bool) -> float:
	if not mobile or dpi <= 0.0 or screen_px.x <= 0.0 or screen_px.y <= 0.0:
		return 1.0
	var long_px := maxf(screen_px.x, screen_px.y)
	var short_px := minf(screen_px.x, screen_px.y)
	var px_per_unit := minf(long_px / BASE.x, short_px / BASE.y)
	var target_px := TARGET_MM / 25.4 * dpi
	return clampf(target_px / (REF_TARGET * px_per_unit), MIN_SCALE, MAX_SCALE)


# Largest scale <= desired at which `extent` canvas units still fit into `available`.
static func fit_scale(desired: float, extent: float, available: float) -> float:
	if extent <= 0.0:
		return desired
	return clampf(minf(desired, available / extent), 0.5, desired)


# {left, top, right, bottom} in canvas units.
static func safe_insets(canvas: Vector2) -> Dictionary:
	if OS.has_environment("SAFE_INSET"):
		var p := OS.get_environment("SAFE_INSET").split(",")
		if p.size() == 4:
			return {"left": float(p[0]), "top": float(p[1]), "right": float(p[2]), "bottom": float(p[3])}
	if not OS.has_feature("mobile"):
		return compute_insets(Rect2(), Vector2.ZERO, canvas)
	return compute_insets(Rect2(DisplayServer.get_display_safe_area()),
		Vector2(DisplayServer.window_get_size()), canvas)


static func compute_insets(safe: Rect2, window_px: Vector2, canvas: Vector2) -> Dictionary:
	var none := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if window_px.x <= 0.0 or window_px.y <= 0.0 or safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return none
	var k := canvas.x / window_px.x
	return {
		"left": maxf(0.0, safe.position.x) * k,
		"top": maxf(0.0, safe.position.y) * k,
		"right": maxf(0.0, window_px.x - safe.end.x) * k,
		"bottom": maxf(0.0, window_px.y - safe.end.y) * k,
	}


# Re-dock a widget authored against the 1280x720 base onto the real canvas: anything left
# of centre keeps its left gap (plus the left inset), anything right of centre keeps its
# right gap; same for top/bottom. `pos`/`size` in base coordinates.
static func dock_pos(pos: Vector2, size: Vector2, canvas: Vector2, insets: Dictionary) -> Vector2:
	var out := pos
	if pos.x + size.x * 0.5 > BASE.x * 0.5:
		out.x = canvas.x - (BASE.x - pos.x) - float(insets.right)
	else:
		out.x = pos.x + float(insets.left)
	if pos.y + size.y * 0.5 > BASE.y * 0.5:
		out.y = canvas.y - (BASE.y - pos.y) - float(insets.bottom)
	else:
		out.y = pos.y + float(insets.top)
	return out
