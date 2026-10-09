import { createHash, randomBytes } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import {
	address,
	appendTransactionMessageInstructions,
	createKeyPairSignerFromPrivateKeyBytes,
	createTransactionMessage,
	getBase64EncodedWireTransaction,
	getProgramDerivedAddress,
	getSignatureFromTransaction,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";
import {
	ASSOCIATED_TOKEN_PROGRAM,
	SYSTEM_PROGRAM,
	TOKEN_2022_PROGRAM,
	cluster,
	computeLimit,
	encoder,
	hibernal,
	joined,
	keypairAt,
	readonly,
	signer,
	sleep,
	u32,
	u64,
	writable,
	writableSigner,
	MEMBER_MINT_BYTES,
	admissionTicket,
	groupDiscriminator,
} from "./hibernal.mjs";

const STAGE = process.env.STAGE ?? "keys";
const FIRST = Number(process.env.FIRST ?? 0);
const COUNT = Number(process.env.COUNT ?? 1000);
const PARALLEL = Number(process.env.PARALLEL ?? 64);
const IN_FLIGHT = Number(process.env.IN_FLIGHT ?? 1500);
const FUND_LAMPORTS = BigInt(process.env.FUND_LAMPORTS ?? 30_000_000);
const MASTER_PATH = process.env.MASTER ?? "out/localnet/playersMaster.hex";
const MAX_WIRE_BYTES = 1232;
const TOKEN_GROUP_EXTENSION = 21;

const { base, baseRead } = cluster();
const wallet = await keypairAt(`${process.env.HOME}/.config/solana/id.json`);
const group = await keypairAt(process.env.GROUP_KEYPAIR ?? "out/localnet/admissionGroup.json");

function masterSeed() {
	if (!existsSync(MASTER_PATH)) writeFileSync(MASTER_PATH, randomBytes(32).toString("hex"));
	return Buffer.from(readFileSync(MASTER_PATH, "utf8").trim(), "hex");
}

const master = STAGE === "keys" || existsSync(MASTER_PATH) ? masterSeed() : null;

async function derived(domain, index) {
	const bytes = createHash("sha256").update(master).update(domain).update(u64(index)).digest();
	return await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(bytes));
}

async function playerAt(index) {
	return { index, owner: await derived("player", index), mint: await derived("mint", index) };
}

async function playersIn(first, count) {
	const out = [];
	for (let index = first; index < first + count; index++) out.push(await playerAt(index));
	return out;
}

async function associated(owner, mint) {
	const [found] = await getProgramDerivedAddress({
		programAddress: ASSOCIATED_TOKEN_PROGRAM,
		seeds: [encoder.encode(owner), encoder.encode(TOKEN_2022_PROGRAM), encoder.encode(mint)],
	});
	return found;
}

async function existing(keys) {
	const found = new Set();
	for (let index = 0; index < keys.length; index += 100) {
		const chunk = keys.slice(index, index + 100);
		const { value } = await patiently(() => baseRead.getMultipleAccounts(chunk, { encoding: "base64", dataSlice: { offset: 0, length: 0 } }).send());
		value.forEach((account, position) => { if (account) found.add(chunk[position]); });
	}
	return found;
}

async function patiently(call) {
	for (let attempt = 1; ; attempt++) {
		try {
			return await call();
		} catch (error) {
			if (attempt >= 8) throw error;
			await sleep(500 * attempt);
		}
	}
}

class Blockhash {
	constructor(rpc) {
		this.rpc = rpc;
		this.value = null;
		this.at = 0;
	}

	async current() {
		if (!this.value || Date.now() - this.at > 2000) {
			const { value } = await patiently(() => this.rpc.getLatestBlockhash({ commitment: "confirmed" }).send());
			this.value = value;
			this.at = Date.now();
		}
		return this.value;
	}
}

async function signed(blockhash, feePayer, instructions) {
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(feePayer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstructions(instructions, m),
	);
	const transaction = await signTransactionMessageWithSigners(message);
	return { wire: getBase64EncodedWireTransaction(transaction), signature: getSignatureFromTransaction(transaction) };
}

function wireBytes(wire) {
	return Buffer.from(wire, "base64").length;
}

async function runBatches(label, items, perTransaction, build, stillTodo) {
	const blockhash = new Blockhash(base);
	const started = Date.now();
	let queue = [];
	for (let index = 0; index < items.length; index += perTransaction) queue.push(items.slice(index, index + perTransaction));
	let transactions = 0;
	let failures = 0;
	let rounds = 0;
	const errors = new Map();
	while (queue.length > 0) {
		rounds++;
		const pending = new Map();
		const retry = [];
		let next = 0;
		const inFlightWait = async () => {
			while (pending.size >= IN_FLIGHT) await confirmSome(pending, retry, errors, () => failures++);
		};
		const lanes = Array.from({ length: Math.min(PARALLEL, queue.length) }, async () => {
			while (next < queue.length) {
				const batch = queue[next++];
				await inFlightWait();
				const hash = await blockhash.current();
				const { feePayer, instructions } = await build(batch);
				const built = await signed(hash, feePayer, [computeLimit(Math.min(1_400_000, 200_000 * batch.length)), ...instructions]);
				if (wireBytes(built.wire) > MAX_WIRE_BYTES) {
					if (batch.length === 1) throw new Error(`${label}: one item does not fit a transaction (${wireBytes(built.wire)} bytes)`);
					const half = Math.ceil(batch.length / 2);
					queue.push(batch.slice(0, half), batch.slice(half));
					continue;
				}
				try {
					await base.sendTransaction(built.wire, { encoding: "base64", skipPreflight: true, maxRetries: 0n }).send();
					transactions++;
					pending.set(built.signature, { batch, sentAt: Date.now() });
				} catch (error) {
					retry.push(batch);
					failures++;
					errors.set(error.message.slice(0, 80), (errors.get(error.message.slice(0, 80)) ?? 0) + 1);
				}
			}
		});
		await Promise.all(lanes);
		while (pending.size > 0) await confirmSome(pending, retry, errors, () => failures++);
		const left = retry.flat();
		const todo = left.length > 0 ? await stillTodo(left) : [];
		queue = [];
		for (let index = 0; index < todo.length; index += perTransaction) queue.push(todo.slice(index, index + perTransaction));
		if (left.length > 0) console.log(`  ${label}: round ${rounds}: ${left.length} unconfirmed, ${todo.length} still to do`);
		if (rounds > 12) throw new Error(`${label}: ${queue.length} batches still failing after ${rounds} rounds: ${[...errors].map(([k, v]) => `${v}× ${k}`).join("; ")}`);
	}
	const seconds = (Date.now() - started) / 1000;
	console.log(`${label}: ${items.length} players in ${seconds.toFixed(1)} s (${(items.length / seconds).toFixed(0)}/s), ${transactions} transactions, ${failures} failed sends or statuses${errors.size ? ": " + [...errors].map(([k, v]) => `${v}× ${k}`).join("; ") : ""}`);
	return { seconds, transactions, failures };
}

async function confirmSome(pending, retry, errors, failed) {
	await sleep(400);
	const signatures = [...pending.keys()];
	for (let index = 0; index < signatures.length; index += 256) {
		const chunk = signatures.slice(index, index + 256);
		const { value } = await patiently(() => base.getSignatureStatuses(chunk).send());
		value.forEach((status, position) => {
			const signature = chunk[position];
			const entry = pending.get(signature);
			if (!entry) return;
			if (status && (status.confirmationStatus === "confirmed" || status.confirmationStatus === "finalized")) {
				pending.delete(signature);
				if (status.err) {
					failed();
					const key = JSON.stringify(status.err, (_, v) => (typeof v === "bigint" ? v.toString() : v)).slice(0, 80);
					errors.set(key, (errors.get(key) ?? 0) + 1);
					retry.push(entry.batch);
				}
			} else if (Date.now() - entry.sentAt > 45_000) {
				pending.delete(signature);
				failed();
				errors.set("not confirmed in 45 s", (errors.get("not confirmed in 45 s") ?? 0) + 1);
				retry.push(entry.batch);
			}
		});
	}
}

function transfer(from, to, lamports) {
	return { programAddress: SYSTEM_PROGRAM, accounts: [writableSigner(from), writable(to)], data: joined(u32(2), u64(lamports)) };
}

async function keys() {
	const started = Date.now();
	const players = await playersIn(FIRST, COUNT);
	console.log(`keys: master ${MASTER_PATH}, ${players.length} players derived in ${((Date.now() - started) / 1000).toFixed(1)} s; first ${players[0].owner.address} mint ${players[0].mint.address}`);
}

async function groupMaxSize(needed) {
	const { value } = await base.getAccountInfo(group.address, { encoding: "base64" }).send();
	const data = Buffer.from(value.data[0], "base64");
	let at = 166;
	while (at + 4 <= data.length && data.readUInt16LE(at) !== TOKEN_GROUP_EXTENSION) at += 4 + data.readUInt16LE(at + 2);
	if (at + 4 > data.length) throw new Error(`group ${group.address} has no TokenGroup extension`);
	const size = data.readBigUInt64LE(at + 4 + 64);
	const maxSize = data.readBigUInt64LE(at + 4 + 72);
	if (maxSize >= BigInt(needed)) return { size, maxSize };
	const raised = BigInt(Math.max(needed, 100_000));
	const blockhash = new Blockhash(base);
	const { wire, signature } = await signed(await blockhash.current(), wallet, [{
		programAddress: TOKEN_2022_PROGRAM,
		accounts: [writable(group.address), signer(wallet)],
		data: joined(groupDiscriminator("update_group_max_size"), u64(raised)),
	}]);
	await base.sendTransaction(wire, { encoding: "base64" }).send();
	for (let attempt = 0; attempt < 60; attempt++) {
		const { value: [status] } = await base.getSignatureStatuses([signature]).send();
		if (status?.confirmationStatus === "confirmed" || status?.confirmationStatus === "finalized") {
			if (status.err) throw new Error(`raising the group max size failed: ${JSON.stringify(status.err)}`);
			break;
		}
		await sleep(400);
	}
	console.log(`admit: group ${group.address} max size ${maxSize} -> ${raised}`);
	return { size, maxSize: raised };
}

async function admit() {
	await groupMaxSize(FIRST + COUNT + 1000);
	const players = await playersIn(FIRST, COUNT);
	const done = await existing(players.map((player) => player.mint.address));
	const todo = players.filter((player) => !done.has(player.mint.address));
	console.log(`admit: ${done.size} of ${players.length} already admitted, ${todo.length} to go`);
	if (todo.length === 0) return;
	const mintRent = BigInt(await base.getMinimumBalanceForRentExemption(MEMBER_MINT_BYTES).send());
	await runBatches("admit", todo, Number(process.env.PER_TRANSACTION ?? 2), async (batch) => ({
		feePayer: wallet,
		instructions: (await Promise.all(batch.map((player) => admissionTicket(wallet, group.address, player.owner.address, player.mint, mintRent)))).flat(),
	}), async (left) => {
		const made = await existing(left.map((player) => player.mint.address));
		return left.filter((player) => !made.has(player.mint.address));
	});
}

async function fund() {
	const players = await playersIn(FIRST, COUNT);
	const balances = new Map();
	const keysOf = players.map((player) => player.owner.address);
	for (let index = 0; index < keysOf.length; index += 100) {
		const chunk = keysOf.slice(index, index + 100);
		const { value } = await patiently(() => baseRead.getMultipleAccounts(chunk, { encoding: "base64", dataSlice: { offset: 0, length: 0 } }).send());
		value.forEach((account, position) => balances.set(chunk[position], account ? BigInt(account.lamports) : 0n));
	}
	const todo = players.filter((player) => balances.get(player.owner.address) < FUND_LAMPORTS / 2n);
	console.log(`fund: ${players.length - todo.length} of ${players.length} already funded, ${todo.length} to go, ${FUND_LAMPORTS} lamports each`);
	if (todo.length === 0) return;
	await runBatches("fund", todo, Number(process.env.PER_TRANSACTION ?? 20), async (batch) => ({
		feePayer: wallet,
		instructions: batch.map((player) => transfer(wallet, player.owner.address, FUND_LAMPORTS - balances.get(player.owner.address))),
	}), async (left) => {
		const funded = await existing(left.map((player) => player.owner.address));
		return left.filter((player) => !funded.has(player.owner.address));
	});
}

async function ownersOf(keys) {
	const owners = new Map();
	for (let index = 0; index < keys.length; index += 100) {
		const chunk = keys.slice(index, index + 100);
		const { value } = await patiently(() => baseRead.getMultipleAccounts(chunk, { encoding: "base64", dataSlice: { offset: 0, length: 0 } }).send());
		value.forEach((account, position) => owners.set(chunk[position], account?.owner ?? null));
	}
	return owners;
}

function delegated(owners, pet) {
	return owners.get(pet) === "DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh";
}

async function claim() {
	const programAddress = address(process.env.PROGRAM ?? process.argv[2]);
	const program = hibernal(programAddress, wallet);
	const players = await playersIn(FIRST, COUNT);
	const pets = await Promise.all(players.map(async (player) => program.address(program.seeds.pet(player.mint.address))));
	const owners = await ownersOf(pets);
	const todo = players.map((player, position) => ({ ...player, pet: pets[position], claimed: owners.get(pets[position]) !== null })).filter((player) => !delegated(owners, player.pet));
	console.log(`claim: ${players.length - todo.length} of ${players.length} pets already claimed and delegated, ${todo.length} to go (${todo.filter((p) => p.claimed).length} claimed, not delegated)`);
	if (todo.length === 0) return;
	await runBatches("claim+delegate", todo, Number(process.env.PER_TRANSACTION ?? 2), async (batch) => {
		const instructions = [];
		for (const player of batch) {
			if (!player.claimed) instructions.push(await program.claim(player.owner, player.mint.address, await associated(player.owner.address, player.mint.address)));
			instructions.push(await program.delegatePet(player.owner, player.mint.address));
		}
		return { feePayer: batch[0].owner, instructions };
	}, async (left) => {
		const now = await ownersOf(left.map((player) => player.pet));
		return left.filter((player) => !delegated(now, player.pet)).map((player) => ({ ...player, claimed: now.get(player.pet) !== null }));
	});
}

async function exported() {
	const players = await playersIn(FIRST, COUNT);
	const path = process.env.PETS_FILE ?? "out/localnet/players.json";
	writeFileSync(path, JSON.stringify(players.map((player) => ({ index: player.index, owner: player.owner.address, mint: player.mint.address }))));
	console.log(`wrote ${players.length} players to ${path}`);
}

const stages = { keys, admit, fund, claim, export: exported };
if (!stages[STAGE]) throw new Error(`unknown stage ${STAGE}; use STAGE=keys|admit|fund|claim|export`);
await stages[STAGE]();
