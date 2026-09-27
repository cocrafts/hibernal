import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { generateKeyPairSync } from "node:crypto";
import {
	AccountRole,
	address,
	appendTransactionMessageInstructions,
	createKeyPairSignerFromBytes,
	createSolanaRpc,
	createTransactionMessage,
	getAddressEncoder,
	getBase64EncodedWireTransaction,
	getProgramDerivedAddress,
	getSignatureFromTransaction,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";

const BASE_RPC = process.env.BASE_RPC ?? "https://api.devnet.solana.com";
const BASE_READ_RPC = process.env.BASE_READ_RPC ?? BASE_RPC;
const ER_RPC = process.env.ER_RPC ?? "https://devnet-as.magicblock.app";
const VALIDATOR = address(process.env.VALIDATOR ?? "MAS1Dt9qreoRMQ14YQuhg8UTZMMzDdKhmkZMECCzk57");
const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const DELEGATION_PROGRAM = address("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
const MAGIC_PROGRAM = address("Magic11111111111111111111111111111111111111");
const MAGIC_CONTEXT = address("MagicContext1111111111111111111111111111111");
const WALLET_LAMPORTS = 6_000_000n;
const SWEEP_FEE_LAMPORTS = 5_000n;
const TRANSFERS_PER_TRANSACTION = 12;
const SCHEDULES_PER_TRANSACTION = 5;
const SENDS_AT_ONCE = 4;
const MANY = Number(process.env.MANY ?? 50);
const INTERVAL_MS = BigInt(process.env.INTERVAL_MS ?? 2000);
const ITERATIONS = BigInt(process.env.ITERATIONS ?? 10);
const LONG = (process.env.LONG ?? "3600000x3x3,21600000x3x2").split(",").filter(Boolean).map((entry) => {
	const [interval, iterations, count] = entry.split("x").map(BigInt);
	return { interval, iterations, count: Number(count) };
});
const LONG_COUNT = LONG.reduce((sum, group) => sum + group.count, 0);
const WALLETS = MANY + LONG_COUNT;

const [programArgument, mode] = process.argv.slice(2);
if (!programArgument || !["many", "long", "observe", "teardown"].includes(mode)) {
	console.log("usage: node tools/chain/crankDevnet.mjs <fight probe program id> many|long|observe|teardown");
	process.exit(2);
}
const PROGRAM = address(programArgument);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const json = (value) => JSON.stringify(value, (_, inner) => typeof inner === "bigint" ? inner.toString() : inner);
const addressEncoder = getAddressEncoder();
const keyBytes = (path) => Uint8Array.from(JSON.parse(readFileSync(path, "utf8")));
const payer = await createKeyPairSignerFromBytes(keyBytes(`${process.env.HOME}/.config/solana/id.json`));
const walletsPath = new URL("../../out/crankWallets.json", import.meta.url);
const longPath = new URL("../../out/crankLong.json", import.meta.url);
const stored = existsSync(walletsPath) ? JSON.parse(readFileSync(walletsPath, "utf8")) : [];
while (stored.length < WALLETS) {
	const { privateKey, publicKey } = generateKeyPairSync("ed25519");
	stored.push([...privateKey.export({ format: "der", type: "pkcs8" }).subarray(-32), ...publicKey.export({ format: "der", type: "spki" }).subarray(-32)]);
}
writeFileSync(walletsPath, JSON.stringify(stored));
const base = createSolanaRpc(BASE_RPC);
const baseRead = createSolanaRpc(BASE_READ_RPC);
const ephemeral = createSolanaRpc(ER_RPC);

async function arenaOf(owner, index) {
	const [key] = await getProgramDerivedAddress({ programAddress: PROGRAM, seeds: ["arena", addressEncoder.encode(owner.address)] });
	const bytes = addressEncoder.encode(key);
	const [buffer] = await getProgramDerivedAddress({ programAddress: PROGRAM, seeds: ["buffer", bytes] });
	const [record] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation", bytes] });
	const [metadata] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation-metadata", bytes] });
	return { index, owner, key, buffer, record, metadata };
}

const arenas = [];
for (const [index, secret] of stored.slice(0, WALLETS).entries()) {
	arenas.push(await arenaOf(await createKeyPairSignerFromBytes(Uint8Array.from(secret)), index));
}
const signer = (who) => ({ address: who.address, role: AccountRole.WRITABLE_SIGNER, signer: who });
const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });
const program = (accounts, data) => ({ programAddress: PROGRAM, accounts, data });

function words(...values) {
	const bytes = new Uint8Array(8 * values.length);
	const view = new DataView(bytes.buffer);
	values.forEach((value, index) => view.setBigUint64(8 * index, BigInt(value), true));
	return bytes;
}

function transferInstruction(from, to, lamports) {
	const bytes = new Uint8Array(12);
	const view = new DataView(bytes.buffer);
	view.setUint32(0, 2, true);
	view.setBigUint64(4, lamports, true);
	return { programAddress: SYSTEM_PROGRAM, accounts: [signer(from), writable(to)], data: bytes };
}

const initialized = (arena) => program([signer(arena.owner), writable(arena.key), readonly(SYSTEM_PROGRAM)], words(0));
const delegated = (arena) => program([
	signer(arena.owner),
	readonly(SYSTEM_PROGRAM),
	writable(arena.key),
	readonly(PROGRAM),
	writable(arena.buffer),
	writable(arena.record),
	writable(arena.metadata),
	readonly(DELEGATION_PROGRAM),
	readonly(VALIDATOR),
], words(2));
const scheduled = (arena, taskId, interval, iterations) => program([signer(payer), writable(arena.key), readonly(MAGIC_PROGRAM)], words(7, taskId, interval, iterations, 8));
const returned = (arena) => program([signer(payer), writable(arena.key), readonly(MAGIC_PROGRAM), writable(MAGIC_CONTEXT)], words(3));

async function patiently(call) {
	for (let attempt = 1; ; attempt++) {
		try {
			return await call();
		} catch (error) {
			if (attempt >= 10) throw error;
			await sleep(1500 * attempt);
		}
	}
}

async function send(rpc, step, instructions) {
	const { value: blockhash } = await patiently(() => rpc.getLatestBlockhash().send());
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(payer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstructions(instructions, m),
	);
	const transaction = await signTransactionMessageWithSigners(message);
	const signature = getSignatureFromTransaction(transaction);
	await patiently(() => rpc.sendTransaction(getBase64EncodedWireTransaction(transaction), { encoding: "base64", skipPreflight: true }).send());
	for (let attempt = 0; attempt < 120; attempt++) {
		const { value } = await patiently(() => rpc.getSignatureStatuses([signature]).send());
		const status = value[0];
		if (status && (status.confirmationStatus === "confirmed" || status.confirmationStatus === "finalized")) {
			if (status.err) throw new Error(`${step} failed: ${json(status.err)} ${signature}`);
			return signature;
		}
		await sleep(500);
	}
	throw new Error(`${step}: not confirmed ${signature}`);
}

async function inBatches(items, size, work) {
	for (let start = 0; start < items.length; start += size) {
		await Promise.all(items.slice(start, start + size).map(work));
	}
}

async function statesOf(rpc, keys) {
	const states = [];
	for (let start = 0; start < keys.length; start += 100) {
		const { value } = await patiently(() => rpc.getMultipleAccounts(keys.slice(start, start + 100), { encoding: "base64", commitment: "confirmed" }).send());
		for (const account of value) {
			const bytes = account ? Buffer.from(account.data[0], "base64") : null;
			states.push(account ? { owner: account.owner, fights: bytes.length >= 8 ? bytes.readBigUInt64LE(0) : 0n, slot: bytes.length >= 16 ? bytes.readBigUInt64LE(8) : 0n, mode: bytes[40] } : null);
		}
	}
	return states;
}

async function balances(owners) {
	const found = [];
	for (const owner of owners) found.push((await patiently(() => base.getBalance(owner).send())).value);
	return found;
}

async function readied(chosen) {
	const onBase = await statesOf(baseRead, chosen.map((arena) => arena.key));
	const missing = chosen.filter((_, position) => onBase[position] === null || onBase[position].owner === SYSTEM_PROGRAM);
	const undelegated = chosen.filter((_, position) => onBase[position]?.owner === PROGRAM);
	if (missing.length > 0) {
		const owed = (await balances(missing.map((arena) => arena.owner.address))).map((lamports, position) => ({ arena: missing[position], lamports: lamports < WALLET_LAMPORTS ? WALLET_LAMPORTS - lamports : 0n })).filter((entry) => entry.lamports > 0n);
		for (let start = 0; start < owed.length; start += TRANSFERS_PER_TRANSACTION) {
			const batch = owed.slice(start, start + TRANSFERS_PER_TRANSACTION);
			await send(base, `fund ${batch.length} wallets`, batch.map((entry) => transferInstruction(payer, entry.arena.owner.address, entry.lamports)));
		}
		console.log(`funded ${owed.length} wallets with ${WALLET_LAMPORTS} lamports each`);
	}
	await inBatches(missing, SENDS_AT_ONCE, (arena) => send(base, `init and delegate ${arena.index}`, [initialized(arena), delegated(arena)]));
	await inBatches(undelegated, SENDS_AT_ONCE, (arena) => send(base, `delegate ${arena.index}`, [delegated(arena)]));
	console.log(`${missing.length} arenas created and delegated, ${undelegated.length} delegated, ${chosen.length - missing.length - undelegated.length} already delegated`);
	const started = Date.now();
	while (Date.now() - started < 120000) {
		const inEr = await statesOf(ephemeral, chosen.map((arena) => arena.key));
		if (inEr.every((state) => state?.owner === PROGRAM)) return inEr;
		await sleep(1000);
	}
	throw new Error("arenas not visible in the ER after 120 s");
}

async function executionsOf(arena, since) {
	const found = [];
	let before;
	for (;;) {
		const page = await patiently(() => ephemeral.getSignaturesForAddress(arena.key, { limit: 1000, ...(before ? { before } : {}) }).send());
		for (const entry of page) {
			if (Number(entry.slot) < since) return found;
			found.push({ signature: entry.signature, slot: Number(entry.slot), blockTime: Number(entry.blockTime), err: entry.err });
		}
		if (page.length < 1000) return found;
		before = page[page.length - 1].signature;
	}
}

async function crankTransaction(signature) {
	for (let attempt = 0; attempt < 10; attempt++) {
		const found = await ephemeral.getTransaction(signature, { maxSupportedTransactionVersion: 0, commitment: "confirmed", encoding: "json" }).send().catch(() => null);
		if (found) return found;
		await sleep(1000);
	}
	return null;
}

function spread(values) {
	if (values.length === 0) return "none";
	const sorted = [...values].sort((left, right) => left - right);
	const at = (share) => sorted[Math.min(sorted.length - 1, Math.floor(share * sorted.length))];
	return `min ${sorted[0]} p50 ${at(0.5)} p90 ${at(0.9)} max ${sorted[sorted.length - 1]} (n ${sorted.length})`;
}

async function slotMillis() {
	const firstSlot = Number((await ephemeral.getSlot().send()));
	const firstAt = Date.now();
	await sleep(5000);
	const secondSlot = Number((await ephemeral.getSlot().send()));
	return (Date.now() - firstAt) / (secondSlot - firstSlot);
}

async function erBalance() {
	return (await patiently(() => ephemeral.getBalance(payer.address).send())).value;
}

async function many() {
	const chosen = arenas.slice(0, MANY);
	const before = await readied(chosen);
	const perSlot = await slotMillis();
	const expected = MANY * Number(ITERATIONS);
	const runId = BigInt(Date.now());
	const payerBefore = await erBalance();
	const startSlot = Number(await ephemeral.getSlot().send());
	const observed = chosen.map(() => []);
	const last = before.map((state) => state.fights);
	const scheduleStarted = Date.now();
	const groups = [];
	for (let start = 0; start < chosen.length; start += SCHEDULES_PER_TRANSACTION) groups.push(chosen.slice(start, start + SCHEDULES_PER_TRANSACTION));
	const schedules = new Set(await Promise.all(groups.map((group) => send(ephemeral, `schedule ${group[0].index}..${group[group.length - 1].index}`, group.map((arena) => scheduled(arena, runId + BigInt(arena.index), INTERVAL_MS, ITERATIONS))))));
	const scheduledIn = Date.now() - scheduleStarted;
	console.log(`${MANY} tasks of ${ITERATIONS} × ${INTERVAL_MS} ms scheduled in ${scheduledIn} ms (${groups.length} transactions of ${SCHEDULES_PER_TRANSACTION}); ER slot ${perSlot.toFixed(1)} ms`);
	const deadline = scheduleStarted + Number(INTERVAL_MS) * (Number(ITERATIONS) + 5) + 20000;
	let total = 0;
	while (Date.now() < deadline && total < expected) {
		const states = await statesOf(ephemeral, chosen.map((arena) => arena.key));
		const now = Date.now() - scheduleStarted;
		states.forEach((state, position) => {
			for (let fight = last[position]; fight < state.fights; fight++) observed[position].push(now);
			last[position] = state.fights;
		});
		total = observed.reduce((sum, times) => sum + times.length, 0);
		await sleep(200);
	}
	console.log(`observed ${total}/${expected} executions by polling, ${(Date.now() - scheduleStarted) / 1000} s after scheduling`);
	const records = [];
	for (const arena of chosen) {
		const history = (await executionsOf(arena, startSlot)).reverse();
		const schedule = history.find((entry) => schedules.has(entry.signature));
		const executions = history.filter((entry) => !schedules.has(entry.signature) && !entry.err);
		records.push({ arena, scheduleSlot: schedule?.slot, executions, failed: history.filter((entry) => entry.err).length });
	}
	const cranked = records.map((record) => record.executions);
	const count = cranked.reduce((sum, list) => sum + list.length, 0);
	const firsts = records.filter((record) => record.executions.length > 0 && record.scheduleSlot !== undefined).map((record) => Math.round((record.executions[0].slot - record.scheduleSlot) * perSlot));
	const gaps = cranked.flatMap((list) => list.slice(1).map((entry, index) => Math.round((entry.slot - list[index].slot) * perSlot)));
	const perTask = cranked.map((list) => list.length);
	const sameSlot = new Map();
	for (const list of cranked) for (const entry of list) sameSlot.set(entry.slot, (sameSlot.get(entry.slot) ?? 0) + 1);
	console.log(`ER history: ${count}/${expected} crank executions, ${records.reduce((sum, record) => sum + record.failed, 0)} failed, per task ${spread(perTask)}`);
	console.log(`  first execution after the schedule transaction (ms, from slots): ${spread(firsts)}`);
	console.log(`  gap between one task's executions (ms, from slots, target ${INTERVAL_MS}): ${spread(gaps)}`);
	console.log(`  executions per slot: ${spread([...sameSlot.values()])} over ${sameSlot.size} slots`);
	console.log(`  polled gaps (ms): ${spread(observed.flatMap((times) => times.slice(1).map((time, index) => time - times[index])))}`);
	const sample = cranked.find((list) => list.length > 0)?.[0];
	if (sample) {
		const detail = await crankTransaction(sample.signature);
		const keys = detail?.transaction?.message?.accountKeys ?? [];
		console.log(`  a crank transaction: fee payer ${keys[0]}, ${detail?.transaction?.signatures?.length} signature(s), fee ${detail?.meta?.fee}, ${detail?.meta?.computeUnitsConsumed} CU, accounts ${keys.join(" ")}`);
	}
	const payerAfter = await erBalance();
	console.log(`  payer balance in the ER ${payerBefore} → ${payerAfter} (${payerAfter - payerBefore})`);
}

async function long() {
	const chosen = arenas.slice(MANY, MANY + LONG_COUNT);
	await readied(chosen);
	const runId = BigInt(Date.now());
	const startSlot = Number(await ephemeral.getSlot().send());
	const plan = [];
	let offset = 0;
	for (const group of LONG) {
		for (const arena of chosen.slice(offset, offset + group.count)) {
			const taskId = runId + BigInt(arena.index);
			const signature = await send(ephemeral, `schedule ${arena.index}`, [scheduled(arena, taskId, group.interval, group.iterations)]);
			plan.push({ index: arena.index, arena: arena.key, taskId: taskId.toString(), interval: Number(group.interval), iterations: Number(group.iterations), scheduledAt: Date.now(), signature });
		}
		offset += group.count;
	}
	writeFileSync(longPath, JSON.stringify({ startSlot, scheduledAt: Date.now(), plan }, null, 1));
	console.log(`scheduled ${plan.length} long tasks from slot ${startSlot}: ${LONG.map((group) => `${group.count} × (${group.iterations} × ${group.interval} ms)`).join(", ")}; plan in out/crankLong.json`);
}

async function observe() {
	const { startSlot, plan } = JSON.parse(readFileSync(longPath, "utf8"));
	const now = Date.now();
	for (const entry of plan) {
		const arena = arenas[entry.index];
		const history = (await executionsOf(arena, startSlot)).reverse();
		const scheduleAt = history.findIndex((item) => item.signature === entry.signature);
		const schedule = history[scheduleAt];
		const cranked = scheduleAt < 0 ? [] : history.slice(scheduleAt + 1).filter((item) => !item.err);
		const offsets = cranked.map((item) => item.blockTime - schedule.blockTime);
		const due = Math.min(entry.iterations, 1 + Math.floor((now - entry.scheduledAt) / entry.interval));
		console.log(`arena ${entry.index} every ${entry.interval / 60000} min × ${entry.iterations}: ${cranked.length} executions, ${due} due by now, at +${offsets.join(" s, +")} s after the schedule transaction, ${history.filter((item) => item.err).length} failed`);
	}
	console.log(`observed ${Math.round((now - Math.min(...plan.map((entry) => entry.scheduledAt))) / 60000)} min after the first schedule`);
}

async function teardown() {
	const inEr = await statesOf(ephemeral, arenas.map((arena) => arena.key));
	const onBase = await statesOf(baseRead, arenas.map((arena) => arena.key));
	const held = arenas.filter((_, position) => onBase[position]?.owner === DELEGATION_PROGRAM && inEr[position]?.owner === PROGRAM);
	await inBatches(held, SENDS_AT_ONCE, (arena) => send(ephemeral, `return ${arena.index}`, [returned(arena)]));
	const started = Date.now();
	while (Date.now() - started < 240000) {
		const states = await statesOf(baseRead, held.map((arena) => arena.key));
		if (states.every((state) => state?.owner === PROGRAM)) break;
		await sleep(3000);
	}
	console.log(`${held.length} arenas returned to L1 in ${Date.now() - started} ms`);
	const owners = arenas.map((arena) => arena.owner);
	const left = await balances(owners.map((owner) => owner.address));
	const sweeps = owners.map((owner, position) => ({ owner, lamports: left[position] })).filter((entry) => entry.lamports > SWEEP_FEE_LAMPORTS);
	for (let start = 0; start < sweeps.length; start += 8) {
		const batch = sweeps.slice(start, start + 8);
		await send(base, `sweep ${batch.length} wallets`, batch.map((entry) => transferInstruction(entry.owner, payer.address, entry.lamports)));
	}
	console.log(`swept ${sweeps.reduce((sum, entry) => sum + entry.lamports, 0n)} lamports from ${sweeps.length} wallets back to the payer`);
}

console.log(`program ${PROGRAM} ER ${ER_RPC} validator ${VALIDATOR} · ${mode}`);
const lamportsBefore = (await base.getBalance(payer.address).send()).value;
await { many, long, observe, teardown }[mode]();
const lamportsAfter = (await base.getBalance(payer.address).send()).value;
console.log(`payer balance on L1 moved by ${lamportsAfter - lamportsBefore} lamports`);
