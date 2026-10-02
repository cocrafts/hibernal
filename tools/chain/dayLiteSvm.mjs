import { readFileSync } from "node:fs";
import { LiteSVM } from "litesvm";
import {
	AccountRole,
	address,
	appendTransactionMessageInstructions,
	createKeyPairSignerFromPrivateKeyBytes,
	createTransactionMessage,
	getAddressDecoder,
	lamports,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";
import { createHash } from "node:crypto";

const COMPUTE_BUDGET_PROGRAM = address("ComputeBudget111111111111111111111111111111");
const VRF_PROGRAM = address("Vrf1RNUjXmQGjmQrQLvJHs9SNkvDJEsRVFPkfSQUwGz");
const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const COMPUTE_UNIT_LIMIT = 1_400_000;
const CALLBACK = 0xaa;

const [programPath, stubPath, fixturePath] = process.argv.slice(2);
if (!programPath || !stubPath || !fixturePath) {
	console.log("usage: node tools/chain/dayLiteSvm.mjs out/std/day.so out/std/vrfStub.so out/std/dayFixture.txt");
	process.exit(2);
}

const decoder = getAddressDecoder();
const keyOf = (hex) => decoder.decode(Buffer.from(hex, "hex"));
const discriminator = (name) => createHash("sha256").update(`global:${name}`).digest().subarray(0, 8);

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
svm.addProgramFromFile(VRF_PROGRAM, stubPath);

for (const holder of accounts) {
	if (holder.owner === "executable") continue;
	if (holder.index === 0) { accounts[0] = { ...holder, key: payer.address }; continue; }
	svm.setAccount({
		address: holder.key,
		data: holder.data,
		executable: false,
		lamports: lamports(1_000_000_000n),
		programAddress: holder.owner === "program" ? program : SYSTEM_PROGRAM,
		space: BigInt(holder.data.length),
	});
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

const role = (holder) => holder.index === 0
	? AccountRole.WRITABLE_SIGNER
	: holder.writable ? AccountRole.WRITABLE : AccountRole.READONLY;

function stepInstruction() {
	return {
		programAddress: program,
		accounts: accounts.map((holder) => ({ address: holder.key, role: role(holder), ...(holder.index === 0 ? { signer: payer } : {}) })),
		data: discriminator("step"),
	};
}

function seededInstruction(request) {
	const data = Buffer.alloc(1 + 8 + 32 + 8);
	data[0] = CALLBACK;
	discriminator("seeded").copy(data, 1);
	data.writeBigUInt64LE(seed, 9);
	data.writeBigUInt64LE(BigInt(request), 41);
	const callbackAccounts = [accounts[2], accounts[3], ...accounts.slice(10, 20)];
	return {
		programAddress: VRF_PROGRAM,
		accounts: [
			{ address: identity, role: AccountRole.READONLY },
			{ address: program, role: AccountRole.READONLY },
			...callbackAccounts.map((holder) => ({ address: holder.key, role: AccountRole.WRITABLE })),
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

const units = { dawn: [], seeded: [], act: [], "act, fight lost": [], "act, fight won": [], dusk: [] };
const FIGHT_HEAD = 8 + 72;
const FIGHTS = 8 + 568;
const FIGHT_RECORD = 120;
const OUTCOME = 112;
const blockData = () => svm.getAccount(accounts[3].key).data;
let differingBytes = 0;
let pendingKind = null;
let steps = 0;
for (const line of lines) {
	const [kind, value] = fields(line);
	if (kind === "clock") {
		const clock = svm.getClock();
		clock.unixTimestamp = BigInt(value);
		svm.setClock(clock);
		continue;
	}
	if (kind === "seeded") {
		const sent = await send(seededInstruction(value));
		if (sent.failed) { console.log(`seeded ${value}: ${sent.error}\n${sent.logs.slice(-8).join("\n")}`); process.exit(1); }
		units.seeded.push(sent.units);
		pendingKind = "seeded";
		continue;
	}
	if (kind !== "expect") continue;
	const label = value;
	if (label !== "seeded") {
		const headBefore = blockData()[FIGHT_HEAD];
		const sent = await send(stepInstruction());
		if (sent.failed) { console.log(`${label} step ${steps}: ${sent.error}\n${sent.logs.slice(-60).join("\n")}`); process.exit(1); }
		const after = blockData();
		const fought = label === "act" && after[FIGHT_HEAD] !== headBefore;
		const won = fought && after[FIGHTS + ((after[FIGHT_HEAD] + 31) % 32) * FIGHT_RECORD + OUTCOME] === 1;
		units[fought ? (won ? "act, fight won" : "act, fight lost") : label].push(sent.units);
	}
	steps++;
	differingBytes += differing(line);
	pendingKind = null;
}

const range = (values) => values.length === 0 ? "none" : `${Math.min(...values)}–${Math.max(...values)} CU (mean ${Math.round(values.reduce((a, b) => a + b, 0) / values.length)})`;
console.log(`day loop on LiteSVM: ${steps} instructions, ${differingBytes} bytes differing from the host simulator`);
for (const [kind, values] of Object.entries(units)) console.log(`  ${kind.padEnd(16)} ${values.length} × ${range(values)}`);
