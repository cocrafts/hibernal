export const WIRE_LIMIT = 1_232;
export const MAX_INSTRUCTIONS = 64;
export const MAX_ACCOUNTS = 30;
export const PACK_UNITS = 1_300_000;
export const PETS_PER_BLOCK = 10;
export const IDENTITY_BYTES = 72;

export function words(...values) {
	const bytes = new Uint8Array(8 * values.length);
	const view = new DataView(bytes.buffer);
	values.forEach((value, index) => view.setBigUint64(8 * index, BigInt(value), true));
	return bytes;
}

export function joined(...parts) {
	const bytes = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
	let offset = 0;
	for (const part of parts) {
		bytes.set(part, offset);
		offset += part.length;
	}
	return bytes;
}

function random(seed) {
	let state = BigInt(seed) | 1n;
	return () => {
		state ^= (state << 13n) & 0xffffffffffffffffn;
		state ^= state >> 7n;
		state ^= (state << 17n) & 0xffffffffffffffffn;
		return state;
	};
}

export function blocksFor(count, blockBytes, sources) {
	const petBytes = sources[0].length / PETS_PER_BLOCK;
	const next = random(0x51ed + count);
	const blocks = [];
	const mints = [];
	for (let id = 0; id < count / PETS_PER_BLOCK; id++) {
		const bytes = new Uint8Array(blockBytes);
		const view = new DataView(bytes.buffer);
		view.setUint8(0, 1);
		view.setUint8(1, 1);
		view.setUint32(4, id, true);
		for (let slot = 0; slot < PETS_PER_BLOCK; slot++) {
			const source = sources[Number(next() % BigInt(sources.length))];
			const pick = Number(next() % BigInt(PETS_PER_BLOCK));
			bytes.set(source.subarray(pick * petBytes, (pick + 1) * petBytes), 8 + slot * petBytes);
			const mint = new Uint8Array(32);
			for (let index = 0; index < 32; index += 8) new DataView(mint.buffer).setBigUint64(index, next(), true);
			bytes.set(mint, identityOffset(petBytes, slot));
			mints.push(mint);
		}
		blocks.push(bytes);
	}
	return { blocks, mints, petBytes };
}

export function identityOffset(petBytes, slot) {
	return 8 + PETS_PER_BLOCK * petBytes + slot * IDENTITY_BYTES;
}

export const hex = (bytes) => Buffer.from(bytes).toString("hex");
const same = (left, right) => left.length === right.length && left.every((value, index) => value === right[index]);

export function swapPlan(ranked, mints) {
	const current = mints.slice();
	const where = new Map(current.map((mint, position) => [hex(mint), position]));
	const swaps = [];
	for (let rank = 0; rank < ranked.length; rank++) {
		if (same(current[rank], ranked[rank])) continue;
		const from = where.get(hex(ranked[rank]));
		swaps.push({ from, rank, arriving: ranked[rank], leaving: current[rank] });
		const moving = current[rank];
		current[rank] = current[from];
		current[from] = moving;
		where.set(hex(current[from]), from);
		where.set(hex(current[rank]), rank);
	}
	return swaps;
}

export function wireBytes(accounts, instructions) {
	const fixed = 1 + 64 + 3 + 32 * (accounts + 3) + 32 + 1 + 1 + 9 + 1;
	return fixed + instructions.reduce((sum, instruction) => sum + 1 + 1 + instruction.accounts.length + 1 + instruction.data.length, 0);
}

export function packed(instructions, unitsEach) {
	const batches = [];
	let batch = [];
	let keys = new Set();
	for (const instruction of instructions) {
		const own = instruction.accounts.map((meta) => meta.address);
		const extra = own.filter((key) => !keys.has(key));
		const full = keys.size + extra.length > MAX_ACCOUNTS ||
			wireBytes(keys.size + extra.length, [...batch, instruction]) > WIRE_LIMIT ||
			batch.length + 2 > MAX_INSTRUCTIONS ||
			(batch.length + 1) * unitsEach * 1.15 > PACK_UNITS;
		if (batch.length > 0 && full) {
			batches.push(batch);
			batch = [];
			keys = new Set();
		}
		batch.push(instruction);
		for (const key of own) keys.add(key);
	}
	if (batch.length > 0) batches.push(batch);
	return batches;
}
