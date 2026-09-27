import { existsSync, readFileSync, writeFileSync } from "node:fs";
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
const ROUTER_RPC = process.env.ROUTER_RPC ?? "https://devnet-router.magicblock.app";
const HOME_RPC = process.env.HOME_RPC ?? "https://devnet-as.magicblock.app";
const HOME_VALIDATOR = address(process.env.HOME_VALIDATOR ?? "MAS1Dt9qreoRMQ14YQuhg8UTZMMzDdKhmkZMECCzk57");
const AWAY_RPC = process.env.AWAY_RPC ?? "https://devnet-eu.magicblock.app";
const AWAY_VALIDATOR = address(process.env.AWAY_VALIDATOR ?? "MEUGGrYPxKk17hCr7wpT6s8dtNokZj5U2L57vjYMS8e");
const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const DELEGATION_PROGRAM = address("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
const MAGIC_PROGRAM = address("Magic11111111111111111111111111111111111111");
const MAGIC_CONTEXT = address("MagicContext1111111111111111111111111111111");
const SECOND_PAYER_LAMPORTS = 50_000_000n;
const matchups = [
	[80, 50, 5, 50, 80, 5, 42n],
	[50, 50, 5, 50, 50, 5, 7n],
	[200, 200, 5, 160, 80, 5, 123456789n],
];

if (!process.argv[2]) {
	console.log("usage: node tools/chain/crossDevnet.mjs <fight probe program id>");
	process.exit(2);
}
const PROGRAM = address(process.argv[2]);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const json = (value) => JSON.stringify(value, (_, inner) => typeof inner === "bigint" ? inner.toString() : inner);
const addressEncoder = getAddressEncoder();
const keyBytes = (path) => Uint8Array.from(JSON.parse(readFileSync(path, "utf8")));
const payer = await createKeyPairSignerFromBytes(keyBytes(`${process.env.HOME}/.config/solana/id.json`));
const secondPayerPath = new URL("../../out/crossPayer.json", import.meta.url);
if (!existsSync(secondPayerPath)) {
	const { generateKeyPairSync } = await import("node:crypto");
	const { privateKey, publicKey } = generateKeyPairSync("ed25519");
	const secret = privateKey.export({ format: "der", type: "pkcs8" }).subarray(-32);
	const pub = publicKey.export({ format: "der", type: "spki" }).subarray(-32);
	writeFileSync(secondPayerPath, JSON.stringify([...secret, ...pub]));
}
const secondPayer = await createKeyPairSignerFromBytes(keyBytes(secondPayerPath));
const base = createSolanaRpc(BASE_RPC);
const baseRead = createSolanaRpc(BASE_READ_RPC);
const router = createSolanaRpc(ROUTER_RPC);
const home = createSolanaRpc(HOME_RPC);
const away = createSolanaRpc(AWAY_RPC);
const layers = new Map([[base, "base"], [router, "router"], [home, "home"], [away, "away"]]);
const urls = new Map([[base, BASE_RPC], [router, ROUTER_RPC], [home, HOME_RPC], [away, AWAY_RPC]]);

async function arenaOf(owner) {
	const [key] = await getProgramDerivedAddress({ programAddress: PROGRAM, seeds: ["arena", addressEncoder.encode(owner.address)] });
	const bytes = addressEncoder.encode(key);
	const [buffer] = await getProgramDerivedAddress({ programAddress: PROGRAM, seeds: ["buffer", bytes] });
	const [record] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation", bytes] });
	const [metadata] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation-metadata", bytes] });
	return { owner, key, buffer, record, metadata };
}

const arenaA = await arenaOf(payer);
const arenaB = await arenaOf(secondPayer);
const signer = (who) => ({ address: who.address, role: AccountRole.WRITABLE_SIGNER, signer: who });
const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });
const program = (accounts, data) => ({ programAddress: PROGRAM, accounts, data });

function u64Bytes(value) {
	const bytes = new Uint8Array(8);
	new DataView(bytes.buffer).setBigUint64(0, BigInt(value), true);
	return bytes;
}

function fightData([attackerMight, attackerGrit, attackerHearts, defenderMight, defenderGrit, defenderHearts, seed]) {
	const bytes = new Uint8Array(40);
	const view = new DataView(bytes.buffer);
	view.setBigUint64(0, 1n, true);
	[attackerMight, attackerGrit, attackerHearts, defenderMight, defenderGrit, defenderHearts].forEach((value, index) => view.setUint32(8 + index * 4, value, true));
	view.setBigUint64(32, seed, true);
	return bytes;
}

function transferInstruction(to, lamports) {
	const bytes = new Uint8Array(12);
	const view = new DataView(bytes.buffer);
	view.setUint32(0, 2, true);
	view.setBigUint64(4, lamports, true);
	return { programAddress: SYSTEM_PROGRAM, accounts: [signer(payer), writable(to)], data: bytes };
}

const fightIn = (arena, matchup, extra = []) => program([signer(payer), writable(arena.key), ...extra], fightData(matchup));

async function patiently(call) {
	for (let attempt = 1; ; attempt++) {
		try {
			return await call();
		} catch (error) {
			if (attempt >= 8) throw error;
			await sleep(1500 * attempt);
		}
	}
}

async function fetchTransaction(rpc, signature) {
	for (let attempt = 0; attempt < 20; attempt++) {
		const found = await rpc.getTransaction(signature, { maxSupportedTransactionVersion: 0, commitment: "confirmed", encoding: "json" }).send().catch(() => null);
		if (found) return found;
		await sleep(1000);
	}
	return null;
}

async function send(rpc, step, instructions, blockhashRpc = rpc) {
	const layer = layers.get(rpc);
	const { value: blockhash } = await patiently(() => blockhashRpc.getLatestBlockhash().send());
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(payer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstructions(instructions, m),
	);
	const transaction = await signTransactionMessageWithSigners(message);
	const signature = getSignatureFromTransaction(transaction);
	const wire = getBase64EncodedWireTransaction(transaction);
	const started = Date.now();
	const response = await fetch(urls.get(rpc), {
		method: "POST",
		headers: { "content-type": "application/json" },
		body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "sendTransaction", params: [wire, { encoding: "base64", skipPreflight: true }] }),
	});
	const reply = await response.json();
	if (reply.error) {
		const reason = json(reply.error);
		console.log(`[${layer}] ${step}: REJECTED at send in ${Date.now() - started}ms: ${reason}`);
		return { rejected: reason, err: reason };
	}
	for (let attempt = 0; attempt < 60; attempt++) {
		const { value } = await patiently(() => rpc.getSignatureStatuses([signature]).send());
		const status = value[0];
		if (status && (status.confirmationStatus === "confirmed" || status.confirmationStatus === "finalized")) {
			const elapsed = Date.now() - started;
			const details = layer !== "base" || status.err ? await fetchTransaction(rpc === base ? baseRead : rpc, signature) : null;
			const logs = details?.meta?.logMessages ?? [];
			const units = details?.meta?.computeUnitsConsumed !== undefined ? Number(details.meta.computeUnitsConsumed) : null;
			console.log(`[${layer}] ${step}: ${status.err ? "FAILED " + json(status.err) : "ok"} ${elapsed}ms ${units ?? "-"} CU ${signature}`);
			if (status.err) console.log(logs.filter((line) => !line.startsWith("Program consumption")).map((line) => `    ${line}`).join("\n"));
			return { signature, logs, units, elapsed, err: status.err };
		}
		await sleep(500);
	}
	console.log(`[${layer}] ${step}: not confirmed after 30 s ${signature}`);
	return { signature, err: "not confirmed" };
}

async function mustSend(rpc, step, instructions) {
	const sent = await send(rpc, step, instructions);
	if (sent.err) throw new Error(`${step} failed`);
	return sent;
}

async function readArena(rpc, arena) {
	const { value } = await patiently(() => rpc.getAccountInfo(arena.key, { encoding: "base64", commitment: "confirmed" }).send());
	if (!value) return null;
	const bytes = Buffer.from(value.data[0], "base64");
	return {
		owner: value.owner,
		fights: bytes.length >= 8 ? bytes.readBigUInt64LE(0) : null,
		seed: bytes.length >= 16 ? bytes.readBigUInt64LE(8) : null,
		mode: bytes.length > 40 ? bytes[40] : null,
	};
}

async function waitFor(rpc, label, arena, predicate, timeoutMs) {
	const started = Date.now();
	while (Date.now() - started < timeoutMs) {
		const state = await readArena(rpc, arena).catch(() => null);
		if (state && predicate(state)) {
			console.log(`${label}: after ${Date.now() - started}ms`);
			return state;
		}
		await sleep(1000);
	}
	throw new Error(`${label}: timed out after ${timeoutMs}ms`);
}

const shown = (state) => state === null ? "absent" : `owner ${state.owner === PROGRAM ? "program" : state.owner === DELEGATION_PROGRAM ? "delegation" : state.owner} fights ${state.fights} seed ${state.seed}`;

async function everywhere(label, arena) {
	const [onBase, onHome, onAway] = await Promise.all([readArena(baseRead, arena), readArena(home, arena).catch((error) => `error ${error.message}`), readArena(away, arena).catch((error) => `error ${error.message}`)]);
	const show = (state) => typeof state === "string" ? state : shown(state);
	console.log(`${label}: L1 ${show(onBase)} | home ER ${show(onHome)} | away ER ${show(onAway)}`);
	return { onBase, onHome, onAway };
}

async function delegatedTo(arena, validator, rpc, label) {
	await mustSend(base, `delegate ${label}`, [program([
		signer(arena.owner),
		readonly(SYSTEM_PROGRAM),
		writable(arena.key),
		readonly(PROGRAM),
		writable(arena.buffer),
		writable(arena.record),
		writable(arena.metadata),
		readonly(DELEGATION_PROGRAM),
		readonly(validator),
	], u64Bytes(2))]);
	await waitFor(rpc, `${label} visible in its ER`, arena, (state) => state.owner === PROGRAM, 60000);
}

async function returnedFrom(arena, rpc, label) {
	const started = Date.now();
	await mustSend(rpc, `commit and undelegate ${label}`, [program([signer(payer), writable(arena.key), readonly(MAGIC_PROGRAM), writable(MAGIC_CONTEXT)], u64Bytes(3))]);
	await waitFor(baseRead, `${label} back on L1`, arena, (state) => state.owner === PROGRAM, 240000);
	return Date.now() - started;
}

async function onBaseUndelegated(arena, label) {
	const state = await readArena(baseRead, arena);
	if (state === null || state.owner === SYSTEM_PROGRAM) {
		await mustSend(base, `initialize ${label}`, [program([signer(arena.owner), writable(arena.key), readonly(SYSTEM_PROGRAM)], u64Bytes(0))]);
		return;
	}
	if (state.owner !== DELEGATION_PROGRAM) return;
	for (const rpc of [home, away]) {
		const inEr = await readArena(rpc, arena).catch(() => null);
		if (inEr?.owner === PROGRAM) {
			await returnedFrom(arena, rpc, `${label} left from an earlier run`);
			return;
		}
	}
	throw new Error(`${label} is delegated on L1 but neither ER holds it`);
}

console.log(`program ${PROGRAM} · arena A ${arenaA.key} (payer ${payer.address}) · arena B ${arenaB.key} (payer ${secondPayer.address})`);
console.log(`home ER ${HOME_RPC} (${HOME_VALIDATOR}) · away ER ${AWAY_RPC} (${AWAY_VALIDATOR}) · router ${ROUTER_RPC}`);
const lamportsBefore = (await base.getBalance(payer.address).send()).value;
const secondBalance = (await base.getBalance(secondPayer.address).send()).value;
if (secondBalance < SECOND_PAYER_LAMPORTS / 2n) {
	await mustSend(base, "fund payer B", [transferInstruction(secondPayer.address, SECOND_PAYER_LAMPORTS - secondBalance)]);
}
await onBaseUndelegated(arenaA, "arena A");
await onBaseUndelegated(arenaB, "arena B");
await everywhere("start", arenaA);
await everywhere("start", arenaB);

console.log("\n1. both arenas delegated to the home ER");
await delegatedTo(arenaA, HOME_VALIDATOR, home, "arena A to home");
await delegatedTo(arenaB, HOME_VALIDATOR, home, "arena B to home");
await send(home, "one transaction writes A and B", [fightIn(arenaA, matchups[0]), fightIn(arenaB, matchups[1])]);
await send(router, "the same through the router", [fightIn(arenaA, matchups[1]), fightIn(arenaB, matchups[2])], home);
await everywhere("after", arenaA);
await everywhere("after", arenaB);

console.log("\n2. arena B moves to the away ER");
const moveStarted = Date.now();
const returnMs = await returnedFrom(arenaB, home, "arena B from home");
await delegatedTo(arenaB, AWAY_VALIDATOR, away, "arena B to away");
console.log(`arena B moved home → L1 → away in ${Date.now() - moveStarted}ms (return ${returnMs}ms)`);
await everywhere("moved", arenaB);

console.log("\n3. A in the home ER, B in the away ER");
await send(home, "home ER: one transaction writes A and B", [fightIn(arenaA, matchups[2]), fightIn(arenaB, matchups[0])]);
await send(away, "away ER: one transaction writes A and B", [fightIn(arenaA, matchups[2]), fightIn(arenaB, matchups[0])]);
await send(router, "router: one transaction writes A and B", [fightIn(arenaA, matchups[2]), fightIn(arenaB, matchups[0])], home);
await send(away, "away ER: B alone", [fightIn(arenaB, matchups[1])]);
await everywhere("B written in the away ER only", arenaB);
await send(home, "home ER: writes A, reads B", [fightIn(arenaA, matchups[0], [readonly(arenaB.key)])]);
await everywhere("B after the home ER was handed it read-only", arenaB);

console.log("\n4. back to L1");
await returnedFrom(arenaA, home, "arena A from home");
await returnedFrom(arenaB, away, "arena B from away");
await everywhere("end", arenaA);
await everywhere("end", arenaB);
const lamportsAfter = (await base.getBalance(payer.address).send()).value;
console.log(`\npayer A balance on L1 moved by ${lamportsAfter - lamportsBefore} lamports, delegation rent refunds included (payer B holds ${(await base.getBalance(secondPayer.address).send()).value})`);
