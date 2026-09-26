# Ship assistant and real Earth facilities

The support jets now act automatically near solid terrain, independently of landing gear. They counter gravity and inward motion near unsafe ground, settle uncommanded drift over a qualified pad, and release during outward flight or outside their hazard envelope. Forward-looking terrain and structure sweeps use the same height sampler and collision boxes as the rendered world. Embedded hull recovery preserves the clearance gained by preceding probes instead of replaying the old underground position. Correction is bounded to 25 m/s²; extreme-speed impacts still rely on physical collision resolution rather than an unlimited braking force.

Planetary attitude assistance waits for five uninterrupted seconds without player flight input, then gently removes roll and pitch within the atmosphere, or within 35 km of airless surfaces. It follows local radial up, preserves heading, ramps in over 1.5 seconds and turns at no more than six degrees per second. Keyboard, mouse, touch, thrust, braking, fire, free look and autopilot input stop the adjustment and reset its timer. The turn is applied after velocity carry and adds no force. Deep space keeps free attitude. `ShipAssistant` accepts a supplied normal, gravity and relative velocity, so its control law also supports future moving berths.

Surface pad locks require deployed gear, actual support contact, low arrival speed, level alignment and all foot corners inside the pad. Hovering three metres above a pad cannot lock. Physical ground contact elsewhere remains distinct from facility attachment. Service structures moved 300 m outward with their matching collision boxes, and the foundation and vegetation exclusion enlarged to keep approaches open for all five hulls.

## Geography and orbit sources

- Kennedy LC-39A: 28.608402° N, 80.604201° W, retained from the [NASA-hosted SpaceX environmental assessment](https://netspublic.grc.nasa.gov/main/20190807_Final_DRAFT_EA_SpaceX_Starship.pdf).
- Wenchang: 19.6144917° N, 110.9511333° E, the published [site reference coordinate](https://www.wikidata.org/wiki/Q1246624). This is not a newly surveyed pad coordinate. Both ground compounds are fictional ship-sized adaptations at the sourced locations.
- ISS: [NASA/JSC OEM](https://nasa-public-data.s3.amazonaws.com/iss-coords/current/ISS_OEM/ISS.OEM_J2K_EPH.txt), created 2026-09-21, covering 2026-09-21 12:00 UTC through 2026-10-06 12:00 UTC. [NASA describes the product and its limitations](https://www.nasa.gov/spot-the-station/).
- Tiangong: [China Manned Space / BACC OEM](https://en.cmse.gov.cn/news/202107/t20210722_48418.html), created 2026-09-24, covering 2026-09-24 through 2026-10-01 UTC.

The bundled 8,475 states retain their timestamps, source, position and velocity in EME2000. Scene coordinates map (x,y,z) to (x,z,y), matching the existing ephemeris. Quintic interpolation passes through the published states; between samples it uses central-gravity acceleration estimates. Outside coverage, a bounded two-body prediction is explicitly labeled SIMULATED. This is dated ephemeris visualization, not live exact tracking. No permanent geographic longitude is assigned to either station.

Stations start at current UTC and advance with ship simulation seconds, independently of the deliberately accelerated eight-minute day/night clock. The ISS uses the existing scaled model; Tiangong uses a simplified reference model. Ctrl+P includes both ground sites and both station rendezvous points. Station rendezvous inherits orbital velocity. These real station references do not yet provide collidable landing berths or hangar services; those remain future station work. Existing fictional hangar interaction is separate.

Refresh the offline catalogue with `python3 tools/fetch_station_ephemerides.py`. Both official feeds must validate before replacement. Desktop and Android export filters include the JSON bundle.

## Verification

Focused tests cover all five hulls, diagonal and edge approaches, hovering without locking, attachment through body rotation, departure, automatic protection with gear stowed, five-second idle delay, slow capped leveling, input override, free attitude in space, frame-independent correction, official orbital sample positions, interpolation velocity, explicit fallback status, and in-scene rendezvous/visual placement.

`tools/render_ship_assistant.tscn` writes pad and station inspection images to `/tmp/ship-assistant/`.
