class_name D
## Static game data, ported from the HTML version.

# LAND SIZE - the one setting for how big the land is (world units; 100 units = 1 km).
# Everything else (world generation, terrain shader, chart and minimap images, ocean
# margin, storm counts) reads this. Changing it makes old saves incompatible.
const WORLD := 60000.0

const NOTES := ["Pump still works if you kick it twice.", "Went east with the Hendersons. Stay off the river, it is full of them.", "Heard a voice on the emergency band again. Said Haven has doctors and a wall, somewhere on the coast.", "The fuel in the back room is spoken for. It is not. Take it.", "The fast ones came from the hospital in town. Aim low.", "Kept the runway lights on for three nights. Nobody came.", "Nothing I own can cross the empty country to Haven. Get a twin or get bigger tanks.", "Men with rifles in the next valley. They want planes, not people.", "Radio says Haven sends a beacon at dusk. I never heard it.", "Buried the mechanic behind the hangar. He would want you to use his tools.", "Crosswind here comes off the ridge. Point the nose into it and crab on in.", "Took the Heron north. Left you the Kestrel. Sorry about the oil leak.", "We are not dead. We went to the church. Knock three times.", "Fuel goes stale after a year. It has been fourteen months. Fly anyway.", "Every shot brings more of them. Get in, get the cans, get out.", "Red barrels in the yard are full of avgas. Keep your distance when you shoot one."]

const PLANES := [
	{"name": "Kestrel", "desc": "Two-seat taildragger. Forgiving, thirsty, short-legged.", "max": 140.0, "stall": 52.0, "cruise": 112.0, "fuel": 24.0, "burn": 0.44, "turn": 1.15, "slots": 1, "price": 0, "tankStep": 8, "tankMax": 1, "col": "#c9a866", "acc": "#7a2f22", "twin": false, "size": 34.0, "airframe": "super_cub", "props": [[0.375, 0.0, 0.12]]},
	{"name": "Heron", "desc": "High-wing utility hauler with room for three loads.", "max": 168.0, "stall": 60.0, "cruise": 138.0, "fuel": 32.0, "burn": 0.5, "turn": 0.98, "slots": 3, "price": 2800, "tankStep": 10, "tankMax": 2, "col": "#93aaa5", "acc": "#2d3b3a", "twin": false, "size": 40.0, "airframe": "skymaster", "props": [[0.48, 0.0, 0.11], [-0.175, 0.0, 0.11]]},
	{"name": "Albatross", "desc": "Twin-engine bush liner. The only thing out here with real legs.", "max": 205.0, "stall": 70.0, "cruise": 170.0, "fuel": 48.0, "burn": 0.6, "turn": 0.82, "slots": 5, "price": 6500, "tankStep": 12, "tankMax": 3, "col": "#dad3c0", "acc": "#8a3b1e", "twin": true, "size": 50.0, "airframe": "twin_otter", "props": [[0.35, -0.185, 0.1], [0.35, 0.185, 0.1]]},
]

const WEAPONS := [
	{"name": "Revolver", "dmg": 30.0, "rate": 0.36, "pel": 1, "spr": 0.035, "spd": 950.0, "life": 0.55, "price": 0, "noise": 2.5, "snd": "pistol", "kb": 6.0, "len": 15, "silent": false, "bolt": false},
	{"name": "Pump shotgun", "dmg": 15.0, "rate": 0.8, "pel": 6, "spr": 0.3, "spd": 820.0, "life": 0.36, "price": 650, "noise": 4.0, "snd": "shotgun", "kb": 8.0, "len": 23, "silent": false, "bolt": false},
	{"name": "Lever rifle", "dmg": 95.0, "rate": 0.5, "pel": 1, "spr": 0.008, "spd": 1400.0, "life": 0.62, "price": 1100, "noise": 4.5, "snd": "rifle", "kb": 10.0, "len": 25, "silent": false, "bolt": false},
	{"name": "Submachine gun", "dmg": 17.0, "rate": 0.085, "pel": 1, "spr": 0.1, "spd": 950.0, "life": 0.45, "price": 1500, "noise": 1.1, "snd": "smg", "kb": 3.0, "len": 18, "silent": false, "bolt": false, "auto": true},
	{"name": "Assault rifle", "dmg": 30.0, "rate": 0.13, "pel": 1, "spr": 0.045, "spd": 1250.0, "life": 0.6, "price": 2400, "noise": 1.8, "snd": "rifle2", "kb": 6.0, "len": 25, "silent": false, "bolt": false, "auto": true},
	{"name": "Double-barrel", "dmg": 14.0, "rate": 1.05, "pel": 10, "spr": 0.4, "spd": 800.0, "life": 0.32, "price": 950, "noise": 6.0, "snd": "shotgun2", "kb": 15.0, "len": 21, "silent": false, "bolt": false},
	{"name": "Crossbow", "dmg": 65.0, "ads_dmg": 100.0, "hip_zdmg": 22.0, "rate": 0.95, "pel": 1, "spr": 0.01, "spd": 880.0, "life": 0.7, "price": 1300, "noise": 0.0, "snd": "bow", "kb": 12.0, "len": 18, "silent": true, "bolt": true},
]

const NAMES := ["Miller", "Cold Creek", "Harlan", "Pine Hollow", "Dry Fork", "Kessler", "Black Rock", "Owl Ridge", "Beaver Dam", "Grady", "Stillwater", "Red Oak", "Hatchet Lake", "Coyote", "Mercy", "Deadwood", "Fairchild", "Lonesome", "Iron Gap", "Juniper", "Sutter", "Bramble", "Cutbank", "Wolf Creek", "Tamarack", "Halcyon", "Burnt Mill", "Cedar Bluff", "Crowley", "Garnet", "Hollis", "Muddy Gap", "Pickett", "Quarry Hill", "Sawtooth", "Thistle", "Vesper", "Wick", "Yarrow", "Alder Bend", "Bitterroot", "Copper Run", "Doyle", "Elk Horn", "Fallow", "Gilead", "Hobb", "Ironwood", "Jericho", "Kettle", "Larkin", "Moss Point", "Norrel", "Oxbow", "Pruitt", "Rook", "Shiloh", "Tolliver", "Umber", "Vail", "Wren", "Ashby", "Bexley", "Calloway", "Prosper", "Lockhart", "Gallow", "Ashford", "Badger Flats", "Barlow", "Bear Paw", "Bellwether", "Birch Run", "Blackwater", "Bluestem", "Bodie", "Bonner", "Boulder Gap", "Brushy Creek", "Buckhorn", "Calico", "Canby", "Carver", "Chalk Bluff", "Cheney", "Cinder Cone", "Clearwater", "Colfax", "Cordell", "Cottonwood", "Coulter", "Cripple Creek", "Winslow", "Darby", "Deer Lodge", "Dillard", "Driftwood", "Dunmore", "Eagle Butte", "Easton", "Ember", "Fairview", "Fenwick", "Flint Ridge", "Fort Lyle", "Foxboro", "Glory", "Goshen", "Granite Falls", "Graves", "Greer", "Halfway", "Harmony", "Hartsel", "Haskell", "Hayden", "Hickory Flat", "High Lonesome", "Holloway", "Hope", "Horsetail", "Idlewild", "Yellow Jacket", "Jasper", "Kearney", "Kinsey", "Lamar", "Larch", "Last Chance", "Ledger", "Lone Pine", "Lowell", "Magpie", "Marrow", "Meeker", "Millbrook", "Mosby", "Needles", "New Bethel", "Nickel Plate", "North Fork", "Odell", "Ophir", "Paradise", "Pardee", "Pinto", "Plainview", "Quill", "Ransom", "Rattlesnake Butte", "Redmond", "Renner", "Ridgway", "Rimrock", "Rio Seco", "Rosebud", "Ruby Valley", "Saddle Butte", "Salt Lick", "Scofield", "Sentinel", "Silver Bow", "Slate Creek", "Sorrow", "Spearfish", "Stony Point", "Sulphur", "Sweetwater", "Tabor", "Tenmile", "Thatcher", "Timber Lake", "Tincup", "Truth", "Two Dot", "Upton", "Vantage", "Gunnison", "Whitehall", "Willow Bend"]
const SUF := {"dirt": ["Field", "Strip", "Ranch Strip", "Farm Field"], "regional": ["Municipal", "County Airport", "Airpark"], "airport": ["Regional", "Airport"]}
const CARGO := [["📦", "canned food"], ["💊", "a cooler of insulin"], ["🔧", "engine parts"], ["📻", "a radio set"], ["🧍", "a passenger"], ["👪", "a family of three"], ["🩸", "blood plasma"], ["🌾", "seed grain"], ["🔋", "truck batteries"], ["✉️", "a sack of letters"], ["🐕", "a dog and its owner"], ["🧰", "well-pump tools"]]

const RNAMES := ["Mara Ellis", "Doc Hollis", "June Parrish", "Eli Watts", "Rosa Dent", "Tom Keller", "the Lind twins", "Pastor Abe", "Nora Quill", "Sam Reyes", "Ada Birch", "Walt Crane"]
const WHERE := {"pharmacy": "the pharmacy", "hardware": "the hardware store", "guns": "the gun shop", "bar": "the saloon", "grocery": "the grocery", "diner": "the diner", "gas": "the gas station", "post": "the post office", "house": "a house at the edge of town"}
const FOUND := ["Thank God. I will stay right behind you.", "You are the pilot? Then let us go, now.", "I heard the engine. I knew someone would come.", "Do not leave me here. Please."]

const ARCH := {"road": "Emergency road landing", "farm": "Farm strip", "lakeside": "Lakeside field", "county": "County field", "military": "Military airfield", "town": "Town airstrip"}
const SHOPS := [
	{"kind": "pharmacy", "sign": "PHARMACY", "mix": {"cabinet": 70, "register": 30}, "floor": "checker", "roof": "#6f7d86", "flat": true},
	{"kind": "hardware", "sign": "HARDWARE", "mix": {"toolbox": 60, "crate": 25, "register": 15}, "floor": "#6d6a64", "roof": "#7a6a4a", "flat": true},
	{"kind": "guns", "sign": "GUNS & AMMO", "mix": {"locker": 70, "register": 30}, "floor": "#4a3526", "roof": "#4d5638", "flat": true},
	{"kind": "bar", "sign": "SALOON", "mix": {"register": 40, "crate": 30, "dresser": 30}, "floor": "#5a3a24", "roof": "#6b3f33", "flat": false},
	{"kind": "grocery", "sign": "GROCERY", "mix": {"crate": 50, "register": 30, "jerry": 20}, "floor": "checker2", "roof": "#5d6a4a", "flat": true},
	{"kind": "diner", "sign": "DINER", "mix": {"register": 40, "crate": 40, "cabinet": 20}, "floor": "checker3", "roof": "#8a3a2a", "flat": true},
	{"kind": "gas", "sign": "GAS", "mix": {"jerry": 60, "register": 40}, "floor": "#6d6a64", "roof": "#8a8a82", "flat": true},
	{"kind": "post", "sign": "POST OFFICE", "mix": {"desk": 60, "crate": 40}, "floor": "#6a5a44", "roof": "#4f5a63", "flat": true}]
const HOUSEROOF := ["#6b3f33", "#4f5a63", "#6a6a5e", "#7a5a3a", "#3f4a3a", "#5a3a4a"]
const ARCHROOF := {"farm": ["#8a3024", "#6b5040"], "lakeside": ["#5a4632", "#3f4a3a"], "county": ["#7b7f82", "#5d6266"], "military": ["#4d5638", "#5a5f48"], "town": ["#6b3f33", "#4f5a63", "#6a6a5e"], "road": ["#7b7f82", "#8a3a2a"]}
const FLATARCH := {"farm": false, "lakeside": false, "county": true, "military": true, "town": false, "road": true}
const GOODS := {"whiskey": ["whiskey", 40], "cigarettes": ["cigarettes", 30], "antibiotics": ["antibiotics", 70], "jewelry": ["jewelry", 90], "batteries": ["batteries", 35]}
const GKEYS := ["whiskey", "cigarettes", "antibiotics", "jewelry", "batteries"]
const MIX := {"farm": {"crate": 40, "toolbox": 25, "jerry": 25, "cabinet": 10}, "lakeside": {"crate": 45, "jerry": 25, "toolbox": 15, "cabinet": 15}, "county": {"crate": 25, "desk": 25, "toolbox": 20, "cabinet": 15, "register": 15},
	"military": {"locker": 55, "crate": 25, "cabinet": 20}, "town": {"register": 35, "cabinet": 25, "crate": 25, "desk": 15}, "road": {"jerry": 35, "register": 25, "crate": 25, "toolbox": 15}}
const CONT := {"crate": {"fuel": 25, "ammo": 25, "cash": 15, "band": 12, "parts": 12, "goods": 8, "bomb": 3, "trinket": 1}, "locker": {"ammo": 40, "bomb": 18, "armor": 8, "med": 12, "goods": 12, "weapon": 8, "cash": 5, "trinket": 3}, "register": {"cash": 70, "goods": 20, "chart": 10, "trinket": 2},
	"toolbox": {"parts": 55, "fuel": 15, "bomb": 10, "chart": 10, "cash": 10}, "cabinet": {"band": 40, "med": 30, "goods": 25, "empty": 5}, "jerry": {"fuel": 85, "parts": 15}, "desk": {"chart": 30, "cash": 35, "goods": 20, "ammo": 15, "trinket": 3}, "dresser": {"cash": 30, "goods": 25, "band": 20, "ammo": 15, "chart": 10, "trinket": 4}, "safe": {"cash": 30, "weapon": 12, "trinket": 30, "goods": 18, "ammo": 10}, "stash": {"goods": 35, "ammo": 25, "cash": 25, "trinket": 8, "bomb": 7}}
const TRINKETS := [["wings", "Aviator wings", "You burn 10% less fuel."], ["gloves", "Mechanic's gloves", "Field repairs patch 25% instead of 15%."], ["rabbit", "Rabbit's foot", "Containers give an extra item more often."],
	["shoes", "Running shoes", "You move 12% faster on foot."], ["scope", "Hunting scope", "Your guns hit 20% harder."], ["ledger", "Trader's ledger", "Goods sell for 20% more."], ["monocle", "Night-vision monocle", "Your flashlight reaches much farther."],
	["boots", "Steel-toe boots", "The machete hits 60% harder."], ["radio", "Pocket radio", "Rescue jobs pay 25% more."], ["bandolier", "Bandolier", "Ammo pickups give 30% more rounds."]]
const RAR := {"fuel": 0, "ammo": 0, "cash": 0, "band": 0, "med": 1, "parts": 1, "goods": 1, "bomb": 1, "armor": 2, "chart": 2, "weapon": 2, "trinket": 3}
const RCOL := ["#e8e2d0", "#9cc063", "#7fb2f0", "#ffd27a"]
const ZSHIRT := ["#5a4a3a", "#3d4a55", "#6b3b34", "#4b5a3b", "#6a6258", "#2f3a2f", "#5b4b5e"]
const ZSKIN := ["#8c9a78", "#9aa58a", "#7d8a6e"]
## Hostile survivor skin tones, lightest to darkest. Add, remove or edit entries freely; one is picked at random per survivor.
const SVSKIN := ["#d4ab84", "#b88a63", "#9a6b47", "#74492e", "#4f2f1d"]
const SVSKIN_LIGHT_CHANCE := 2.0 / 3.0   # how often a survivor's tone comes from the lighter half of SVSKIN

## Random survivor skin tone: lighter half of SVSKIN with SVSKIN_LIGHT_CHANCE, darker half otherwise.
## With an odd count the middle tone straddles both halves.
static func sv_skin() -> String:
	var t := randf() * 0.5 if randf() < SVSKIN_LIGHT_CHANCE else 0.5 + randf() * 0.5
	return SVSKIN[mini(int(t * SVSKIN.size()), SVSKIN.size() - 1)]

const DIFFS := [
	{"name": "Relaxed", "noise": 0.55, "dmg": 0.55, "count": 0.65, "lunge": 1.6, "desc": "Fewer and weaker dead, slow noise. For enjoying the trip."},
	{"name": "Standard", "noise": 0.8, "dmg": 0.8, "count": 0.85, "lunge": 1.9, "desc": "The intended balance."},
	{"name": "Brutal", "noise": 1.1, "dmg": 1.05, "count": 1.1, "lunge": 2.4, "desc": "The original harsh tuning."}]

const DEATHS := {
	"ditch": ["Ditched", "You put it down in the water. The cold was quick. What waited in the reeds was quicker."],
	"crash": ["Crashed", "You hit the ground hard enough that nobody will find much to bury."],
	"misalign": ["Cartwheeled", "You caught the runway crosswise and the plane went end over end into the brush."],
	"overrun": ["Overrun", "You walked away from the wreck. The dead came out of the tree line before you found your bearings."],
	"loop": ["Ground loop", "You left the runway at speed and the plane folded itself into the dirt."],
	"bitten": ["Bitten", "They got you on the ground. You always figured you would go out in the air."],
	"breakup": ["Broke up", "The airframe gave out in the air. You had a long way down to think about it."],
	"gas": ["Gassed", "A bloater burst beside you, and the air itself turned on you."],
	"blast": ["Blast", "You stood too close to your own fireworks."],
	"shot": ["Shot", "A stranger with a rifle decided your plane was worth more than you were."]}

const TAGS := ["HAVEN?", "NO HOPE", "THEY HEAR YOU", "GOD LEFT", "TURN BACK", "KEEP QUIET", "DEAD INSIDE"]

static func wpick(tab: Dictionary, rf: Callable) -> String:
	var s := 0.0
	for k in tab: s += tab[k]
	var r: float = rf.call() * s
	for k in tab:
		r -= tab[k]
		if r < 0: return k
	return tab.keys()[0]
