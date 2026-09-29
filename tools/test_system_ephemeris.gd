class_name TestSystemEphemeris
extends Node3D
## Slice 1 of docs/plans/2026-09-29-one-physics-ripout.md. (a) Sol through the
## SystemEphemeris delegation is bit-identical to b62b8a5 (SNAPSHOT, dumped from
## that commit's ephemeris.gd: per body pos64, gm, radius, spin, atmo,
## scene_spin, anchorable, surface_angle at CLOCKS, sweet_spot_off, sweet_spot).
## (b) generated Proxima flies Newton at real km with anchoring. (c) switching
## back restores Sol exactly.
## godot --headless tools/test_system_ephemeris.tscn  -> "system_ephemeris: OK"
const E := preload("res://scripts/autoload/ephemeris.gd")
const ShipScript := preload("res://scripts/flight/ship.gd")
const CLOCKS := [1.8e9, 1.9e9 + 12345.678, 2.05e9 + 0.5]
const PROXIMA := "proxima"
const SNAPSHOT := {
	"Ariel": "bc5a68082e22d5417bcf134174d3cf41f32c5fc4fe83e2410000000000a055403333333333178240e101afe0c84dfe3e0000000000000000c501afe0c84dfebe000000000000f03f202cebb5da5d11c000a552ad99bb11c0a074c3eab36d0dc00000000004eb7440000000803a446e4000000020059e8140000000602e22d541000000c074d3cf4100000000ff83e241",
	"Callisto": "74c95ce4c9a3b7c18cace44d849fb341438a350ffd3cc641cdcccccc4c0bbc409a99999999d4a24069579dac8349d23e000000000000000058579dac8349d2be000000000000f03f0004a9bbd3d8e3bf10f2c170f61209c090865d2f86080dc0000000a0262395c0000000602e108b40000000405f8c9e4000000020cfa3b7c1000000a0879fb341000000e0003dc641",
	"Charon": "0ea8429769dddb4140a40eb1a247c241ee5be6663a63f1c19a99999999795a400000000000f082401c0cd01154e8e73e0000000000000000060cd01154e8e7be000000000000f03f00d74ef01ac2edbfd0f194405e830ec0684febbf889612c0000000a0d72c704000000020176a5340000000a0c10e85c0000000e069dddb41000000e0a247c241000000803a63f1c1",
	"Deimos": "adff85572902aa41b358350871ed95415e33eb98392aaa412d431cebe2361a3fcdcccccccccc1840314514eef0320e3f0000000000000000154514eef0320ebf000000000000f03fc0b2a3c88344f6bf805b1c8e9900dbbf001d17c8a02fd5bf00000040a1b75c40000000409b313340000000604d4e4840000000402a02aa410000004071ed9541000000003a2aaa41",
	"Dione": "84ae161d734bd54177a78f9729d5914150b9b8a73127b341666666666646524033333333338b8140210ec81462e4fb3e0000000000000000070ec81462e4fbbe000000000000f03fc0022e0ce55b01c0b80e2b13f1d712c030e4e0c0433d12c0000000c0ce1c8540000000807c351d40000000c0231a5640000000c0734bd541000000c029d59141000000003227b341",
	"Earth": "0000000000000000000000000000000000000000000000001d3867c4215418410000000000e3b84065db57d1a71d133f00000000000059407821f8f3a71d13bf000000000000f03f579d12cee95f10c0711169f932a702c0bfb48ae1e88be2bf00000000fc7490c0000000e084fea3c0000000a09910b7c0000000200899ba40000000804728d0400000000083a3e240",
	"Enceladus": "35d4f66bae49d541a374cd49e6e7914101710188e527b341cdcccccccccc1c403333333333836f40caaf7a1bf6d60b3f0000000000000000b0af7a1bf6d60bbf000000000000f03fc067bb7ad634e6bf80a9a4369f7600c0f8e6a0922a6d16c000000020dc0e774000000020374710400000002020274840000000c0ae49d54100000060e6e79141000000c0e527b341",
	"Europa": "bef58110409cb7c16353725fe9b0b341fb29200a4b3ec641666666666605a94033333333336398405d18e945ed7ef53e00000000000000004918e945ed7ef5be000000000000f03f18c883e099e217c0c0f9a448e9f6f9bf305723eeff220fc000000040200a8cc0000000c01d0c8240000000c0944a9440000000a0439cb7c1000000a0ebb0b341000000804d3ec641",
	"Ganymede": "9de20de0b1a4b7c1d2360d65b5bcb341d6c78b8a2d3fc64166666666e64fc340333333333394a440ae5b4e531564e53e00000000000000009a5b4e531564e5be000000000000f03fa0245a479f9af2bff0bfad6f1e4d0bc000a30b7f3042c8bf00000000cafb96c000000000b6a18d4000000060209da040000000a0b7a4b7c100000020b9bcb341000000a0313fc641",
	"Iapetus": "835d977cc24ad541838386d34e0e91415d2ec5a6bc1fb3410000000000205e400000000000f4864093c92565bddeae3e000000000000000076c92565bddeaebe000000000000f03fe099be89bf9417c0f0afa4134e450dc0d0a585f5d8560bc000000060427a8a400000002003c61c40000000c002a65b4000000060c34ad541000000004f0e914100000000bd1fb341",
	"Io": "74ec35a7d09ab7c13ab71c97edbab34144be195b0b3fc64166666666e647b7406666666666769c40b576363f598c053f0000000000000000a176363f598c05bf000000000000f03f90d7abaa0e2d08c0783812db0b4e11c0804b0089610e14c0000000e0b42f90c00000008039e4844000000020a66f9740000000a0d49ab7c100000040f0bab341000000400e3fc641",
	"Jupiter": "04532c980295b7c188e27ee026b8b3418481670dd63ec6419a99991b55349e41000000007011f14041237dff8b0c273f00000000000079402b237dff8b0c27bf000000000000f03f409966d30caa15c0d80f48d535ce17c048188eb4cddf11c0000000e0085ce2c000000000b1b3d74000000080029bea40000000809595b7c1000000a085b8b34100000060403fc641",
	"Mars": "435707dcab01aa4174fe8c467cee95410093fea34d2aaa41cdcccccc8ce9e44000000000007baa40a2d1cc7ccf94123f000000000000544091d1cc7ccf9412bf000000000000f03fa85426c389de17c040d7fd471a38f5bfc0ac24e92da0f9bf000000e09af4a840000000c08fb08040000000e0d41f9540000000e0c401aa41000000a084ee954100000020582aaa41",
	"Mercury": "25099662862f80c1785191c020028a4168b58ac4e1d29b41cdccccccec83d54066666666660fa34095f8de69cdcdb43e000000000000000081f8de69cdcdb4be000000000000f03f804c4538eaec03c000e3912b2efceabfa895da80e97712c00000008057c6a2c0000000c01e0d6ac0000000a018c38ac000000080d12f80c1000000401a028a4100000060d4d29b41",
	"Mimas": "3cc55cbde949d5412d420f1443e49141b6e8639cc227b34100000000000004406666666666c66840cee15aed612f143f0000000000000000bbe15aed612f14bf000000000000f03fc0f30b2f6ed513c0a0fdad7276ca05c00079826dbf3a0ac000000000d2b77340000000e070bb0b40000000c000a7444000000000ea49d5410000002043e49141000000c0c227b341",
	"Miranda": "00598729ad22d541a7308973acd5cf41986010131484e2419a999999999911409a99999999796d404fcaa48636000b3f000000000000000036caa48636000bbf000000000000f03f68b3954cc8c514c0104548589cef0cc05066f69631c917c000000000764c654000000020c3d25e4000000000bfef714000000040ad22d541000000c0acd5cf41000000401484e241",
	"Moon": "32e6be05ef421241618253b2e437fd40beba9317e8900941cdcccccccc26b3409a99999999259b405b60c10cf553c63e00000000000000004660c10cf553c6be000000000000f03f50ee5fe5bb6407c038d39cc8dcee14c070a6f03501a702c0000000a05d8e72c000000060edc686c000000060af499ac0000000604b3e1241000000e0560afd40000000c0545c0941",
	"Neptune": "78372e0e83baf0412a76ae43453a76412d7a26edbb19b341333333d3e8125a4100000000800bd840620e27d5e3631c3f0000000000c07240470e27d5e3631cbf000000000000f03f704c3352096904c060e2328d65d4fabf804201f762720ac0000000008b76d84000000080d57469c000000080e60790400000002089baf04100000080383a7641000000e0bf19b341",
	"Nowhere": "000000000000000000000000000000000000000000000000000000000000000000000000000000007b14ae47e17a943f00000000000000006814ae47e17a94bf000000000000000040eb16a53f8ceabfc0fc8927bfbdffbf984b5d38065715c0000000000000000000000000000000000000000000000000000000200899ba40000000804728d0400000000083a3e240",
	"Oberon": "89044c530424d5411c3f3eeeebd7cf41ef5daaa72984e2419a99999999a969403333333333cb87402b4c007af1b0d63e0000000000000000164c007af1b0d6be000000000000f03f30a9cca6bf5f11c02033d7f8b53914c008561297acd517c00000002081627a4000000020bb177340000000c0ec368640000000c00424d54100000080ecd7cf41000000002a84e241",
	"Phobos": "d6995b04f501aa41a3d9bbea74ee9541d749b5164d2aaa416b48dc63e943473f295c8fc2f5282640240f441669e22d3f0000000000000000080f441669e22dbf000000000000f03f501f3db04c2118c000a80195344fecbfd09ca862f0e613c000000020bdd35d40000000e04bf2334000000020303f4940000000e0f501aa410000002075ee9541000000804d2aaa41",
	"Pluto": "ffffefe161dddb41d036cdab7f47c241fc95ff0e3b63f1c1cdcccccccc2c8b4033333333339192401f7b9aeccfe0e73e0000000000000000097b9aeccfe0e7be000000000000f03f40348488e0cef8bf307670f7b94608c06006290ef647fcbf000000400b267d40000000c0127e61400000004041f992c00000006062dddb41000000e07f47c241000000403b63f1c1",
	"Rhea": "81d0a4bc024cd541fcb1420660fe91411b70df4bbd28b341cdcccccccc3c63406666666666de87403caa5093cfe1f03e00000000000000002caa5093cfe1f0be000000000000f03f2062894cc51605c01059598b975b11c000fe6df2b045bdbf0000006023628b40000000e060c8234000000080fdad5c40000000a0034cd5410000002060fe9141000000c0bd28b341",
	"Saturn": "559667c0964ad541551ef53ca0e79141f82086e7e227b3419a9999314616824100000000006fec40ad57cb7c8b77253f0000000000e085409957cb7c8b7725bf000000000000f03fe8cd94d9454112c080162d5e574911c0e0b3204b865c00c0000000201eb3ec40000000806e408440000000e09f0ebe4000000020d04ad54100000060aae79141000000e00028b341",
	"Sun": "173e8f37c26577415ac75ef6306d8c41a054ae6d6565a0410000d22047e63e4200000000283b2541dafe3adcb353c83e0000000000000000c3fe3adcb353c8be000000000000f03f28ea0fa0b3c914c0d897a5e233d318c0202de949478ff5bf00000000283b454100000000000000000000000000000000000000200899ba40000000804728d0400000000083a3e240",
	"Tethys": "3022eca2ed49d5410dbd81782cf69141b93328906e28b3419a9999999999444000000000009880402640a8e6cd3c043f00000000000000001340a8e6cd3c04bf000000000000f03fa8af5c54018018c00076d6a6698a03c0a89f81ca0c9c14c0000000c0972b84400000006062e81c40000000a08a21554000000040ee49d541000000a02cf69141000000006f28b341",
	"Titan": "0d9747db0d47d5414d5c477b03b79141b269dc391026b341cdcccccc0c89c14066666666661da440e43c73414320d33e0000000000c08240d23c73414320d3be000000000000f03fe08b7973ce0efabf3850e0a5a92e15c0009daca1017d11c0000000c03beaaa4000000020fa064240000000e033307c40000000401147d5410000002004b79141000000001226b341",
	"Titania": "ad1cf1565c21d541c5190a5f69d7cf41899c4bc22484e2416666666666866c403333333333a388407ba2a9a63d88e13e00000000000000006ba2a9a63d88e1be000000000000f03f60aa869b7d04ffbf40b2ecf0780603c07807fb362faf17c0000000a0cf2e7b4000000020c1ad734000000080d7e58640000000c05c21d541000000006ad7cf41000000202584e241",
	"Triton": "aba61c8382baf04141e25443a9e3754164d65810ec18b34100000000005296409a99999999259540cec9e6053301ea3e0000000000000000b6c9e6053301eabe000000000000f03f3823181941e317c050957d36416f00c0d09d383b8ca000c0000000e077009740000000c0712b28c0000000804a234e40000000e082baf04100000080a8e3754100000060ec18b341",
	"Umbriel": "94e341b30222d541b3260794f8d2cf41d3191521fa83e24100000000006054409a9999999945824082b861ca7674f23e000000000000000071b861ca7674f2be000000000000f03f80cf9e0332c7e8bfc03e1f0f0732fbbfa0c82e495c5b04c0000000c060177540000000c02c846e400000004082c38140000000200322d54100000020f9d2cf4100000060fa83e241",
	"Uranus": "cd54fadc6922d54134bdec61d5d4cf41774f67020c84e241333333d3271a56410000000080c4d8404cbfc8f4198a1abf0000000000c0724033bfc8f4198a1a3f000000000000f03ff0330492600f02c0188d3a4a670216c0c0fc542527b1edbf000000007124c840000000a0e077c140000000400755d440000000007622d541000000e0e6d4cf41000000201684e241",
	"Venus": "0982bbd3dbbd93c136f2f061df2b90411b6d86dc44c5a04166666666ead31341cdcccccccca3b74048291f663f1594be0000000000406f4035291f663f15943e000000000000f03ff033a57d561502c02023b61324f90dc07043a297c7bf06c0000000605705b9c000000040bea17e4000000040286f67400000000040be93c100000000e72b90410000006046c5a041",
	"Voyager 1": "62fcd5e49080f2c1c5f8cff66ee4f2416d3ae4a878b815c2000000000000000000000000000020407b14ae47e17a943f00000000000000006814ae47e17a94bf000000000000000040eb16a53f8ceabfc0fc8927bfbdffbf984b5d38065715c000000000c1123ac000000040432e3a400000002044a35ec0000000e09080f2c1000000006fe4f241000000a078b815c2",
	"Voyager 2": "ccccd4c909bcf54162fc818a960a0fc2036ab8962ad602c2000000000000000000000000000020407b14ae47e17a943f00000000000000006814ae47e17a94bf000000000000000040eb16a53f8ceabfc0fc8927bfbdffbf984b5d38065715c000000040c02c42400000002004295ac0000000a07c0850c0000000c009bcf54100000080960a0fc2000000a02ad602c2",
	"_geo": "000000200899ba40000000804728d0400000000083a3e240",
	"_gravity": "1d3867c4215418410000d22047e63e42cdcccccccc26b340cdccccccec83d54066666666ead31341cdcccccc8ce9e4409a99991b55349e419a99993146168241333333d3271a5641333333d3e8125a41cdcccccccc2c8b406b48dc63e943473f2d431cebe2361a3f66666666e647b740666666666605a94066666666e64fc340cdcccccc4c0bbc400000000000000440cdcccccccccc1c409a999999999944406666666666465240cdcccccccc3c6340cdcccccc0c89c1400000000000205e409a999999999911400000000000a0554000000000006054406666666666866c409a99999999a9694000000000005296409a99999999795a40"
}

var failures := 0


func check(name: String, ok: bool) -> void:
	if not ok:
		failures += 1
		print("system_ephemeris: FAIL ", name)


static func dump(e: Node, names: Array, with_pos := true) -> Dictionary:
	var out := {}
	var saved: float = e.rotation_clock.unix_s
	for n in names:
		var a := PackedFloat64Array()
		a.append_array(e.pos64(n) if with_pos else PackedFloat64Array([0.0, 0.0, 0.0]))
		a.append_array([e.gm(n), e.body_radius_km(n), e.spin_rad_s(n), e.atmo_top_km(n),
			e.scene_spin_rad_s(n), 1.0 if e.is_anchorable(n) else 0.0])
		for t in CLOCKS:
			e.rotation_clock.unix_s = t
			a.append(e.surface_angle(n))
		var so: Vector3 = e.sweet_spot_off(n)
		var ss: Vector3 = e.sweet_spot(n)
		a.append_array([so.x, so.y, so.z, ss.x, ss.y, ss.z])
		out[n] = a.to_byte_array().hex_encode()
	e.rotation_clock.unix_s = saved
	var g: Vector3 = e.geo_start_pos()
	out["_geo"] = PackedFloat64Array([g.x, g.y, g.z]).to_byte_array().hex_encode()
	var gb := PackedFloat64Array()
	for b in e.gravity_bodies():
		gb.append(float(b.mu))
	out["_gravity"] = gb.to_byte_array().hex_encode()
	return out


static func sol_names() -> Array:
	var names := []
	for p in SolEphemeris.worlds():
		names.append(str(p.name))
	names.append("Nowhere")
	return names


func _ready() -> void:
	_sol_matches_snapshot()
	var sol_live := dump(Ephemeris, sol_names())
	var sol_instance = Ephemeris.current()
	_proxima()
	Ephemeris.switch_system(SolEphemeris.new().id)
	check("switch_back_same_instance", Ephemeris.current() == sol_instance)
	check("switch_back_physical", Ephemeris.is_physical_system())
	check("switch_back_primary_sun", Ephemeris.primary_star == "Sun")
	check("switch_back_spawn_earth", Ephemeris.spawn_body() == "Earth")
	check("switch_back_proxima_gone", not Ephemeris.is_anchorable("Proxima b"))
	var again := dump(Ephemeris, sol_names())
	for k in sol_live:
		check("sol_restored_%s" % k, again[k] == sol_live[k])
	await get_tree().process_frame
	print("system_ephemeris: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


# Fallback-seeded Sol (no live JPL, no cache) through a fresh wrapper instance,
# plus the live autoload for everything that does not depend on positions.
func _sol_matches_snapshot() -> void:
	var e: Node = E.new()
	e.current().seed_fallback()
	var now := dump(e, sol_names())
	check("sol_snapshot_size", now.size() == SNAPSHOT.size())
	for k in SNAPSHOT:
		check("sol_bit_identical_%s" % k, now.get(k, "") == SNAPSHOT[k])
	e.free()
	check("autoload_starts_in_sol", Ephemeris.system_id == "sol" and Ephemeris.primary_star == "Sun")
	var live := dump(Ephemeris, sol_names(), false)
	for n in sol_names():
		# bytes 24.. = everything after pos64; sweet_spot tail depends on positions
		var tail_live: String = live[n].substr(48, 16 * 9)
		var tail_snap: String = SNAPSHOT[n].substr(48, 16 * 9)
		check("autoload_tables_%s" % n, tail_live == tail_snap)


func _proxima() -> void:
	Ephemeris.switch_system(PROXIMA)
	check("proxima_physical", Ephemeris.is_physical_system())
	var star := Ephemeris.primary_star
	check("proxima_primary", star == "Proxima Centauri")
	var worlds := Ephemeris.live_worlds()
	check("proxima_2_to_6_worlds", worlds.size() >= 3 and worlds.size() <= 7)
	var star_r := Ephemeris.body_radius_km(star)
	check("proxima_star_radius_real", star_r > 80000.0 and star_r < 140000.0)
	check("proxima_star_gm_real", absf(Ephemeris.gm(star) / (0.123 * E.GM_SUN) - 1.0) < 0.05)
	check("proxima_star_at_origin", Ephemeris.scene_pos(star) == Vector3.ZERO)
	check("proxima_is_star", Ephemeris.is_star(star))
	for p in worlds:
		var n := str(p.name)
		check("anchorable_%s" % n, Ephemeris.is_anchorable(n))
		if n == star:
			continue
		var d := Ephemeris.rel_km(n, star).length()
		check("real_scale_orbit_%s" % n, d > star_r * 20.0 and d < 60.0 * E.KM_PER_AU)
		var r := Ephemeris.body_radius_km(n)
		check("real_radius_%s" % n, r > 2000.0 and r < 90000.0)
		check("gm_%s" % n, Ephemeris.gm(n) > 0.0)
		check("drag_follows_recipe_air_%s" % n,
			FlightMode.has_drag_model(n) == (float(p.get("air_amount", 0.0)) > 0.0))
		check("air_column_with_air_%s" % n,
			(Ephemeris.atmo_top_km(n) > 0.0) == (float(p.get("air_amount", 0.0)) > 0.0))
	var home := Ephemeris.spawn_body()
	check("spawn_is_a_world", home != "" and home != star and Ephemeris.has_pos(home))
	var bodies := SystemDB.bodies(PROXIMA)
	check("systemdb_specs_physical", bodies.size() == worlds.size() and bodies.all(func(b): return b.physical and b.live))
	_anchored(home, star)
	_skin_and_spin(home)
	_newton_falls(home, star)


func _anchored(home: String, star: String) -> void:
	var ship := ShipScript.new()
	add_child(ship)
	ship.newton = true
	ship.set_anchor(home)
	check("ship_anchors_generated_world", ship.anchor_name == home)
	var off := Vector3(1.0, 0.2, -0.4).normalized() * (Ephemeris.body_radius_km(home) + 5.0)
	ship.relocate(off)
	var a: PackedFloat64Array = Ephemeris.pos64(star)
	var b: PackedFloat64Array = Ephemeris.pos64(home)
	var want := Vector3(a[0] - b[0], a[1] - b[1], a[2] - b[2]) - off
	check("to_body_is_64bit_math", ship.to_body(star) == want)
	check("anchor_is_own_origin", ship.to_body(home) == -off)
	# A 150 m step survives in the anchored offset; at the absolute position
	# (millions of km from the star) a Vector3 ULP swallows it.
	ship.relocate(off + Vector3(0.15, 0.0, 0.0))
	check("anchored_150m_step_survives", absf((ship.anchor_off - off).x - 0.15) < 0.001)
	var abs_x := float(b[0]) + off.x
	check("absolute_frame_would_lose_it", absf(Vector3(abs_x + 0.15, 0, 0).x - Vector3(abs_x, 0, 0).x - 0.15) > 0.01)
	for p in Ephemeris.live_worlds():
		var other := str(p.name)
		if other == home:
			continue
		var shift := ship.set_anchor(other)
		check("reanchor_%s" % other, ship.anchor_name == other and shift == Ephemeris.rel_km(other, home))
		ship.set_anchor(home)
	ship.queue_free()


func _skin_and_spin(home: String) -> void:
	var r := Ephemeris.body_radius_km(home)
	check("skin_kill_margin", Ephemeris.surface_kill_km(home) == E.CONTACT_KILL_FLOOR_KM)
	check("zone_skin", Ephemeris.flight_zone(home, r + 0.01) == "SKIN")
	check("zone_space", Ephemeris.flight_zone(home, r * 3.0) == "SPACE")
	var air := Ephemeris.atmo_top_km(home)
	if air > 0.0:
		check("zone_air", Ephemeris.flight_zone(home, r + air * 0.5) == "AIR")
	var t0: float = Ephemeris.rotation_clock.unix_s
	var basis := Ephemeris.surface_basis(home)
	check("surface_basis_orthonormal", basis.is_equal_approx(basis.orthonormalized()) and is_equal_approx(basis.determinant(), 1.0))
	var a0 := Ephemeris.surface_angle(home)
	Ephemeris.rotation_clock.unix_s = t0 + 100.0
	var a1 := Ephemeris.surface_angle(home)
	Ephemeris.rotation_clock.unix_s = t0
	var turned := angle_difference(a0, a1)
	check("surface_turns_at_spin", absf(turned + Ephemeris.spin_rad_s(home) * 100.0) < 1.0e-6)
	check("scene_spin_finite", is_finite(Ephemeris.scene_spin_rad_s(home)))
	var solar := Ephemeris.solar_state(home, Vector3.RIGHT)
	check("solar_state_uses_primary", is_finite(float(solar.elevation)) and solar.phase in ["DAY", "TWILIGHT", "NIGHT"])
	var park := Ephemeris.spawn_pos()
	check("spawn_park_outside_world", park.length() > r * 1.4)
	check("spawn_faces_star", park.normalized().dot(Ephemeris.rel_km(Ephemeris.primary_star, home).normalized()) > 0.999)


# 60 s of the ship's own Newton integration, placed off the star line so the
# star's pull is tangential: radial fall must match GM/r² within 1 %.
func _newton_falls(home: String, star: String) -> void:
	var ship := ShipScript.new()
	add_child(ship)
	ship.newton = true
	ship.set_anchor(home)
	var to_star := Ephemeris.rel_km(star, home).normalized()
	var side := to_star.cross(Vector3.UP).normalized()
	var r0 := Ephemeris.body_radius_km(home) + 2000.0
	ship.relocate(side * r0)
	ship.velocity = Vector3.ZERO
	var g0 := Ephemeris.gm(home) / (r0 * r0)
	var g_radial := -ship.call("_newton_g").dot(side) as float
	check("newton_g_is_gm_over_r2", absf(g_radial / g0 - 1.0) < 0.01)
	var secs := 60.0
	for i in 3600:
		ship.call("_newton_advance", 1.0 / 60.0)   # main's per-frame call, one substep each
	var fell := r0 - ship.anchor_off.length()
	var a_meas := 2.0 * fell / (secs * secs)
	print("system_ephemeris: %s fell %.3f km in 60 s, a=%.6f km/s² vs GM/r²=%.6f" % [home, fell, a_meas, g0])
	check("newton_60s_within_1pct", absf(a_meas / g0 - 1.0) < 0.01)
	check("newton_still_anchored", ship.anchor_name == home)
	ship.queue_free()
