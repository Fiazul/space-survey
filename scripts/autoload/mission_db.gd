class_name MissionDB
extends RefCounted
# The MISSION / QUEST log. Every body you can fly to and survey — every star, planet, and
# moon in SystemDB.bodies() — is its own mission. The objective is always the same simple
# loop the game already has: fly close to the body and it is surveyed automatically
# (codex.discover) → mission COMPLETE. This file is just the STORY layer over that: a title +
# a (crude, savage, mostly-true) blurb (+ a legacy coin value no UI shows any more),
# keyed by the EXACT body name SystemDB/codex use.
#
# Tone: the Survey's mission board is written by a bitter, foul-mouthed dispatcher who hates
# every rock in the sky. The facts are real (nearest-star science, the pop-culture baggage);
# the attitude is not. No story for a body? mission_for() generates a generic one so the log
# never has a hole.
#
# Lookup is by body name so it works for single-star systems (body == star name), the
# authored systems (Sol's planets/moons, Proxima/TRAPPIST/K2-18 worlds) and the Alien zone.

# body name -> { title, story, reward }
const STORIES := {
# ── Sol — home, and the dispatcher's least favourite system ──────────────────
"Sun": { "title": "Stare Into the Boss",
	"story": "The flaming gasbag that owns 99.8% of everything and still lets you take all the\nrisks. A G-type main-sequence star — utterly average, like most things that\nthink they're the centre of the universe. Survey it before it tans your hull off.",
	"reward": 400 },
"Mercury": { "title": "The Little Crater That Couldn't",
	"story": "Smallest planet, no atmosphere, no dignity. Roasts on one side, freezes on the\nother, and a single day there outlasts its own year. A burnt rock with\ncommitment issues. Tag it and let's not linger.",
	"reward": 150 },
"Venus": { "title": "Hell With Better PR",
	"story": "Named after the goddess of love; 464 °C, raining sulphuric acid, air thick\nenough to crush a submarine. The galaxy's hottest girl and she will literally\nmelt you. Survey from a respectful distance, romantic.",
	"reward": 180 },
"Earth": { "title": "The Pale Blue Dump You Came From",
	"story": "The only rock we know of stupid enough to grow things that complain. 71% water,\n100% drama, and the one place in the catalogue that owes you back rent. Scan the\nold neighbourhood — somebody has to.",
	"reward": 160 },
"Mars": { "title": "Real Estate for Optimists",
	"story": "A freeze-dried rust ball that billionaires keep promising to ruin next. Tallest\nvolcano in the system, thinnest excuses for an atmosphere. Survey the Red Planet\nbefore another colony brochure does.",
	"reward": 200 },
"Jupiter": { "title": "The Fat Bully With a Storm Problem",
	"story": "The giant. Big enough to swallow every other planet and still hungry, with a\nstorm — the Great Red Spot — that's been throwing a 350-year tantrum. Survey the\nslab. Try not to get eaten by the gravity.",
	"reward": 260 },
"Saturn": { "title": "Pretty Boy With the Rings",
	"story": "So low-density it would float in a bathtub the size of a galaxy, and it knows it's\nthe prettiest thing out here. All looks, mostly hydrogen, zero substance. Survey\nthe show-off and his ring collection.",
	"reward": 240 },
"Uranus": { "title": "Yes, We're Doing the Joke",
	"story": "An ice giant lying on its side, rolling around the Sun at a 98° tilt because\nstanding up straight is for cowards. Coldest atmosphere in the system. Go on,\nsurvey it. Get it out of your system.",
	"reward": 220 },
"Neptune": { "title": "The One Nobody Visits",
	"story": "Last planet out, windiest place in the system — 2,000 km/h gales screaming into a\nblue void where the Sun is just another star. Survey the forgotten one. It's been\nwaiting since 1846.",
	"reward": 220 },
"Voyager 1": { "title": "Grandpa Left the Solar System",
	"story": "Launched 1977, running on less compute than your toaster, and it's still the most\ndistant thing humanity ever made — 160-odd AU out, in interstellar space, carrying\na gold record of whale songs for aliens. Salute the old machine and survey it.",
	"reward": 300 },
"Voyager 2": { "title": "The Other One",
	"story": "Voyager 1's overlooked sibling — except it's the ONLY craft to buzz all four giant\nplanets. Does the most, gets the least credit, exactly like you. In 40,000 years\nit'll drift past Ross 248. Survey the legend before it ghosts us forever.",
	"reward": 300 },
"Moon": { "title": "Earth's Clingy Ex",
	"story": "Tidally locked — shows us the same face forever, like a stalker that never blinks.\nStabilises our axis, runs the tides, and got more visitors in 1969 than it's had\nsince. Survey the big grey rock everyone takes for granted.",
	"reward": 150 },
"Phobos": { "title": "Living on Borrowed Time",
	"story": "Mars's bigger moon — a captured asteroid orbiting so low it laps the planet three\ntimes a day, and it's spiralling in to crash (or become a ring) in ~50 million years.\nSurvey the doomed potato while it's still up here.",
	"reward": 170 },
"Deimos": { "title": "Mind the Escape Velocity",
	"story": "Mars's tiny outer moon — so small its escape velocity is about 5 m/s, meaning a\nhalfway-decent jump would fling you into orbit forever. Survey the smooth grey\npebble. Gently. No sudden movements.",
	"reward": 170 },
"Io": { "title": "The Zit of Jupiter",
	"story": "The most volcanically violent body in the system — a sulphur-yellow hellscape that\nJupiter squeezes until it erupts. Looks like a mouldy pizza and smells worse. Scan\nit fast before it pops.",
	"reward": 160 },
"Europa": { "title": "Maybe There's Fish",
	"story": "An ice shell over a global saltwater ocean with more water than all of Earth's —\nthe top suspect in the 'is there life out here' case. Survey the frozen eyeball;\ntry not to wake whatever's swimming.",
	"reward": 200 },
"Ganymede": { "title": "Bigger Than a Planet, Still a Moon",
	"story": "The largest moon in the system — fatter than Mercury and the only moon with its\nown magnetic field — and it STILL has to orbit Jupiter like an intern. Survey the\noverqualified rock.",
	"reward": 180 },
"Callisto": { "title": "The Cratered Punching Bag",
	"story": "One of the most beaten-up surfaces known — every dent is a few billion years of\n'no one moved me out of the way.' Probably hides an ocean under all that scar\ntissue. Survey the system's oldest face.",
	"reward": 160 },
"Titan": { "title": "Rains Gasoline, Honestly",
	"story": "The only moon with a thick atmosphere, and it spends it raining liquid methane\ninto lakes you could light with a match. Saturn's smoggy giant. Survey it — bring\na lighter, leave the cigarettes.",
	"reward": 210 },

# ── Proxima — the nearest other sun ──────────────────────────────────────────
"Proxima Centauri": { "title": "The Nearest Coward",
	"story": "The closest star to home and a dim red dwarf that hides in Alpha Centauri's\nshadow — too faint to even see with your naked eye despite being right next door.\nFlares like it's having a breakdown. Survey the runt of the nearest litter.",
	"reward": 260 },
"Proxima b": { "title": "First Light, Worst Tan",
	"story": "The first exoplanet most pilots ever claim — roughly Earth-mass, in the 'habitable'\nzone of a star that keeps blasting it with radiation. Scorched on the day side,\nfrozen on the night, nothing in between. Plant the flag and run.",
	"reward": 240 },

# ── TRAPPIST-1 — seven worlds, one tiny ember ────────────────────────────────
"TRAPPIST-1": { "title": "The Hoarder",
	"story": "An ultra-cool red dwarf barely bigger than Jupiter that somehow crammed SEVEN\nrocky worlds around itself, all closer than Mercury is to the Sun. From any one\nyou'd see the others as moons. Survey the greedy little ember.",
	"reward": 300 },
"TRAPPIST-1b": { "title": "Front Row to the Furnace",
	"story": "Innermost of the seven — close enough to the star to be a slab of cooked rock\nwith a magma habit. The hottest seat in a very crowded theatre. Survey it before\nit bakes you a matching set.",
	"reward": 160 },
"TRAPPIST-1d": { "title": "The Maybe Planet",
	"story": "Small, light, and parked near the warm edge of the habitable zone — the system's\neternal 'well, MAYBE there's water.' Decades of telescope time and it still won't\ncommit. Survey the tease.",
	"reward": 180 },
"TRAPPIST-1e": { "title": "The Golden Child",
	"story": "The one the scientists actually get excited about — rocky, Earth-sized, smack in\nthe habitable zone, the best shot at liquid water in the whole pile. Survey the\nfavourite child; the others are watching.",
	"reward": 240 },
"TRAPPIST-1g": { "title": "The Cold Out-Back",
	"story": "Out near the chilly edge of the family — bigger, probably icy, definitely\nignored. The seven-world system's quiet cousin who lives in the freezer. Survey\nit so it stops feeling left out.",
	"reward": 180 },

# ── K2-18 — the famous far one ───────────────────────────────────────────────
"K2-18": { "title": "124 Light-Years for THIS",
	"story": "A nothing red dwarf you'd never glance at — except one of its kids made every\nfront page on Earth. You flew 124 light-years to a star whose only personality is\nits planet. Survey the famous nobody.",
	"reward": 340 },
"K2-18b": { "title": "The 'We Found Life!' Headline",
	"story": "The sub-Neptune 'hycean' candidate that had Earth screaming about alien farts —\npossible water clouds, maybe a sign of life, maybe just bad data and worse hype.\nSurvey the most over-promised rock in the catalogue.",
	"reward": 280 },
"K2-18c": { "title": "The One Nobody Headlined",
	"story": "K2-18b's inner sibling, orbiting even closer and hotter, completely buried by its\nfamous brother's press tour. The Survey still wants it on the books. Scan the\nforgotten warm rock.",
	"reward": 200 },

# ── The Alien zone ───────────────────────────────────────────────────────────
"Hostile Star": { "title": "Into the Red, Idiot",
	"story": "A dim, blood-red sun past the safe lanes where the hostiles drift and Vortex\nrules. Surveying it means surviving it. The deep catalogue lies on the far side\nof a very large, very angry alien. Fly armed or fly home.",
	"reward": 500 },
"Veil Nebula": { "title": "Pretty Gas, Will Kill You",
	"story": "A vast soft cloud glowing out past the hostiles — the kind of view they paint on\nbedroom ceilings, sitting in the worst neighbourhood in the catalogue. Survey the\ndeep-space mirage. The aliens think it's pretty too.",
	"reward": 420 },

# ── The real nearest stars (single-sun systems) ──────────────────────────────
"Alpha Centauri": { "title": "The Famous Neighbour",
	"story": "The closest STAR SYSTEM, 4.3 ly out — a Sun-like pair that every sci-fi writer\nand his dog has colonised on paper. Bright, smug, and convinced it's the main\ncharacter of the local sky. Survey the celebrity.",
	"reward": 320 },
"Barnard's Star": { "title": "Catch Me If You Can",
	"story": "The fastest-moving star in our sky — a red dwarf sprinting across the heavens so\nfast astronomers call it the 'Runaway Star.' Hid its planets for a century, then\ncoughed up four sub-Earths in 2024. Survey the speed demon before it bolts.",
	"reward": 300 },
"Luhman 16": { "title": "Not Even a Real Star",
	"story": "The third-closest system to home and it's two FAILED stars — brown dwarfs too\ngutless to ignite — with banded clouds and actual weather, the nearest of their\nkind. Survey the cosmic dropouts. They never finished the job.",
	"reward": 280 },
"Wolf 359": { "title": "Where the Fleet Died",
	"story": "This pathetic red ember is so dim that Star Trek blew up a whole Starfleet armada\nhere just because nobody would miss the location. One of the faintest stars known.\nSurvey the cosmic bottom-feeder before it forgets it's even a star.",
	"reward": 260 },
"Lalande 21185": { "title": "The Quiet Achiever",
	"story": "One of the brightest red dwarfs in our sky and still nobody's heard of it — a\nsteady old star with a couple of confirmed planets and zero ego. The introvert of\nthe neighbourhood. Survey it; it won't make a fuss.",
	"reward": 260 },
"Sirius": { "title": "The Loudmouth",
	"story": "The brightest star in Earth's night sky and it will NEVER let you forget it.\nDrags around a dead white-dwarf companion, Sirius B, like a trophy. The ancient\nDogon supposedly knew about the invisible one — spooky. Survey the show-off.",
	"reward": 360 },
"Luyten 726-8": { "title": "The Twitchy Twins",
	"story": "A pair of red dwarfs, one of them the famous flare star UV Ceti that can DOUBLE in\nbrightness in seconds out of pure spite. Unstable, cramped, and prone to tantrums.\nSurvey the firecracker twins between outbursts.",
	"reward": 240 },
"Ross 154": { "title": "Young, Dumb, and Flaring",
	"story": "One of the youngest stars in the neighbourhood — a hyperactive red dwarf that\nflares like a teenager slamming doors. Closest star in Sagittarius. Survey the\nbrat; mind the radiation tantrums.",
	"reward": 240 },
"Ross 248": { "title": "The Future Champion",
	"story": "A nobody red dwarf today — but in ~40,000 years it'll glide within 3 light-years\nof the Sun and briefly become the CLOSEST star to home, stealing Alpha Centauri's\ncrown. Voyager 2 is headed its way. Survey tomorrow's celebrity early.",
	"reward": 260 },
"Epsilon Eridani": { "title": "The Sci-Fi Darling",
	"story": "Young, Sun-ish, ringed with dusty debris belts — basically a baby solar system,\nwhich is why every TV writer (Babylon 5, Halo, Star Trek) plonks a colony here.\nReal planet too. Survey the genre's favourite address.",
	"reward": 320 },
"Lacaille 9352": { "title": "The Record-Setter Nobody Claps For",
	"story": "Charted from South Africa centuries ago, one of the first red dwarfs ever to have\nits distance measured, now with a couple of planets. A historic star with a\nforgettable name. Survey the unsung pioneer.",
	"reward": 240 },
"Ross 128": { "title": "The 'Weird!' Signal",
	"story": "In 2017 Arecibo caught a bizarre radio signal from this quiet red dwarf and the\ninternet lost its mind over aliens. Turned out to be... satellites. The galaxy's\nbiggest anticlimax. Survey the star that catfished Earth.",
	"reward": 280 },
"EZ Aquarii": { "title": "Three's a Crowd",
	"story": "A tight triple system of red dwarfs all tangled around each other, one of them a\nflare star — a cramped, flickering knot of failed thermostats. Survey the\nthrouple before they set something off.",
	"reward": 240 },
"61 Cygni": { "title": "The First to Be Measured",
	"story": "The 'Flying Star' — the very FIRST star (other than the Sun) to have its distance\nmeasured, by Bessel in 1838. Without this orange pair, nobody knew how far away\nANYTHING was. Survey the star that built the ruler.",
	"reward": 300 },
"Procyon": { "title": "Always a Bridesmaid",
	"story": "Eighth-brightest star in Earth's sky and forever overshadowed by louder Sirius.\nDrags its own dead white-dwarf companion, Procyon B. Bright, bitter, second\nplace. Survey the eternal runner-up.",
	"reward": 320 },
"Struve 2398": { "title": "Two Flares, One Number",
	"story": "A binary of red dwarfs that both flare, both have planets, and both got stuck with\na catalogue number instead of a name. Anonymous and twitchy. Survey the nameless\ntwins.",
	"reward": 240 },
"Groombridge 34": { "title": "The Old Charted Pair",
	"story": "A binary red dwarf logged back in the 1700s, now known to host planets — one of\nthe oldest entries in the neighbourhood's address book. Survey the ancient pair\nthat's been on the map longer than the map.",
	"reward": 250 },
"DX Cancri": { "title": "Tiny, Furious, Pointless",
	"story": "One of the smallest, faintest, LEAST luminous stars known — a barely-glowing red\ndwarf that still throws violent flares like it has something to prove. All temper,\nno wattage. Survey the angry little spark.",
	"reward": 240 },
"Epsilon Indi": { "title": "The Star With a Pet Monster",
	"story": "A nearby orange dwarf dragging along brown-dwarf companions — and JWST just\nimaged a giant planet here, a true 'look at the actual world' moment. Survey the\nstar that walks its own gas giants like dogs.",
	"reward": 320 },
"Tau Ceti": { "title": "Earth's Stunt Double",
	"story": "The nearest single Sun-like star — humanity's go-to 'plan B planet' in a hundred\nnovels. Reality check: it's wrapped in a debris ring that machine-guns its worlds\nwith comets. Survey the overhyped backup Earth.",
	"reward": 340 },
"GJ 1061": { "title": "The Underdog With Worlds",
	"story": "A dim, ancient red dwarf almost nobody could name — yet it quietly hosts a little\nfamily of planets, one possibly temperate. Punches way above its weight. Survey\nthe overlooked landlord.",
	"reward": 250 },
"YZ Ceti": { "title": "The Star That Phoned Home",
	"story": "A red dwarf with a tight pack of planets — and the first system where we may have\ncaught a PLANET'S radio aurora, a world talking to its star. Survey the chatty\nrock-pile; see who's transmitting.",
	"reward": 280 },
"Luyten's Star": { "title": "We Already Texted It",
	"story": "A red dwarf with a potentially habitable planet, GJ 273b — so Earth literally\nBEAMED it a message (the 'Sónar Calling' broadcast) without asking anyone. Survey\nthe star we cold-DMed. The reply lands around 2043.",
	"reward": 280 },
"Teegarden's Star": { "title": "The Twin Earths",
	"story": "A tiny, ancient red dwarf hiding two of the most Earth-LIKE worlds ever found —\none rated 95% Earth-similar. Best 'second home' candidates in the catalogue, around\na star you'd never look at twice. Survey the dark horse.",
	"reward": 320 },
"Kapteyn's Star": { "title": "The Time-Travelling Alien",
	"story": "An 11-billion-year-old halo star — over twice the Sun's age — that orbits the\ngalaxy BACKWARDS because it was stolen from a devoured dwarf galaxy. Its planet\nmay be the oldest habitable world known. Survey the ancient runaway immigrant.",
	"reward": 340 },
"Lacaille 8760": { "title": "The Brightest of the Runts",
	"story": "One of the brightest red dwarfs in our sky — borderline visible to the naked eye,\nwhich for an M-dwarf is practically showing off. A flare star with delusions of\ngrandeur. Survey the overachieving runt.",
	"reward": 250 },
"SCR 1845-6357": { "title": "Drag a Failed Star Home",
	"story": "A dim red dwarf hauling a T-dwarf — a genuinely cold, nearly-planet brown dwarf —\naround as a companion. One of the chilliest things you'll scan that still counts as\na 'star'. Survey the odd couple.",
	"reward": 260 },
"Kruger 60": { "title": "The Flaring Couple",
	"story": "A binary red dwarf where one half, DO Cephei, is a classic flare star prone to\ndoubling its brightness on a whim. A married pair where one of them keeps setting\nthe house on fire. Survey the volatile duo.",
	"reward": 240 },
"DENIS J1048-3956": { "title": "Barely a Star At All",
	"story": "An ultra-cool dwarf right on the line between 'star' and 'gave up' — incredibly\nfaint, incredibly cold, and a surprisingly loud radio flarer for something so dim.\nSurvey the almost-star.",
	"reward": 240 },
"Ross 614": { "title": "The Heavy Little Secret",
	"story": "A red dwarf binary where the tiny companion helped pin down just how feather-light\nthe smallest stars get. Looks like one star, is secretly two. Survey the rock\nhiding a partner.",
	"reward": 240 },
"Wolf 1061": { "title": "The Quiet Habitable Bet",
	"story": "A calm, well-behaved red dwarf — rare out here — with a planet, Wolf 1061c, parked\nin the habitable zone. No flares, no drama, just a maybe-liveable rock. Survey the\nresponsible adult of the neighbourhood.",
	"reward": 270 },
"Van Maanen's Star": { "title": "The Nearest Corpse",
	"story": "The closest SOLITARY white dwarf — a dead Sun-like star crushed to Earth-size, no\ncompanion, just a cooling stellar ghost. Its surface is even polluted by the\nplanets it ate. Survey the lonely cinder.",
	"reward": 300 },
"Gliese 1": { "title": "Number One, Mood Zero",
	"story": "First entry in the famous Gliese catalogue of nearby stars — and it's a quiet,\nold, metal-poor red dwarf with nothing to say. Top of the list, bottom of the\npersonality chart. Survey #1.",
	"reward": 240 },
"TZ Arietis": { "title": "The Flaring Loner",
	"story": "A solitary red dwarf flare star with a possible planet and a tendency to belch\nradiation when you least expect it. Keeps to itself, then explodes. Survey the\nantisocial firework.",
	"reward": 240 },
"Wolf 424": { "title": "The Inseparable Twins",
	"story": "A pair of nearly-identical red dwarfs orbiting so close they're practically\nholding hands — both flare stars, of course. A codependent flickering mess.\nSurvey the clingy duo.",
	"reward": 240 },
"Gliese 687": { "title": "The Wobbler",
	"story": "A nearby red dwarf with a Neptune-mass planet caught by the tiny gravitational\nwobble it gives its star. Drunk-walks across the sky thanks to its hidden world.\nSurvey the staggering star.",
	"reward": 260 },
"Gliese 674": { "title": "Companion: Classified",
	"story": "A young, active red dwarf with a low-mass companion that sits right on the fuzzy\nline between 'big planet' and 'failed star.' Even the scientists shrug. Survey the\nstar with the mystery roommate.",
	"reward": 250 },
"LHS 292": { "title": "Faint Beyond Belief",
	"story": "A red dwarf so dim it's invisible to the naked eye despite being practically next\ndoor — you need a serious telescope to find a star this close. A whisper of a sun.\nSurvey the ghost light.",
	"reward": 240 },
"Gliese 440": { "title": "The Southern Cinder",
	"story": "A white dwarf — the cooling corpse of a once-real star — and one of the closest of\nits kind down in the southern sky. Dead, dense, and going cold. Survey the\nburnt-out husk.",
	"reward": 280 },
"GJ 1245": { "title": "Triple the Flares",
	"story": "A triple red-dwarf system, all of them faint, at least one a flare star — a tangled\nlittle knot of dim, twitchy suns. Survey the flickering throuple and get out before\none pops.",
	"reward": 240 },
"Gliese 876": { "title": "The Resonant Showpiece",
	"story": "The first red dwarf ever caught with planets — and they orbit in a beautiful\nlocked resonance, a tiny clockwork solar system. A genuine textbook landmark.\nSurvey the star that proved M-dwarfs have worlds.",
	"reward": 290 },
"Groombridge 1618": { "title": "The Orange Old-Timer",
	"story": "A nearby orange dwarf, a bit beefier than the usual red runts, charted centuries\nago and prone to the odd flare. Old, stable, overlooked. Survey the veteran nobody\nthanks.",
	"reward": 250 },
"Gliese 412": { "title": "The Mismatched Pair",
	"story": "A wide binary pairing an ordinary red dwarf with WX Ursae Majoris — a violent\nlittle flare star that screams for attention. The odd couple of Ursa Major. Survey\nthe mismatched duo.",
	"reward": 240 },
"AD Leonis": { "title": "The Drama Queen",
	"story": "One of the most-studied flare stars in the sky — a red dwarf that erupts so often\nand so hard it's basically a science-class lab rat for stellar tantrums. Survey the\nattention-seeking firework. Bring sunscreen.",
	"reward": 260 },
"Gliese 832": { "title": "The Mini Solar System",
	"story": "A red dwarf with a Jupiter-like giant far out AND a super-Earth tucked in close —\na compact echo of our own system's layout. Tidy, balanced, underrated. Survey the\nlittle copy of home.",
	"reward": 280 },
"Omicron-2 Eridani": { "title": "Live Long, Whatever",
	"story": "Also called 40 Eridani — and Star Trek's official home of VULCAN, blessed by\nRoddenberry himself. A real triple system with a white dwarf you can actually\nfind. The astronomers' 'planet' here turned out to be a glitch. Survey Spock's\nbusted hometown.",
	"reward": 320 },
}

# Mission types for the log's grouping/icons. Derived, not stored per-body.
enum { STAR, PLANET, MOON, CRAFT, OTHER }

const DEFAULT_REWARD := 150

static var _body_system := {}   # body name -> system id (lazy reverse index)
static var _by_system := {}     # system id -> Array[body name]  (lazy, build order)


# --- reverse index over SystemDB --------------------------------------------
static func _ensure_index() -> void:
	if not _body_system.is_empty():
		return
	for id in SystemDB.all():
		var names := []
		for spec in SystemDB.bodies(id):
			var bn: String = spec.name
			if bn.contains("✦"):
				continue                      # hub gate markers aren't real bodies
			_body_system[bn] = id
			names.append(bn)
		_by_system[id] = names


# The system a body lives in ("" if unknown).
static func system_of(body: String) -> String:
	_ensure_index()
	return _body_system.get(body, "")


# All body names in a system, in the order SystemDB lists them.
static func bodies_in(system_id: String) -> Array:
	_ensure_index()
	return _by_system.get(system_id, [])


# True if this body has a hand-written story (vs a generated fallback).
static func has_story(body: String) -> bool:
	return STORIES.has(body)


# The mission for a body: { title, story, reward }. Generated if not authored, so the
# log never has an empty entry.
static func mission_for(body: String) -> Dictionary:
	if STORIES.has(body):
		return STORIES[body]
	return _generated(body)


static func title_for(body: String) -> String:
	return str(mission_for(body).get("title", "Survey %s" % body))

static func story_for(body: String) -> String:
	return str(mission_for(body).get("story", ""))

static func reward(body: String) -> int:
	return int(mission_for(body).get("reward", DEFAULT_REWARD))


# Every mission across the whole catalogue, grouped, in system order. Returns
# Array[ { system, body, title, reward } ].
static func all_missions() -> Array:
	_ensure_index()
	var out := []
	for id in SystemDB.all():
		for body in _by_system.get(id, []):
			out.append({ "system": id, "body": body,
				"title": title_for(body), "reward": reward(body) })
	return out


# Generic crude mission for any body without an authored story (keeps the log whole).
static func _generated(body: String) -> Dictionary:
	var sys := system_of(body)
	var is_star: bool = false
	for spec in SystemDB.bodies(sys):
		if spec.name == body:
			is_star = bool(spec.get("star", false))
			break
	if is_star:
		var sp := SystemDB.spectral(sys)
		var ly := SystemDB.light_years(sys)
		return { "title": "Tag the Nameless Sun",
			"story": "A %s star %.1f light-years out with no fame, no planets worth a headline, and\nno reason to exist except to be a dot on the Survey's map. Go put it on the\nbooks anyway. The dispatcher doesn't care; the dispatcher just wants it logged." % [sp, ly],
			"reward": 220 }
	return { "title": "Survey %s" % body,
		"story": "Just another rock the Survey wants on file. No legend, no headline, no excuse —\nfly out, point your scanner, and tag it.",
		"reward": DEFAULT_REWARD }
