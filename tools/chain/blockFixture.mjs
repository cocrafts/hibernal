import { readFileSync } from "node:fs";

export const BLOCK_ID = 4;
export const BLOCK_KIND = 1;
export const BLOCK_VERSION = 1;
export const PETS = 10;
export const FIGHTS = 32;
export const RELATIONSHIPS = 45;
const IDENTITY_OWNER = 32;
const PET_ALIVE = 5;

export function sizesOf(logged) {
	const [block, pet, identity, grace, fight, listing, global, context, pets] = logged.map(Number);
	const offsets = { pets: 8 };
	offsets.identities = offsets.pets + PETS * pet;
	offsets.graces = offsets.identities + PETS * identity;
	offsets.fights = offsets.graces + PETS * grace;
	offsets.listings = offsets.fights + FIGHTS * fight;
	offsets.relationships = offsets.listings + PETS * listing;
	const end = offsets.relationships + RELATIONSHIPS;
	const padded = Math.ceil(end / 8) * 8;
	if (padded !== block || pets !== PETS * pet) {
		throw new Error(`Block is ${block} bytes but its fields end at ${end} (${padded} aligned), BlockPets ${pets} vs ${PETS} × ${pet}`);
	}
	return { block, pet, identity, grace, fight, listing, global, context, offsets };
}

function filler(seed, length) {
	const bytes = new Uint8Array(length);
	let state = BigInt(seed) | 1n;
	for (let index = 0; index < length; index++) {
		state ^= (state << 13n) & 0xffffffffffffffffn;
		state ^= state >> 7n;
		state ^= (state << 17n) & 0xffffffffffffffffn;
		bytes[index] = Number(state & 0xffn);
	}
	return bytes;
}

export function blockOf(sizes, pets, claimSlot, ownerBytes) {
	const bytes = new Uint8Array(sizes.block);
	const { offsets } = sizes;
	bytes.set(filler(0x5eed, sizes.block - offsets.identities), offsets.identities);
	bytes.fill(0, offsets.relationships + RELATIONSHIPS);
	for (let slot = 0; slot < PETS; slot++) {
		const identity = offsets.identities + slot * sizes.identity;
		bytes.fill(0, identity + IDENTITY_OWNER + 32 + 2, identity + sizes.identity);
	}
	bytes.set(ownerBytes, offsets.identities + claimSlot * sizes.identity + IDENTITY_OWNER);
	bytes.set(pets, offsets.pets);
	let living = 0;
	for (let slot = 0; slot < PETS; slot++) living += pets[slot * sizes.pet + PET_ALIVE] ? 1 : 0;
	const view = new DataView(bytes.buffer);
	view.setUint8(0, BLOCK_KIND);
	view.setUint8(1, BLOCK_VERSION);
	view.setUint8(2, living);
	view.setUint8(3, 0);
	view.setUint32(4, BLOCK_ID, true);
	return bytes;
}

export function withPets(block, sizes, pets) {
	const bytes = new Uint8Array(block);
	bytes.set(pets, sizes.offsets.pets);
	return bytes;
}

export function scenarioOf(directory, name) {
	const fields = {};
	for (const line of readFileSync(new URL(`${name}.txt`, directory), "utf8").split("\n")) {
		const [key, ...rest] = line.split(" ");
		if (key) { fields[key] = rest; }
	}
	const bytes = (key) => Uint8Array.from(fields[key].map(Number));
	return {
		name,
		pets: bytes("pets"),
		wilds: bytes("wilds"),
		context: bytes("context"),
		global: bytes("global"),
		after: bytes("after"),
		afterGlobal: bytes("afterGlobal"),
		choice: fields.choice.map(Number),
		digest: BigInt(fields.digest[0]),
		engine: BigInt(fields.engine[0]),
		header: fields.scenario.join(" "),
	};
}

export function differing(expected, actual) {
	return expected.reduce((count, value, position) => count + (actual[position] === value ? 0 : 1), Math.abs(expected.length - actual.length));
}
