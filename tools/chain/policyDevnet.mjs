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

const BASE_RPC = process.env.BASE_RPC ?? "https://rpc.magicblock.app/devnet";
const BASE_READ_RPC = process.env.BASE_READ_RPC ?? BASE_RPC;
const ER_RPC = process.env.ER_RPC ?? "https://devnet-as.magicblock.app";
const VALIDATOR = address(process.env.VALIDATOR ?? "MAS1Dt9qreoRMQ14YQuhg8UTZMMzDdKhmkZMECCzk57");
const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const COMPUTE_BUDGET_PROGRAM = address("ComputeBudget111111111111111111111111111111");
const DELEGATION_PROGRAM = address("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
const MAGIC_PROGRAM = address("Magic11111111111111111111111111111111111111");
const MAGIC_CONTEXT = address("MagicContext1111111111111111111111111111111");
const COMPUTE_UNIT_LIMIT = 1_400_000;
const ENGINE = 16948401298924711931n;
const HOST_CHECKSUM = process.env.HOST_CHECKSUM ?? "0xbcdd5dac7cb68f98";
const REWRITTEN_CHECKSUM = process.env.REWRITTEN_CHECKSUM ?? "0x662e5ba1e8353f24";
const REWRITE_OFFSET = 17;
const REWRITE_BYTES = 46;
const CHUNK_BYTES = 900;
const ATTACK_TARGETS = 9;
const NODE_CANDIDATES = 6;
const WEIGHTS = { economy: 46 * 32 + 32 * 12, attack: 25 * 32 + 32 * 16 + 16 * 4, node: 30 * 32 + 32 };

const [programArgument, policyPath] = process.argv.slice(2);
if (!programArgument || !policyPath) {
	console.log("usage: node tools/chain/policyDevnet.mjs <program id> <checkpoint>.policy");
	process.exit(2);
}
const PROGRAM = address(programArgument);
const blob = new Uint8Array(readFileSync(policyPath));
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const addressEncoder = getAddressEncoder();
const payer = await createKeyPairSignerFromBytes(Uint8Array.from(JSON.parse(readFileSync(`${process.env.HOME}/.config/solana/id.json`, "utf8"))));
const base = createSolanaRpc(BASE_RPC);
const baseRead = createSolanaRpc(BASE_READ_RPC);
const ephemeral = createSolanaRpc(ER_RPC);
const [policy] = await getProgramDerivedAddress({ programAddress: PROGRAM, seeds: ["policy"] });
const policyBytes = addressEncoder.encode(policy);
const [buffer] = await getProgramDerivedAddress({ programAddress: PROGRAM, seeds: ["buffer", policyBytes] });
const [delegationRecord] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation", policyBytes] });
const [delegationMetadata] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation-metadata", policyBytes] });

const signerMeta = { address: payer.address, role: AccountRole.WRITABLE_SIGNER, signer: payer };
const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });

function u64Bytes(value) {
	const bytes = new Uint8Array(8);
	new DataView(bytes.buffer).setBigUint64(0, BigInt(value), true);
	return bytes;
}

function withHeader(discriminator, argument, tail = new Uint8Array(0)) {
	const bytes = new Uint8Array(16 + tail.length);
	const view = new DataView(bytes.buffer);
	view.setBigUint64(0, BigInt(discriminator), true);
	view.setBigUint64(8, BigInt(argument), true);
	bytes.set(tail, 16);
	return bytes;
}

function limitInstruction(units) {
	const bytes = new Uint8Array(5);
	const view = new DataView(bytes.buffer);
	view.setUint8(0, 2);
	view.setUint32(1, units, true);
	return { programAddress: COMPUTE_BUDGET_PROGRAM, accounts: [], data: bytes };
}

const program = (accounts, data) => ({ programAddress: PROGRAM, accounts, data });
async function patiently(call) {
	for (let attempt = 1; ; attempt++) {
		try {
			return await call();
		} catch (error) {
			if (!String(error.message).includes("429") || attempt >= 10) throw error;
			await sleep(2000 * attempt);
		}
	}
}

const json = (value) => JSON.stringify(value, (_, inner) => typeof inner === "bigint" ? inner.toString() : inner);

async function fetchTransaction(rpc, signature) {
	for (let attempt = 0; attempt < 30; attempt++) {
		const found = await rpc.getTransaction(signature, { maxSupportedTransactionVersion: 0, commitment: "confirmed", encoding: "json" }).send().catch(() => null);
		if (found) return found;
		await sleep(1500);
	}
	return null;
}

async function send(rpc, layer, step, instructions) {
	const { value: blockhash } = await patiently(() => rpc.getLatestBlockhash().send());
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(payer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstructions(instructions, m),
	);
	const transaction = await signTransactionMessageWithSigners(message);
	const signature = getSignatureFromTransaction(transaction);
	const started = Date.now();
	await patiently(() => rpc.sendTransaction(getBase64EncodedWireTransaction(transaction), { encoding: "base64", skipPreflight: true }).send());
	for (let attempt = 0; attempt < 120; attempt++) {
		const { value } = await patiently(() => rpc.getSignatureStatuses([signature]).send());
		const status = value[0];
		if (status && (status.confirmationStatus === "confirmed" || status.confirmationStatus === "finalized")) {
			const elapsed = Date.now() - started;
			const details = layer === "er" || status.err ? await fetchTransaction(rpc === base ? baseRead : rpc, signature) : null;
			const logs = details?.meta?.logMessages ?? [];
			const units = details?.meta?.computeUnitsConsumed !== undefined ? Number(details.meta.computeUnitsConsumed) : null;
			console.log(`[${layer}] ${step}: ${status.err ? "FAILED " + json(status.err) : "ok"} ${elapsed}ms ${units} CU ${signature}`);
			return { signature, logs, units, elapsed, err: status.err };
		}
		await sleep(500);
	}
	throw new Error(`${step}: not confirmed`);
}

async function mustSend(rpc, layer, step, instructions) {
	const sent = await send(rpc, layer, step, instructions);
	if (sent.err) {
		console.log(sent.logs.join("\n"));
		throw new Error(`${step} failed`);
	}
	return sent;
}

async function readPolicy(rpc) {
	const { value } = await patiently(() => rpc.getAccountInfo(policy, { encoding: "base64", commitment: "confirmed" }).send());
	if (!value) return null;
	return { owner: value.owner, data: new Uint8Array(Buffer.from(value.data[0], "base64")) };
}

async function waitFor(rpc, label, predicate, timeoutMs) {
	const started = Date.now();
	while (Date.now() - started < timeoutMs) {
		const state = await readPolicy(rpc).catch((error) => (console.log(`${label}: read failed, ${error.message}`), null));
		if (state && predicate(state)) {
			console.log(`${label}: after ${Date.now() - started}ms, owner ${state.owner}`);
			return state;
		}
		await sleep(2000);
	}
	throw new Error(`${label}: timed out after ${timeoutMs}ms`);
}

const holds = (expected) => (state) => state.data.length === expected.length && state.data.every((value, index) => value === expected[index]);
const sameBlob = holds(blob);
const checksumIn = (logs) => {
	const logged = logs.filter((line) => line.startsWith("Program log: 0x")).pop();
	return logged ? `0x${BigInt(logged.split(", ").pop()).toString(16)}` : null;
};

function report(label, sent, expected = HOST_CHECKSUM) {
	if (sent.err) {
		console.log(`${label}: FAILED ${json(sent.err)}`);
		console.log(sent.logs.join("\n"));
		return;
	}
	const remaining = sent.logs.filter((line) => line.startsWith("Program consumption:")).map((line) => Number(line.split(" ")[2]));
	if (remaining.length !== 6) {
		console.log(`${label}: expected 6 compute-unit logs, got ${remaining.length}`);
		console.log(sent.logs.join("\n"));
		return;
	}
	const checksum = checksumIn(sent.logs);
	const [start, afterLog, afterCheck, afterEconomy, afterAttack, afterNode] = remaining;
	const logCost = start - afterLog;
	const sections = [
		["checkPolicy", afterLog - afterCheck, 0, 1],
		["economy", afterCheck - afterEconomy, WEIGHTS.economy, 1],
		[`attack × ${ATTACK_TARGETS}`, afterEconomy - afterAttack, WEIGHTS.attack, ATTACK_TARGETS],
		[`node × ${NODE_CANDIDATES}`, afterAttack - afterNode, WEIGHTS.node, NODE_CANDIDATES],
	];
	console.log(`${label}: ok in ${sent.elapsed}ms wall clock, compute-unit log ${logCost} CU subtracted`);
	for (const [name, units, weights, count] of sections) {
		const net = units - logCost;
		const perWeight = weights ? ` · ${(net / (weights * count)).toFixed(2)} CU/weight` : "";
		console.log(`  ${name.padEnd(12)} ${String(net).padStart(7)} CU · ${Math.round(net / count)} each${perWeight}`);
	}
	console.log(`  inference    ${String(afterLog - afterNode - 4 * logCost).padStart(7)} CU`);
	console.log(`  transaction  ${String(sent.units).padStart(7)} CU`);
	console.log(`  checksum ${checksum} · host ${expected} · ${checksum === expected ? "equal" : "DIFFERENT"}`);
}

const runInstructions = () => [limitInstruction(COMPUTE_UNIT_LIMIT), program([readonly(policy)], withHeader(0, ENGINE))];
const lamportsBefore = (await base.getBalance(payer.address).send()).value;
const deployed = (await patiently(() => baseRead.getAccountInfo(PROGRAM, { encoding: "base64" }).send())).value;
if (!deployed?.executable) {
	console.log(`program ${PROGRAM} is not deployed on ${BASE_RPC}`);
	process.exit(1);
}
console.log(`program ${PROGRAM} policy ${policy} payer ${payer.address}`);

let state = await readPolicy(baseRead);
if (state?.owner === DELEGATION_PROGRAM) {
	await mustSend(ephemeral, "er", "return a policy left delegated", [program([signerMeta, writable(policy), readonly(MAGIC_PROGRAM), writable(MAGIC_CONTEXT)], u64Bytes(4))]);
	state = await waitFor(baseRead, "undelegated on base", (current) => current.owner === PROGRAM, 120000);
}
if (state === null || state.owner === SYSTEM_PROGRAM) {
	await mustSend(base, "base", "initialize policy", [program([signerMeta, writable(policy), readonly(SYSTEM_PROGRAM)], u64Bytes(1))]);
	state = await readPolicy(baseRead);
}
if (!sameBlob(state)) {
	for (let offset = 0; offset < blob.length; offset += CHUNK_BYTES) {
		const chunk = blob.subarray(offset, Math.min(offset + CHUNK_BYTES, blob.length));
		await mustSend(base, "base", `write ${offset}+${chunk.length}`, [program([signerMeta, writable(policy)], withHeader(2, offset, chunk))]);
	}
	state = await readPolicy(baseRead);
}
console.log(`policy on base: ${state.data.length} bytes, ${sameBlob(state) ? "equals the checkpoint" : "DIFFERS from the checkpoint"}`);
if (!sameBlob(state)) process.exit(1);

report("A. ER, policy on L1 not delegated", await send(ephemeral, "er", "run, policy not delegated", runInstructions()));

async function untilErRuns(label, expected, timeoutMs) {
	const started = Date.now();
	let seen = null;
	while (Date.now() - started < timeoutMs) {
		const sent = await send(ephemeral, "er", label, runInstructions());
		seen = sent.err ? null : checksumIn(sent.logs);
		if (seen === expected) {
			console.log(`${label}: ER runs on ${expected} after ${Date.now() - started}ms`);
			return true;
		}
		await sleep(5000);
	}
	console.log(`${label}: ER still runs on ${seen} after ${timeoutMs}ms, expected ${expected}`);
	return false;
}

const rewritten = blob.slice();
for (let index = REWRITE_OFFSET; index < REWRITE_OFFSET + REWRITE_BYTES; index++) rewritten[index] ^= 0xff;
await mustSend(base, "base", "rewrite weights on L1", [program([signerMeta, writable(policy)], withHeader(2, REWRITE_OFFSET, rewritten.subarray(REWRITE_OFFSET, REWRITE_OFFSET + REWRITE_BYTES)))]);
const erView = await readPolicy(ephemeral);
console.log(`C. ER account view right after the L1 rewrite: ${holds(rewritten)(erView) ? "new bytes" : "old bytes"}`);
await untilErRuns("C. ER run after the L1 rewrite", REWRITTEN_CHECKSUM, 180000);
await mustSend(base, "base", "restore weights on L1", [program([signerMeta, writable(policy)], withHeader(2, REWRITE_OFFSET, blob.subarray(REWRITE_OFFSET, REWRITE_OFFSET + REWRITE_BYTES)))]);
await untilErRuns("C. ER run after the L1 restore", HOST_CHECKSUM, 180000);

await mustSend(base, "base", "delegate policy", [program([
	signerMeta,
	readonly(SYSTEM_PROGRAM),
	writable(policy),
	readonly(PROGRAM),
	writable(buffer),
	writable(delegationRecord),
	writable(delegationMetadata),
	readonly(DELEGATION_PROGRAM),
	readonly(VALIDATOR),
], u64Bytes(3))]);
await waitFor(ephemeral, "policy visible in ER", (current) => current.owner === PROGRAM && sameBlob(current), 60000);

report("B. ER, policy delegated", await send(ephemeral, "er", "run, policy delegated", runInstructions()));

await mustSend(ephemeral, "er", "commit and undelegate", [program([signerMeta, writable(policy), readonly(MAGIC_PROGRAM), writable(MAGIC_CONTEXT)], u64Bytes(4))]);
const landed = await waitFor(baseRead, "undelegated on base", (current) => current.owner === PROGRAM, 120000);
const lamportsAfter = (await base.getBalance(payer.address).send()).value;
console.log(`policy back on base: owner program, ${sameBlob(landed) ? "equals the checkpoint" : "DIFFERS from the checkpoint"}`);
console.log(`payer spent ${lamportsBefore - lamportsAfter} lamports on base during this run`);
