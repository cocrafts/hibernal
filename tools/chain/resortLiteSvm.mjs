import { readFileSync } from "node:fs";
import { LiteSVM } from "litesvm";
import {
	AccountRole,
	address,
	appendTransactionMessageInstructions,
	createKeyPairSignerFromPrivateKeyBytes,
	createTransactionMessage,
	getAddressEncoder,
	getProgramDerivedAddress,
	lamports,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";
import { scenarioOf } from "./blockFixture.mjs";

const COMPUTE_BUDGET_PROGRAM = address("ComputeBudget111111111111111111111111111111");
const COMPUTE_UNIT_LIMIT = 1_400_000;
const PACK_UNITS = 1_300_000;
const MAX_ACCOUNTS = 30;
const RUN = 32;
const MEASURES = ["level", "power", "combat"];
const RENT_PER_BYTE = 5_080n;
const ACCOUNT_OVERHEAD = 128n;
const WIRE_LIMIT = 1_232;
const MAX_INSTRUCTIONS = 64;
const probeDirectory = new URL("../../out/actProbe/", import.meta.url);

function wireBytes(accounts, instructions) {
	const fixed = 1 + 64 + 3 + 32 * (accounts + 3) + 32 + 1 + 1 + 9 + 1;
	return fixed + instructions.reduce((sum, instruction) => sum + 1 + 1 + instruction.accounts.length + 1 + instruction.data.length, 0);
}

const [programPath, countsArgument = "200,1000,10000", measureName = "combat"] = process.argv.slice(2);
if (!programPath) {
	console.log("usage: node tools/chain/resortLiteSvm.mjs out/resortProbe.so [200,1000,10000] [level|power|combat] (run blockLiteSvm.mjs first: it writes the host's pets)");
	process.exit(2);
}
const measure = MEASURES.indexOf(measureName);
const encoder = getAddressEncoder();
const signerOf = (fill) => createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(fill));
const payer = await signerOf(1);
const programKey = await signerOf(3);
const fixturePets = ["typical", "busiest"].map((name) => scenarioOf(probeDirectory, name).pets);
const PET_BYTES = fixturePets[0].length / 10;

function words(...values) {
	const bytes = new Uint8Array(8 * values.length);
	const view = new DataView(bytes.buffer);
	values.forEach((value, index) => view.setBigUint64(8 * index, BigInt(value), true));
	return bytes;
}

function limitInstruction(units) {
	const bytes = new Uint8Array(5);
	const view = new DataView(bytes.buffer);
	view.setUint8(0, 2);
	view.setUint32(1, units, true);
	return { programAddress: COMPUTE_BUDGET_PROGRAM, accounts: [], data: bytes };
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

const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });
const same = (left, right) => left.length === right.length && left.every((value, index) => value === right[index]);

async function measured(count) {
	const svm = new LiteSVM();
	svm.airdrop(payer.address, lamports(10_000_000_000n));
	svm.addProgramFromFile(programKey.address, programPath);
	const program = programKey.address;
	const probe = (accounts, data) => ({ programAddress: program, accounts, data });
	async function send(instructions) {
		const message = pipe(
			createTransactionMessage({ version: 0 }),
			(m) => setTransactionMessageFeePayerSigner(payer, m),
			(m) => setTransactionMessageLifetimeUsingBlockhash({ blockhash: svm.latestBlockhash(), lastValidBlockHeight: 1000n }, m),
			(m) => appendTransactionMessageInstructions([limitInstruction(COMPUTE_UNIT_LIMIT), ...instructions], m),
		);
		const result = svm.sendTransaction(await signTransactionMessageWithSigners(message));
		svm.expireBlockhash();
		const failed = result.constructor.name === "FailedTransactionMetadata";
		const meta = failed ? result.meta() : result;
		if (failed) throw new Error(`${result.err().toString()}\n${meta.logs().slice(-6).join("\n")}`);
		return { units: Number(meta.computeUnitsConsumed()), logs: meta.logs() };
	}
	const layout = await send([probe([], words(0))]);
	const [blockBytes, entryBytes, headerBytes] = layout.logs.filter((line) => line.startsWith("Program log: 0x")).map((line) => Number(BigInt(line.split(", ").pop())));
	const blocks = count / 10;
	const ladderBytes = headerBytes + 2 * count * entryBytes + Math.ceil(count / 8);
	const [ladder] = await getProgramDerivedAddress({ programAddress: program, seeds: ["ladder"] });
	const blockKeys = [];
	for (let id = 0; id < blocks; id++) {
		blockKeys.push((await getProgramDerivedAddress({ programAddress: program, seeds: ["block", words(id)] }))[0]);
	}
	const next = random(0x51ed + count);
	const mints = [];
	const indexes = new Map();
	for (let id = 0; id < blocks; id++) {
		const bytes = new Uint8Array(blockBytes);
		const view = new DataView(bytes.buffer);
		view.setUint8(0, 1);
		view.setUint8(1, 1);
		view.setUint32(4, id, true);
		for (let slot = 0; slot < 10; slot++) {
			const source = fixturePets[Number(next() % 2n)];
			const pick = Number(next() % 10n);
			bytes.set(source.subarray(pick * PET_BYTES, (pick + 1) * PET_BYTES), 8 + slot * PET_BYTES);
			const mint = new Uint8Array(32);
			for (let index = 0; index < 32; index += 8) new DataView(mint.buffer).setBigUint64(index, next(), true);
			bytes.set(mint, 8 + 10 * PET_BYTES + slot * 72);
			mints.push(mint);
			const [indexKey, bump] = await getProgramDerivedAddress({ programAddress: program, seeds: ["pet", mint] });
			indexes.set(Buffer.from(mint).toString("hex"), indexKey);
			const indexData = new Uint8Array(24);
			new DataView(indexData.buffer).setBigUint64(0, BigInt(id), true);
			new DataView(indexData.buffer).setBigUint64(8, BigInt(slot), true);
			new DataView(indexData.buffer).setBigUint64(16, BigInt(bump), true);
			svm.setAccount({ address: indexKey, data: indexData, executable: false, lamports: lamports(1_000_000n), programAddress: program, space: 24n });
		}
		svm.setAccount({ address: blockKeys[id], data: bytes, executable: false, lamports: lamports(1_000_000_000n), programAddress: program, space: BigInt(bytes.length) });
	}
	const header = new Uint8Array(ladderBytes);
	new DataView(header.buffer).setBigUint64(0, BigInt(count), true);
	new DataView(header.buffer).setBigUint64(8, BigInt(measure), true);
	svm.setAccount({ address: ladder, data: header, executable: false, lamports: lamports(1_000_000_000n), programAddress: program, space: BigInt(ladderBytes) });
	const phases = [];
	async function packed(name, instructions, accountsOf) {
		if (instructions.length === 0) return;
		const single = await send([instructions[0]]);
		const perInstruction = Math.max(single.units, 1);
		let transactions = 1;
		let units = single.units;
		let peak = single.units;
		let batch = [];
		let keys = new Set();
		const flush = async () => {
			if (batch.length === 0) return;
			const sent = await send(batch);
			transactions += 1;
			units += sent.units;
			peak = Math.max(peak, sent.units);
			batch = [];
			keys = new Set();
		};
		for (const instruction of instructions.slice(1)) {
			const extra = accountsOf(instruction).filter((key) => !keys.has(key));
			const bytes = wireBytes(keys.size + extra.length, [...batch, instruction]);
			const full = keys.size + extra.length > MAX_ACCOUNTS || bytes > WIRE_LIMIT || batch.length + 2 > MAX_INSTRUCTIONS;
			if (batch.length > 0 && (full || (batch.length + 1) * perInstruction * 1.15 > PACK_UNITS)) await flush();
			batch.push(instruction);
			for (const key of accountsOf(instruction)) keys.add(key);
		}
		await flush();
		phases.push({ name, instructions: instructions.length, transactions, units, peak, perInstruction });
	}
	const keysOf = (instruction) => instruction.accounts.map((meta) => meta.address);
	await packed("snapshot", blockKeys.map((key, id) => probe([writable(ladder), readonly(key)], words(1, id))), keysOf);
	const sortChunk = 256;
	const runs = [];
	for (let start = 0; start < count; start += sortChunk) runs.push(probe([writable(ladder)], words(2, start, Math.min(sortChunk, count - start), RUN)));
	await packed("sort runs", runs, keysOf);
	let source = 0;
	for (let width = RUN; width < count; width *= 2) {
		const chunk = Math.max(2 * width, 512);
		const passes = [];
		for (let start = 0; start < count; start += chunk) passes.push(probe([writable(ladder)], words(3, width, start, Math.min(chunk, count - start), source)));
		await packed(`merge width ${width}`, passes, keysOf);
		source = 1 - source;
	}
	const ladderData = svm.getAccount(ladder).data;
	const sortedArea = Number(new DataView(ladderData.buffer, ladderData.byteOffset).getBigUint64(16, true));
	const entryAt = (index) => headerBytes + (sortedArea * count + index) * entryBytes;
	const ranked = [];
	for (let index = 0; index < count; index++) ranked.push(ladderData.subarray(entryAt(index) + 16, entryAt(index) + 48));
	const current = mints.slice();
	const where = new Map(current.map((mint, position) => [Buffer.from(mint).toString("hex"), position]));
	const swaps = [];
	const confirms = [];
	const blockOf = (position) => blockKeys[Math.floor(position / 10)];
	for (let rank = 0; rank < count; rank++) {
		if (same(current[rank], ranked[rank])) continue;
		const from = where.get(Buffer.from(ranked[rank]).toString("hex"));
		const indexOf = (mint) => indexes.get(Buffer.from(mint).toString("hex"));
		swaps.push(probe([writable(ladder), writable(blockOf(from)), writable(blockOf(rank)), writable(indexOf(ranked[rank])), writable(indexOf(current[rank]))], words(4, from, rank)));
		const moving = current[rank];
		current[rank] = current[from];
		current[from] = moving;
		where.set(Buffer.from(current[from]).toString("hex"), from);
		where.set(Buffer.from(current[rank]).toString("hex"), rank);
	}
	await packed("swap", swaps, keysOf);
	const placedAt = (data, index) => (data[headerBytes + 2 * count * entryBytes + Math.floor(index / 8)] >> (index % 8)) & 1;
	const afterSwaps = svm.getAccount(ladder).data;
	for (let position = 0; position < count; position++) {
		if (!placedAt(afterSwaps, position)) confirms.push(probe([writable(ladder), readonly(blockOf(position))], words(6, position)));
	}
	await packed("confirm", confirms, keysOf);
	await packed("finish", [probe([writable(ladder)], words(5))], keysOf);
	let ordered = true;
	let lastStrength = Infinity;
	let placedRight = 0;
	let indexedRight = 0;
	for (let position = 0; position < count; position++) {
		const block = svm.getAccount(blockOf(position)).data;
		const slot = position % 10;
		const mint = block.subarray(8 + 10 * PET_BYTES + slot * 72, 8 + 10 * PET_BYTES + slot * 72 + 32);
		if (same(mint, ranked[position])) placedRight += 1;
		const indexData = svm.getAccount(indexes.get(Buffer.from(mint).toString("hex"))).data;
		const indexView = new DataView(indexData.buffer, indexData.byteOffset);
		if (Number(indexView.getBigUint64(0, true)) === Math.floor(position / 10) && Number(indexView.getBigUint64(8, true)) === slot) indexedRight += 1;
		const view = new DataView(block.buffer, block.byteOffset);
		if (view.getUint32(8 + slot * PET_BYTES, true) !== Math.floor(position / 10) || block[8 + slot * PET_BYTES + 4] !== slot) ordered = false;
		const strength = Number(new DataView(ladderData.buffer, ladderData.byteOffset).getBigUint64(entryAt(position), true));
		if (strength > lastStrength) ordered = false;
		lastStrength = strength;
	}
	const transactions = phases.reduce((sum, phase) => sum + phase.transactions, 0);
	const units = phases.reduce((sum, phase) => sum + phase.units, 0);
	const rent = (BigInt(ladderBytes) + ACCOUNT_OVERHEAD) * RENT_PER_BYTE;
	console.log(`\n${count} pets in ${blocks} blocks, strength ${measureName} · Ladder ${ladderBytes} bytes, rent ${rent} lamports (${Number(rent) / 1e9} SOL, once)`);
	for (const phase of phases) {
		console.log(`  ${phase.name.padEnd(16)} ${String(phase.instructions).padStart(6)} instructions ${String(phase.transactions).padStart(5)} transactions ${String(phase.units).padStart(11)} CU · ${phase.perInstruction} CU each, ${phase.peak} the fullest transaction`);
	}
	console.log(`  total ${transactions} transactions, ${units} CU · ${swaps.length} swaps · ${placedRight} of ${count} slots hold their rank's pet, ${indexedRight} pet indexes point at them · blocks ordered by strength with their own place: ${ordered}`);
}

for (const count of countsArgument.split(",").map(Number)) await measured(count);
