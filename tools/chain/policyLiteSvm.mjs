import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { LiteSVM } from "litesvm";
import {
	AccountRole,
	address,
	appendTransactionMessageInstructions,
	createKeyPairSignerFromPrivateKeyBytes,
	createTransactionMessage,
	lamports,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";

const COMPUTE_BUDGET_PROGRAM = address("ComputeBudget111111111111111111111111111111");
const COMPUTE_UNIT_LIMIT = 1_400_000;
const ENGINE = 16948401298924711931n;
const ATTACK_TARGETS = 9;
const NODE_CANDIDATES = 6;
const WEIGHTS = { economy: 46 * 32 + 32 * 12, attack: 25 * 32 + 32 * 16 + 16 * 4, node: 30 * 32 + 32 };
const hostInput = new URL("../../out/policyProbe/policy.txt", import.meta.url);

const [programPath, policyPath] = process.argv.slice(2);
if (!programPath || !policyPath) {
	console.log("usage: node tools/chain/policyLiteSvm.mjs out/policyProbe.so <checkpoint>.policy");
	process.exit(2);
}
const policy = new Uint8Array(readFileSync(policyPath));
mkdirSync(new URL(".", hostInput), { recursive: true });
writeFileSync(hostInput, Array.from(policy).join("\n") + "\n");

function limitData(units) {
	const bytes = new Uint8Array(5);
	const view = new DataView(bytes.buffer);
	view.setUint8(0, 2);
	view.setUint32(1, units, true);
	return bytes;
}

function runData(engine) {
	const bytes = new Uint8Array(16);
	const view = new DataView(bytes.buffer);
	view.setBigUint64(0, 0n, true);
	view.setBigUint64(8, engine, true);
	return bytes;
}

const svm = new LiteSVM();
const payer = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(1));
const program = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(3));
const holder = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(5));
svm.airdrop(payer.address, lamports(10_000_000_000n));
svm.addProgramFromFile(program.address, programPath);
svm.setAccount({
	address: holder.address,
	data: policy,
	executable: false,
	lamports: lamports(1_000_000_000n),
	programAddress: program.address,
	space: BigInt(policy.length),
});

const message = pipe(
	createTransactionMessage({ version: 0 }),
	(m) => setTransactionMessageFeePayerSigner(payer, m),
	(m) => setTransactionMessageLifetimeUsingBlockhash({ blockhash: svm.latestBlockhash(), lastValidBlockHeight: 1000n }, m),
	(m) => appendTransactionMessageInstructions([
		{ programAddress: COMPUTE_BUDGET_PROGRAM, accounts: [], data: limitData(COMPUTE_UNIT_LIMIT) },
		{ programAddress: program.address, accounts: [{ address: holder.address, role: AccountRole.READONLY }], data: runData(ENGINE) },
	], m),
);
const result = svm.sendTransaction(await signTransactionMessageWithSigners(message));
const failed = result.constructor.name === "FailedTransactionMetadata";
const meta = failed ? result.meta() : result;
if (failed) {
	console.log(`FAILED ${result.err().toString()}`);
	console.log(meta.logs().join("\n"));
	process.exit(1);
}

const logs = meta.logs();
const remaining = logs.filter((line) => line.startsWith("Program consumption:")).map((line) => Number(line.split(" ")[2]));
if (remaining.length !== 6) {
	console.log(`expected 6 compute-unit logs, got ${remaining.length}`);
	console.log(logs.join("\n"));
	process.exit(1);
}
const logged = logs.filter((line) => line.startsWith("Program log: 0x")).pop();
const checksum = BigInt(logged.split(", ").pop());
const [start, afterLog, afterCheck, afterEconomy, afterAttack, afterNode] = remaining;
const logCost = start - afterLog;
const sections = [
	["checkPolicy", afterLog - afterCheck, 0, 1],
	["economy", afterCheck - afterEconomy, WEIGHTS.economy, 1],
	[`attack × ${ATTACK_TARGETS}`, afterEconomy - afterAttack, WEIGHTS.attack, ATTACK_TARGETS],
	[`node × ${NODE_CANDIDATES}`, afterAttack - afterNode, WEIGHTS.node, NODE_CANDIDATES],
];
console.log(`policy ${policyPath} (${policy.length} bytes), compute-unit log ${logCost} CU, subtracted below`);
for (const [name, units, weights, count] of sections) {
	const net = units - logCost;
	const each = Math.round(net / count);
	const perWeight = weights ? ` · ${weights} weights each · ${(net / (weights * count)).toFixed(2)} CU/weight` : "";
	console.log(`${name.padEnd(12)} ${String(net).padStart(7)} CU · ${each} each${perWeight}`);
}
const inference = afterLog - afterNode - 4 * logCost;
console.log(`inference    ${String(inference).padStart(7)} CU · ${WEIGHTS.economy + ATTACK_TARGETS * WEIGHTS.attack + NODE_CANDIDATES * WEIGHTS.node} weights`);
console.log(`instruction  ${String(Number(meta.computeUnitsConsumed())).padStart(7)} CU (transaction total, with the compute-budget instruction)`);
console.log(`chain checksum 0x${checksum.toString(16)}`);
