import { LiteSVM } from "litesvm";
import {
	AccountRole,
	address,
	appendTransactionMessageInstruction,
	createTransactionMessage,
	createKeyPairSignerFromPrivateKeyBytes,
	generateKeyPairSigner,
	getAddressEncoder,
	getProgramDerivedAddress,
	lamports,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";

const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const DELEGATION_PROGRAM = address("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
const delegationProgramPath = process.env.DELEGATION_PROGRAM_SO ?? "";
const addressEncoder = getAddressEncoder();

function u64Bytes(value) {
	const bytes = new Uint8Array(8);
	new DataView(bytes.buffer).setBigUint64(0, BigInt(value), true);
	return bytes;
}

function concatBytes(...parts) {
	const out = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
	let offset = 0;
	for (const part of parts) {
		out.set(part, offset);
		offset += part.length;
	}
	return out;
}

async function runCounterFlow(label, programPath) {
	const svm = new LiteSVM();
	const payer = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(1));
	const program = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(2));
	svm.airdrop(payer.address, lamports(10_000_000_000n));
	svm.addProgramFromFile(program.address, programPath);
	if (delegationProgramPath !== "") svm.addProgramFromFile(DELEGATION_PROGRAM, delegationProgramPath);
	const [counter] = await getProgramDerivedAddress({
		programAddress: program.address,
		seeds: ["counter", addressEncoder.encode(payer.address)],
	});
	const payerMeta = { address: payer.address, role: AccountRole.WRITABLE_SIGNER, signer: payer };
	const counterMeta = { address: counter, role: AccountRole.WRITABLE };
	const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
	const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });

	async function send(step, accounts, data, expectFailure = false) {
		const instruction = { programAddress: program.address, accounts, data };
		const message = pipe(
			createTransactionMessage({ version: 0 }),
			(m) => setTransactionMessageFeePayerSigner(payer, m),
			(m) => setTransactionMessageLifetimeUsingBlockhash({ blockhash: svm.latestBlockhash(), lastValidBlockHeight: 1000n }, m),
			(m) => appendTransactionMessageInstruction(instruction, m),
		);
		const transaction = await signTransactionMessageWithSigners(message);
		const result = svm.sendTransaction(transaction);
		svm.expireBlockhash();
		const failed = result.constructor.name === "FailedTransactionMetadata";
		const meta = failed ? result.meta() : result;
		const computeUnits = Number(meta.computeUnitsConsumed());
		if (failed !== expectFailure) {
			console.log(`[${label}] ${step}: ${failed ? "FAILED " + result.err().toString() : "unexpected success"}`);
			console.log(meta.logs().join("\n"));
			process.exitCode = 1;
			return { ok: false, computeUnits };
		}
		const verdict = failed ? `rejected as expected (${result.err().toString()})` : "ok";
		console.log(`[${label}] ${step}: ${verdict}, ${computeUnits} CU`);
		return { ok: true, computeUnits };
	}

	function snapshot(key) {
		const stored = svm.getAccount(key);
		if (!stored.exists) return { exists: false };
		const view = new DataView(stored.data.buffer, stored.data.byteOffset, stored.data.length);
		return {
			exists: true,
			owner: stored.programAddress,
			lamports: stored.lamports,
			length: stored.data.length,
			count: stored.data.length >= 8 ? view.getBigUint64(0, true) : null,
		};
	}

	const steps = [];
	steps.push(["initialize", await send("initialize", [payerMeta, counterMeta, readonly(SYSTEM_PROGRAM)], u64Bytes(0))]);
	steps.push(["increase 5", await send("increase 5", [payerMeta, counterMeta], concatBytes(u64Bytes(1), u64Bytes(5)))]);
	steps.push(["increase 7", await send("increase 7", [payerMeta, counterMeta], concatBytes(u64Bytes(1), u64Bytes(7)))]);
	const stranger = await generateKeyPairSigner();
	steps.push(["wrong counter", await send("increase on a non-PDA account", [payerMeta, writable(stranger.address)], concatBytes(u64Bytes(1), u64Bytes(1)), true)]);

	const state = snapshot(counter);
	const ownerMatches = state.exists && state.owner === program.address;
	console.log(`[${label}] counter ${counter}: count=${state.count} owner=${ownerMatches ? "program" : state.owner} lamports=${state.lamports} length=${state.length}`);
	if (!ownerMatches || state.count !== 12n) process.exitCode = 1;

	if (delegationProgramPath !== "") {
		const counterBytes = addressEncoder.encode(counter);
		const [buffer] = await getProgramDerivedAddress({ programAddress: program.address, seeds: ["buffer", counterBytes] });
		const [record] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation", counterBytes] });
		const [metadata] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation-metadata", counterBytes] });
		steps.push(["delegate", await send("delegate", [
			payerMeta,
			readonly(SYSTEM_PROGRAM),
			counterMeta,
			readonly(program.address),
			writable(buffer),
			writable(record),
			writable(metadata),
			readonly(DELEGATION_PROGRAM),
		], u64Bytes(2))]);
		const delegated = snapshot(counter);
		const recordState = snapshot(record);
		const bufferState = snapshot(buffer);
		const delegatedToProgram = delegated.owner === DELEGATION_PROGRAM;
		console.log(`[${label}] after delegate: counter owner=${delegatedToProgram ? "delegation program" : delegated.owner} count=${delegated.count} record=${recordState.exists ? recordState.length + " bytes" : "missing"} buffer=${bufferState.exists ? bufferState.lamports + " lamports" : "closed"}`);
		if (!delegatedToProgram || !recordState.exists) process.exitCode = 1;
	}
	return steps;
}

const targets = process.argv.slice(2).map((entry) => {
	const [label, path] = entry.includes("=") ? entry.split("=") : [entry, entry];
	return { label, path };
});
const table = [];
for (const target of targets) {
	table.push({ label: target.label, steps: await runCounterFlow(target.label, target.path) });
}
if (table.length > 1) {
	console.log("\nstep".padEnd(34) + table.map((t) => t.label.padStart(14)).join(""));
	for (let i = 0; i < table[0].steps.length; i++) {
		console.log(table[0].steps[i][0].padEnd(33) + table.map((t) => String(t.steps[i]?.[1]?.computeUnits ?? "-").padStart(14)).join(""));
	}
}
