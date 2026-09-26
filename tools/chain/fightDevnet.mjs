import { readFileSync } from "node:fs";
import {
	AccountRole,
	address,
	appendTransactionMessageInstruction,
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
const PROGRAM = address(process.argv[2]);
const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const DELEGATION_PROGRAM = address("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
const MAGIC_PROGRAM = address("Magic11111111111111111111111111111111111111");
const MAGIC_CONTEXT = address("MagicContext1111111111111111111111111111111");
const VRF_PROGRAM = address("Vrf1RNUjXmQGjmQrQLvJHs9SNkvDJEsRVFPkfSQUwGz");
const VRF_EPHEMERAL_QUEUE = address(process.env.VRF_QUEUE ?? "5hBR571xnXppuCPveTrctfTU7tJLSN94nq7kv7FRK5Tc");
const SLOT_HASHES = address("SysvarS1otHashes111111111111111111111111111");
const matchups = [
	[80, 50, 5, 50, 80, 5, 42n],
	[50, 50, 5, 50, 50, 5, 7n],
	[200, 200, 5, 160, 80, 5, 123456789n],
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const addressEncoder = getAddressEncoder();
const payer = await createKeyPairSignerFromBytes(Uint8Array.from(JSON.parse(readFileSync(`${process.env.HOME}/.config/solana/id.json`, "utf8"))));
const base = createSolanaRpc(BASE_RPC);
const baseRead = createSolanaRpc(BASE_READ_RPC);
const ephemeral = createSolanaRpc(ER_RPC);
const [arena] = await getProgramDerivedAddress({ programAddress: PROGRAM, seeds: ["arena", addressEncoder.encode(payer.address)] });
const arenaBytes = addressEncoder.encode(arena);
const [buffer] = await getProgramDerivedAddress({ programAddress: PROGRAM, seeds: ["buffer", arenaBytes] });
const [delegationRecord] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation", arenaBytes] });
const [delegationMetadata] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation-metadata", arenaBytes] });
const [programIdentity] = await getProgramDerivedAddress({ programAddress: PROGRAM, seeds: ["identity"] });

const signerMeta = { address: payer.address, role: AccountRole.WRITABLE_SIGNER, signer: payer };
const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });

function u64Bytes(value) {
	const bytes = new Uint8Array(8);
	new DataView(bytes.buffer).setBigUint64(0, BigInt(value), true);
	return bytes;
}

function matchupData(discriminator, [attackerMight, attackerGrit, attackerHearts, defenderMight, defenderGrit, defenderHearts, seed], trailer) {
	const bytes = new Uint8Array(40);
	const view = new DataView(bytes.buffer);
	view.setBigUint64(0, BigInt(discriminator), true);
	[attackerMight, attackerGrit, attackerHearts, defenderMight, defenderGrit, defenderHearts].forEach((value, index) => view.setUint32(8 + index * 4, value, true));
	if (trailer === "seed") view.setBigUint64(32, seed, true);
	else view.setUint8(32, Number(seed & 0xffn));
	return bytes;
}

function fightUnits(logs) {
	const remaining = logs.filter((line) => line.startsWith("Program consumption:")).map((line) => Number(line.split(" ")[2]));
	return remaining.length >= 2 ? remaining[0] - remaining[1] : null;
}

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

async function fetchTransaction(rpc, signature) {
	for (let attempt = 0; attempt < 30; attempt++) {
		const found = await patiently(() => rpc.getTransaction(signature, { maxSupportedTransactionVersion: 0, commitment: "confirmed", encoding: "json" }).send());
		if (found) return found;
		await sleep(500);
	}
	return null;
}

async function send(rpc, layer, step, accounts, data) {
	const { value: blockhash } = await rpc.getLatestBlockhash().send();
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(payer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstruction({ programAddress: PROGRAM, accounts, data }, m),
	);
	const transaction = await signTransactionMessageWithSigners(message);
	const signature = getSignatureFromTransaction(transaction);
	const started = Date.now();
	await rpc.sendTransaction(getBase64EncodedWireTransaction(transaction), { encoding: "base64", skipPreflight: true }).send();
	for (let attempt = 0; attempt < 120; attempt++) {
		const { value } = await rpc.getSignatureStatuses([signature]).send();
		const status = value[0];
		if (status && (status.confirmationStatus === "confirmed" || status.confirmationStatus === "finalized")) {
			const elapsed = Date.now() - started;
			const details = await fetchTransaction(rpc === base ? baseRead : rpc, signature);
			const logs = details?.meta?.logMessages ?? [];
			const units = details?.meta?.computeUnitsConsumed !== undefined ? Number(details.meta.computeUnitsConsumed) : null;
			console.log(`[${layer}] ${step}: ${status.err ? "FAILED " + JSON.stringify(status.err, (_, v) => typeof v === "bigint" ? v.toString() : v) : "ok"} ${elapsed}ms ${units} CU ${signature}`);
			if (status.err) {
				console.log(logs.join("\n"));
				throw new Error(`${step} failed`);
			}
			return { signature, logs, units };
		}
		await sleep(500);
	}
	throw new Error(`${step}: not confirmed`);
}

async function readArena(rpc) {
	const { value } = await patiently(() => rpc.getAccountInfo(arena, { encoding: "base64", commitment: "confirmed" }).send());
	if (!value) return null;
	const bytes = Buffer.from(value.data[0], "base64");
	return {
		owner: value.owner,
		fights: bytes.length >= 8 ? bytes.readBigUInt64LE(0) : null,
		seed: bytes.length >= 16 ? bytes.readBigUInt64LE(8) : null,
		outcome: bytes.length > 16 ? bytes[16] : null,
		rounds: bytes.length >= 24 ? bytes.readUInt32LE(20) : null,
		attackerHp: bytes.length >= 28 ? bytes.readUInt32LE(24) : null,
		defenderHp: bytes.length >= 32 ? bytes.readUInt32LE(28) : null,
		mode: bytes.length > 40 ? bytes[40] : null,
	};
}

async function waitFor(rpc, label, predicate, timeoutMs) {
	const started = Date.now();
	while (Date.now() - started < timeoutMs) {
		const state = await readArena(rpc);
		if (state && predicate(state)) {
			console.log(`${label}: after ${Date.now() - started}ms`, state);
			return state;
		}
		await sleep(1000);
	}
	const last = await readArena(rpc);
	console.log(`${label}: TIMED OUT after ${timeoutMs}ms`, last);
	process.exitCode = 1;
	return last;
}

const describe = (state) => `seed=${state.seed} outcome=${state.outcome} rounds=${state.rounds} attackerHp=${state.attackerHp} defenderHp=${state.defenderHp}`;
console.log(`program ${PROGRAM} arena ${arena} identity ${programIdentity}`);

const existing = await readArena(baseRead);
if (existing === null || existing.owner === SYSTEM_PROGRAM) {
	await send(base, "base", "initialize arena", [signerMeta, writable(arena), readonly(SYSTEM_PROGRAM)], u64Bytes(0));
}
const baseFight = await send(base, "base", "fight 0", [signerMeta, writable(arena)], matchupData(1, matchups[0], "seed"));
console.log(`  fight CU ${fightUnits(baseFight.logs)} | ${describe(await readArena(baseRead))}`);

await send(base, "base", "delegate arena", [
	signerMeta,
	readonly(SYSTEM_PROGRAM),
	writable(arena),
	readonly(PROGRAM),
	writable(buffer),
	writable(delegationRecord),
	writable(delegationMetadata),
	readonly(DELEGATION_PROGRAM),
	readonly(VALIDATOR),
], u64Bytes(2));
await waitFor(ephemeral, "arena visible in ER", (state) => state.owner === PROGRAM, 30000);

for (const [index, matchup] of matchups.entries()) {
	const sent = await send(ephemeral, "er", `fight ${index}`, [signerMeta, writable(arena)], matchupData(1, matchup, "seed"));
	console.log(`  fight CU ${fightUnits(sent.logs)} | ${describe(await readArena(ephemeral))}`);
}

if (process.env.SKIP_VRF !== "1") {
	const beforeVrf = await readArena(ephemeral);
	await send(ephemeral, "er", "request VRF fight", [
		signerMeta,
		writable(arena),
		writable(VRF_EPHEMERAL_QUEUE),
		readonly(programIdentity),
		readonly(VRF_PROGRAM),
		readonly(SLOT_HASHES),
		readonly(SYSTEM_PROGRAM),
	], matchupData(5, matchups[0], "client"));
	await waitFor(ephemeral, "VRF callback fight", (state) => state.mode === 1 && state.fights > beforeVrf.fights, 90000);
}

if (process.env.SKIP_CRANK !== "1") {
	const beforeCrank = await readArena(ephemeral);
	const crank = new Uint8Array(40);
	const crankView = new DataView(crank.buffer);
	crankView.setBigUint64(0, 7n, true);
	crankView.setBigUint64(8, BigInt(Date.now()), true);
	crankView.setBigUint64(16, 1000n, true);
	crankView.setBigUint64(24, 3n, true);
	crankView.setBigUint64(32, 8n, true);
	await send(ephemeral, "er", "schedule crank fights", [signerMeta, writable(arena), readonly(MAGIC_PROGRAM)], crank);
	await waitFor(ephemeral, "crank fights", (state) => state.mode === 2 && state.fights >= beforeCrank.fights + 3n, 60000);
}

const finalEphemeral = await readArena(ephemeral);
await send(ephemeral, "er", "commit and undelegate", [signerMeta, writable(arena), readonly(MAGIC_PROGRAM), writable(MAGIC_CONTEXT)], u64Bytes(3));
const landed = await waitFor(baseRead, "undelegated on base", (state) => state.owner === PROGRAM && state.fights === finalEphemeral.fights, 120000);
console.log(`final base arena: fights=${landed?.fights} mode=${landed?.mode} owner=${landed?.owner === PROGRAM ? "program" : landed?.owner}`);
