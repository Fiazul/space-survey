class_name AnchorFrame
extends RefCounted
# 64-bit arithmetic for the anchored ship frame (docs/adr/0002). The ship's
# physical state is (anchor body, offset from that body's centre in km); every
# cross-body subtraction happens here, in GDScript floats — which are 64-bit
# even in a single-precision engine build — BEFORE the result is packed into a
# Vector3. That is the whole trick: a Vector3 near Venus has a ~14 km ULP, so
# `true_pos += velocity * dt` swallowed a 150 m substep outright; an offset
# measured from Venus itself is a few thousand km and loses nothing.
#
# Static-only and autoload-free on purpose — this is the one piece of the anchor
# design a plain `godot --headless --script` test can exercise.

# Earth sits at the origin of the geocentric frame, so this IS Earth's position.
# A `const` cannot hold a PackedFloat64Array literal; packed arrays are value
# types, so callers get a copy and cannot scribble on it.
static var ZERO64 := PackedFloat64Array([0.0, 0.0, 0.0])


static func vec64(v: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([v.x, v.y, v.z])


static func sub64(a: PackedFloat64Array, b: PackedFloat64Array) -> Vector3:
	return Vector3(a[0] - b[0], a[1] - b[1], a[2] - b[2])


# Absolute (Earth-centred) position of a point sitting `off` from `anchor64`.
# Lossy by construction — the sum lands back in a Vector3. Legacy readers only.
static func absolute(anchor64: PackedFloat64Array, off: Vector3) -> Vector3:
	return Vector3(anchor64[0] + off.x, anchor64[1] + off.y, anchor64[2] + off.z)


# Absolute -> offset from the anchor, per axis in doubles.
static func decompose(abs_pos: Vector3, anchor64: PackedFloat64Array) -> Vector3:
	return Vector3(abs_pos.x - anchor64[0], abs_pos.y - anchor64[1], abs_pos.z - anchor64[2])


# The same physical point expressed against a new anchor: off - (new - old).
static func reanchor(off: Vector3, old64: PackedFloat64Array, new64: PackedFloat64Array) -> Vector3:
	return off - sub64(new64, old64)


# Render-space vector to an absolute point, seen from a ship at (anchor64, off).
static func rel_to(abs_pos: Vector3, anchor64: PackedFloat64Array, off: Vector3) -> Vector3:
	return decompose(abs_pos, anchor64) - off
