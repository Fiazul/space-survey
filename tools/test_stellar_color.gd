extends SceneTree
var failures := 0

func _initialize() -> void:
	var color := StarRecipe.color_at(6500).srgb_to_linear()
	var x := .4124564 * color.r + .3575761 * color.g + .1804375 * color.b
	var y := .2126729 * color.r + .7151522 * color.g + .0721750 * color.b
	var z := .0193339 * color.r + .1191920 * color.g + .9503041 * color.b
	check("6500 K follows the Planckian locus", absf(x / (x + y + z) - .3135) < .005 and absf(y / (x + y + z) - .3237) < .005)
	var sun := StarRecipe.resolve({"name": "Sun", "spectral": "G2V"})
	var granule_km: float = sun.stellar.radius_km / (sun.stellar.cells * 2.0)
	check("solar granules have roughly 1000 km spacing", granule_km > 500 and granule_km < 2000)
	check("solar photosphere is warm white", sun.color_a.b / sun.color_a.r > .87)
	var hot := StarRecipe.resolve({"spectral": "B1V"})
	var cool := StarRecipe.resolve({"spectral": "M5V"})
	check("radiative hot stars suppress convection texture", hot.stellar.detail_contrast < sun.stellar.detail_contrast * .3)
	check("cool stars stay warmer than hot stars", cool.color_a.r / cool.color_a.b > hot.color_a.r / hot.color_a.b)
	for recipe in [sun, hot, cool]:
		check("photosphere temperature colors are explicit", recipe.stellar.has("cool_color") and recipe.stellar.has("hot_color"))
	print("stellar_color: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)

func check(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", label)
