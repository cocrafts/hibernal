import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { generateKeyPairSync, randomBytes } from "node:crypto";
import {
	AccountRole,
	address,
	appendTransactionMessageInstructions,
	createKeyPairSignerFromBytes,
	createSolanaRpc,
	generateKeyPairSigner,
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
import { scenarioOf } from "./blockFixture.mjs";
import { joined, packed, words } from "./resortFixture.mjs";

const BASE_RPC = process.env.BASE_RPC ?? "https://api.devnet.solana.com";
const BASE_READ_RPC = process.env.BASE_READ_RPC ?? BASE_RPC;
const ER_RPC = process.env.ER_RPC ?? "https://devnet-as.magicblock.app";
const ROUTER_RPC = process.env.ROUTER_RPC ?? "https://devnet-router.magicblock.app";
const VALIDATOR = address(process.env.VALIDATOR ?? "MAS1Dt9qreoRMQ14YQuhg8UTZMMzDdKhmkZMECCzk57");
const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const COMPUTE_BUDGET_PROGRAM = address("ComputeBudget111111111111111111111111111111");
const DELEGATION_PROGRAM = address("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
const MAGIC_PROGRAM = address("Magic11111111111111111111111111111111111111");
const MAGIC_CONTEXT = address("MagicContext1111111111111111111111111111111");
const COMPUTE_UNIT_LIMIT = 1_400_000;
const CHUNK_BYTES = 850;
const COUNT = Number(process.env.COUNT ?? 200);
const MEASURE = ["level", "power", "combat"].indexOf(process.env.MEASURE ?? "combat");
const STAGE = process.env.STAGE ?? "all";
const KIND = { fixture: 0, pet: 1, page: 2, mirror: 3, bitmap: 4 };
const UNITS = { assign: 30_000, lifecycle: 40_000 };
const PET_KIND = 2;
const SOCIAL_BYTES = 32 * 120 + 10 * 40 + 45;
const HYDRA_PROGRAM = address("eHyd5BU8QffvHi4GnXwxrK4WpS7pM2x9UGKHBWii7mf");
const MAGIC_VAULT = address("MagicVau1t999999999999999999999999999999999");
const INSTRUCTIONS_SYSVAR = address("Sysvar1nstructions1111111111111111111111111");
const SPONSOR_LAMPORTS = 20_000_000n;
const PAGE_KIND = 3;
const MEMBERS = 10;

const [programArgument, policyPath] = process.argv.slice(2);
if (!programArgument || !policyPath) {
	console.log("usage: [STAGE=all|setup|run|teardown] node tools/chain/lookupDevnet.mjs <program> <checkpoint>.policy (run blockLiteSvm.mjs first)");
	process.exit(2);
}
const PROGRAM = address(programArgument);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const encoder = getAddressEncoder();
const payer = await createKeyPairSignerFromBytes(Uint8Array.from(JSON.parse(readFileSync(`${process.env.HOME}/.config/solana/id.json`, "utf8"))));
const base = createSolanaRpc(BASE_RPC);
const baseRead = createSolanaRpc(BASE_READ_RPC);
const ephemeral = createSolanaRpc(ER_RPC);
const signerMeta = { address: payer.address, role: AccountRole.WRITABLE_SIGNER, signer: payer };
const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });
const probe = (accounts, data) => ({ programAddress: PROGRAM, accounts, data });
const json = (value) => JSON.stringify(value, (_, inner) => typeof inner === "bigint" ? inner.toString() : inner);
const pda = async (programAddress, ...seeds) => await getProgramDerivedAddress({ programAddress, seeds });

function limitInstruction(units) {
	const bytes = new Uint8Array(5);
	const view = new DataView(bytes.buffer);
	view.setUint8(0, 2);
	view.setUint32(1, units, true);
	return { programAddress: COMPUTE_BUDGET_PROGRAM, accounts: [], data: bytes };
}

async function patiently(call) {
	for (let attempt = 1; ; attempt++) {
		try {
			return await call();
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
		await sleep(1000);
	}
	return null;
}

async function send(rpc, step, instructions, details = false, feePayer = payer) {
	const { value: blockhash } = await patiently(() => rpc.getLatestBlockhash().send());
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(feePayer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstructions([limitInstruction(COMPUTE_UNIT_LIMIT), ...instructions], m),
	);
	const transaction = await signTransactionMessageWithSigners(message);
	const signature = getSignatureFromTransaction(transaction);
	const started = Date.now();
	await patiently(() => rpc.sendTransaction(getBase64EncodedWireTransaction(transaction), { encoding: "base64", skipPreflight: true }).send());
	for (let attempt = 0; attempt < 240; attempt++) {
		const { value } = await patiently(() => rpc.getSignatureStatuses([signature]).send());
		const status = value[0];
		if (status && (status.confirmationStatus === "confirmed" || status.confirmationStatus === "finalized")) {
			const elapsed = Date.now() - started;
			const found = details || status.err ? await fetchTransaction(rpc === base ? baseRead : rpc, signature) : null;
			if (status.err) {
				console.log(`${step}: FAILED ${json(status.err)} ${signature}\n${(found?.meta?.logMessages ?? []).slice(-8).join("\n")}`);
				throw new Error(`${step} failed`);
			}
			return { signature, elapsed, units: found?.meta?.computeUnitsConsumed !== undefined ? Number(found.meta.computeUnitsConsumed) : null, fee: found?.meta?.fee !== undefined ? Number(found.meta.fee) : null };
		}
		await sleep(250);
	}
	throw new Error(`${step}: not confirmed`);
}

async function read(rpc, key) {
	const { value } = await patiently(() => rpc.getAccountInfo(key, { encoding: "base64", commitment: "confirmed" }).send());
	if (!value) return null;
	return { owner: value.owner, lamports: BigInt(value.lamports), data: new Uint8Array(Buffer.from(value.data[0], "base64")) };
}

async function readMany(rpc, keys) {
	const found = [];
	for (let start = 0; start < keys.length; start += 100) {
		const { value } = await patiently(() => rpc.getMultipleAccounts(keys.slice(start, start + 100), { encoding: "base64", commitment: "confirmed" }).send());
		for (const entry of value) found.push(entry ? { owner: entry.owner, lamports: BigInt(entry.lamports), data: new Uint8Array(Buffer.from(entry.data[0], "base64")) } : null);
	}
	return found;
}

async function holder(kind, param, size, content) {
	const seeds = kind === KIND.pet ? ["pet", param] : kind === KIND.page ? ["block", words(param)] : kind === KIND.fixture ? ["fixture", words(param)] : ["assigned"];
	const [key, bump] = await pda(PROGRAM, ...seeds);
	const keyBytes = encoder.encode(key);
	const paramBytes = kind === KIND.pet ? param : joined(words(kind === KIND.bitmap ? 0 : param), new Uint8Array(24));
	return {
		kind,
		key,
		bump,
		size,
		content,
		tail: joined(words(kind), paramBytes),
		buffer: (await pda(PROGRAM, "buffer", keyBytes))[0],
		record: (await pda(DELEGATION_PROGRAM, "delegation", keyBytes))[0],
		metadata: (await pda(DELEGATION_PROGRAM, "delegation-metadata", keyBytes))[0],
	};
}

async function sentInBatches(rpc, label, instructions, unitsEach, details = false, feePayer = payer) {
	const batches = packed(instructions, unitsEach);
	const started = Date.now();
	let units = 0;
	let fees = 0;
	let slowest = 0;
	for (const [index, batch] of batches.entries()) {
		const sent = await send(rpc, `${label} ${index + 1}/${batches.length}`, batch, details, feePayer);
		units += sent.units ?? 0;
		fees += sent.fee ?? 0;
		slowest = Math.max(slowest, sent.elapsed);
	}
	const elapsed = Date.now() - started;
	console.log(`  ${label.padEnd(18)} ${String(instructions.length).padStart(5)} instructions ${String(batches.length).padStart(4)} transactions ${String(elapsed).padStart(7)} ms${details ? ` · ${units} CU · fees ${fees} lamports` : ""} · slowest confirmation ${slowest} ms`);
	return { transactions: batches.length, elapsed, units, fees };
}

const policy = new Uint8Array(readFileSync(policyPath));
const scenarios = ["typical", "busiest"].map((name) => scenarioOf(new URL("../../out/actProbe/", import.meta.url), name));
const layout = await send(base, "layout", [probe([], words(0))], true);
const logged = (logs) => logs.filter((line) => line.startsWith("Program log: 0x")).map((line) => BigInt(line.split(", ").pop()));
const [petAccountBytes, pageHeader, , bitmapHeader, petBytes, identityBytes] = logged((await fetchTransaction(baseRead, layout.signature)).meta.logMessages).map(Number);
const petsOf = (scenario, key) => Array.from({ length: 10 }, (_, slot) => scenario[key].subarray(slot * petBytes, (slot + 1) * petBytes));
const pool = [...petsOf(scenarios[0], "pets"), ...petsOf(scenarios[1], "pets")];
let state = 0x0b10cn | 1n;
const next = () => {
	state ^= (state << 13n) & 0xffffffffffffffffn;
	state ^= state >> 7n;
	state ^= (state << 17n) & 0xffffffffffffffffn;
	return state;
};

function petAccount(pet, ordinal, mint) {
	const bytes = new Uint8Array(petAccountBytes);
	bytes[0] = PET_KIND;
	bytes[1] = 1;
	new DataView(bytes.buffer).setUint32(4, ordinal, true);
	bytes.set(mint, 8);
	bytes.set(encoder.encode(payer.address), 40);
	bytes.set(pet, 8 + identityBytes);
	return bytes;
}

function pageAccount(id, keys, filled) {
	const bytes = new Uint8Array(pageHeader + 32 * keys.length + SOCIAL_BYTES);
	const view = new DataView(bytes.buffer);
	bytes[0] = PAGE_KIND;
	bytes[1] = 1;
	view.setUint32(4, id, true);
	view.setUint32(8, keys.length, true);
	view.setUint32(12, filled, true);
	keys.forEach((key, index) => key && bytes.set(encoder.encode(key), pageHeader + 32 * index));
	return bytes;
}

const typical = scenarios[0];
const fixtures = [];
for (const [id, content] of [policy, typical.context, typical.global, typical.wilds].entries()) fixtures.push(await holder(KIND.fixture, id, content.length, content));
const pets = [];
for (let ordinal = 0; ordinal < COUNT; ordinal++) {
	const mint = words(next(), next(), next(), next());
	const pet = ordinal < 10 ? petsOf(typical, "pets")[ordinal] : pool[Number(next() % BigInt(pool.length))];
	pets.push(await holder(KIND.pet, mint, petAccountBytes, petAccount(pet, ordinal, mint)));
}
const pages = [];
for (let id = 0; id < COUNT / MEMBERS; id++) {
	const members = id === 0 ? pets.slice(0, 10).map((entry) => entry.key) : pets.slice(id * MEMBERS, (id + 1) * MEMBERS).map((entry) => entry.key);
	pages.push(await holder(KIND.page, id, pageHeader + 32 * MEMBERS + SOCIAL_BYTES, pageAccount(id, members, MEMBERS)));
}
const bitmapContent = new Uint8Array(bitmapHeader + Math.ceil(COUNT / 8));
new DataView(bitmapContent.buffer).setBigUint64(0, BigInt(COUNT), true);
const bitmap = await holder(KIND.bitmap, 0, bitmapContent.length, bitmapContent);
const everyone = [...fixtures, ...pets, ...pages, bitmap];
console.log(`program ${PROGRAM} · ${COUNT} pet accounts of ${petAccountBytes} bytes, ${pages.length} Blocks of ${pageHeader + 32 * MEMBERS + SOCIAL_BYTES} bytes (members + fights, listings, relationships) · ${everyone.length} accounts · ER ${ER_RPC}`);

async function setup() {
	const states = await readMany(baseRead, everyone.map((entry) => entry.key));
	const missing = everyone.filter((entry, index) => states[index] === null);
	await sentInBatches(base, "create", missing.map((entry) => probe([signerMeta, writable(entry.key), readonly(SYSTEM_PROGRAM)], joined(words(10), entry.tail, words(entry.size)))), UNITS.lifecycle);
	const now = await readMany(baseRead, everyone.map((entry) => entry.key));
	const writes = [];
	for (const [index, entry] of everyone.entries()) {
		const onChain = now[index]?.data ?? new Uint8Array();
		for (let offset = 0; offset < entry.size; offset += CHUNK_BYTES) {
			const chunk = entry.content.subarray(offset, Math.min(offset + CHUNK_BYTES, entry.size));
			if (chunk.every((value, position) => onChain[offset + position] === value)) continue;
			writes.push(probe([signerMeta, writable(entry.key)], joined(words(11), entry.tail, words(offset), chunk)));
		}
	}
	await sentInBatches(base, "write", writes, UNITS.lifecycle);
	const owners = await readMany(baseRead, everyone.map((entry) => entry.key));
	const toDelegate = everyone.filter((entry, index) => owners[index]?.owner === PROGRAM);
	await sentInBatches(base, "delegate", toDelegate.map((entry) => probe([
		signerMeta,
		readonly(SYSTEM_PROGRAM),
		writable(entry.key),
		readonly(PROGRAM),
		writable(entry.buffer),
		writable(entry.record),
		writable(entry.metadata),
		readonly(DELEGATION_PROGRAM),
		readonly(VALIDATOR),
	], joined(words(12), entry.tail))), UNITS.lifecycle);
	const started = Date.now();
	for (;;) {
		const seen = await readMany(ephemeral, everyone.map((entry) => entry.key));
		const ready = seen.filter((found, index) => found && found.data.length === everyone[index].size).length;
		if (ready === everyone.length) break;
		if (Date.now() - started > 180_000) throw new Error(`only ${ready} of ${everyone.length} accounts readable in the ER`);
		await sleep(2000);
	}
	console.log(`  all ${everyone.length} accounts readable in the ER ${Date.now() - started} ms after the last delegation`);
}

const differing = (expected, actual) => expected.reduce((count, value, position) => count + (actual[position] === value ? 0 : 1), Math.abs(expected.length - actual.length));

function keypairAt(name) {
	const path = new URL(`../../out/${name}.json`, import.meta.url);
	if (!existsSync(path)) {
		const { privateKey, publicKey } = generateKeyPairSync("ed25519");
		writeFileSync(path, JSON.stringify([...privateKey.export({ format: "der", type: "pkcs8" }).subarray(-32), ...publicKey.export({ format: "der", type: "spki" }).subarray(-32)]));
	}
	return createKeyPairSignerFromBytes(Uint8Array.from(JSON.parse(readFileSync(path, "utf8"))));
}

const systemInstruction = (index, accounts, tail) => ({ programAddress: SYSTEM_PROGRAM, accounts, data: joined(Uint8Array.of(index, 0, 0, 0), tail) });

async function rpcCall(url, method, params) {
	const started = Date.now();
	const response = await fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) });
	const body = await response.json();
	return { result: body.result, error: body.error, elapsed: Date.now() - started };
}

async function walletDelegated(sponsor) {
	if ((await rpcCall(ER_RPC, "getDelegationStatus", [sponsor.address])).result?.isDelegated) return;
	const sponsorBytes = encoder.encode(sponsor.address);
	const [record] = await pda(DELEGATION_PROGRAM, "delegation", sponsorBytes);
	const [metadata] = await pda(DELEGATION_PROGRAM, "delegation-metadata", sponsorBytes);
	const [buffer] = await pda(SYSTEM_PROGRAM, "buffer", sponsorBytes);
	const rent = BigInt((await rpcCall(BASE_RPC, "getMinimumBalanceForRentExemption", [256])).result);
	const onL1 = (await base.getBalance(sponsor.address).send()).value;
	if (onL1 < SPONSOR_LAMPORTS) await send(base, "fund the Hydra sponsor", [systemInstruction(2, [signerMeta, writable(sponsor.address)], words(SPONSOR_LAMPORTS - onL1))]);
	const sponsorMeta = { address: sponsor.address, role: AccountRole.WRITABLE_SIGNER, signer: sponsor };
	const delegateData = joined(words(0), Uint8Array.of(0xff, 0xff, 0xff, 0xff, 0, 0, 0, 0, 1), encoder.encode(VALIDATOR));
	await send(base, "delegate the Hydra sponsor wallet", [
		systemInstruction(2, [sponsorMeta, writable(record)], words(rent)),
		systemInstruction(2, [sponsorMeta, writable(metadata)], words(rent)),
		systemInstruction(1, [sponsorMeta], encoder.encode(DELEGATION_PROGRAM)),
		{ programAddress: DELEGATION_PROGRAM, accounts: [sponsorMeta, sponsorMeta, readonly(SYSTEM_PROGRAM), writable(buffer), writable(record), writable(metadata), readonly(SYSTEM_PROGRAM)], data: delegateData },
	]);
	const started = Date.now();
	while (!(await rpcCall(ER_RPC, "getDelegationStatus", [sponsor.address])).result?.isDelegated) {
		if (Date.now() - started > 60000) throw new Error("the Hydra sponsor is not delegated after 60 s");
		await sleep(1000);
	}
}

async function walletReturned(sponsor) {
	const sponsorMeta = { address: sponsor.address, role: AccountRole.WRITABLE_SIGNER, signer: sponsor };
	const throwaway = await generateKeyPairSigner();
	const { value: blockhash } = await patiently(() => ephemeral.getLatestBlockhash().send());
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(sponsor, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstructions([{ programAddress: MAGIC_PROGRAM, accounts: [{ address: throwaway.address, role: AccountRole.READONLY_SIGNER, signer: throwaway }, writable(MAGIC_CONTEXT), sponsorMeta], data: Uint8Array.of(2, 0, 0, 0) }], m),
	);
	const transaction = await signTransactionMessageWithSigners(message);
	await patiently(() => ephemeral.sendTransaction(getBase64EncodedWireTransaction(transaction), { encoding: "base64", skipPreflight: true }).send());
}

function hydraCreateData(seed, authority, startSlot, interval, remaining, cuLimit, scheduled) {
	const head = joined(Uint8Array.of(0), seed, encoder.encode(authority));
	const limit = new Uint8Array(4);
	new DataView(limit.buffer).setUint32(0, cuLimit, true);
	const size = new Uint8Array(3);
	size[0] = scheduled.accounts.length;
	new DataView(size.buffer).setUint16(1, scheduled.data.length, true);
	const parts = [head, words(startSlot, interval, remaining, 0), limit, size, encoder.encode(scheduled.programAddress)];
	for (const meta of scheduled.accounts) parts.push(Uint8Array.of(meta.role === AccountRole.WRITABLE ? 2 : 0), encoder.encode(meta.address));
	parts.push(scheduled.data);
	return joined(...parts);
}

const actOf = (members) => probe([readonly(fixtures[0].key), readonly(fixtures[1].key), writable(fixtures[2].key), readonly(fixtures[3].key), readonly(pages[members.block].key), ...members.pets.map((key) => writable(key))], words(1, typical.engine));

async function cranksCreated(label, sponsor, memberships, startSlotOf) {
	const sponsorMeta = { address: sponsor.address, role: AccountRole.WRITABLE_SIGNER, signer: sponsor };
	const cranks = [];
	const instructions = [];
	for (const members of memberships) {
		const seed = new Uint8Array(randomBytes(32));
		const [crank] = await pda(HYDRA_PROGRAM, "crank", seed);
		const act = actOf(members);
		cranks.push({ crank, act, block: members.block });
		instructions.push({ programAddress: HYDRA_PROGRAM, accounts: [sponsorMeta, writable(crank), writable(MAGIC_VAULT), readonly(MAGIC_PROGRAM)], data: hydraCreateData(seed, sponsor.address, startSlotOf(members.block), 2_160_000, 5, COMPUTE_UNIT_LIMIT, act) });
	}
	const before = (await ephemeral.getBalance(sponsor.address).send()).value;
	const sent = await sentInBatches(ephemeral, label, instructions, 16_000, true, sponsor);
	const after = (await ephemeral.getBalance(sponsor.address).send()).value;
	console.log(`    sponsor paid ${before - after} lamports of crank rent in the ER for ${cranks.length} cranks`);
	return { cranks, sent };
}

async function cranksCancelled(label, sponsor, cranks) {
	const sponsorMeta = { address: sponsor.address, role: AccountRole.WRITABLE_SIGNER, signer: sponsor };
	const before = (await ephemeral.getBalance(sponsor.address).send()).value;
	const sent = await sentInBatches(ephemeral, label, cranks.map(({ crank }) => ({ programAddress: HYDRA_PROGRAM, accounts: [sponsorMeta, writable(crank), writable(sponsor.address), writable(MAGIC_VAULT), readonly(MAGIC_PROGRAM)], data: Uint8Array.of(2) })), 2_000, true, sponsor);
	const after = (await ephemeral.getBalance(sponsor.address).send()).value;
	console.log(`    sponsor got back ${after - before} lamports`);
	return sent;
}

async function programAccountsBy(url, label, blockId) {
	const filters = [{ dataSize: petAccountBytes }, { memcmp: { offset: 8 + identityBytes, bytes: Buffer.from(Uint8Array.of(blockId & 0xff, (blockId >> 8) & 0xff, 0, 0)).toString("base64"), encoding: "base64" } }];
	const answer = await rpcCall(url, "getProgramAccounts", [PROGRAM, { encoding: "base64", commitment: "confirmed", filters }]);
	return { label, ...answer, keys: answer.result ? answer.result.map((entry) => entry.pubkey) : null };
}

async function run() {
	const sponsor = await keypairAt("hydraSponsor");
	await walletDelegated(sponsor);
	const slot = BigInt(await ephemeral.getSlot().send());
	const before = pages.map((_, id) => ({ block: id, pets: pets.slice(id * MEMBERS, (id + 1) * MEMBERS).map((entry) => entry.key) }));
	console.log("  one Hydra crank per block (the act lists the Block and its ten pets), first runs far in the future:");
	const first = await cranksCreated("create cranks", sponsor, before, (block) => block === 0 ? slot : slot + 100_000_000n);
	const crank0 = first.cranks[0];
	const trigger = { programAddress: HYDRA_PROGRAM, accounts: [writable(crank0.crank), signerMeta, readonly(INSTRUCTIONS_SYSVAR)], data: Uint8Array.of(1) };
	const acted = await send(ephemeral, "trigger block 0's crank", [trigger, crank0.act], true);
	const actedLogs = (await fetchTransaction(ephemeral, acted.signature)).meta.logMessages;
	const choice = logged(actedLogs);
	console.log(`    block 0's crank run by a trigger: ${actedLogs.filter((line) => line.includes(`${PROGRAM} consumed`)).join(" ")}`);
	const after = await readMany(ephemeral, pets.slice(0, 10).map((entry) => entry.key));
	const petDiffers = after.reduce((sum, found, slot) => sum + differing(petsOf(typical, "after")[slot], found.data.subarray(8 + identityBytes)), 0);
	const globalDiffers = differing(typical.afterGlobal, (await read(ephemeral, fixtures[2].key)).data);
	console.log(`  act through the crank in the ER on ten pet accounts and a ${pageHeader + 32 * MEMBERS + SOCIAL_BYTES}-byte Block: ${acted.units} CU in ${acted.elapsed} ms, fee ${acted.fee} · choice match ${choice.slice(0, 3).map(Number).join(" ") === typical.choice.join(" ")} · bytes differing from the host's: pets ${petDiffers} of ${10 * petBytes}, GlobalConfig ${globalDiffers} of 64`);
	const strengths = [];
	for (let start = 0; start < COUNT; start += 25) {
		const sent = await send(ephemeral, `strengths ${start}`, [probe(pets.slice(start, start + 25).map((entry) => readonly(entry.key)), words(16, MEASURE))], true);
		strengths.push(...logged((await fetchTransaction(ephemeral, sent.signature)).meta.logMessages));
	}
	const order = pets.map((_, ordinal) => ordinal).sort((left, right) => (strengths[right] > strengths[left] ? 1 : strengths[right] < strengths[left] ? -1 : left - right));
	const started = Date.now();
	let transactions = 0;
	let units = 0;
	let fees = 0;
	let slowest = 0;
	const step = async (label, instructions) => {
		const sent = await send(ephemeral, label, instructions, true);
		transactions += 1;
		units += sent.units ?? 0;
		fees += sent.fee ?? 0;
		slowest = Math.max(slowest, sent.elapsed);
	};
	await step("begin", [probe([writable(bitmap.key)], words(3, MEASURE))]);
	for (let id = 0; id < pages.length; id++) {
		const chosen = order.slice(id * MEMBERS, (id + 1) * MEMBERS).map((ordinal) => writable(pets[ordinal].key));
		await step(`assign ${id}`, [probe([writable(bitmap.key), writable(pages[id].key), readonly(pages[Math.max(id - 1, 0)].key), ...chosen], words(17, 0))]);
	}
	await step("finish", [probe([writable(bitmap.key)], words(5))]);
	const elapsed = Date.now() - started;
	const written = await readMany(ephemeral, pages.map((entry) => entry.key));
	const seatsNow = await readMany(ephemeral, pets.map((entry) => entry.key));
	let right = 0;
	let seated = 0;
	for (let id = 0; id < pages.length; id++) {
		for (let member = 0; member < MEMBERS; member++) {
			const ordinal = order[id * MEMBERS + member];
			const key = encoder.encode(pets[ordinal].key);
			const at = pageHeader + 32 * member;
			if (key.every((value, index) => written[id].data[at + index] === value)) right += 1;
			const record = seatsNow[ordinal].data;
			if (new DataView(record.buffer, record.byteOffset).getUint32(8 + identityBytes, true) === id && record[8 + identityBytes + 4] === member) seated += 1;
		}
	}
	console.log(`  rotation in the ER, each pet's block and seat written in place, sent one after another: ${transactions} transactions, ${units} CU, fees ${fees} lamports, ${elapsed} ms (slowest confirmation ${slowest} ms) · ${right} of ${COUNT} members where the proposal put them · ${seated} of ${COUNT} pets carry their new block and seat`);
	const probes = [];
	for (const blockId of [0, 7, 19]) {
		for (const [url, label] of [[ER_RPC, "ER"], [ROUTER_RPC, "router"], [BASE_READ_RPC, "L1"]]) {
			const answer = await programAccountsBy(url, label, blockId);
			const expected = order.slice(blockId * MEMBERS, (blockId + 1) * MEMBERS).map((ordinal) => pets[ordinal].key).sort();
			const got = answer.keys ? [...answer.keys].sort() : null;
			const verdict = answer.error ? `error ${answer.error.code} ${String(answer.error.message).slice(0, 60)}` : `${got.length} accounts, the block's ten ${JSON.stringify(got) === JSON.stringify(expected)}`;
			probes.push(`    block ${String(blockId).padStart(2)} via ${label.padEnd(6)} ${answer.elapsed} ms: ${verdict}`);
		}
	}
	console.log(`  getProgramAccounts filtered by the pet's blockId:\n${probes.join("\n")}`);
	const afterRotation = pages.map((_, id) => ({ block: id, pets: order.slice(id * MEMBERS, (id + 1) * MEMBERS).map((ordinal) => pets[ordinal].key) }));
	console.log("  re-create the cranks after the rotation (every block's ten changed):");
	const resortStarted = Date.now();
	await cranksCancelled("cancel cranks", sponsor, first.cranks);
	const second = await cranksCreated("create cranks", sponsor, afterRotation, () => slot + 100_000_000n);
	console.log(`    cancel and create for ${pages.length} blocks took ${Date.now() - resortStarted} ms`);
	await cranksCancelled("cancel cranks", sponsor, second.cranks);
	await walletReturned(sponsor);
}

async function teardown() {
	const inEr = await readMany(baseRead, everyone.map((entry) => entry.key));
	const delegatedHolders = everyone.filter((entry, index) => inEr[index]?.owner === DELEGATION_PROGRAM);
	await sentInBatches(ephemeral, "commit and undelegate", delegatedHolders.map((entry) => probe([signerMeta, writable(entry.key), readonly(MAGIC_PROGRAM), writable(MAGIC_CONTEXT)], words(13))), UNITS.lifecycle);
	const started = Date.now();
	for (;;) {
		const states = await readMany(baseRead, everyone.map((entry) => entry.key));
		const back = states.filter((found) => found === null || found.owner === PROGRAM).length;
		if (back === everyone.length) break;
		if (Date.now() - started > 300_000) throw new Error(`only ${back} of ${everyone.length} accounts back on L1`);
		await sleep(3000);
	}
	console.log(`  all accounts back on L1 ${Date.now() - started} ms after the last return`);
	const states = await readMany(baseRead, everyone.map((entry) => entry.key));
	const open = everyone.filter((entry, index) => states[index] && states[index].lamports > 0n);
	await sentInBatches(base, "close", open.map((entry) => probe([signerMeta, writable(entry.key)], joined(words(14), entry.tail))), UNITS.lifecycle);
}

const before = (await base.getBalance(payer.address).send()).value;
if (STAGE === "all" || STAGE === "setup") await setup();
if (STAGE === "all" || STAGE === "run") await run();
if (STAGE === "all" || STAGE === "teardown") await teardown();
const after = (await base.getBalance(payer.address).send()).value;
console.log(`payer spent ${before - after} lamports on L1 during this run`);
