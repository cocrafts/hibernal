import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { address, getBase58Decoder, getProgramDerivedAddress } from "@solana/kit";
import {
	DELEGATION_PROGRAM,
	HYDRA_PROGRAM,
	MAGIC_PROGRAM,
	MAGIC_VAULT,
	SYSTEM_PROGRAM,
	accountOffsets,
	cluster,
	encoder,
	fieldsOf,
	hibernal,
	idlAt,
	instructionDiscriminator,
	joined,
	json,
	keypairAt,
	patiently,
	read,
	readU32,
	readU64,
	readonly,
	send,
	sleep,
	u32,
	u64,
	writable,
	writableSigner,
} from "./hibernal.mjs";
import { sponsorDelegated } from "./hydra.mjs";

const STAGE = process.env.STAGE ?? "status";
const NET_DIR = process.env.NET_DIR ?? "out/localnet";
const SEATS = 10;
const NO_BLOCK = 0xffffffff;
const CHUNK = 900;
const CRANK_RENT = BigInt(process.env.CRANK_RENT ?? 32_128);
const CRANKS_PER_BLOCK = BigInt(process.env.CRANKS_PER_BLOCK ?? 8);
const FUNDER_LAMPORTS = BigInt(process.env.FUNDER_LAMPORTS ?? 2_000_000_000);
const BLOCKS_PER_TRANSACTION = Number(process.env.BLOCKS_PER_TRANSACTION ?? 2);
const PLACES_PER_TRANSACTION = Number(process.env.PLACES_PER_TRANSACTION ?? 5);
const SWEEP_BATCH = Number(process.env.SWEEP_BATCH ?? 20);
const PARALLEL = Number(process.env.PARALLEL ?? 16);
const WATCHDOG_SLOTS = BigInt(process.env.WATCHDOG_SLOTS ?? 6_000);
const TICK_SECONDS = Number(process.env.TICK_SECONDS ?? 10);
const MEASURE = ["level", "power", "combat"].indexOf(process.env.MEASURE ?? "combat");
const PHASES = ["Idle", "Seeding", "Acting", "Dusk"];

const [programArgument, policyPath] = process.argv.slice(2);
if (!programArgument) {
	console.log("usage: STAGE=bootstrap|blocks|sweep|watchdog|resort|status|run node tools/chain/ops.mjs <program id> [<checkpoint>.policy]");
	process.exit(2);
}
const programAddress = address(programArgument);
const STATE_PATH = `${NET_DIR}/ops-${programArgument}.json`;
const STATUS_PATH = `${NET_DIR}/opsStatus.json`;
const { base, baseRead, ephemeral, validator } = cluster();
const authority = await keypairAt(`${process.env.HOME}/.config/solana/id.json`);
const program = hibernal(programAddress, authority);
const idl = idlAt();
const blockAt = accountOffsets(idl, "Block");
const worldAt = accountOffsets(idl, "World");
const petAccountAt = accountOffsets(idl, "PetAccount");
const configAt = accountOffsets(idl, "Config");
const petAt = fieldsOf(idl, "Pet").offsets;
const gearAt = fieldsOf(idl, "Gear").offsets;
const itemAt = fieldsOf(idl, "Item").offsets;
const globalAt = fieldsOf(idl, "GlobalConfig").offsets;
const claimDiscriminator = Buffer.from(instructionDiscriminator("Claim")).toString("hex");
const state = existsSync(STATE_PATH) ? JSON.parse(readFileSync(STATE_PATH, "utf8")) : {};
state.pets ??= {};
state.swept ??= {};
state.resumes ??= [];
state.events ??= [];
const save = () => writeFileSync(STATE_PATH, json(state));
const onL1 = (step, instructions, units) => send(base, baseRead, step, instructions, authority, units, false);
const onEr = (step, instructions, units) => send(ephemeral, ephemeral, step, instructions, authority, units, false);
const base58 = getBase58Decoder();

function note(kind, message) {
	const line = `${new Date().toISOString()} ${kind}: ${message}`;
	console.log(line);
	state.events.push(line);
	if (state.events.length > 200) state.events.splice(0, state.events.length - 200);
}

async function inParallel(items, work) {
	let next = 0;
	const lanes = Array.from({ length: Math.min(PARALLEL, items.length) }, async () => {
		while (next < items.length) {
			const item = items[next++];
			await work(item);
		}
	});
	await Promise.all(lanes);
}

async function readMany(rpc, keys) {
	const found = [];
	for (let start = 0; start < keys.length; start += 100) {
		const { value } = await patiently(() => rpc.getMultipleAccounts(keys.slice(start, start + 100), { encoding: "base64", commitment: "confirmed" }).send());
		for (const entry of value) found.push(entry ? { owner: entry.owner, lamports: BigInt(entry.lamports), data: new Uint8Array(Buffer.from(entry.data[0], "base64")) } : null);
	}
	return found;
}

async function readCloned(keys, attempts = 20) {
	let found = await readMany(ephemeral, keys);
	for (let attempt = 0; attempt < attempts && found.some((entry) => !entry); attempt++) {
		await sleep(1000);
		const missing = keys.filter((_, index) => !found[index]);
		const fresh = await readMany(ephemeral, missing);
		let cursor = 0;
		found = found.map((entry) => entry ?? fresh[cursor++]);
	}
	return found;
}

function decodeAddress(bytes) {
	return base58.decode(bytes);
}

const addressOf = async (derived) => (await derived)[0];
const configAddress = () => addressOf(program.seeds.config());
const worldAddress = () => addressOf(program.seeds.world());
const vrfPayerAddress = () => addressOf(program.seeds.vrfPayer());
const blockAddress = (id) => addressOf(program.seeds.block(id));
const petAddress = (mint) => addressOf(program.seeds.pet(mint));
const delegated = (holder) => holder?.owner === DELEGATION_PROGRAM;

function blockOf(id, holder) {
	const data = holder.data;
	const members = [];
	for (let seat = 0; seat < SEATS; seat++) {
		const bytes = data.subarray(blockAt.members + seat * 32, blockAt.members + seat * 32 + 32);
		members.push(bytes.every((byte) => byte === 0) ? null : decodeAddress(bytes));
	}
	return {
		id,
		phase: data[blockAt.phase],
		round: data[blockAt.round],
		cursor: data[blockAt.cursor],
		epoch: readU64(data, blockAt.epoch),
		filled: data[blockAt.filled],
		members,
		crankSeq: blockAt.crank_seq !== undefined ? readU64(data, blockAt.crank_seq) : null,
		dueSlot: blockAt.due_slot !== undefined ? readU64(data, blockAt.due_slot) : null,
	};
}

function worldOf(holder) {
	const data = holder.data;
	const global = {};
	for (const [field, offset] of Object.entries(globalAt)) {
		const at = worldAt.global + offset;
		global[field] = field === "living_pets" || field === "floor_slots" ? readU32(data, at) : readU64(data, at);
	}
	return {
		global,
		epoch: readU64(data, worldAt.epoch),
		resortEvery: readU64(data, worldAt.resort_every),
		resortedEpoch: readU64(data, worldAt.resorted_epoch),
		resorting: data[worldAt.resorting],
		unplaced: readU32(data, worldAt.unplaced),
		placed: readU32(data, worldAt.placed),
	};
}

function petOf(key, holder) {
	const data = holder.data;
	const at = (field) => petAccountAt.pet + petAt[field];
	const gear = [];
	for (const slot of ["head", "body", "hands", "feet"]) {
		const start = petAccountAt.pet + petAt.gear + gearAt[slot];
		gear.push({ rarity: data[start + itemAt.rarity], stat: data[start + itemAt.stat], wear: data[start + itemAt.wear] });
	}
	return {
		key,
		owner: decodeAddress(data.subarray(petAccountAt.owner, petAccountAt.owner + 32)),
		mint: decodeAddress(data.subarray(petAccountAt.mint, petAccountAt.mint + 32)),
		blockId: readU32(data, at("block_id")),
		slot: data[at("slot")],
		alive: data[at("alive")] !== 0,
		level: new DataView(data.buffer, data.byteOffset).getUint16(at("level"), true),
		forage: new DataView(data.buffer, data.byteOffset).getUint16(at("forage"), true),
		might: new DataView(data.buffer, data.byteOffset).getUint16(at("might"), true),
		grit: new DataView(data.buffer, data.byteOffset).getUint16(at("grit"), true),
		gear,
	};
}

const GRADE_BONUS_BPS = [200, 400, 700, 1000, 1300].map((bonus) => Math.trunc(bonus * 200 / 100));
const ITEM_WEAR_MAX = 200;
const TALENT = { forage: 1, might: 2, grit: 3 };

function statBonusBps(gear, stat) {
	let bonus = 0;
	for (const item of gear) {
		if (item.rarity === 0 || item.stat !== stat) continue;
		bonus += Math.trunc(GRADE_BONUS_BPS[item.rarity - 1] * (ITEM_WEAR_MAX - item.wear) / ITEM_WEAR_MAX);
	}
	return bonus;
}

function geared(value, bonusBps) {
	return Math.trunc(value * (10_000 + bonusBps) / 10_000);
}

export function strengthOf(pet, measure = MEASURE) {
	if (!pet.alive) return 0n;
	const forage = geared(pet.forage, statBonusBps(pet.gear, TALENT.forage));
	const might = geared(pet.might, statBonusBps(pet.gear, TALENT.might));
	const grit = geared(pet.grit, statBonusBps(pet.gear, TALENT.grit));
	const power = BigInt(forage + might + grit);
	const strength = measure === 0 ? BigInt(pet.level) * 10_000n + power : measure === 1 ? power : BigInt(might + grit);
	return strength + 1n;
}

async function crankAddressOf(blockId, seq) {
	const seed = joined(u64(blockId), u64(seq), encoder.encode(programAddress).subarray(0, 16));
	const [found] = await getProgramDerivedAddress({ programAddress: HYDRA_PROGRAM, seeds: ["crank", seed] });
	return found;
}

async function startBlockInstruction(blockId, crankSeq) {
	if (program.startBlock) return program.startBlock(blockId, crankSeq);
	return {
		programAddress,
		accounts: [
			writableSigner(authority),
			readonly(await configAddress()),
			readonly(await worldAddress()),
			writable(await blockAddress(blockId)),
			writable(await vrfPayerAddress()),
			writable(await crankAddressOf(blockId, crankSeq)),
			writable(MAGIC_VAULT),
			readonly(MAGIC_PROGRAM),
			readonly(HYDRA_PROGRAM),
		],
		data: joined(instructionDiscriminator("StartBlock"), u32(blockId)),
	};
}

async function sweepInstruction(cranks) {
	if (program.sweep) return program.sweep(cranks);
	return {
		programAddress,
		accounts: [
			writable(await vrfPayerAddress()),
			writable(MAGIC_VAULT),
			readonly(MAGIC_PROGRAM),
			readonly(HYDRA_PROGRAM),
			...cranks.map((crank) => writable(crank)),
		],
		data: instructionDiscriminator("Sweep"),
	};
}

const supportsRelay = () => blockAt.crank_seq !== undefined && idl.instructions.some((entry) => entry.name === "start_block");
const supportsSweep = () => idl.instructions.some((entry) => entry.name === "sweep");

async function bootstrap() {
	const config = await configAddress();
	if (!(await read(baseRead, config))) {
		if (!policyPath) throw new Error("bootstrap needs the policy path as the second argument");
		const policy = new Uint8Array(readFileSync(policyPath));
		const engine = new DataView(policy.buffer, policy.byteOffset).getBigUint64(8, true);
		const skrMint = await keypairAt(process.env.SKR_MINT ?? "out/devSkrMint.json");
		const treasuryOwner = await keypairAt(process.env.TREASURY ?? "out/devTreasury.json");
		const [treasury] = await getProgramDerivedAddress({
			programAddress: address("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"),
			seeds: [encoder.encode(treasuryOwner.address), encoder.encode(address("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")), encoder.encode(skrMint.address)],
		});
		const genesisTimestamp = BigInt(process.env.GENESIS ?? Math.floor(Date.now() / 1000));
		await onL1("initialize", [await program.initialize({
			admissionGroup: address(process.env.GROUP),
			engine,
			genesisTimestamp,
			claimCapPerDay: BigInt(process.env.CLAIM_CAP_PER_DAY ?? 10_000_000),
			resortEvery: BigInt(process.env.RESORT_EVERY ?? 7),
			validator,
			skrMint: skrMint.address,
			treasury,
			vrfQueue: address(process.env.VRF_QUEUE),
			secondsPerDay: BigInt(process.env.SECONDS_PER_DAY ?? 86_400),
			staggerSeconds: BigInt(process.env.STAGGER_SECONDS ?? process.env.ROUND_STAGGER_SECONDS ?? 600),
			turnGapSlots: BigInt(process.env.TURN_GAP_SLOTS ?? 100),
			slotMillis: BigInt(process.env.SLOT_MILLIS ?? 10),
		})]);
		note("bootstrap", `initialized, genesis ${genesisTimestamp}`);
	}
	if (policyPath) {
		const policy = new Uint8Array(readFileSync(policyPath));
		const holder = await read(baseRead, await addressOf(program.seeds.policy()));
		const policyFields = accountOffsets(idl, "Policy");
		const written = holder ? readU32(holder.data, policyFields.written) : 0;
		for (let offset = written; offset < policy.length; offset += CHUNK) {
			const end = Math.min(offset + CHUNK, policy.length);
			await onL1(`policy ${offset}`, [await program.writePolicy(offset, policy.subarray(offset, end), end === policy.length)]);
		}
		if (written < policy.length) note("bootstrap", `policy uploaded (${policy.length} bytes)`);
	}
	if (!delegated(await read(baseRead, await worldAddress()))) {
		await onL1("delegate world", [await program.delegateWorld()]);
		note("bootstrap", "world delegated");
	}
	if (!delegated(await read(baseRead, await vrfPayerAddress()))) {
		await onL1("delegate VRF payer", [await program.delegateVrfPayer()]);
		note("bootstrap", "VRF payer delegated");
	}
	await fundVrfPayer();
}

async function fundVrfPayer() {
	const funderPath = `${NET_DIR}/opsFunder.json`;
	if (!existsSync(funderPath)) {
		const { generateKeyPairSync } = await import("node:crypto");
		const { privateKey, publicKey } = generateKeyPairSync("ed25519");
		const secret = privateKey.export({ format: "der", type: "pkcs8" }).subarray(-32);
		const pub = publicKey.export({ format: "der", type: "spki" }).subarray(-32);
		writeFileSync(funderPath, JSON.stringify([...secret, ...pub]));
	}
	const funder = await keypairAt(funderPath);
	const fundedNow = await sponsorDelegated({ sponsor: funder, funder: authority, base, baseRead, ephemeralUrl: process.env.ER_RPC, validator, lamports: FUNDER_LAMPORTS, send });
	if (fundedNow) note("bootstrap", `ops funder ${funder.address} delegated with ${FUNDER_LAMPORTS} lamports`);
	const config = await read(baseRead, await configAddress());
	const blocks = config ? readU32(config.data, configAt.blocks) : 0;
	const payer = (await readCloned([await vrfPayerAddress()]))[0];
	if (!payer) throw new Error("the VRF payer never appeared in the ER");
	const floor = 2_000_000n;
	const target = floor + CRANK_RENT * CRANKS_PER_BLOCK * BigInt(Math.max(blocks, 1));
	if (payer.lamports >= target) return payer.lamports;
	const amount = target - payer.lamports;
	const transfer = { programAddress: SYSTEM_PROGRAM, accounts: [writableSigner(funder), writable(await vrfPayerAddress())], data: joined(u32(2), u64(amount)) };
	await onEr("fund the VRF payer", [transfer]);
	note("bootstrap", `VRF payer topped up by ${amount} to ${target} lamports in the ER`);
	return target;
}

async function discoverPets() {
	const registry = process.env.PETS_FILE ?? `${NET_DIR}/players.json`;
	if (existsSync(registry)) {
		const raw = readFileSync(registry, "utf8").trim();
		const entries = raw.startsWith("[") || raw.startsWith("{") ? JSON.parse(raw) : raw.split("\n").map((line) => line.trim().split(/\s+/).pop());
		const list = Array.isArray(entries) ? entries : entries.players ?? Object.values(entries);
		for (const entry of list) {
			const mint = typeof entry === "string" ? entry : entry.mint;
			if (!mint) continue;
			const pet = typeof entry === "object" && entry.pet ? entry.pet : await petAddress(address(mint));
			state.pets[pet] ??= { mint };
		}
		if (process.env.DISCOVER === "registry") return Object.keys(state.pets);
	}
	const config = await configAddress();
	const fresh = [];
	let before;
	for (let page = 0; page < 1000; page++) {
		const signatures = await patiently(() => baseRead.getSignaturesForAddress(config, { limit: 1000, ...(before ? { before } : {}), ...(state.claimCursor ? { until: state.claimCursor } : {}) }).send());
		if (signatures.length === 0) break;
		fresh.push(...signatures.filter((entry) => entry.err === null));
		before = signatures[signatures.length - 1].signature;
		if (signatures.length < 1000) break;
	}
	if (fresh.length > 0) state.claimCursor = fresh[0].signature;
	await inParallel(fresh, async (entry) => {
		const found = await patiently(() => baseRead.getTransaction(entry.signature, { maxSupportedTransactionVersion: 0, encoding: "json" }).send());
		if (!found) return;
		const keys = found.transaction.message.accountKeys;
		for (const instruction of found.transaction.message.instructions) {
			if (keys[instruction.programIdIndex] !== programAddress) continue;
			const data = Buffer.from(base58Bytes(instruction.data));
			if (data.subarray(0, 8).toString("hex") !== claimDiscriminator) continue;
			const pet = keys[instruction.accounts[4]];
			state.pets[pet] ??= { mint: keys[instruction.accounts[2]], owner: keys[instruction.accounts[0]] };
		}
	});
	return Object.keys(state.pets);
}

function base58Bytes(text) {
	const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
	let value = 0n;
	for (const character of text) value = value * 58n + BigInt(alphabet.indexOf(character));
	const bytes = [];
	while (value > 0n) {
		bytes.unshift(Number(value % 256n));
		value /= 256n;
	}
	for (const character of text) {
		if (character !== "1") break;
		bytes.unshift(0);
	}
	return Uint8Array.from(bytes);
}

async function allBlocks() {
	const config = await read(baseRead, await configAddress());
	const count = config ? readU32(config.data, configAt.blocks) : 0;
	const keys = await Promise.all(Array.from({ length: count }, (_, id) => blockAddress(id)));
	const holders = await readCloned(keys);
	return holders.map((holder, id) => (holder ? blockOf(id, holder) : { id, missing: true }));
}

async function allBlocksAt(ids) {
	const keys = await Promise.all(ids.map((id) => blockAddress(id)));
	const holders = await readCloned(keys);
	return holders.map((holder, index) => (holder ? blockOf(ids[index], holder) : null));
}

async function createBlocks(count) {
	const config = await read(baseRead, await configAddress());
	const first = readU32(config.data, configAt.blocks);
	const ids = Array.from({ length: count }, (_, index) => first + index);
	for (let start = 0; start < ids.length; start += BLOCKS_PER_TRANSACTION) {
		const batch = ids.slice(start, start + BLOCKS_PER_TRANSACTION);
		await onL1(`create blocks ${batch.join(",")}`, await Promise.all(batch.map((id) => program.createBlock(id))));
	}
	note("blocks", `created blocks ${first}..${first + count - 1}`);
}

async function delegateBlocks() {
	const config = await read(baseRead, await configAddress());
	const count = readU32(config.data, configAt.blocks);
	const keys = await Promise.all(Array.from({ length: count }, (_, id) => blockAddress(id)));
	const holders = await readMany(baseRead, keys);
	const ids = holders.flatMap((holder, id) => (holder && !delegated(holder) ? [id] : []));
	if (ids.length === 0) return;
	const batches = [];
	for (let start = 0; start < ids.length; start += BLOCKS_PER_TRANSACTION) batches.push(ids.slice(start, start + BLOCKS_PER_TRANSACTION));
	await inParallel(batches, async (batch) => {
		await onL1(`delegate blocks ${batch.join(",")}`, await Promise.all(batch.map((id) => program.delegateBlock(id))));
	});
	note("blocks", `delegated ${ids.length} blocks, ${ids[0]}..${ids[ids.length - 1]}`);
	await fundVrfPayer();
}

async function blocks() {
	const known = await discoverPets();
	const keys = known.map((key) => address(key));
	const l1 = await readMany(baseRead, keys);
	const delegatedKeys = keys.filter((_, index) => delegated(l1[index]));
	const notDelegated = keys.length - delegatedKeys.length;
	const holders = await readCloned(delegatedKeys);
	const pets = holders.map((holder, index) => (holder ? petOf(delegatedKeys[index], holder) : null)).filter(Boolean);
	const unplaced = pets.filter((pet) => pet.blockId === NO_BLOCK);
	await delegateBlocks();
	let current = await allBlocks();
	const idle = (block) => !block.missing && block.phase === 0;
	const freeSeats = current.filter(idle).reduce((total, block) => total + block.members.filter((member) => member === null).length, 0);
	const needed = Math.ceil(Math.max(0, unplaced.length - freeSeats) / SEATS);
	if (needed > 0) {
		await createBlocks(needed);
		await delegateBlocks();
		current = await allBlocks();
	}
	const plan = [];
	let queue = unplaced.slice();
	for (const block of current.filter(idle)) {
		const empty = block.members.filter((member) => member === null).length;
		if (empty === 0 || queue.length === 0) continue;
		plan.push({ block, pets: queue.slice(0, empty) });
		queue = queue.slice(empty);
	}
	let placed = 0;
	await inParallel(plan, async ({ block, pets: chosen }) => {
		for (let start = 0; start < chosen.length; start += PLACES_PER_TRANSACTION) {
			const batch = chosen.slice(start, start + PLACES_PER_TRANSACTION);
			try {
				await onEr(`place ${batch.length} in block ${block.id}`, await Promise.all(batch.map((pet) => program.place(block.id, address(pet.mint)))));
				placed += batch.length;
			} catch (error) {
				note("blocks", `placing in block ${block.id} refused: ${error.message}`);
			}
		}
	});
	if (placed > 0) note("blocks", `placed ${placed} pets`);
	let started = 0;
	if (supportsRelay()) {
		current = await allBlocks();
		const waiting = current.filter((block) => !block.missing && block.crankSeq === 0n && block.members.some(Boolean));
		await inParallel(waiting, async (block) => {
			try {
				await onEr(`start block ${block.id}`, [await startBlockInstruction(block.id, block.crankSeq)]);
				started++;
			} catch (error) {
				note("blocks", `start block ${block.id} refused: ${error.message}`);
			}
		});
		if (started > 0) note("blocks", `started ${started} block chains`);
	}
	state.lastBlocks = { at: new Date().toISOString(), known: keys.length, notDelegated, unplacedBefore: unplaced.length, placed, started, unplacedLeft: queue.length };
	save();
	return state.lastBlocks;
}

async function exhaustedCranks(blocksNow) {
	const vrfPayer = await vrfPayerAddress();
	const candidates = new Set();
	const { value } = await patiently(() => ephemeral.getProgramAccounts(HYDRA_PROGRAM, {
		encoding: "base64",
		dataSlice: { offset: 0, length: 0 },
		filters: [{ memcmp: { offset: 0n, bytes: vrfPayer, encoding: "base58" } }, { memcmp: { offset: 80n, bytes: "11111111", encoding: "base58" } }],
		withContext: true,
	}).send());
	for (const entry of value) candidates.add(entry.pubkey);
	if (supportsRelay()) {
		for (const block of blocksNow) {
			if (block.missing || block.crankSeq === null || block.crankSeq < 2n) continue;
			const from = BigInt(state.swept[block.id] ?? 0);
			for (let seq = from; seq < block.crankSeq - 1n; seq++) candidates.add(await crankAddressOf(block.id, seq));
		}
	}
	const keys = [...candidates];
	const holders = await readMany(ephemeral, keys);
	return keys.filter((_, index) => {
		const holder = holders[index];
		if (!holder || holder.owner !== HYDRA_PROGRAM || holder.data.length < 88) return false;
		return decodeAddress(holder.data.subarray(0, 32)) === vrfPayer && readU64(holder.data, 80) === 0n;
	});
}

async function sweep() {
	const blocksNow = await allBlocks();
	const cranks = await exhaustedCranks(blocksNow);
	if (cranks.length > 0 && !supportsSweep()) {
		note("sweep", `${cranks.length} exhausted cranks waiting: the program has no Sweep instruction yet`);
		state.lastSweep = { at: new Date().toISOString(), exhausted: cranks.length, swept: 0, blocked: "no Sweep instruction" };
		save();
		return state.lastSweep;
	}
	const batches = [];
	for (let start = 0; start < cranks.length; start += SWEEP_BATCH) batches.push(cranks.slice(start, start + SWEEP_BATCH));
	let swept = 0;
	await inParallel(batches, async (batch) => {
		try {
			await onEr(`sweep ${batch.length}`, [await sweepInstruction(batch)]);
			swept += batch.length;
		} catch (error) {
			note("sweep", `a sweep of ${batch.length} cranks failed: ${error.message}`);
		}
	});
	for (const block of blocksNow) {
		if (!block.missing && block.crankSeq !== null && block.crankSeq > 1n) state.swept[block.id] = (block.crankSeq - 1n).toString();
	}
	state.lastSweep = { at: new Date().toISOString(), exhausted: cranks.length, swept };
	if (swept > 0) note("sweep", `swept ${swept} exhausted cranks`);
	save();
	return state.lastSweep;
}

async function watchdog() {
	if (!supportsRelay()) {
		state.lastWatchdog = { at: new Date().toISOString(), blocked: "no StartBlock instruction or crank_seq field yet" };
		save();
		return state.lastWatchdog;
	}
	const slot = BigInt(await ephemeral.getSlot().send());
	const blocksNow = (await allBlocks()).filter((block) => !block.missing && block.crankSeq !== null && block.crankSeq > 0n);
	const lives = await Promise.all(blocksNow.map((block) => crankAddressOf(block.id, block.crankSeq - 1n)));
	const holders = await readMany(ephemeral, lives);
	let maxOverdue = 0n;
	let resumed = 0;
	let stuck = 0;
	for (let index = 0; index < blocksNow.length; index++) {
		const block = blocksNow[index];
		const holder = holders[index];
		const live = holder && holder.owner === HYDRA_PROGRAM && readU64(holder.data, 80) > 0n;
		const overdue = slot > block.dueSlot ? slot - block.dueSlot : 0n;
		if (live && overdue > maxOverdue) maxOverdue = overdue;
		if (overdue <= WATCHDOG_SLOTS) continue;
		if (live) {
			stuck++;
			continue;
		}
		const fresh = (await allBlocksAt([block.id]))[0];
		if (!fresh || fresh.crankSeq !== block.crankSeq) continue;
		const recheck = (await readMany(ephemeral, [lives[index]]))[0];
		if (recheck && recheck.owner === HYDRA_PROGRAM && readU64(recheck.data, 80) > 0n) continue;
		try {
			await onEr(`resume block ${block.id}`, [await startBlockInstruction(block.id, block.crankSeq)]);
			resumed++;
			state.resumes.push({ at: new Date().toISOString(), block: block.id, overdue: overdue.toString(), phase: PHASES[block.phase] });
			note("watchdog", `RESUMED BLOCK ${block.id}: chain broken ${overdue} slots after its due slot, phase ${PHASES[block.phase]}`);
		} catch (error) {
			note("watchdog", `RESUME OF BLOCK ${block.id} REFUSED: ${error.message}`);
		}
	}
	if (stuck > 0) note("watchdog", `${stuck} blocks have a live crank more than ${WATCHDOG_SLOTS} slots overdue (cranker behind); worst ${maxOverdue} slots`);
	state.lastWatchdog = { at: new Date().toISOString(), slot: slot.toString(), maxOverdue: maxOverdue.toString(), resumed, stuck };
	save();
	return state.lastWatchdog;
}

async function resort() {
	const world = worldOf((await readCloned([await worldAddress()]))[0]);
	const forced = process.env.FORCE_RESORT === "1";
	const due = world.resortEvery > 0n && world.epoch > 0n && world.epoch % world.resortEvery === 0n && world.resortedEpoch < world.epoch;
	if (!forced && !due) return { skipped: "not due" };
	let blocksNow = await allBlocks();
	if (blocksNow.some((block) => block.missing || block.phase !== 0)) {
		note("resort", "due, waiting for every block to be Idle");
		return { skipped: "blocks busy" };
	}
	const resortKey = await addressOf(program.seeds.resort());
	if (!delegated(await read(baseRead, resortKey))) await onL1("delegate resort", [await program.delegateResort()]);
	await readCloned([resortKey]);
	if (world.resorting === 0) await onEr("resort begin", [await program.resortBegin(MEASURE, BigInt(world.placed))]);
	blocksNow = await allBlocks();
	const resortHolder = (await readCloned([resortKey]))[0];
	const rotation = readU64(resortHolder.data, accountOffsets(idl, "Resort").rotation);
	await inParallel(blocksNow, async (block) => {
		const holder = (await readMany(ephemeral, [await blockAddress(block.id)]))[0];
		if (readU64(holder.data, blockAt.rotation) === rotation) return;
		const members = block.members.slice(0, block.filled).map((member) => address(member));
		await onEr(`resort clear ${block.id}`, [await program.resortClear(block.id, members)]);
	});
	const memberKeys = blocksNow.flatMap((block) => block.members.filter(Boolean)).map((member) => address(member));
	const pets = (await readCloned(memberKeys)).map((holder, index) => petOf(memberKeys[index], holder));
	pets.sort((left, right) => {
		const difference = strengthOf(right) - strengthOf(left);
		if (difference !== 0n) return difference > 0n ? 1 : -1;
		if (left.blockId !== right.blockId) return left.blockId - right.blockId;
		return left.slot - right.slot;
	});
	for (let id = 0; id * SEATS < pets.length; id++) {
		const chosen = pets.slice(id * SEATS, id * SEATS + SEATS).map((pet) => address(pet.key));
		await onEr(`resort assign ${id}`, [await program.resortAssign(id, Math.max(id - 1, 0), 0n, chosen)]);
	}
	await onEr("resort finish", [await program.resortFinish()]);
	note("resort", `re-sorted ${pets.length} pets into ${Math.ceil(pets.length / SEATS)} blocks by ${["level", "power", "combat"][MEASURE]}`);
	if (supportsRelay()) await watchdog();
	return { resorted: pets.length };
}

async function status() {
	const config = await read(baseRead, await configAddress());
	const worldHolder = (await readMany(ephemeral, [await worldAddress()]))[0];
	const payer = (await readMany(ephemeral, [await vrfPayerAddress()]))[0];
	const blocksNow = await allBlocks();
	const phases = {};
	for (const block of blocksNow) {
		const name = block.missing ? "missing" : PHASES[block.phase] ?? `phase${block.phase}`;
		phases[name] = (phases[name] ?? 0) + 1;
	}
	const vrfPayer = await vrfPayerAddress();
	const { value: cranks } = await patiently(() => ephemeral.getProgramAccounts(HYDRA_PROGRAM, {
		encoding: "base64",
		dataSlice: { offset: 80, length: 8 },
		filters: [{ memcmp: { offset: 0n, bytes: vrfPayer, encoding: "base58" } }],
		withContext: true,
	}).send());
	const exhausted = cranks.filter((entry) => Buffer.from(entry.account.data[0], "base64").readBigUInt64LE(0) === 0n).length;
	const world = worldHolder ? worldOf(worldHolder) : null;
	const mint = await read(baseRead, await addressOf(program.seeds.mint()));
	const supply = mint ? readU64(mint.data, 36) : 0n;
	const placed = blocksNow.reduce((total, block) => total + (block.members?.filter(Boolean).length ?? 0), 0);
	const snapshot = {
		at: new Date().toISOString(),
		program: programAddress,
		config: config ? { blocks: readU32(config.data, configAt.blocks), pets: readU32(config.data, configAt.pets) } : null,
		blocks: { total: blocksNow.length, byPhase: phases },
		pets: { claimed: config ? readU32(config.data, configAt.pets) : 0, known: Object.keys(state.pets).length, placed, unplaced: (config ? readU32(config.data, configAt.pets) : 0) - placed },
		cranks: { live: cranks.length - exhausted, exhausted },
		vrfPayerLamports: payer ? payer.lamports.toString() : null,
		world: world ? { epoch: world.epoch.toString(), resorting: world.resorting, placed: world.placed, resortedEpoch: world.resortedEpoch.toString(), global: Object.fromEntries(Object.entries(world.global).map(([key, valueOf]) => [key, valueOf.toString()])) } : null,
		rounds: blocksNow.filter((block) => !block.missing).reduce((acc, block) => ({ ...acc, [`epoch ${block.epoch} round ${block.round}`]: (acc[`epoch ${block.epoch} round ${block.round}`] ?? 0) + 1 }), {}),
		hbrnSupply: supply.toString(),
		lastBlocks: state.lastBlocks ?? null,
		lastSweep: state.lastSweep ?? null,
		lastWatchdog: state.lastWatchdog ?? null,
		resumes: state.resumes.length,
		crankerLagSlots: state.lastWatchdog?.maxOverdue ?? null,
		relayInstructions: { startBlock: supportsRelay(), sweep: supportsSweep() },
		events: state.events.slice(-20),
	};
	writeFileSync(STATUS_PATH, json(snapshot));
	save();
	return snapshot;
}

async function run() {
	await bootstrap();
	for (;;) {
		const started = Date.now();
		for (const [name, work] of [["blocks", blocks], ["sweep", sweep], ["watchdog", watchdog], ["resort", resort], ["fund", bootstrap], ["status", status]]) {
			try {
				await work();
			} catch (error) {
				note("run", `${name} failed: ${error.message}`);
			}
		}
		save();
		await sleep(Math.max(0, TICK_SECONDS * 1000 - (Date.now() - started)));
	}
}

const stages = { bootstrap, blocks, sweep, watchdog, resort, status, run };
if (!stages[STAGE]) throw new Error(`unknown stage ${STAGE}`);
const outcome = await stages[STAGE]();
if (outcome !== undefined && STAGE !== "run") console.log(json(outcome));
