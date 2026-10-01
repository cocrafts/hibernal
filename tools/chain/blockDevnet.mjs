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
import {
	TOKEN_PROGRAM_ADDRESS,
	findAssociatedTokenPda,
	getCreateAssociatedTokenIdempotentInstruction,
	getTokenDecoder,
} from "@solana-program/token";
import { BLOCK_ID, blockOf, differing, scenarioOf, sizesOf, withPets } from "./blockFixture.mjs";

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
const CHUNK_BYTES = 900;
const SCENARIO = process.env.SCENARIO ?? "busiest";
const CLAIM_SLOT = 3;
const GIFT = 3_000_000n;

const [programArgument, policyPath] = process.argv.slice(2);
if (!programArgument || !policyPath) {
	console.log("usage: node tools/chain/blockDevnet.mjs <program> <checkpoint>.policy (run blockLiteSvm.mjs first: it writes the host's scenarios)");
	process.exit(2);
}
const PROGRAM = address(programArgument);
const policy = new Uint8Array(readFileSync(policyPath));
const probeDirectory = new URL("../../out/actProbe/", import.meta.url);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const encoder = getAddressEncoder();
const payer = await createKeyPairSignerFromBytes(Uint8Array.from(JSON.parse(readFileSync(`${process.env.HOME}/.config/solana/id.json`, "utf8"))));
const base = createSolanaRpc(BASE_RPC);
const baseRead = createSolanaRpc(BASE_READ_RPC);
const ephemeral = createSolanaRpc(ER_RPC);
const router = createSolanaRpc(ROUTER_RPC);
const pda = async (programAddress, ...seeds) => (await getProgramDerivedAddress({ programAddress, seeds }))[0];
const holders = [];
for (let id = 0; id <= BLOCK_ID; id++) {
	const key = await pda(PROGRAM, "block", Uint8Array.of(id));
	holders.push({
		id,
		key,
		buffer: await pda(PROGRAM, "buffer", encoder.encode(key)),
		record: await pda(DELEGATION_PROGRAM, "delegation", encoder.encode(key)),
		metadata: await pda(DELEGATION_PROGRAM, "delegation-metadata", encoder.encode(key)),
	});
}
const [POLICY, CONTEXT, CONFIG, WILDS, BLOCK] = holders;
const DELEGATED = [CONFIG, BLOCK];
const mint = await pda(PROGRAM, "mint");
const ledger = await pda(PROGRAM, "paid", Uint8Array.of(CLAIM_SLOT));
const [ownerTokens] = await findAssociatedTokenPda({ owner: payer.address, mint, tokenProgram: TOKEN_PROGRAM_ADDRESS });

const signerMeta = { address: payer.address, role: AccountRole.WRITABLE_SIGNER, signer: payer };
const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });
const probe = (accounts, data) => ({ programAddress: PROGRAM, accounts, data });
const json = (value) => JSON.stringify(value, (_, inner) => typeof inner === "bigint" ? inner.toString() : inner);
const gameAccounts = (writableHolders) => holders.map((holder) => writableHolders.includes(holder) ? writable(holder.key) : readonly(holder.key));
const logged = (logs) => logs.filter((line) => line.startsWith("Program log: 0x")).map((line) => BigInt(line.split(", ").pop()));
const same = (left, right) => left.length === right.length && left.every((value, index) => Number(value) === right[index]);

function words(...values) {
	const bytes = new Uint8Array(8 * values.length);
	const view = new DataView(bytes.buffer);
	values.forEach((value, index) => view.setBigUint64(8 * index, BigInt(value), true));
	return bytes;
}

function joined(head, tail) {
	const bytes = new Uint8Array(head.length + tail.length);
	bytes.set(head);
	bytes.set(tail, head.length);
	return bytes;
}

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
			const details = await fetchTransaction(rpc === base ? baseRead : rpc, signature);
			const logs = details?.meta?.logMessages ?? [];
			const units = details?.meta?.computeUnitsConsumed !== undefined ? Number(details.meta.computeUnitsConsumed) : null;
			const fee = details?.meta?.fee !== undefined ? Number(details.meta.fee) : null;
			console.log(`[${layer}] ${step}: ${status.err ? "FAILED " + json(status.err) : "ok"} ${elapsed}ms ${units ?? "-"} CU fee ${fee ?? "-"} ${signature}`);
			return { signature, logs, units, fee, elapsed, err: status.err };
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

async function read(rpc, key) {
	const { value } = await patiently(() => rpc.getAccountInfo(key, { encoding: "base64", commitment: "confirmed" }).send());
	if (!value) return null;
	return { owner: value.owner, lamports: BigInt(value.lamports), data: new Uint8Array(Buffer.from(value.data[0], "base64")) };
}

async function waitFor(rpc, label, key, predicate, timeoutMs) {
	const started = Date.now();
	while (Date.now() - started < timeoutMs) {
		const state = await read(rpc, key).catch(() => null);
		if (state && predicate(state)) return { elapsed: Date.now() - started, state };
		await sleep(1000);
	}
	throw new Error(`${label}: timed out after ${timeoutMs}ms`);
}

const holds = (expected) => (state) => state.data.length === expected.length && state.data.every((value, index) => value === expected[index]);

async function returned(holder) {
	await mustSend(ephemeral, "er", `commit and undelegate ${holder.id}`, [probe([signerMeta, writable(holder.key), readonly(MAGIC_PROGRAM), writable(MAGIC_CONTEXT)], words(10))]);
}

async function prepared(contents) {
	const left = [];
	for (const holder of DELEGATED) {
		const state = await read(baseRead, holder.key);
		if (state?.owner === DELEGATION_PROGRAM) left.push(holder);
	}
	for (const holder of left) await returned(holder);
	for (const holder of left) await waitFor(baseRead, `account ${holder.id} back on L1`, holder.key, (state) => state.owner === PROGRAM, 180000);
	for (const holder of holders) {
		const content = contents[holder.id];
		let state = await read(baseRead, holder.key);
		if (state === null || state.owner === SYSTEM_PROGRAM) {
			await mustSend(base, "base", `create ${holder.id} (${content.length} bytes)`, [probe([signerMeta, writable(holder.key), readonly(SYSTEM_PROGRAM)], words(7, holder.id, content.length))]);
			state = (await waitFor(baseRead, `account ${holder.id} created`, holder.key, (found) => found.owner === PROGRAM, 60000)).state;
		}
		if (holds(content)(state)) continue;
		for (let offset = 0; offset < content.length; offset += CHUNK_BYTES) {
			const chunk = content.subarray(offset, Math.min(offset + CHUNK_BYTES, content.length));
			if (holds(chunk)({ data: state.data.subarray(offset, offset + chunk.length) })) continue;
			await mustSend(base, "base", `write ${holder.id} ${offset}+${chunk.length}`, [probe([signerMeta, writable(holder.key)], joined(words(3, holder.id, offset), chunk))]);
		}
		await waitFor(baseRead, `account ${holder.id} written`, holder.key, holds(content), 60000);
	}
}

async function delegated(holder) {
	await mustSend(base, "base", `delegate ${holder.id}`, [probe([
		signerMeta,
		readonly(SYSTEM_PROGRAM),
		writable(holder.key),
		readonly(PROGRAM),
		writable(holder.buffer),
		writable(holder.record),
		writable(holder.metadata),
		readonly(DELEGATION_PROGRAM),
		readonly(VALIDATOR),
	], words(8, holder.id))]);
}

async function claimed(label) {
	const sent = await send(base, "base", label, [probe(
		[signerMeta, readonly(BLOCK.key), writable(ledger), writable(mint), writable(ownerTokens), readonly(TOKEN_PROGRAM_ADDRESS)],
		words(11, CLAIM_SLOT),
	)]);
	const [gift, paid, amount] = logged(sent.logs);
	const tokens = await read(baseRead, ownerTokens);
	console.log(`  ${label}: ${sent.err ? `FAILED ${json(sent.err)}` : "ok"} · ${sent.units} CU · fee ${sent.fee} · gift owed ${gift} paid before ${paid} paid now ${amount} · owner holds ${tokens ? getTokenDecoder().decode(tokens.data).amount : 0n}`);
	return sent;
}

const deployed = (await patiently(() => baseRead.getAccountInfo(PROGRAM, { encoding: "base64" }).send())).value;
if (!deployed?.executable) {
	console.log(`program ${PROGRAM} is not deployed on ${BASE_READ_RPC}`);
	process.exit(1);
}
const lamportsBefore = (await base.getBalance(payer.address).send()).value;
console.log(`program ${PROGRAM} payer ${payer.address} ER ${ER_RPC} validator ${VALIDATOR}`);

const layout = await mustSend(base, "base", "layout", [probe([], words(0))]);
const sizes = sizesOf(logged(layout.logs));
const rent = await patiently(() => baseRead.getMinimumBalanceForRentExemption(BigInt(sizes.block)).send());
console.log(`Block ${sizes.block} bytes on SBF · rent-exempt minimum on devnet ${rent} lamports`);

const scenario = scenarioOf(probeDirectory, SCENARIO);
const block = blockOf(sizes, scenario.pets, CLAIM_SLOT, encoder.encode(payer.address));
const expected = withPets(block, sizes, scenario.after);
console.log(`\n${scenario.header} · expected choice ${scenario.choice.join(" ")} digest 0x${scenario.digest.toString(16)}`);
await prepared([policy, scenario.context, scenario.global, scenario.wilds, block]);
const blockOnL1 = await read(baseRead, BLOCK.key);
console.log(`Block on L1: ${blockOnL1.data.length} bytes, ${blockOnL1.lamports} lamports`);

if (!(await read(baseRead, mint))) await mustSend(base, "base", "create mint", [probe([signerMeta, writable(mint), readonly(SYSTEM_PROGRAM), readonly(TOKEN_PROGRAM_ADDRESS)], words(5))]);
if (!(await read(baseRead, ledger))) await mustSend(base, "base", `create ledger of slot ${CLAIM_SLOT}`, [probe([signerMeta, writable(ledger), readonly(SYSTEM_PROGRAM)], words(6, CLAIM_SLOT))]);
await mustSend(base, "base", "owner token account", [getCreateAssociatedTokenIdempotentInstruction({ payer, ata: ownerTokens, owner: payer.address, mint })]);
await claimed("claim before the Block is delegated (gift owed of the fixture)");

for (const holder of DELEGATED) await delegated(holder);
const inEr = await waitFor(ephemeral, "Block in the ER", BLOCK.key, holds(block), 60000);
console.log(`Block readable in the ER ${inEr.elapsed}ms after delegation, bytes equal to L1`);

const acted = await send(ephemeral, "er", "act on the whole Block", [limitInstruction(COMPUTE_UNIT_LIMIT), probe(gameAccounts(DELEGATED), words(1, scenario.engine))]);
console.log(`act ${acted.err ? `FAILED ${json(acted.err)}` : `${acted.units} CU in ${acted.elapsed}ms, fee ${acted.fee}`} · choice match ${same(logged(acted.logs), scenario.choice)}`);
const digest = logged((await send(ephemeral, "er", "digest in ER", [probe(gameAccounts([]), words(2))])).logs).pop();
const erBlock = await read(ephemeral, BLOCK.key);
const erGlobal = await read(ephemeral, CONFIG.key);
const routerBlock = await read(router, BLOCK.key);
console.log(`ER after the act: digest match ${digest === scenario.digest} · bytes differing from the host's: Block ${differing(expected, erBlock.data)} of ${expected.length} (router ${differing(expected, routerBlock.data)}), GlobalConfig ${differing(scenario.afterGlobal, erGlobal.data)} of ${scenario.afterGlobal.length}`);

const gifted = await send(ephemeral, "er", `gift ${GIFT} to slot ${CLAIM_SLOT}`, [probe([writable(BLOCK.key)], words(4, CLAIM_SLOT, GIFT))]);
console.log(`gift: gift owed now ${logged(gifted.logs).pop()}`);
const afterGift = (await read(ephemeral, BLOCK.key)).data;
console.log(`Block after the gift differs from the host's after-act bytes in ${differing(expected, afterGift)} bytes (the slot's gift owed)`);

const commitStarted = Date.now();
const committed = await send(ephemeral, "er", "commit the Block, stays delegated", [probe([signerMeta, writable(BLOCK.key), readonly(MAGIC_PROGRAM), writable(MAGIC_CONTEXT)], words(9))]);
const landed = await waitFor(baseRead, "committed Block on L1", BLOCK.key, holds(afterGift), 180000).catch(async (error) => {
	const state = await read(baseRead, BLOCK.key);
	console.log(`${error.message}: L1 holds ${state?.data.length} bytes, ${state ? differing(afterGift, state.data) : "-"} differing from the ER's`);
	return null;
});
console.log(`commit ${committed.err ? `FAILED ${json(committed.err)}` : `${committed.units} CU fee ${committed.fee}`} · Block on L1 ${landed ? `${Date.now() - commitStarted}ms after the send, owner ${landed.state.owner}, 0 of ${afterGift.length} bytes differing from the ER` : "not equal to the ER"}`);

if (landed) {
	await claimed("owner claims its slot from the committed Block");
	await claimed("owner claims again");
}

const returnStarted = Date.now();
for (const holder of DELEGATED) await returned(holder);
for (const holder of DELEGATED) await waitFor(baseRead, `account ${holder.id} back on L1`, holder.key, (state) => state.owner === PROGRAM, 180000);
const backBlock = await read(baseRead, BLOCK.key);
const backGlobal = await read(baseRead, CONFIG.key);
console.log(`Block and GlobalConfig back on L1 ${Date.now() - returnStarted}ms after the first return · Block ${differing(afterGift, backBlock.data)} of ${afterGift.length} bytes differing from the ER, GlobalConfig ${differing(scenario.afterGlobal, backGlobal.data)} differing from the host's, Block lamports ${backBlock.lamports}`);

const lamportsAfter = (await base.getBalance(payer.address).send()).value;
console.log(`\npayer spent ${lamportsBefore - lamportsAfter} lamports on L1 during this run (rent of new accounts included)`);
