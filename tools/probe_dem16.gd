extends SceneTree
# Empirical probe: does Godot 4.6.3 preserve 16-bit-per-channel PNG precision
# through Image.load()/load_png_from_buffer(), or does it flatten to 8-bit?
# Referenced by docs/research/2026-09-09-dem-ingest.md. Test fixture is a 4x4
# I;16 grayscale PNG with two adjacent values (12345, 12347) that share the
# same HIGH byte (0x30) and would collapse to the identical 8-bit sample if
# Godot truncated/quantized on load.

const TEST_PNG := "/tmp/claude-1000/-home-fiazul-Desktop-space-survey/4c1556a2-d0c9-408c-a89a-9f27a5932015/scratchpad/probe16_test.png"
# hi/lo byte-pack fallback: same 16 source values, but pre-split by
# tools/ingest_dem.py into R (hi byte) / G (lo byte) of an RGB8 PNG.
const PACK_PNG := "/tmp/claude-1000/-home-fiazul-Desktop-space-survey/4c1556a2-d0c9-408c-a89a-9f27a5932015/scratchpad/probe_pack16_test.png"
const PACK_EXPECT := {
	Vector2i(0, 0): 12345, Vector2i(1, 0): 12347, Vector2i(2, 0): 0, Vector2i(3, 0): 65535,
	Vector2i(0, 1): 100, Vector2i(1, 1): 200, Vector2i(2, 1): 300, Vector2i(3, 1): 400,
	Vector2i(0, 2): 1000, Vector2i(1, 2): 2000, Vector2i(2, 2): 3000, Vector2i(3, 2): 4000,
	Vector2i(0, 3): 60000, Vector2i(1, 3): 61000, Vector2i(2, 3): 62000, Vector2i(3, 3): 63000,
}

func _init() -> void:
	print("--- probe_dem16: Image.load() path ---")
	var img := Image.new()
	var err := img.load(TEST_PNG)
	print("load() err=", err)
	if err == OK:
		_report(img)

	print("--- probe_dem16: load_png_from_buffer() path ---")
	var f := FileAccess.open(TEST_PNG, FileAccess.READ)
	if f == null:
		print("FileAccess.open failed: ", FileAccess.get_open_error())
	else:
		var bytes := f.get_buffer(f.get_length())
		f.close()
		var img2 := Image.new()
		var err2 := img2.load_png_from_buffer(bytes)
		print("load_png_from_buffer() err=", err2)
		if err2 == OK:
			_report(img2)

	print("--- probe_dem16: R=hi/G=lo byte-pack fallback (RGB8, no 16-bit format involved) ---")
	var img3 := Image.new()
	var err3 := img3.load(PACK_PNG)
	print("load() err=", err3)
	if err3 == OK:
		print("format=", img3.get_format(), " (expect FORMAT_RGB8=", Image.FORMAT_RGB8, ")")
		var ok := true
		for coord in PACK_EXPECT:
			var px := img3.get_pixel(coord.x, coord.y)
			var r255 := int(round(px.r * 255.0))
			var g255 := int(round(px.g * 255.0))
			var decoded := r255 * 256 + g255
			var expected: int = PACK_EXPECT[coord]
			var match_ok := decoded == expected
			if not match_ok:
				ok = false
			print(coord, " R=", r255, " G=", g255, " decoded=", decoded,
				" expected=", expected, " match=", match_ok)
		print("pack16_roundtrip: ", "OK" if ok else "FAIL")

	quit()


func _report(img: Image) -> void:
	print("format=", img.get_format(), " (Image.FORMAT_L8=", Image.FORMAT_L8,
		" FORMAT_LA8=", Image.FORMAT_LA8, " FORMAT_RH=", Image.FORMAT_RH,
		" FORMAT_RF=", Image.FORMAT_RF, ")")
	print("size=", img.get_size())
	# Row 0: [12345, 12347, 0, 65535] as 16-bit source values.
	var c00 := img.get_pixel(0, 0)
	var c10 := img.get_pixel(1, 0)
	var c30 := img.get_pixel(3, 0)
	print("pixel(0,0)=", c00, " -> r*65535=", c00.r * 65535.0)
	print("pixel(1,0)=", c10, " -> r*65535=", c10.r * 65535.0)
	print("pixel(3,0)=", c30, " -> r*65535=", c30.r * 65535.0)
	var same_8bit_hi_byte := int(c00.r * 65535.0) >> 8 == int(c10.r * 65535.0) >> 8
	var distinguishable := absf(c00.r - c10.r) > 0.00001
	print("12345 vs 12347 share hi byte (expected true): ", same_8bit_hi_byte)
	print("12345 vs 12347 distinguishable after Godot load (16-bit survives if true): ", distinguishable)
