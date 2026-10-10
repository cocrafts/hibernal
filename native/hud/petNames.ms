export const PET_NAME_COUNT: int32 = 256;

const PET_NAMES: string[256] = [
	"Leo", "Luna", "Milo", "Nova", "Loki", "Nala", "Otis", "Cleo",
	"Finn", "Kira", "Remy", "Zara", "Arlo", "Mika", "Theo", "Niko",
	"Pip", "Momo", "Kiki", "Bobo", "Toto", "Lulu", "Jojo", "Dodo",
	"Zuzu", "Coco", "Fifi", "Gigi", "Bibi", "Nunu", "Yoyo", "Pogo",
	"Ember", "Ash", "Flint", "Spark", "Cinder", "Blaze", "Pyro", "Coal",
	"Soot", "Torch", "Kindle", "Flicker", "Glow", "Scorch", "Furnace", "Phoenix",
	"Frost", "Snow", "Winter", "Glacier", "Tundra", "Flurry", "Icicle", "Chill",
	"Polar", "Sleet", "Blizzard", "Hail", "Crystal", "Shiver", "Frigid", "Yeti",
	"Fern", "Moss", "Clover", "Willow", "Maple", "Birch", "Cedar", "Aspen",
	"Hazel", "Ivy", "Basil", "Sage", "Sprout", "Bramble", "Acorn", "Cypress",
	"River", "Brook", "Delta", "Ripple", "Tide", "Coral", "Reef", "Pearl",
	"Pebble", "Drift", "Rain", "Mist", "Dew", "Storm", "Puddle", "Cascade",
	"Cosmo", "Orbit", "Comet", "Astra", "Vega", "Sirius", "Orion", "Lyra",
	"Pluto", "Saturn", "Neptune", "Mars", "Venus", "Eclipse", "Nebula", "Halo",
	"Bolt", "Volt", "Flux", "Pixel", "Byte", "Bit", "Chip", "Cache",
	"Echo", "Glitch", "Widget", "Gizmo", "Vector", "Servo", "Radar", "Turbo",
	"Mochi", "Tofu", "Miso", "Boba", "Dumpling", "Noodle", "Bao", "Sushi",
	"Kimchi", "Ramen", "Onigiri", "Dango", "Udon", "Wonton", "Soba", "Matcha",
	"Cookie", "Waffle", "Biscuit", "Muffin", "Brownie", "Pudding", "Custard", "Honey",
	"Maplepop", "Caramel", "Nougat", "Truffle", "Fudge", "Bonbon", "Jelly", "Candy",
	"Peanut", "Cashew", "Almond", "Walnut", "Pecan", "Pistachio", "Chestnut", "Sesame",
	"Pumpkin", "Pepper", "Pickle", "Turnip", "Radish", "Carrot", "Bean", "Lentil",
	"Mango", "Peach", "Plum", "Cherry", "Berry", "Fig", "Kiwi", "Melon",
	"Lemon", "Lime", "Pomelo", "Lychee", "Guava", "Papaya", "Apricot", "Coconut",
	"Cub", "Kit", "Fawn", "Pup", "Otter", "Badger", "Fox", "Wolf",
	"Lynx", "Panda", "Koala", "Wombat", "Gecko", "Newt", "Axolotl", "Capy",
	"Robin", "Wren", "Finch", "Sparrow", "Raven", "Crow", "Owl", "Falcon",
	"Kestrel", "Heron", "Crane", "Swift", "Lark", "Puffin", "Penguin", "Dove",
	"Ruby", "Opal", "Jade", "Onyx", "Topaz", "Amber", "Garnet", "Quartz",
	"Jasper", "Agate", "Beryl", "Mica", "Slate", "Basalt", "Copper", "Cobalt",
	"Atlas", "Apollo", "Hermes", "Odin", "Freya", "Thor", "Tyr", "Fenrir",
	"Rune", "Fable", "Myth", "Charm", "Sprite", "Sylph", "Pixie", "Nix",
];

export function petName(nameId: uint8): string {
	return PET_NAMES[nameId as int32];
}

export const NO_PET_NAME: int32 = -1;

// Any of the 256 names but the one shown, so every press changes it.
export function randomPetName(shown: int32): uint8 {
	const choices: int32 = shown == NO_PET_NAME ? PET_NAME_COUNT : PET_NAME_COUNT - 1;
	const pick: int32 = Math.min(Math.floor(Math.random() * (choices as float64)) as int32, choices - 1);
	return (shown != NO_PET_NAME && pick >= shown ? pick + 1 : pick) as uint8;
}

const NUMERAL_VALUES: int32[13] = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
const NUMERAL_WORDS: string[13] = [
	"M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I",
];

export function petDisplayName(nameId: uint8, lineageGeneration: uint16): string {
	if (lineageGeneration == 0) { return petName(nameId); }
	let remaining: int32 = (lineageGeneration as int32) + 1;
	let numeral: string = "";
	for (let index: int32 = 0; index < 13; index += 1) {
		while (remaining >= NUMERAL_VALUES[index]) {
			numeral += NUMERAL_WORDS[index];
			remaining -= NUMERAL_VALUES[index];
		}
	}
	return petName(nameId) + " " + numeral;
}

test "every byte selects a unique nonempty Pet name with a stable mapping" {
	assert PET_NAMES.length == PET_NAME_COUNT;
	let fingerprint: uint64 = 2166136261;
	for (let index: int32 = 0; index < PET_NAME_COUNT; index += 1) {
		assert petName(index as uint8) != "";
		for (let other: int32 = index + 1; other < PET_NAME_COUNT; other += 1) {
			assert petName(index as uint8) != petName(other as uint8);
		}
		for (const byte of petName(index as uint8).asBytes()) {
			fingerprint = ((fingerprint ^ (byte as uint64)) * 16777619) % 4294967296;
		}
		fingerprint = (fingerprint * 16777619) % 4294967296;
	}
	assert fingerprint == 2791144096;
	assert petName(0) == "Leo";
	assert petName(255) == "Nix";
}

test "a random name is always a new one, and over many presses reaches far across the 256" {
	let shown: uint8 = randomPetName(NO_PET_NAME);
	let low: int32 = PET_NAME_COUNT;
	let high: int32 = -1;
	for (let press: int32 = 0; press < 2000; press += 1) {
		const next: uint8 = randomPetName(shown as int32);
		assert next != shown;
		low = Math.min(low, next as int32);
		high = Math.max(high, next as int32);
		shown = next;
	}
	assert low < 16 && high > PET_NAME_COUNT - 17;
}

test "first-life names omit I and later lives keep Roman lineage" {
	assert petDisplayName(0, 0) == "Leo";
	assert petDisplayName(68, 0) == "Maple";
	assert petDisplayName(0, 1) == "Leo II";
	assert petDisplayName(0, 3) == "Leo IV";
	assert petDisplayName(0, 6) == "Leo VII";
	assert petDisplayName(0, 8) == "Leo IX";
	assert petDisplayName(0, 39) == "Leo XL";
	assert petDisplayName(0, 89) == "Leo XC";
	assert petDisplayName(0, 399) == "Leo CD";
	assert petDisplayName(0, 899) == "Leo CM";
	assert petDisplayName(0, 999) == "Leo M";
	assert petDisplayName(255, 6) == "Nix VII";
	assert petDisplayName(0, 65535).endsWith("DXXXVI");
}
