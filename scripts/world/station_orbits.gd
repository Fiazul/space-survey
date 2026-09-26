class_name StationOrbits
extends RefCounted
## Official, dated EME2000 state vectors (km, km/s), not fixed geographic points.
## Quintic interpolation within the OEM span; explicitly approximate Kepler
## propagation outside it. No runtime network dependency or live-tracking claim.
const MU := 398600.4418
var rows: Array = []

func _init() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/earth_station_ephemerides.json"))
	if parsed is Array: rows = parsed

func state_at(id: String, unix_s: float) -> Dictionary:
	if not is_finite(unix_s): return {}
	for row in rows:
		if row.id != id: continue
		var samples: Array = row.samples
		if samples.is_empty(): return {}
		if unix_s < float(samples[0][0]) or unix_s > float(samples[-1][0]):
			return _predict(samples[0] if unix_s < float(samples[0][0]) else samples[-1],unix_s)
		var lo := 0
		var hi := samples.size()-1
		while hi-lo > 1:
			var mid := (lo+hi)/2
			if float(samples[mid][0]) <= unix_s: lo = mid
			else: hi = mid
		var a: Array = samples[lo]
		var b: Array = samples[hi]
		var h := float(b[0])-float(a[0])
		var t := clampf((unix_s-float(a[0]))/h,0,1)
		var p0 := _vector(a,1)
		var p1 := _vector(b,1)
		var v0 := _vector(a,4)*h
		var v1 := _vector(b,4)*h
		var a0 := -MU*p0/pow(p0.length(),3)*h*h
		var a1 := -MU*p1/pow(p1.length(),3)*h*h
		var d := p1-p0
		var c2 := a0*.5
		var c3 := d*10-v0*6-v1*4-a0*1.5+a1*.5
		var c4 := d*-15+v0*8+v1*7+a0*1.5-a1
		var c5 := d*6-(v0+v1)*3-(a0-a1)*.5
		return {"position":p0+t*(v0+t*(c2+t*(c3+t*(c4+t*c5)))),
			"velocity":(v0+t*(c2*2+t*(c3*3+t*(c4*4+t*c5*5))))/h,
			"approximate":false,"epoch":unix_s}
	return {}

static func _vector(sample: Array, offset: int) -> Vector3:
	return Vector3(sample[offset],sample[offset+2],sample[offset+1])

static func _predict(sample: Array, unix_s: float) -> Dictionary:
	var r := _vector(sample,1)
	var v := _vector(sample,4)
	var a := 1.0/(2.0/r.length()-v.length_squared()/MU)
	var evec := v.cross(r.cross(v))/MU-r.normalized()
	var e := evec.length()
	var p := evec.normalized() if e > .000001 else r.normalized()
	var q := r.cross(v).normalized().cross(p)
	var minor := sqrt(1-e*e)
	var e0 := atan2(r.dot(q)/(a*minor),r.dot(p)/a+e)
	var n := sqrt(MU/(a*a*a))
	var mean := fposmod(e0-e*sin(e0)+n*(unix_s-float(sample[0])),TAU)
	var anomaly := mean
	for i in 10: anomaly -= (anomaly-e*sin(anomaly)-mean)/(1-e*cos(anomaly))
	var position := a*((cos(anomaly)-e)*p+minor*sin(anomaly)*q)
	var velocity := a*n/(1-e*cos(anomaly))*(-sin(anomaly)*p+minor*cos(anomaly)*q)
	return {"position":position,"velocity":velocity,"approximate":true,"epoch":float(sample[0])}
