import { readFileSync } from "node:fs";
import { LiteSVM } from "litesvm";
import {
	AccountRole,
	address,
	appendTransactionMessageInstructions,
	createKeyPairSignerFromPrivateKeyBytes,
	createTransactionMessage,
	getAddressDecoder,
	getAddressEncoder,
	getProgramDerivedAddress,
	lamports,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";
import { createHash } from "node:crypto";

const COMPUTE_BUDGET_PROGRAM = address("ComputeBudget111111111111111111111111111111");
const VRF_PROGRAM = address("Vrf1RNUjXmQGjmQrQLvJHs9SNkvDJEsRVFPkfSQUwGz");
const HYDRA_PROGRAM = address("eHyd5BU8QffvHi4GnXwxrK4WpS7pM2x9UGKHBWii7mf");
const COMPUTE_UNIT_LIMIT = 1_400_000;
const CALLBACK = 0xaa;
const BLOCK_ID = 0n;
const NEXT_CRANK = 10;
const ROUND_START_ACCOUNTS = [0, 1, 2, 3, 5, 6, 7, 8, 9, NEXT_CRANK, 11, 12, 13];
const READONLY_IN_ROUND_START = new Set([2]);

const [programPath, vrfStubPath, hydraStubPath, fixturePath] = process.argv.slice(2);
if (!programPath || !vrfStubPath || !hydraStubPath || !fixturePath) {
	console.log("usage: node tools/chain/dayLiteSvm.mjs out/std/day.so out/std/vrfStub.so out/std/hydraStub.so out/std/dayFixture.txt");
	process.exit(2);
}

const decoder = getAddressDecoder();
const encoder = getAddressEncoder();
const keyOf = (hex) => decoder.decode(Buffer.from(hex, "hex"));
const snakeCase = (name) => name.replace(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase();
const discriminator = (name) => createHash("sha256").update(`global:${snakeCase(name)}`).digest().subarray(0, 8);

const lines = readFileSync(fixturePath, "utf8").split("\n").filter(Boolean);
const fields = (line) => line.split(" ");
const program = keyOf(fields(lines.find((line) => line.startsWith("program ")))[1]);
const identity = keyOf(fields(lines.find((line) => line.startsWith("identity ")))[1]);
const seed = BigInt(fields(lines.find((line) => line.startsWith("seed ")))[1]);
const accounts = lines.filter((line) => line.startsWith("account ")).map((line) => {
	const [, index, key, owner, writable, signer, data = ""] = fields(line);
	return { index: Number(index), key: keyOf(key), owner, writable: writable === "1", signer: signer === "1", data: Buffer.from(data, "hex") };
});

const svm = new LiteSVM();
const payer = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(1));
svm.airdrop(payer.address, lamports(100_000_000_000n));
svm.addProgramFromFile(program, programPath);
svm.addProgramFromFile(VRF_PROGRAM, vrfStubPath);
svm.addProgramFromFile(HYDRA_PROGRAM, hydraStubPath);

for (const holder of accounts) {
	if (holder.owner !== "program") continue;
	svm.setAccount({
		address: holder.key,
		data: holder.data,
		executable: false,
		lamports: lamports(1_000_000_000n),
		programAddress: program,
		space: BigInt(holder.data.length),
	});
}

function u64(value) {
	const bytes = Buffer.alloc(8);
	bytes.writeBigUInt64LE(BigInt(value));
	return bytes;
}

async function crankAddress(seq) {
	const seedBytes = Buffer.concat([u64(BLOCK_ID), u64(seq), Buffer.from(encoder.encode(program)).subarray(0, 16)]);
	const [found] = await getProgramDerivedAddress({ programAddress: HYDRA_PROGRAM, seeds: ["crank", seedBytes] });
	return found;
}

function limitData(units) {
	const bytes = new Uint8Array(5);
	new DataView(bytes.buffer).setUint8(0, 2);
	new DataView(bytes.buffer).setUint32(1, units, true);
	return bytes;
}

async function send(instruction) {
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(payer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash({ blockhash: svm.latestBlockhash(), lastValidBlockHeight: 1000n }, m),
		(m) => appendTransactionMessageInstructions([
			{ programAddress: COMPUTE_BUDGET_PROGRAM, accounts: [], data: limitData(COMPUTE_UNIT_LIMIT) },
			instruction,
		], m),
	);
	const result = svm.sendTransaction(await signTransactionMessageWithSigners(message));
	svm.expireBlockhash();
	const failed = result.constructor.name === "FailedTransactionMetadata";
	const meta = failed ? result.meta() : result;
	return { failed, error: failed ? result.err().toString() : null, units: Number(meta.computeUnitsConsumed()), logs: meta.logs() };
}

const role = (writable) => writable ? AccountRole.WRITABLE : AccountRole.READONLY;

async function turnInstruction(seq) {
	const next = await crankAddress(seq + 1n);
	return {
		programAddress: program,
		accounts: accounts.map((holder) => ({ address: holder.index === NEXT_CRANK ? next : holder.key, role: role(holder.writable) })),
		data: Buffer.concat([discriminator("Turn"), u64(seq)]),
	};
}

async function roundStartInstruction(seq) {
	const next = await crankAddress(seq + 1n);
	return {
		programAddress: program,
		accounts: ROUND_START_ACCOUNTS.map((index) => ({
			address: index === NEXT_CRANK ? next : accounts[index].key,
			role: role(accounts[index].writable && !READONLY_IN_ROUND_START.has(index)),
		})),
		data: Buffer.concat([discriminator("RoundStart"), u64(seq)]),
	};
}

function seededInstruction(request) {
	const data = Buffer.alloc(1 + 8 + 32 + 8);
	data[0] = CALLBACK;
	discriminator("Seeded").copy(data, 1);
	data.writeBigUInt64LE(seed, 9);
	data.writeBigUInt64LE(BigInt(request), 41);
	return {
		programAddress: VRF_PROGRAM,
		accounts: [
			{ address: identity, role: AccountRole.READONLY },
			{ address: program, role: AccountRole.READONLY },
			{ address: accounts[3].key, role: AccountRole.WRITABLE },
		],
		data,
	};
}

function differing(expectLine) {
	let count = 0;
	for (const part of fields(expectLine).slice(2)) {
		const [index, hex] = part.split(":");
		const expected = Buffer.from(hex, "hex");
		const actual = svm.getAccount(accounts[Number(index)].key).data;
		for (let position = 0; position < expected.length; position++) {
			if (actual[position] !== expected[position]) count++;
		}
		count += Math.abs(actual.length - expected.length);
	}
	return count;
}

const success = (logs, id) => logs.filter((line) => line === `Program ${id} success`).length;
const units = { roundStart: [], seeded: [], dawn: [], act: [], "act with a fight": [], dayEnd: [] };
const FIGHT_HEAD = 8 + 96;
const blockData = () => svm.getAccount(accounts[3].key).data;
let differingBytes = 0;
let instructions = 0;
let requests = 0;
let creates = 0;
let pending = null;
for (const line of lines) {
	const [kind, value, slot] = fields(line);
	if (kind === "clock") {
		const clock = svm.getClock();
		clock.unixTimestamp = BigInt(value);
		clock.slot = BigInt(slot);
		svm.setClock(clock);
		continue;
	}
	if (kind === "roundStart" || kind === "turn" || kind === "seeded") {
		pending = { kind, value: BigInt(value) };
		continue;
	}
	if (kind !== "expect") continue;
	const label = value;
	const headBefore = blockData()[FIGHT_HEAD];
	const instruction = pending.kind === "turn"
		? await turnInstruction(pending.value)
		: pending.kind === "roundStart" ? await roundStartInstruction(pending.value) : seededInstruction(pending.value);
	const sent = await send(instruction);
	if (sent.failed) {
		console.log(`${label} ${pending.kind} ${pending.value}: ${sent.error}\n${sent.logs.slice(-40).join("\n")}`);
		process.exit(1);
	}
	requests += success(sent.logs, VRF_PROGRAM) - (pending.kind === "seeded" ? 1 : 0);
	creates += success(sent.logs, HYDRA_PROGRAM);
	const fought = label === "act" && blockData()[FIGHT_HEAD] !== headBefore;
	units[fought ? "act with a fight" : label].push(sent.units);
	instructions++;
	differingBytes += differing(line);
	pending = null;
}

const range = (values) => values.length === 0 ? "none" : `${Math.min(...values)}–${Math.max(...values)} CU (mean ${Math.round(values.reduce((a, b) => a + b, 0) / values.length)})`;
console.log(`relay day on LiteSVM: ${instructions} instructions, ${differingBytes} bytes differing from the host simulator, ${requests} VRF requests and ${creates} Hydra creates accepted by the stubs with the payer PDA signing (no wallet signs a step)`);
for (const [kind, values] of Object.entries(units)) console.log(`  ${kind.padEnd(16)} ${values.length} × ${range(values)}`);
