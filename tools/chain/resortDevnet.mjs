import { readFileSync } from "node:fs";
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
import { scenarioOf } from "./blockFixture.mjs";
import { blocksFor, hex, identityOffset, joined, packed, swapPlan, words } from "./resortFixture.mjs";

const BASE_RPC = process.env.BASE_RPC ?? "https://api.devnet.solana.com";
const BASE_READ_RPC = process.env.BASE_READ_RPC ?? BASE_RPC;
const ER_RPC = process.env.ER_RPC ?? "https://devnet-as.magicblock.app";
const VALIDATOR = address(process.env.VALIDATOR ?? "MAS1Dt9qreoRMQ14YQuhg8UTZMMzDdKhmkZMECCzk57");
const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const COMPUTE_BUDGET_PROGRAM = address("ComputeBudget111111111111111111111111111111");
const DELEGATION_PROGRAM = address("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
const MAGIC_PROGRAM = address("Magic11111111111111111111111111111111111111");
const MAGIC_CONTEXT = address("MagicContext1111111111111111111111111111111");
const COMPUTE_UNIT_LIMIT = 1_400_000;
const CHUNK_BYTES = 850;
const COUNT = Number(process.env.COUNT ?? 200);
const MEASURE = ["level", "power", "combat"].indexOf(process.env.MEASURE ?? "combat");
const STAGE = process.env.STAGE ?? "all";
const KIND = { block: 0, index: 1, ladder: 2 };
const INDEX_BYTES = 24;
const UNITS = { snapshot: 12_000, sort: 70_000, merge: 70_000, swap: 20_000, confirm: 9_000, lifecycle: 40_000 };

const [programArgument] = process.argv.slice(2);
if (!programArgument) {
	console.log("usage: [STAGE=all|setup|resort|teardown] node tools/chain/resortDevnet.mjs <program>");
	process.exit(2);
}
const PROGRAM = address(programArgument);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const encoder = getAddressEncoder();
const payer = await createKeyPairSignerFromBytes(Uint8Array.from(JSON.parse(readFileSync(`${process.env.HOME}/.config/solana/id.json`, "utf8"))));
const base = createSolanaRpc(BASE_RPC);
const baseRead = createSolanaRpc(BASE_READ_RPC);
const ephemeral = createSolanaRpc(ER_RPC);
const signerMeta = { address: payer.address, role: AccountRole.WRITABLE_SIGNER, signer: payer };
const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });
const probe = (accounts, data) => ({ programAddress: PROGRAM, accounts, data });
const json = (value) => JSON.stringify(value, (_, inner) => typeof inner === "bigint" ? inner.toString() : inner);
const pda = async (programAddress, ...seeds) => await getProgramDerivedAddress({ programAddress, seeds });

function limitInstruction(units) {
	const bytes = new Uint8Array(5);
	const view = new DataView(bytes.buffer);
	view.setUint8(0, 2);
	view.setUint32(1, units, true);
	return { programAddress: COMPUTE_BUDGET_PROGRAM, accounts: [], data: bytes };
}

async function patiently(call) {
	for (let attempt = 1; ; attempt++) {
		try {
			return await call();
		} catch (error) {
			if (attempt >= 10) throw error;
			await sleep(2000 * attempt);
		}
	}
}

async function fetchTransaction(rpc, signature) {
	for (let attempt = 0; attempt < 30; attempt++) {
		const found = await rpc.getTransaction(signature, { maxSupportedTransactionVersion: 0, commitment: "confirmed", encoding: "json" }).send().catch(() => null);
		if (found) return found;
		await sleep(1000);
	}
	return null;
}

async function send(rpc, step, instructions, details = false) {
	const { value: blockhash } = await patiently(() => rpc.getLatestBlockhash().send());
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(payer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstructions([limitInstruction(COMPUTE_UNIT_LIMIT), ...instructions], m),
	);
	const transaction = await signTransactionMessageWithSigners(message);
	const signature = getSignatureFromTransaction(transaction);
	const started = Date.now();
	await patiently(() => rpc.sendTransaction(getBase64EncodedWireTransaction(transaction), { encoding: "base64", skipPreflight: true }).send());
	for (let attempt = 0; attempt < 240; attempt++) {
		const { value } = await patiently(() => rpc.getSignatureStatuses([signature]).send());
		const status = value[0];
		if (status && (status.confirmationStatus === "confirmed" || status.confirmationStatus === "finalized")) {
			const elapsed = Date.now() - started;
			const found = details || status.err ? await fetchTransaction(rpc === base ? baseRead : rpc, signature) : null;
			if (status.err) {
				console.log(`${step}: FAILED ${json(status.err)} ${signature}\n${(found?.meta?.logMessages ?? []).slice(-8).join("\n")}`);
				throw new Error(`${step} failed`);
			}
			return { signature, elapsed, units: found?.meta?.computeUnitsConsumed !== undefined ? Number(found.meta.computeUnitsConsumed) : null, fee: found?.meta?.fee !== undefined ? Number(found.meta.fee) : null };
		}
		await sleep(250);
	}
	throw new Error(`${step}: not confirmed`);
}

async function read(rpc, key) {
	const { value } = await patiently(() => rpc.getAccountInfo(key, { encoding: "base64", commitment: "confirmed" }).send());
	if (!value) return null;
	return { owner: value.owner, lamports: BigInt(value.lamports), data: new Uint8Array(Buffer.from(value.data[0], "base64")) };
}

async function readMany(rpc, keys) {
	const found = [];
	for (let start = 0; start < keys.length; start += 100) {
		const { value } = await patiently(() => rpc.getMultipleAccounts(keys.slice(start, start + 100), { encoding: "base64", commitment: "confirmed" }).send());
		for (const entry of value) found.push(entry ? { owner: entry.owner, lamports: BigInt(entry.lamports), data: new Uint8Array(Buffer.from(entry.data[0], "base64")) } : null);
	}
	return found;
}

async function holder(kind, param, size, content) {
	const seeds = kind === KIND.block ? ["block", words(param)] : kind === KIND.index ? ["pet", param] : ["ladder"];
	const [key, bump] = await pda(PROGRAM, ...seeds);
	const keyBytes = encoder.encode(key);
	const paramBytes = kind === KIND.index ? param : joined(words(kind === KIND.block ? param : 0), new Uint8Array(24));
	return {
		kind,
		key,
		bump,
		size,
		content,
		tail: joined(words(kind), paramBytes),
		buffer: (await pda(PROGRAM, "buffer", keyBytes))[0],
		record: (await pda(DELEGATION_PROGRAM, "delegation", keyBytes))[0],
		metadata: (await pda(DELEGATION_PROGRAM, "delegation-metadata", keyBytes))[0],
	};
}

async function sentInBatches(rpc, label, instructions, unitsEach, details = false) {
	const batches = packed(instructions, unitsEach);
	const started = Date.now();
	let units = 0;
	let fees = 0;
	let slowest = 0;
	for (const [index, batch] of batches.entries()) {
		const sent = await send(rpc, `${label} ${index + 1}/${batches.length}`, batch, details);
		units += sent.units ?? 0;
		fees += sent.fee ?? 0;
		slowest = Math.max(slowest, sent.elapsed);
	}
	const elapsed = Date.now() - started;
	console.log(`  ${label.padEnd(18)} ${String(instructions.length).padStart(5)} instructions ${String(batches.length).padStart(4)} transactions ${String(elapsed).padStart(7)} ms${details ? ` · ${units} CU · fees ${fees} lamports` : ""} · slowest confirmation ${slowest} ms`);
	return { transactions: batches.length, elapsed, units, fees };
}

const fixturePets = ["typical", "busiest"].map((name) => scenarioOf(new URL("../../out/actProbe/", import.meta.url), name).pets);
const layout = await send(base, "layout", [probe([], words(0))], true);
const logged = (await fetchTransaction(baseRead, layout.signature)).meta.logMessages.filter((line) => line.startsWith("Program log: 0x")).map((line) => Number(BigInt(line.split(", ").pop())));
const [blockBytes, entryBytes, headerBytes] = logged;
const ladderBytes = headerBytes + 2 * COUNT * entryBytes + Math.ceil(COUNT / 8);
const { blocks: blockContents, mints, petBytes } = blocksFor(COUNT, blockBytes, fixturePets);
const blockHolders = [];
for (const [id, content] of blockContents.entries()) blockHolders.push(await holder(KIND.block, id, blockBytes, content));
const indexHolders = new Map();
for (const [position, mint] of mints.entries()) {
	const entry = await holder(KIND.index, mint, INDEX_BYTES, null);
	entry.content = joined(words(Math.floor(position / 10), position % 10, entry.bump));
	indexHolders.set(hex(mint), entry);
}
const ladderHeader = new Uint8Array(ladderBytes);
new DataView(ladderHeader.buffer).setBigUint64(0, BigInt(COUNT), true);
new DataView(ladderHeader.buffer).setBigUint64(8, BigInt(MEASURE), true);
const ladder = await holder(KIND.ladder, 0, ladderBytes, ladderHeader);
const everyone = [ladder, ...blockHolders, ...indexHolders.values()];
console.log(`program ${PROGRAM} · ${COUNT} pets in ${blockHolders.length} blocks · Ladder ${ladderBytes} bytes · ${everyone.length} accounts · ER ${ER_RPC}`);

async function setup() {
	const states = await readMany(baseRead, everyone.map((entry) => entry.key));
	const missing = everyone.filter((entry, index) => states[index] === null);
	await sentInBatches(base, "create", missing.map((entry) => probe([signerMeta, writable(entry.key), readonly(SYSTEM_PROGRAM)], joined(words(7), entry.tail, words(entry.size)))), UNITS.lifecycle);
	const grow = [];
	for (let size = 10_240; size < ladderBytes; size += 10_240) grow.push(probe([signerMeta, writable(ladder.key)], joined(words(9), ladder.tail, words(ladderBytes))));
	const ladderState = await read(baseRead, ladder.key);
	if (!ladderState || ladderState.data.length < ladderBytes) {
		const rent = await patiently(() => baseRead.getMinimumBalanceForRentExemption(BigInt(ladderBytes)).send());
		const topUp = joined(Uint8Array.of(2, 0, 0, 0), words(rent - ladderState.lamports));
		const transfer = { programAddress: SYSTEM_PROGRAM, accounts: [signerMeta, writable(ladder.key)], data: topUp };
		await sentInBatches(base, "grow ladder", [transfer, ...grow], UNITS.lifecycle);
	}
	const now = await readMany(baseRead, everyone.map((entry) => entry.key));
	const writes = [];
	for (const [index, entry] of everyone.entries()) {
		const onChain = now[index]?.data ?? new Uint8Array();
		for (let offset = 0; offset < entry.size; offset += CHUNK_BYTES) {
			const chunk = entry.content.subarray(offset, Math.min(offset + CHUNK_BYTES, entry.size));
			if (chunk.every((value, position) => onChain[offset + position] === value)) continue;
			writes.push(probe([signerMeta, writable(entry.key)], joined(words(8), entry.tail, words(offset), chunk)));
		}
	}
	await sentInBatches(base, "write", writes, UNITS.lifecycle);
	const owners = await readMany(baseRead, everyone.map((entry) => entry.key));
	const toDelegate = everyone.filter((entry, index) => owners[index]?.owner === PROGRAM);
	await sentInBatches(base, "delegate", toDelegate.map((entry) => probe([
		signerMeta,
		readonly(SYSTEM_PROGRAM),
		writable(entry.key),
		readonly(PROGRAM),
		writable(entry.buffer),
		writable(entry.record),
		writable(entry.metadata),
		readonly(DELEGATION_PROGRAM),
		readonly(VALIDATOR),
	], joined(words(10), entry.tail))), UNITS.lifecycle);
	const started = Date.now();
	for (;;) {
		const seen = await readMany(ephemeral, everyone.map((entry) => entry.key));
		const ready = seen.filter((state, index) => state && state.data.length === everyone[index].size).length;
		if (ready === everyone.length) break;
		if (Date.now() - started > 180_000) throw new Error(`only ${ready} of ${everyone.length} accounts readable in the ER`);
		await sleep(2000);
	}
	console.log(`  all ${everyone.length} accounts readable in the ER ${Date.now() - started} ms after the last delegation`);
}

async function resort() {
	const phases = [];
	const started = Date.now();
	phases.push(await sentInBatches(ephemeral, "snapshot", blockHolders.map((entry, id) => probe([writable(ladder.key), readonly(entry.key)], words(1, id))), UNITS.snapshot, true));
	const runs = [];
	for (let start = 0; start < COUNT; start += 256) runs.push(probe([writable(ladder.key)], words(2, start, Math.min(256, COUNT - start), 32)));
	phases.push(await sentInBatches(ephemeral, "sort runs", runs, UNITS.sort, true));
	let source = 0;
	for (let width = 32; width < COUNT; width *= 2) {
		const chunk = Math.max(2 * width, 512);
		const passes = [];
		for (let start = 0; start < COUNT; start += chunk) passes.push(probe([writable(ladder.key)], words(3, width, start, Math.min(chunk, COUNT - start), source)));
		phases.push(await sentInBatches(ephemeral, `merge ${width}`, passes, UNITS.merge, true));
		source = 1 - source;
	}
	const ladderData = (await read(ephemeral, ladder.key)).data;
	const sortedArea = Number(new DataView(ladderData.buffer, ladderData.byteOffset).getBigUint64(16, true));
	const ranked = [];
	for (let index = 0; index < COUNT; index++) {
		const at = headerBytes + (sortedArea * COUNT + index) * entryBytes;
		ranked.push(ladderData.subarray(at + 16, at + 48));
	}
	const blockOf = (position) => blockHolders[Math.floor(position / 10)].key;
	const swaps = swapPlan(ranked, mints).map(({ from, rank, arriving, leaving }) => probe(
		[writable(ladder.key), writable(blockOf(from)), writable(blockOf(rank)), writable(indexHolders.get(hex(arriving)).key), writable(indexHolders.get(hex(leaving)).key)],
		words(4, from, rank),
	));
	phases.push(await sentInBatches(ephemeral, "swap", swaps, UNITS.swap, true));
	const afterSwaps = (await read(ephemeral, ladder.key)).data;
	const placedAt = (index) => (afterSwaps[headerBytes + 2 * COUNT * entryBytes + Math.floor(index / 8)] >> (index % 8)) & 1;
	const confirms = [];
	for (let position = 0; position < COUNT; position++) {
		if (!placedAt(position)) confirms.push(probe([writable(ladder.key), readonly(blockOf(position))], words(6, position)));
	}
	if (confirms.length > 0) phases.push(await sentInBatches(ephemeral, "confirm", confirms, UNITS.confirm, true));
	phases.push(await sentInBatches(ephemeral, "finish", [probe([writable(ladder.key)], words(5))], UNITS.confirm, true));
	const total = Date.now() - started;
	const blocks = await readMany(ephemeral, blockHolders.map((entry) => entry.key));
	let placedRight = 0;
	for (let position = 0; position < COUNT; position++) {
		const block = blocks[Math.floor(position / 10)].data;
		const at = identityOffset(petBytes, position % 10);
		if (block.subarray(at, at + 32).every((value, index) => value === ranked[position][index])) placedRight += 1;
	}
	const indexes = await readMany(ephemeral, [...indexHolders.values()].map((entry) => entry.key));
	const rankOf = new Map(ranked.map((mint, rank) => [hex(mint), rank]));
	let indexedRight = 0;
	for (const [position, entry] of [...indexHolders.entries()].entries()) {
		const view = new DataView(indexes[position].data.buffer, indexes[position].data.byteOffset);
		const rank = rankOf.get(entry[0]);
		if (Number(view.getBigUint64(0, true)) === Math.floor(rank / 10) && Number(view.getBigUint64(8, true)) === rank % 10) indexedRight += 1;
	}
	const transactions = phases.reduce((sum, phase) => sum + phase.transactions, 0);
	const units = phases.reduce((sum, phase) => sum + phase.units, 0);
	const fees = phases.reduce((sum, phase) => sum + phase.fees, 0);
	console.log(`  re-sort in the ER: ${transactions} transactions, ${units} CU, fees ${fees} lamports, ${total} ms from the first snapshot to the finish · ${swaps.length} swaps · ${placedRight} of ${COUNT} slots hold their rank's pet · ${indexedRight} of ${COUNT} indexes point at them`);
}

async function teardown() {
	const inEr = await readMany(baseRead, everyone.map((entry) => entry.key));
	const delegatedHolders = everyone.filter((entry, index) => inEr[index]?.owner === DELEGATION_PROGRAM);
	await sentInBatches(ephemeral, "commit and undelegate", delegatedHolders.map((entry) => probe([signerMeta, writable(entry.key), readonly(MAGIC_PROGRAM), writable(MAGIC_CONTEXT)], words(11))), UNITS.lifecycle);
	const started = Date.now();
	for (;;) {
		const states = await readMany(baseRead, everyone.map((entry) => entry.key));
		const back = states.filter((state) => state === null || state.owner === PROGRAM).length;
		if (back === everyone.length) break;
		if (Date.now() - started > 300_000) throw new Error(`only ${back} of ${everyone.length} accounts back on L1`);
		await sleep(3000);
	}
	console.log(`  all accounts back on L1 ${Date.now() - started} ms after the last return`);
	const states = await readMany(baseRead, everyone.map((entry) => entry.key));
	const open = everyone.filter((entry, index) => states[index] && states[index].lamports > 0n);
	await sentInBatches(base, "close", open.map((entry) => probe([signerMeta, writable(entry.key)], joined(words(12), entry.tail))), UNITS.lifecycle);
}

const before = (await base.getBalance(payer.address).send()).value;
if (STAGE === "all" || STAGE === "setup") await setup();
if (STAGE === "all" || STAGE === "resort") await resort();
if (STAGE === "all" || STAGE === "teardown") await teardown();
const after = (await base.getBalance(payer.address).send()).value;
console.log(`payer spent ${before - after} lamports on L1 during this run`);
