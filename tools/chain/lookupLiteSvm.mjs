import { readFileSync } from "node:fs";
import { ComputeBudget, LiteSVM } from "litesvm";
import {
	AccountRole,
	address,
	appendTransactionMessageInstructions,
	compressTransactionMessageUsingAddressLookupTables,
	createKeyPairSignerFromPrivateKeyBytes,
	createTransactionMessage,
	getAddressEncoder,
	getProgramDerivedAddress,
	lamports,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";
import {
	TOKEN_PROGRAM_ADDRESS,
	findAssociatedTokenPda,
	getCreateAssociatedTokenIdempotentInstruction,
	getTokenDecoder,
} from "@solana-program/token";
import { differing, scenarioOf } from "./blockFixture.mjs";
import { joined, words } from "./resortFixture.mjs";

const COMPUTE_BUDGET_PROGRAM = address("ComputeBudget111111111111111111111111111111");
const LOOKUP_TABLE_PROGRAM = address("AddressLookupTab1e1111111111111111111111111");
const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const DELEGATION_PROGRAM = address("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
const COMPUTE_UNIT_LIMIT = 1_400_000;
const PET_KIND = 2;
const PAGE_KIND = 3;
const MIRROR_KIND = 4;
const MIRROR_PETS = 50;
const RENT_PER_BYTE = 5_080n;
const ACCOUNT_OVERHEAD = 128n;
const CREATE_LIMIT = 10_240;
const FIGHT_RECORD_BYTES = 120;
const LISTING_BYTES = 40;
const FIGHT_RING = 32;
const MEASURES = ["level", "power", "combat"];
const BLOCK_SIZES = [10, 100, 200];
const probeDirectory = new URL("../../out/actProbe/", import.meta.url);

const [programPath, policyPath, countsArgument = "1000,10000"] = process.argv.slice(2);
if (!programPath || !policyPath) {
	console.log("usage: node tools/chain/lookupLiteSvm.mjs out/lookupProbe.so <checkpoint>.policy [pets per rotation, e.g. 1000,10000] (run blockLiteSvm.mjs first: it writes the host's scenarios)");
	process.exit(2);
}
const policy = new Uint8Array(readFileSync(policyPath));
const encoder = getAddressEncoder();
const signerOf = (fill) => createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(fill));
const payer = await signerOf(1);
const owner = await signerOf(2);
const programKey = await signerOf(3);
const stranger = await signerOf(4);
const program = programKey.address;
const scenarios = ["typical", "busiest"].map((name) => scenarioOf(probeDirectory, name));
const rent = (bytes) => (BigInt(bytes) + ACCOUNT_OVERHEAD) * RENT_PER_BYTE;
const sol = (value) => (Number(value) / 1e9).toFixed(4);
const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });
const signing = (signer) => ({ address: signer.address, role: AccountRole.WRITABLE_SIGNER, signer });
const probe = (accounts, data) => ({ programAddress: program, accounts, data });
const logged = (logs) => logs.filter((line) => line.startsWith("Program log: 0x")).map((line) => BigInt(line.split(", ").pop()));
const pda = async (...seeds) => (await getProgramDerivedAddress({ programAddress: program, seeds }))[0];
const same = (left, right) => left.length === right.length && left.every((value, index) => Number(value) === Number(right[index]));

function random(seed) {
	let state = BigInt(seed) | 1n;
	return () => {
		state ^= (state << 13n) & 0xffffffffffffffffn;
		state ^= state >> 7n;
		state ^= (state << 17n) & 0xffffffffffffffffn;
		return state;
	};
}

function limitInstruction(units) {
	const bytes = new Uint8Array(5);
	const view = new DataView(bytes.buffer);
	view.setUint8(0, 2);
	view.setUint32(1, units, true);
	return { programAddress: COMPUTE_BUDGET_PROGRAM, accounts: [], data: bytes };
}

function freshSvm(unbounded = false) {
	const budget = new ComputeBudget();
	budget.computeUnitLimit = 50_000_000n;
	const svm = unbounded ? new LiteSVM().withComputeBudget(budget) : new LiteSVM();
	svm.airdrop(payer.address, lamports(1_000_000_000_000n));
	svm.airdrop(owner.address, lamports(10_000_000_000n));
	svm.airdrop(stranger.address, lamports(10_000_000_000n));
	svm.addProgramFromFile(program, programPath);
	return svm;
}

async function sendOn(svm, instructions, { feePayer = payer, tables = null, limit = COMPUTE_UNIT_LIMIT } = {}) {
	let message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(feePayer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash({ blockhash: svm.latestBlockhash(), lastValidBlockHeight: 100000n }, m),
		(m) => appendTransactionMessageInstructions([...(limit ? [limitInstruction(limit)] : []), ...instructions], m),
	);
	if (tables) message = compressTransactionMessageUsingAddressLookupTables(message, tables);
	let signed;
	try {
		signed = await signTransactionMessageWithSigners(message);
	} catch (error) {
		return { failed: true, error: `not buildable: ${error.message.split("\n")[0]}`, units: 0, logs: [] };
	}
	const result = svm.sendTransaction(signed);
	svm.expireBlockhash();
	const failed = result.constructor.name === "FailedTransactionMetadata";
	const meta = failed ? result.meta() : result;
	return { failed, error: failed ? result.err().toString().replace(/\s+/g, " ").slice(0, 120) : null, units: Number(meta.computeUnitsConsumed()), logs: meta.logs() };
}

function put(svm, key, data, programAddress = program) {
	svm.setAccount({ address: key, data, executable: false, lamports: lamports(rent(data.length)), programAddress, space: BigInt(data.length) });
}

function lookupTable(svm, key, addresses) {
	const data = new Uint8Array(56 + 32 * addresses.length);
	const view = new DataView(data.buffer);
	view.setUint32(0, 1, true);
	view.setBigUint64(4, 0xffffffffffffffffn, true);
	view.setBigUint64(12, 0n, true);
	data[20] = 0;
	data[21] = 0;
	addresses.forEach((key, index) => data.set(encoder.encode(key), 56 + 32 * index));
	put(svm, key, data, LOOKUP_TABLE_PROGRAM);
	return { [key]: addresses };
}

function petAccount(sizes, pet, ordinal, mint, ownerKey) {
	const bytes = new Uint8Array(sizes.petAccount);
	const view = new DataView(bytes.buffer);
	bytes[0] = PET_KIND;
	bytes[1] = 1;
	view.setUint32(4, ordinal, true);
	bytes.set(mint, 8);
	bytes.set(ownerKey, 40);
	bytes.set(pet, 8 + sizes.identity);
	return bytes;
}

function pageAccount(id, members, filled = 0) {
	const bytes = new Uint8Array(48 + 32 * members.length);
	const view = new DataView(bytes.buffer);
	bytes[0] = PAGE_KIND;
	bytes[1] = 1;
	view.setUint32(4, id, true);
	view.setUint32(8, members.length, true);
	view.setUint32(12, filled, true);
	members.forEach((key, index) => key && bytes.set(encoder.encode(key), 48 + 32 * index));
	return bytes;
}

function mirrorAccount(sizes, id, page, pets) {
	const bytes = new Uint8Array(sizes.mirror);
	const view = new DataView(bytes.buffer);
	bytes[0] = MIRROR_KIND;
	bytes[1] = 1;
	view.setUint32(4, id, true);
	view.setUint32(8, page, true);
	view.setUint32(12, pets.length, true);
	pets.forEach((pet, index) => bytes.set(pet, 16 + index * sizes.pet));
	return bytes;
}

const sizing = freshSvm();
const layout = await sendOn(sizing, [probe([], words(0))]);
const [petAccountBytes, pageHeader, mirrorBytes, bitmapHeader, petBytes, identityBytes] = logged(layout.logs).map(Number);
const sizes = { petAccount: petAccountBytes, pageHeader, mirror: mirrorBytes, bitmapHeader, pet: petBytes, identity: identityBytes };
const petsOf = (scenario, key) => Array.from({ length: 10 }, (_, slot) => scenario[key].subarray(slot * petBytes, (slot + 1) * petBytes));

console.log(`Pet account ${petAccountBytes} bytes (identity ${identityBytes} + Pet ${petBytes}), rent ${sol(rent(petAccountBytes))} SOL each; member page header ${pageHeader} + 32 per member; mirror page ${mirrorBytes} bytes for ${MIRROR_PETS} pets`);
for (const members of BLOCK_SIZES) {
	const page = pageHeader + 32 * members;
	const mirrors = members > 10 ? Math.ceil(members / MIRROR_PETS) : 0;
	const social = FIGHT_RING * FIGHT_RECORD_BYTES + members * LISTING_BYTES + (members * (members - 1)) / 2;
	const socialPages = Math.ceil(social / CREATE_LIMIT);
	const blockRent = rent(page) + BigInt(mirrors) * rent(mirrorBytes) + BigInt(socialPages) * rent(Math.ceil(social / socialPages));
	console.log(`  block of ${String(members).padStart(3)}: members ${page} B, mirror ${mirrors} × ${mirrorBytes} B, fights + listings + relationships ${social} B in ${socialPages} account(s) · rent ${sol(blockRent)} SOL a block, ${sol(blockRent / BigInt(members) + rent(petAccountBytes))} SOL a pet with its own account`);
}

console.log("\nact, ten neighbours read from their own accounts (block of 10)");
for (const scenario of scenarios) {
	const svm = freshSvm();
	const fixture = await Promise.all([0, 1, 2, 3].map((id) => pda("fixture", words(id))));
	put(svm, fixture[0], policy);
	put(svm, fixture[1], scenario.context);
	put(svm, fixture[2], scenario.global);
	put(svm, fixture[3], scenario.wilds);
	const before = petsOf(scenario, "pets");
	const after = petsOf(scenario, "after");
	const keys = [];
	for (let slot = 0; slot < 10; slot++) {
		const mint = encoder.encode(await signerOf(40 + slot).then((signer) => signer.address));
		const key = await pda("pet", mint);
		keys.push(key);
		put(svm, key, petAccount(sizes, before[slot], slot, mint, encoder.encode(owner.address)));
	}
	const page = await pda("block", words(0));
	put(svm, page, pageAccount(0, keys, 10));
	const acted = await sendOn(svm, [probe([...fixture.map(readonly).map((meta, index) => index === 2 ? writable(meta.address) : meta), readonly(page), ...keys.map(writable)], words(1, scenario.engine))]);
	if (acted.failed) {
		console.log(`  ${scenario.name}: ${acted.error}`);
		continue;
	}
	const values = logged(acted.logs);
	const petDiffers = keys.reduce((sum, key, slot) => sum + differing(after[slot], svm.getAccount(key).data.subarray(8 + identityBytes)), 0);
	const globalDiffers = differing(scenario.afterGlobal, svm.getAccount(fixture[2]).data);
	console.log(`  ${scenario.name}: ${acted.units} CU · choice match ${same(values.slice(0, 3), scenario.choice)} · digest match ${values[3] === scenario.digest} · bytes differing from the host's: pets ${petDiffers} of ${10 * petBytes}, GlobalConfig ${globalDiffers} of ${scenario.afterGlobal.length} · accounts in the transaction ${15}`);
}

console.log("\naccounts one transaction can carry (a no-op instruction listing K writable accounts)");
{
	const svm = freshSvm();
	const keys = [];
	for (let index = 0; index < 256; index++) {
		const key = await pda("fixture", words(1000 + index));
		keys.push(key);
		put(svm, key, new Uint8Array(8));
	}
	const table = await pda("table");
	const tables = lookupTable(svm, table, keys);
	svm.warpToSlot(100n);
	const lines = [];
	for (const count of [24, 30, 32, 64, 65, 100, 128, 129, 200, 254]) {
		const plain = await sendOn(svm, [probe(keys.slice(0, count).map(writable), words(15))]);
		const viaTable = await sendOn(svm, [probe(keys.slice(0, count).map(writable), words(15))], { tables });
		const show = (sent) => sent.failed ? sent.error.slice(0, 70) : "ok";
		lines.push(`  ${String(count).padStart(3)} accounts: plain ${show(plain)} · with a lookup table ${show(viaTable)}`);
	}
	console.log(lines.join("\n"));
}

console.log("\nact through mirror pages (neighbours copied into the block's own accounts), busiest moment");
for (const members of BLOCK_SIZES) {
	const scenario = scenarios[1];
	const actorSlot = Number(scenario.header.match(/actor (\d+)/)[1]);
	for (const windows of [...new Set([1, Math.floor((members - 1) / 9)])]) {
		const svm = freshSvm(true);
		const fixture = await Promise.all([0, 1, 2, 3].map((id) => pda("fixture", words(id))));
		put(svm, fixture[0], policy);
		put(svm, fixture[1], scenario.context);
		put(svm, fixture[2], scenario.global);
		put(svm, fixture[3], scenario.wilds);
		const pool = [...petsOf(scenarios[0], "pets"), ...petsOf(scenarios[1], "pets")].filter((pet) => pet[5] === 1);
		const memberPets = [];
		const memberKeys = [];
		const actorMint = encoder.encode((await signerOf(90)).address);
		for (let member = 0; member < members; member++) {
			memberPets.push(member === 0 ? petsOf(scenario, "pets")[actorSlot] : petsOf(scenario, "pets")[(actorSlot + member) % 10]);
			memberKeys.push(member === 0 ? await pda("pet", actorMint) : await pda("pet", words(member, member, member, member)));
		}
		for (let member = 10; member < members; member++) memberPets[member] = pool[member % pool.length];
		put(svm, memberKeys[0], petAccount(sizes, memberPets[0], 0, actorMint, encoder.encode(owner.address)));
		const page = await pda("block", words(0));
		put(svm, page, pageAccount(0, memberKeys, members));
		const mirrorKeys = [];
		for (let index = 0; index * MIRROR_PETS < members; index++) {
			const key = await pda("mirror", words(index));
			mirrorKeys.push(key);
			put(svm, key, mirrorAccount(sizes, 0, index, memberPets.slice(index * MIRROR_PETS, (index + 1) * MIRROR_PETS)));
		}
		const accounts = [readonly(fixture[0]), readonly(fixture[1]), writable(fixture[2]), readonly(fixture[3]), readonly(page), writable(memberKeys[0]), ...mirrorKeys.map(writable)];
		const acted = await sendOn(svm, [probe(accounts, words(2, scenario.engine, 0, windows))], { limit: 0 });
		const verdict = acted.failed ? acted.error : `${acted.units} CU${acted.units > COMPUTE_UNIT_LIMIT ? " (over the 1.4M a transaction may use)" : ""}`;
		console.log(`  block of ${String(members).padStart(3)}, the actor scores ${String(windows * 9).padStart(3)} of its ${members - 1} neighbours: ${verdict} · ${accounts.length} accounts`);
	}
}

async function rotation(count, members, measure, withTable) {
	const svm = freshSvm();
	const next = random(0x0b10c + count + members);
	const pool = [...petsOf(scenarios[0], "pets"), ...petsOf(scenarios[1], "pets")];
	const keys = [];
	for (let ordinal = 0; ordinal < count; ordinal++) {
		const mint = words(next(), next(), next(), next());
		const key = await pda("pet", mint);
		keys.push(key);
		put(svm, key, petAccount(sizes, pool[Number(next() % BigInt(pool.length))], ordinal, mint, encoder.encode(owner.address)));
	}
	const bitmap = await pda("assigned");
	const bits = new Uint8Array(sizes.bitmapHeader + Math.ceil(count / 8));
	new DataView(bits.buffer).setBigUint64(0, BigInt(count), true);
	put(svm, bitmap, bits);
	const blocks = Math.ceil(count / members);
	const pages = [];
	for (let id = 0; id < blocks; id++) {
		const key = await pda("block", words(id));
		pages.push(key);
		put(svm, key, pageAccount(id, new Array(Math.min(members, count - id * members)).fill(null)));
	}
	const strengths = [];
	for (let start = 0; start < count; start += 25) {
		const sent = await sendOn(svm, [probe(keys.slice(start, start + 25).map(readonly), words(16, measure))]);
		strengths.push(...logged(sent.logs));
	}
	const order = keys.map((_, ordinal) => ordinal).sort((left, right) => (strengths[right] > strengths[left] ? 1 : strengths[right] < strengths[left] ? -1 : left - right));
	const begin = await sendOn(svm, [probe([writable(bitmap)], words(3, measure))]);
	let transactions = 1;
	let units = begin.units;
	let peak = 0;
	const tables = withTable ? lookupTable(svm, await pda("table"), keys.slice(0, 256)) : null;
	const perTransaction = withTable ? 57 : 25;
	for (let id = 0; id < blocks; id++) {
		const chosen = order.slice(id * members, (id + 1) * members);
		for (let offset = 0; offset < chosen.length; offset += perTransaction) {
			const group = chosen.slice(offset, offset + perTransaction).map((ordinal) => readonly(keys[ordinal]));
			const sent = await sendOn(svm, [probe([writable(bitmap), writable(pages[id]), readonly(pages[Math.max(id - 1, 0)]), ...group], words(4, offset))], { tables });
			if (sent.failed) throw new Error(`assign block ${id} offset ${offset}: ${sent.error}`);
			transactions += 1;
			units += sent.units;
			peak = Math.max(peak, sent.units);
		}
	}
	const finish = await sendOn(svm, [probe([writable(bitmap)], words(5))]);
	transactions += 1;
	units += finish.units;
	return { svm, keys, pages, bitmap, order, transactions, units, peak, finished: !finish.failed, perTransaction };
}

console.log("\nrotation: proposed off chain, every block checked on chain (a block's weakest is at least as strong as the next block's strongest, each pet placed once)");
for (const count of countsArgument.split(",").map(Number)) {
	for (const members of BLOCK_SIZES) {
		const result = await rotation(count, members, MEASURES.indexOf("combat"), false);
		const perPet = Math.round(result.units / count);
		console.log(`  ${String(count).padStart(5)} pets, blocks of ${String(members).padStart(3)}: ${result.transactions} transactions, ${result.units} CU (${perPet} a pet, ${result.peak} the fullest transaction, ${result.perTransaction} pets a transaction) · finished ${result.finished}`);
	}
}
{
	const result = await rotation(1000, 100, MEASURES.indexOf("combat"), true);
	console.log(`   1000 pets, blocks of 100, pet accounts through a lookup table: ${result.transactions} transactions, ${result.units} CU (${result.perTransaction} pets a transaction) · finished ${result.finished}`);
	const tampered = await rotation(200, 10, MEASURES.indexOf("combat"), false);
	const { svm, keys, pages, bitmap, order } = tampered;
	const restart = await sendOn(svm, [probe([writable(bitmap)], words(3, 2))]);
	const strong = order.slice(0, 10).map((ordinal) => readonly(keys[ordinal]));
	const weakFirst = [...order.slice(10, 20)].map((ordinal) => readonly(keys[ordinal]));
	const first = await sendOn(svm, [probe([writable(bitmap), writable(pages[0]), readonly(pages[0]), ...weakFirst], words(4, 0))]);
	const second = await sendOn(svm, [probe([writable(bitmap), writable(pages[1]), readonly(pages[0]), ...strong], words(4, 0))]);
	const again = await sendOn(svm, [probe([writable(bitmap), writable(pages[1]), readonly(pages[0]), ...weakFirst.slice(0, 1)], words(4, 0))]);
	const early = await sendOn(svm, [probe([writable(bitmap)], words(5))]);
	const outcome = (sent) => sent.failed ? `refused (${sent.error.match(/Custom \{ code: (\d+)/)?.[1] ?? sent.error})` : "accepted";
	console.log(`  checks (new rotation ${outcome(restart)}): the second-strongest ten as block 0 ${outcome(first)}, then the strongest ten as block 1 ${outcome(second)}; a pet already placed placed again ${outcome(again)}; finish before every pet is placed ${outcome(early)}`);
}

console.log("\nclaim straight from the pet's own account");
{
	const svm = freshSvm();
	const mintKey = await pda("mint");
	const admission = encoder.encode((await signerOf(70)).address);
	const petKey = await pda("pet", admission);
	const ledger = await pda("paid", admission);
	put(svm, petKey, petAccount(sizes, petsOf(scenarios[0], "after")[3], 3, admission, encoder.encode(owner.address)));
	const [ownerTokens] = await findAssociatedTokenPda({ owner: owner.address, mint: mintKey, tokenProgram: TOKEN_PROGRAM_ADDRESS });
	const [strangerTokens] = await findAssociatedTokenPda({ owner: stranger.address, mint: mintKey, tokenProgram: TOKEN_PROGRAM_ADDRESS });
	await sendOn(svm, [probe([signing(payer), writable(mintKey), readonly(SYSTEM_PROGRAM), readonly(TOKEN_PROGRAM_ADDRESS)], words(7))]);
	await sendOn(svm, [probe([signing(payer), writable(ledger), readonly(SYSTEM_PROGRAM)], joined(words(8), admission))]);
	for (const [holder, tokens] of [[owner, ownerTokens], [stranger, strangerTokens]]) {
		await sendOn(svm, [getCreateAssociatedTokenIdempotentInstruction({ payer: holder, ata: tokens, owner: holder.address, mint: mintKey })], { feePayer: holder });
	}
	const gift = await sendOn(svm, [probe([writable(petKey)], words(6, 3_000_000))]);
	const balance = (key) => getTokenDecoder().decode(svm.getAccount(key).data).amount;
	const claim = (claimer, tokens) => sendOn(svm, [probe([signing(claimer), readonly(petKey), writable(ledger), writable(mintKey), writable(tokens), readonly(TOKEN_PROGRAM_ADDRESS)], words(9))], { feePayer: claimer });
	const first = await claim(owner, ownerTokens);
	const second = await claim(owner, ownerTokens);
	const thief = await claim(stranger, strangerTokens);
	await sendOn(svm, [probe([writable(petKey)], words(6, 1))]);
	put(svm, petKey, svm.getAccount(petKey).data, DELEGATION_PROGRAM);
	const delegatedClaim = await claim(owner, ownerTokens);
	const show = (sent) => sent.failed ? `refused (${sent.error.match(/Custom \{ code: (\d+)/)?.[1] ?? sent.error})` : `${sent.units} CU, paid ${logged(sent.logs).pop()}`;
	console.log(`  gift 3,000,000 ${gift.failed ? gift.error : `${gift.units} CU`} · owner claims ${show(first)} · again ${show(second)} · stranger ${show(thief)} · pet account delegated (owned by the delegation program on L1) ${show(delegatedClaim)} · owner holds ${balance(ownerTokens)}`);
}
