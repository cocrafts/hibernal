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
	generateKeyPairSigner,
	getBase64EncodedWireTransaction,
	getProgramDerivedAddress,
	getSignatureFromTransaction,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";
import {
	TOKEN_PROGRAM_ADDRESS,
	findAssociatedTokenPda,
	getCreateAssociatedTokenIdempotentInstruction,
	getMintDecoder,
	getTokenDecoder,
} from "@solana-program/token";

const BASE_RPC = process.env.BASE_RPC ?? "https://api.devnet.solana.com";
const BASE_READ_RPC = process.env.BASE_READ_RPC ?? BASE_RPC;
const ER_RPC = process.env.ER_RPC ?? "https://devnet-as.magicblock.app";
const VALIDATOR = address(process.env.VALIDATOR ?? "MAS1Dt9qreoRMQ14YQuhg8UTZMMzDdKhmkZMECCzk57");
const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const DELEGATION_PROGRAM = address("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
const MAGIC_PROGRAM = address("Magic11111111111111111111111111111111111111");
const MAGIC_CONTEXT = address("MagicContext1111111111111111111111111111111");
const OWNER_LAMPORTS = 10_000_000n;
const PET_EARNED = 32;

const [programArgument, mode = "claim", countArgument = "25"] = process.argv.slice(2);
if (!programArgument || !["claim", "commits", "emptyWallet"].includes(mode)) {
	console.log("usage: node tools/chain/payoutDevnet.mjs <payout probe program id> [claim | commits <n> | emptyWallet]");
	process.exit(2);
}
const PROGRAM = address(programArgument);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const encoder = getAddressEncoder();
const base = createSolanaRpc(BASE_RPC);
const baseRead = createSolanaRpc(BASE_READ_RPC);
const ephemeral = createSolanaRpc(ER_RPC);
const payer = await createKeyPairSignerFromBytes(Uint8Array.from(JSON.parse(readFileSync(`${process.env.HOME}/.config/solana/id.json`, "utf8"))));
const owner = await keypairAt("payoutOwner");
const pda = async (programAddress, ...seeds) => (await getProgramDerivedAddress({ programAddress, seeds }))[0];
const mint = await pda(PROGRAM, "mint");
const pet = await pda(PROGRAM, "pet", Uint8Array.of(0));
const ledger = await pda(PROGRAM, "paid", Uint8Array.of(0));
const petBuffer = await pda(PROGRAM, "buffer", encoder.encode(pet));
const record = await pda(DELEGATION_PROGRAM, "delegation", encoder.encode(pet));
const metadata = await pda(DELEGATION_PROGRAM, "delegation-metadata", encoder.encode(pet));
const [ownerTokens] = await findAssociatedTokenPda({ owner: owner.address, mint, tokenProgram: TOKEN_PROGRAM_ADDRESS });

const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });
const signing = (signer) => ({ address: signer.address, role: AccountRole.WRITABLE_SIGNER, signer });
const call = (accounts, data) => ({ programAddress: PROGRAM, accounts, data });
const json = (value) => JSON.stringify(value, (_, inner) => typeof inner === "bigint" ? inner.toString() : inner);
const logged = (logs) => logs.filter((line) => line.startsWith("Program log: 0x")).map((line) => BigInt(line.split(", ").pop()));

function keypairAt(name) {
	const path = new URL(`../../out/${name}.json`, import.meta.url);
	if (!existsSync(path)) {
		const { privateKey, publicKey } = generateKeyPairSync("ed25519");
		writeFileSync(path, JSON.stringify([...privateKey.export({ format: "der", type: "pkcs8" }).subarray(-32), ...publicKey.export({ format: "der", type: "spki" }).subarray(-32)]));
	}
	return createKeyPairSignerFromBytes(Uint8Array.from(JSON.parse(readFileSync(path, "utf8"))));
}

function words(...values) {
	const bytes = new Uint8Array(8 * values.length);
	const view = new DataView(bytes.buffer);
	values.forEach((value, index) => view.setBigUint64(8 * index, BigInt(value), true));
	return bytes;
}

async function patiently(action) {
	for (let attempt = 1; ; attempt++) {
		try {
			return await action();
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
		await sleep(1500);
	}
	return null;
}

async function send(rpc, layer, step, instructions, feePayer = payer) {
	const { value: blockhash } = await patiently(() => rpc.getLatestBlockhash().send());
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(feePayer, m),
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
			const details = await fetchTransaction(rpc === base ? baseRead : rpc, signature);
			const logs = details?.meta?.logMessages ?? [];
			const [earned, paid, amount] = logged(logs);
			console.log(`[${layer}] ${step}: ${status.err ? "REFUSED " + json(status.err) : "ok"} ${Date.now() - started}ms ${details?.meta?.computeUnitsConsumed ?? "-"} CU · fee ${details?.meta?.fee ?? "-"} · signed by ${feePayer === owner ? "the owner" : feePayer === payer ? "the game's payer" : feePayer.address}${amount === undefined ? "" : ` · earned ${earned} paid before ${paid} paid now ${amount}`}`);
			return { signature, logs, err: status.err };
		}
		await sleep(500);
	}
	throw new Error(`${step}: not confirmed`);
}

async function read(rpc, key) {
	const { value } = await patiently(() => rpc.getAccountInfo(key, { encoding: "base64", commitment: "confirmed" }).send());
	return value ? { owner: value.owner, lamports: value.lamports, data: new Uint8Array(Buffer.from(value.data[0], "base64")) } : null;
}

const earnedIn = (state) => state ? new DataView(state.data.buffer).getBigUint64(PET_EARNED, true) : null;
const tokensHeld = async () => { const state = await read(baseRead, ownerTokens); return state ? getTokenDecoder().decode(state.data).amount : 0n; };
const balanceOf = async (rpc, key) => (await patiently(() => rpc.getBalance(key).send())).value;

async function onL1(label, predicate, timeoutMs = 120000) {
	const started = Date.now();
	while (Date.now() - started < timeoutMs) {
		const state = await read(baseRead, pet);
		if (predicate(state)) return Date.now() - started;
		await sleep(1000);
	}
	throw new Error(`${label}: not seen on L1 within ${timeoutMs}ms`);
}

async function commitsSettled(count) {
	const delegate = () => send(base, "base", "delegate pet 0 to the ER", [call([signing(payer), readonly(SYSTEM_PROGRAM), writable(pet), readonly(PROGRAM), writable(petBuffer), writable(record), writable(metadata), readonly(DELEGATION_PROGRAM), readonly(VALIDATOR)], words(2, 0))]);
	if ((await read(baseRead, pet)).owner !== DELEGATION_PROGRAM) await delegate();
	const deposit = (await read(baseRead, record)).lamports + (await read(baseRead, metadata)).lamports;
	const payerBefore = await balanceOf(baseRead, payer.address);
	let seen = earnedIn(await read(baseRead, pet));
	let accepted = null;
	for (let index = 0; index < count; index++) {
		await earn(1);
		const sent = await commit(false);
		if (sent.err) {
			const refusal = sent.logs.find((line) => line.includes("commit limit")) ?? json(sent.err);
			accepted = Number(refusal.match(/nonce (\d+)/)?.[1] ?? NaN);
			console.log(`commit refused: ${refusal}`);
			break;
		}
		seen += 1n;
		await onL1(`commit ${index + 1}`, (state) => earnedIn(state) === seen);
	}
	await commit(true);
	await onL1("undelegation", (state) => state?.owner === PROGRAM);
	await sleep(3000);
	const refunded = (await balanceOf(baseRead, payer.address)) - payerBefore;
	const commits = (accepted ?? count) + 1;
	const asked = 300_000n + 100_000n * BigInt(commits - 1);
	console.log(`${commits} commits in this delegation, the last one undelegating: deposit ${deposit} lamports · MagicBlock asks min(300,000 + 100,000 × ${commits - 1}, deposit) = ${asked < deposit ? asked : deposit} · kept ${deposit - refunded} · refunded ${refunded} to the game's payer`);
}

async function emptyWalletActed() {
	const empty = await generateKeyPairSigner();
	console.log(`fresh wallet ${empty.address}: ${await balanceOf(baseRead, empty.address)} lamports on L1, ${await balanceOf(ephemeral, empty.address)} in the ER`);
	if ((await read(baseRead, pet)).owner !== DELEGATION_PROGRAM) {
		await send(base, "base", "delegate pet 0 to the ER", [call([signing(payer), readonly(SYSTEM_PROGRAM), writable(pet), readonly(PROGRAM), writable(petBuffer), writable(record), writable(metadata), readonly(DELEGATION_PROGRAM), readonly(VALIDATOR)], words(2, 0))]);
	}
	const before = earnedIn(await read(ephemeral, pet));
	const sent = await send(ephemeral, "er", "the empty wallet signs and pays a write to pet 0", [call([writable(pet)], words(3, 1))], empty).catch((error) => ({ err: String(error.message ?? error).slice(0, 300) }));
	console.log(`empty wallet in the ER: ${sent.err ? `refused ${json(sent.err)}` : "accepted"} · pet earned ${before} → ${earnedIn(await read(ephemeral, pet))} · wallet now ${await balanceOf(ephemeral, empty.address)} lamports in the ER`);
	await commit(true);
	await onL1("undelegation", (state) => state?.owner === PROGRAM);
}

const claim = () => send(base, "base", "owner claims on L1", [call([signing(owner), readonly(pet), writable(ledger), writable(mint), writable(ownerTokens), readonly(TOKEN_PROGRAM_ADDRESS)], words(6, 0))], owner);
const earn = (amount) => send(ephemeral, "er", `pet earns ${amount} in the ER`, [call([writable(pet)], words(3, amount))]);
const commit = (undelegating) => send(ephemeral, "er", undelegating ? "commit and undelegate the pet" : "commit the pet, it stays delegated", [call([signing(payer), writable(pet), readonly(MAGIC_PROGRAM), writable(MAGIC_CONTEXT)], words(undelegating ? 5 : 4))]);

console.log(`program ${PROGRAM} · owner ${owner.address} · pet ${pet} · mint ${mint}`);
if (mode === "commits") {
	await commitsSettled(Number(countArgument));
	process.exit(0);
}
if (mode === "emptyWallet") {
	await emptyWalletActed();
	process.exit(0);
}
if ((await balanceOf(baseRead, owner.address)) < OWNER_LAMPORTS / 2n) {
	await send(base, "base", "fund the owner's wallet", [{ programAddress: SYSTEM_PROGRAM, accounts: [signing(payer), writable(owner.address)], data: new Uint8Array([2, 0, 0, 0, ...words(OWNER_LAMPORTS)]) }]);
}
const ownerBefore = await balanceOf(baseRead, owner.address);
if (!(await read(baseRead, mint))) {
	await send(base, "base", "the program creates the mint", [call([signing(payer), writable(mint), readonly(SYSTEM_PROGRAM), readonly(TOKEN_PROGRAM_ADDRESS)], words(0))]);
}
const minted = getMintDecoder().decode((await read(baseRead, mint)).data);
console.log(`mint: decimals ${minted.decimals}, supply ${minted.supply}, mint authority ${minted.mintAuthority.value === mint ? "the mint PDA itself" : minted.mintAuthority.value}, freeze authority ${minted.freezeAuthority.__option}`);
if (!(await read(baseRead, pet))) {
	await send(base, "base", "create pet 0 for the owner", [call([signing(payer), writable(pet), writable(ledger), readonly(SYSTEM_PROGRAM)], new Uint8Array([...words(1, 0), ...encoder.encode(owner.address)]))]);
}
await send(base, "base", "the owner opens its token account", [getCreateAssociatedTokenIdempotentInstruction({ payer: owner, ata: ownerTokens, owner: owner.address, mint })], owner);
if ((await read(baseRead, pet)).owner !== DELEGATION_PROGRAM) {
	await send(base, "base", "delegate pet 0 to the ER", [call([signing(payer), readonly(SYSTEM_PROGRAM), writable(pet), readonly(PROGRAM), writable(petBuffer), writable(record), writable(metadata), readonly(DELEGATION_PROGRAM), readonly(VALIDATOR)], words(2, 0))]);
}
const petStart = await read(baseRead, pet);
const startEarned = earnedIn(petStart);
console.log(`pet on L1: owned by ${petStart.owner === DELEGATION_PROGRAM ? "the delegation program (delegated)" : petStart.owner}, ${petStart.lamports} lamports, earned ${startEarned}; owner holds ${await tokensHeld()}`);

for (let turn = 0; turn < 3; turn++) await earn(1_000_000);
console.log(`pet in the ER: earned ${earnedIn(await read(ephemeral, pet))}; on L1 still ${earnedIn(await read(baseRead, pet))}`);
await claim();
await commit(false);
console.log(`commit seen on L1 after ${await onL1("first commit", (state) => earnedIn(state) === startEarned + 3_000_000n)}ms, pet still ${(await read(baseRead, pet)).owner === DELEGATION_PROGRAM ? "delegated" : "NOT delegated"}`);
await claim();
await claim();
await earn(20_000_000);
await commit(false);
console.log(`second commit seen on L1 after ${await onL1("second commit", (state) => earnedIn(state) === startEarned + 23_000_000n)}ms`);
await claim();
await earn(1);
console.log(`the pet keeps earning in the ER after the claims: earned ${earnedIn(await read(ephemeral, pet))}`);
await commit(true);
console.log(`pet back on L1 after ${await onL1("undelegation", (state) => state?.owner === PROGRAM)}ms, owned by the program, earned ${earnedIn(await read(baseRead, pet))}`);
const petEnd = await read(baseRead, pet);
const supply = getMintDecoder().decode((await read(baseRead, mint)).data).supply;
console.log(`owner holds ${await tokensHeld()} of supply ${supply} · owner's SOL moved ${(await balanceOf(baseRead, owner.address)) - ownerBefore} lamports (its token account's rent and its claim fees) · pet lamports ${petStart.lamports} → ${petEnd.lamports}`);
