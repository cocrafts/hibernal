import { address, appendTransactionMessageInstructions, createSolanaRpcSubscriptions, createTransactionMessage, getBase58Decoder, getBase64EncodedWireTransaction, pipe, setTransactionMessageFeePayerSigner, setTransactionMessageLifetimeUsingBlockhash, signTransactionMessageWithSigners } from "@solana/kit";
import {
	HYDRA_PROGRAM,
	INSTRUCTIONS_SYSVAR,
	accountDiscriminator,
	accountOffsets,
	cluster,
	computeLimit,
	hibernal,
	idlAt,
	keypairAt,
	readU32,
	readU64,
	readonly,
	sleep,
	writable,
	writableSigner,
} from "./hibernal.mjs";

const TICK_MS = Number(process.env.TICK_MS ?? 50);
const RESYNC_SECONDS = Number(process.env.RESYNC_SECONDS ?? 60);
const RETRY_SLOTS = BigInt(process.env.RETRY_SLOTS ?? 300);
const MAX_BACKOFF_SLOTS = BigInt(process.env.MAX_BACKOFF_SLOTS ?? 3000);
const MAX_IN_FLIGHT = Number(process.env.MAX_IN_FLIGHT ?? 512);
const REPORT_SECONDS = Number(process.env.REPORT_SECONDS ?? 10);
const FREEZE_SECONDS = Number(process.env.FREEZE_SECONDS ?? 10);
const UNFREEZE_BURST = Number(process.env.UNFREEZE_BURST ?? 4);
const CRANK_HEADER = 120;
const REMAINING_OFFSET = 80;
const CU_LIMIT_OFFSET = 115;
const META_WRITABLE = 2;

const programs = (process.env.PROGRAMS ?? process.argv[2] ?? "").split(",").filter(Boolean);
if (programs.length === 0) {
	console.log("usage: [PROGRAMS=a,b] node tools/chain/gameCranker.mjs <program>[,<program>…]  (ER_RPC, ER_WS, BASE_RPC from env; CRANKER keypair)");
	process.exit(2);
}
const { baseRead, ephemeral } = cluster();
const erWs = process.env.ER_WS ?? (process.env.ER_RPC ?? "https://devnet-as.magicblock.app").replace(/^http/, "ws").replace(/:(\d+)$/, (_, port) => `:${Number(port) + 1}`);
const cranker = await keypairAt(process.env.CRANKER ?? `${process.env.HOME}/.config/solana/id.json`);
const authority = await keypairAt(`${process.env.HOME}/.config/solana/id.json`);
const idl = idlAt();
const blockAt = accountOffsets(idl, "Block");
const configAt = accountOffsets(idl, "Config");
const decoder = getBase58Decoder();
const programsByKey = new Map(programs.map((programAddress) => [programAddress, hibernal(address(programAddress), authority)]));

const blocks = new Map();
const inFlight = new Map();
const crankKeys = new Map();
const stats = { sent: 0, retried: 0, failedSends: 0, skippedSpent: 0, refreshed: 0, notifications: 0, resyncs: 0, maxLag: 0n, unfreezeBursts: 0, unfreezeSent: 0 };
const erClock = { slot: null, since: Date.now(), burstAt: Date.now() };
let slot = 0n;
let slotMillis = 0n;
let blockhash = null;
let sending = 0;

function blockFrom(program, key, data) {
	return {
		program,
		key,
		id: readU32(data, blockAt.id),
		crankSeq: readU64(data, blockAt.crank_seq),
		dueSlot: readU64(data, blockAt.due_slot),
	};
}

async function crankOf(program, block) {
	const known = crankKeys.get(block.key);
	if (known && known.seq === block.crankSeq) return known.crank;
	const crank = await program.crankOf(block.id, block.crankSeq - 1n);
	crankKeys.set(block.key, { seq: block.crankSeq, crank });
	return crank;
}

async function readMany(keys) {
	const out = [];
	for (let start = 0; start < keys.length; start += 100) {
		const { value } = await ephemeral.getMultipleAccounts(keys.slice(start, start + 100), { encoding: "base64" }).send();
		out.push(...value.map((entry) => (entry ? { owner: entry.owner, data: new Uint8Array(Buffer.from(entry.data[0], "base64")) } : null)));
	}
	return out;
}

async function resync() {
	for (const programAddress of programs) {
		const program = programsByKey.get(programAddress);
		const config = await baseRead.getAccountInfo(await program.address(program.seeds.config()), { encoding: "base64" }).send();
		if (!config.value) continue;
		const configData = new Uint8Array(Buffer.from(config.value.data[0], "base64"));
		const count = readU32(configData, configAt.blocks);
		slotMillis = readU64(configData, configAt.slot_millis);
		const keys = await Promise.all(Array.from({ length: count }, (_, id) => program.address(program.seeds.block(id))));
		const holders = await readMany(keys);
		holders.forEach((holder, id) => {
			if (!holder || holder.owner !== programAddress) return;
			blocks.set(keys[id], blockFrom(programAddress, keys[id], holder.data));
		});
	}
	stats.resyncs++;
}

async function watchBlocks() {
	const subscriptions = createSolanaRpcSubscriptions(erWs);
	const discriminator = decoder.decode(accountDiscriminator("Block"));
	for (const programAddress of programs) {
		const stream = await subscriptions.programNotifications(address(programAddress), {
			encoding: "base64",
			commitment: "processed",
			filters: [{ memcmp: { offset: 0n, bytes: discriminator, encoding: "base58" } }],
		}).subscribe({ abortSignal: new AbortController().signal });
		(async () => {
			for await (const note of stream) {
				stats.notifications++;
				const data = new Uint8Array(Buffer.from(note.value.account.data[0], "base64"));
				const block = blockFrom(programAddress, note.value.pubkey, data);
				const known = blocks.get(block.key);
				if (!known || block.crankSeq >= known.crankSeq) blocks.set(block.key, block);
			}
		})().catch((error) => console.error(`block stream for ${programAddress} ended: ${error.message}`));
	}
	const slots = await subscriptions.slotNotifications().subscribe({ abortSignal: new AbortController().signal });
	(async () => {
		for await (const note of slots) slot = BigInt(note.slot);
	})().catch((error) => console.error(`slot stream ended: ${error.message}`));
}

function scheduledFrom(data) {
	const tail = data.subarray(CRANK_HEADER);
	const view = new DataView(tail.buffer, tail.byteOffset, tail.byteLength);
	const instructions = [];
	let offset = 0;
	while (offset < tail.length) {
		const count = view.getUint16(offset, true);
		const metasStart = offset + 2;
		const metasEnd = metasStart + count * 33;
		const programAddress = decoder.decode(tail.subarray(metasEnd, metasEnd + 32));
		const length = view.getUint16(metasEnd + 32, true);
		const accounts = [];
		for (let index = 0; index < count; index++) {
			const base = metasStart + index * 33;
			const key = decoder.decode(tail.subarray(base + 1, base + 33));
			accounts.push((tail[base] & META_WRITABLE) !== 0 ? writable(key) : readonly(key));
		}
		instructions.push({ programAddress, accounts, data: tail.slice(metasEnd + 34, metasEnd + 34 + length) });
		offset = metasEnd + 34 + length;
	}
	return instructions;
}

async function fire(crank, data) {
	const cuLimit = new DataView(data.buffer, data.byteOffset).getUint32(CU_LIMIT_OFFSET, true);
	const trigger = { programAddress: HYDRA_PROGRAM, accounts: [writable(crank), writableSigner(cranker), readonly(INSTRUCTIONS_SYSVAR)], data: Uint8Array.of(1) };
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(cranker, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstructions([...(cuLimit > 0 ? [computeLimit(cuLimit)] : []), trigger, ...scheduledFrom(data)], m),
	);
	const signed = await signTransactionMessageWithSigners(message);
	await ephemeral.sendTransaction(getBase64EncodedWireTransaction(signed), { encoding: "base64", skipPreflight: true }).send();
}

async function tick() {
	const due = [];
	let lag = 0n;
	for (const block of blocks.values()) {
		if (block.crankSeq === 0n || block.dueSlot > slot) continue;
		if (slot - block.dueSlot > lag) lag = slot - block.dueSlot;
		const pending = inFlight.get(block.key);
		if (pending && pending.seq === block.crankSeq && slot < pending.retryAt) continue;
		due.push(block);
	}
	if (lag > stats.maxLag) stats.maxLag = lag;
	if (due.length === 0 || !blockhash) return;
	const room = Math.max(0, MAX_IN_FLIGHT - sending);
	const batch = due.slice(0, room);
	const cranks = await Promise.all(batch.map((block) => crankOf(programsByKey.get(block.program), block)));
	const holders = await readMany(cranks);
	const stale = [];
	batch.forEach((block, index) => {
		const holder = holders[index];
		const pending = inFlight.get(block.key);
		const attempts = pending && pending.seq === block.crankSeq ? pending.attempts + 1 : 1;
		const wait = RETRY_SLOTS * BigInt(Math.min(2 ** (attempts - 1), Number(MAX_BACKOFF_SLOTS / RETRY_SLOTS)));
		inFlight.set(block.key, { seq: block.crankSeq, attempts, retryAt: slot + wait });
		if (!holder || holder.owner !== HYDRA_PROGRAM || readU64(holder.data, REMAINING_OFFSET) === 0n) {
			stats.skippedSpent++;
			stale.push(block);
			return;
		}
		if (attempts > 1) stats.retried++;
		sending++;
		fire(cranks[index], holder.data)
			.then(() => { stats.sent++; })
			.catch(() => { stats.failedSends++; })
			.finally(() => { sending--; });
	});
	if (stale.length > 0) await refreshed(stale);
}

async function refreshed(stale) {
	const holders = await readMany(stale.map((block) => block.key));
	holders.forEach((holder, index) => {
		if (!holder) return;
		const fresh = blockFrom(stale[index].program, stale[index].key, holder.data);
		const known = blocks.get(fresh.key);
		if (!known || fresh.crankSeq >= known.crankSeq) blocks.set(fresh.key, fresh);
		if (fresh.crankSeq !== stale[index].crankSeq) inFlight.delete(fresh.key);
	});
	stats.refreshed += stale.length;
}

async function refreshBlockhash() {
	for (;;) {
		try {
			const { value } = await ephemeral.getLatestBlockhash().send();
			blockhash = value;
			const polledSlot = BigInt(await ephemeral.getSlot().send());
			if (polledSlot > slot) slot = polledSlot;
			await unfrozen(polledSlot, Date.now());
		} catch (error) {
			console.error(`blockhash: ${error.message}`);
		}
		await sleep(1000);
	}
}

// MagicBlock RPC freezes its slot until it sees transactions (magicblock-validator#1783);
// the frozen blockhash stays accepted. Remove once a release with the fix is deployed.
async function unfrozen(polledSlot, now) {
	if (erClock.slot !== polledSlot) {
		erClock.slot = polledSlot;
		erClock.since = now;
		erClock.burstAt = now;
		return;
	}
	if (slotMillis > 0n) {
		const estimate = polledSlot + BigInt(now - erClock.since) / slotMillis;
		if (estimate > slot) slot = estimate;
	}
	if (now - erClock.burstAt < FREEZE_SECONDS * 1000) return;
	erClock.burstAt = now;
	stats.unfreezeBursts++;
	console.error(`${new Date(now).toISOString()} ER slot frozen at ${polledSlot} for ${Math.round((now - erClock.since) / 1000)} s, sending ${UNFREEZE_BURST} transactions`);
	await Promise.all(Array.from({ length: UNFREEZE_BURST }, () => nudge(1_000 + (stats.unfreezeSent++ % 1_000_000))));
}

async function nudge(units) {
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(cranker, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstructions([computeLimit(units)], m),
	);
	const signed = await signTransactionMessageWithSigners(message);
	await ephemeral.sendTransaction(getBase64EncodedWireTransaction(signed), { encoding: "base64", skipPreflight: true }).send().catch(() => { stats.failedSends++; });
}

async function report() {
	let last = { ...stats };
	for (;;) {
		await sleep(REPORT_SECONDS * 1000);
		const rate = (stats.sent - last.sent) / REPORT_SECONDS;
		console.log(`${new Date().toISOString()} blocks ${blocks.size} slot ${slot} sent ${stats.sent} (${rate.toFixed(0)}/s) retried ${stats.retried} spent-skipped ${stats.skippedSpent} failed-sends ${stats.failedSends} in-flight ${sending} max-lag ${stats.maxLag} notifications ${stats.notifications} unfreeze-bursts ${stats.unfreezeBursts}`);
		stats.maxLag = 0n;
		last = { ...stats };
	}
}

async function resyncLoop() {
	for (;;) {
		await sleep(RESYNC_SECONDS * 1000);
		try {
			await resync();
		} catch (error) {
			console.error(`resync: ${error.message}`);
		}
	}
}

console.log(`gameCranker: cranker ${cranker.address}, programs ${programs.join(", ")}, ER ${process.env.ER_RPC} / ${erWs}`);
await resync();
console.log(`gameCranker: ${blocks.size} blocks loaded`);
await watchBlocks();
refreshBlockhash();
report();
resyncLoop();
for (;;) {
	try {
		await tick();
	} catch (error) {
		console.error(`tick: ${error.message}`);
	}
	await sleep(TICK_MS);
}
