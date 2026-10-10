import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { address } from "@solana/kit";
import {
	DELEGATION_PROGRAM,
	HYDRA_PROGRAM,
	MAGIC_PROGRAM,
	MAGIC_VAULT,
	SYSTEM_PROGRAM,
	cluster,
	encoder,
	instructionDiscriminator,
	joined,
	json,
	keypairAt,
	pda,
	read,
	readU64,
	readonly,
	send,
	sleep,
	u64,
	writable,
	writableSigner,
} from "./hibernal.mjs";
import { crankAddress } from "./hydra.mjs";

const STAGE = process.env.STAGE ?? "open";
const CHAINS = Number(process.env.CHAINS ?? 1);
const FIRST_CHAIN = Number(process.env.FIRST_CHAIN ?? 0);
const MAX_HOPS = BigInt(process.env.MAX_HOPS ?? 20);
const GAP_SLOTS = BigInt(process.env.GAP_SLOTS ?? 100);
const COMPUTE_UNITS = BigInt(process.env.COMPUTE_UNITS ?? 200_000);
const SPONSOR_LAMPORTS = BigInt(process.env.SPONSOR_LAMPORTS ?? 1_000_000);
const PER_TRANSACTION = Number(process.env.PER_TRANSACTION ?? 3);
const PARALLEL = Number(process.env.PARALLEL ?? 16);
const CANCELS_PREVIOUS = process.env.CANCELS_PREVIOUS === "1";
const WATCH_MINUTES = Number(process.env.WATCH_MINUTES ?? 5);

const RELAY = { hops: 16, maxHops: 24, gapSlots: 32, dueSlot: 48, lateTotal: 56, lateMax: 64, firstSlot: 72, lastSlot: 80 };

const [programArgument] = process.argv.slice(2);
if (!programArgument) {
	console.log("usage: STAGE=open|start|watch node tools/chain/relayProbe.mjs <program id>");
	process.exit(2);
}
const programAddress = address(programArgument);
const STATE_PATH = `out/localnet/relayProbe-${programArgument}.json`;
const { base, baseRead, ephemeral, validator } = cluster();
const authority = await keypairAt(`${process.env.HOME}/.config/solana/id.json`);
const state = existsSync(STATE_PATH) ? JSON.parse(readFileSync(STATE_PATH, "utf8")) : { chains: {} };
const save = () => writeFileSync(STATE_PATH, json(state));
const chainIds = Array.from({ length: CHAINS }, (_, index) => FIRST_CHAIN + index);

function crankSeed(chain, hop) {
	return joined(u64(chain), u64(hop), new Uint8Array(16));
}

async function relayAddress(chain) {
	const [found] = await pda(programAddress, "relay", u64(chain));
	return found;
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

async function openInstruction(chain) {
	const relay = await relayAddress(chain);
	const [buffer] = await pda(programAddress, "buffer", encoder.encode(relay));
	const [record] = await pda(DELEGATION_PROGRAM, "delegation", encoder.encode(relay));
	const [metadata] = await pda(DELEGATION_PROGRAM, "delegation-metadata", encoder.encode(relay));
	return {
		programAddress,
		accounts: [
			writableSigner(authority),
			writable(relay),
			readonly(programAddress),
			writable(buffer),
			writable(record),
			writable(metadata),
			readonly(DELEGATION_PROGRAM),
			readonly(SYSTEM_PROGRAM),
		],
		data: joined(
			instructionDiscriminator("OpenRelay"),
			u64(chain),
			u64(MAX_HOPS),
			u64(GAP_SLOTS),
			u64(COMPUTE_UNITS),
			u64(SPONSOR_LAMPORTS),
			encoder.encode(validator),
			Uint8Array.of(CANCELS_PREVIOUS ? 1 : 0),
		),
	};
}

async function hopInstruction(chain, hop) {
	return {
		programAddress,
		accounts: [
			writable(await relayAddress(chain)),
			readonly(await crankAddress(crankSeed(chain, hop))),
			writable(await crankAddress(crankSeed(chain, hop + 1n))),
			writable(MAGIC_VAULT),
			readonly(MAGIC_PROGRAM),
			readonly(HYDRA_PROGRAM),
		],
		data: joined(instructionDiscriminator("Hop"), u64(hop)),
	};
}

async function open() {
	const pending = [];
	for (const chain of chainIds) {
		if (!(await read(baseRead, await relayAddress(chain)))) pending.push(chain);
	}
	const batches = [];
	for (let index = 0; index < pending.length; index += PER_TRANSACTION) batches.push(pending.slice(index, index + PER_TRANSACTION));
	const started = Date.now();
	const units = [];
	await inParallel(batches, async (batch) => {
		const sent = await send(base, baseRead, `open ${batch.join(",")}`, await Promise.all(batch.map(openInstruction)), authority, 1_400_000, false);
		units.push(sent.elapsed);
	});
	for (const chain of pending) state.chains[chain] = { maxHops: MAX_HOPS, gapSlots: GAP_SLOTS };
	save();
	console.log(`opened ${pending.length} relays in ${batches.length} transactions, ${((Date.now() - started) / 1000).toFixed(1)} s`);
}

async function relayState(chain) {
	const holder = await read(ephemeral, await relayAddress(chain));
	if (!holder) return null;
	const field = (name) => readU64(holder.data, RELAY[name]);
	return {
		lamports: holder.lamports,
		hops: field("hops"),
		maxHops: field("maxHops"),
		gapSlots: field("gapSlots"),
		dueSlot: field("dueSlot"),
		lateTotal: field("lateTotal"),
		lateMax: field("lateMax"),
		firstSlot: field("firstSlot"),
		lastSlot: field("lastSlot"),
	};
}

async function start() {
	const units = [];
	const started = Date.now();
	await inParallel(chainIds, async (chain) => {
		let relay = null;
		for (let attempt = 0; attempt < 30 && !relay; attempt++) {
			relay = await relayState(chain);
			if (!relay) await sleep(1000);
		}
		if (!relay) throw new Error(`relay ${chain} never appeared in the ER`);
		state.chains[chain] = { ...state.chains[chain], lamportsBefore: relay.lamports };
		const sent = await send(ephemeral, ephemeral, `hop 0 of ${chain}`, [await hopInstruction(chain, 0n)], authority, Number(COMPUTE_UNITS), CHAINS <= 4);
		units.push(sent.units);
		if (CHAINS <= 4) console.log(`chain ${chain} hop 0: ${sent.units} CU\n${sent.logs.filter((line) => line.includes("consumed") || line.includes("Created ephemeral")).join("\n")}`);
	});
	save();
	console.log(`started ${chainIds.length} chains in ${((Date.now() - started) / 1000).toFixed(1)} s`);
}

async function watch() {
	const until = Date.now() + WATCH_MINUTES * 60_000;
	let relays = [];
	while (Date.now() < until) {
		relays = [];
		await inParallel(chainIds, async (chain) => relays.push({ chain, ...(await relayState(chain)) }));
		const done = relays.filter((relay) => relay.hops >= relay.maxHops).length;
		const hops = relays.reduce((total, relay) => total + Number(relay.hops), 0);
		console.log(`${new Date().toISOString()} chains done ${done}/${relays.length}, hops ${hops}`);
		if (done === relays.length) break;
		await sleep(5000);
	}
	const lateMax = relays.reduce((most, relay) => Math.max(most, Number(relay.lateMax)), 0);
	const lateSum = relays.reduce((total, relay) => total + Number(relay.lateTotal), 0);
	const lateCount = relays.reduce((total, relay) => total + Math.max(0, Number(relay.hops) - 1), 0);
	console.log(`late after due: mean ${(lateSum / Math.max(1, lateCount)).toFixed(2)} slots, max ${lateMax} slots over ${lateCount} scheduled hops`);
	const sample = relays.slice(0, Math.min(3, relays.length));
	for (const relay of sample) {
		const before = BigInt(state.chains[relay.chain]?.lamportsBefore ?? 0);
		let open = 0;
		for (let hop = 1n; hop < relay.maxHops; hop++) {
			if (await read(ephemeral, await crankAddress(crankSeed(relay.chain, hop)))) open++;
		}
		console.log(`chain ${relay.chain}: hops ${relay.hops}/${relay.maxHops}, slots ${relay.firstSlot}..${relay.lastSlot} (${relay.lastSlot - relay.firstSlot}, ideal ${(relay.maxHops - 1n) * relay.gapSlots}), lamports ${before} -> ${relay.lamports} (${relay.lamports - before}), cranks still open ${open}`);
	}
	const relayKey = await relayAddress(sample[0].chain);
	const signatures = await ephemeral.getSignaturesForAddress(relayKey, { limit: 3 }).send();
	for (const entry of signatures) {
		const found = await ephemeral.getTransaction(entry.signature, { maxSupportedTransactionVersion: 0, encoding: "json" }).send();
		const lines = (found?.meta?.logMessages ?? []).filter((line) => line.includes("consumed") || line.includes("Created ephemeral") || line.includes("Closed ephemeral") || line.includes("failed"));
		console.log(`  ${entry.signature.slice(0, 16)} err ${json(entry.err)} CU ${found?.meta?.computeUnitsConsumed}\n    ${lines.join("\n    ")}`);
	}
}

const stages = { open, start, watch };
if (!stages[STAGE]) throw new Error(`unknown stage ${STAGE}`);
await stages[STAGE]();
