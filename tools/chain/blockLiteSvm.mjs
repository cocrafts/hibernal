import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { LiteSVM } from "litesvm";
import {
	AccountRole,
	address,
	appendTransactionMessageInstructions,
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
import { BLOCK_ID, blockOf, differing, scenarioOf, sizesOf, withPets } from "./blockFixture.mjs";

const COMPUTE_BUDGET_PROGRAM = address("ComputeBudget111111111111111111111111111111");
const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const DELEGATION_PROGRAM = address("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
const COMPUTE_UNIT_LIMIT = 1_400_000;
const SCENARIOS = ["typical", "busiest"];
const CLAIM_SLOT = 3;
const GIFT = 3_000_000n;
const root = new URL("../../", import.meta.url);
const probeDirectory = new URL("out/actProbe/", root);

const [programPath, policyPath] = process.argv.slice(2);
if (!programPath || !policyPath) {
	console.log("usage: node tools/chain/blockLiteSvm.mjs out/blockProbe.so <checkpoint>.policy");
	process.exit(2);
}
const policy = new Uint8Array(readFileSync(policyPath));
mkdirSync(probeDirectory, { recursive: true });
writeFileSync(new URL("policy.txt", probeDirectory), Array.from(policy).join("\n") + "\n");
console.log(execFileSync("msc", ["run", "tools/actHost.ms"], { cwd: root, encoding: "utf8" })
	.split("\n")
	.filter((line) => /^(typical|busiest):/.test(line))
	.join("\n"));

const svm = new LiteSVM();
const signerOf = (fill) => createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(fill));
const payer = await signerOf(1);
const owner = await signerOf(2);
const program = await signerOf(3);
const stranger = await signerOf(4);
for (const wallet of [payer, owner, stranger]) svm.airdrop(wallet.address, lamports(10_000_000_000n));
svm.addProgramFromFile(program.address, programPath);
const encoder = getAddressEncoder();
const pda = async (...seeds) => (await getProgramDerivedAddress({ programAddress: program.address, seeds }))[0];
const holders = [];
for (let id = 0; id <= BLOCK_ID; id++) holders.push(await pda("block", Uint8Array.of(id)));
const [POLICY, CONTEXT, CONFIG, WILDS, BLOCK] = holders;
const mint = await pda("mint");
const ledgers = [];
for (let slot = 0; slot < 10; slot++) ledgers.push(await pda("paid", Uint8Array.of(slot)));
const [ownerTokens] = await findAssociatedTokenPda({ owner: owner.address, mint, tokenProgram: TOKEN_PROGRAM_ADDRESS });
const [strangerTokens] = await findAssociatedTokenPda({ owner: stranger.address, mint, tokenProgram: TOKEN_PROGRAM_ADDRESS });

const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });
const signing = (signer) => ({ address: signer.address, role: AccountRole.WRITABLE_SIGNER, signer });

function words(...values) {
	const bytes = new Uint8Array(8 * values.length);
	const view = new DataView(bytes.buffer);
	values.forEach((value, index) => view.setBigUint64(8 * index, BigInt(value), true));
	return bytes;
}

function limitInstruction(units) {
	const bytes = new Uint8Array(5);
	const view = new DataView(bytes.buffer);
	view.setUint8(0, 2);
	view.setUint32(1, units, true);
	return { programAddress: COMPUTE_BUDGET_PROGRAM, accounts: [], data: bytes };
}

async function send(feePayer, instructions) {
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(feePayer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash({ blockhash: svm.latestBlockhash(), lastValidBlockHeight: 1000n }, m),
		(m) => appendTransactionMessageInstructions(instructions, m),
	);
	const result = svm.sendTransaction(await signTransactionMessageWithSigners(message));
	svm.expireBlockhash();
	const failed = result.constructor.name === "FailedTransactionMetadata";
	const meta = failed ? result.meta() : result;
	return { failed, error: failed ? result.err().toString() : null, units: Number(meta.computeUnitsConsumed()), logs: meta.logs() };
}

const logged = (logs) => logs.filter((line) => line.startsWith("Program log: 0x")).map((line) => BigInt(line.split(", ").pop()));
const same = (left, right) => left.length === right.length && left.every((value, index) => Number(value) === right[index]);
const outcome = (sent) => sent.failed ? `refused (${sent.error.replace(/\s+/g, " ").slice(0, 90)})` : "accepted";
const balance = (key) => { const found = svm.getAccount(key); return found ? getTokenDecoder().decode(found.data).amount : 0n; };
const probe = (accounts, data) => ({ programAddress: program.address, accounts, data });
const gameAccounts = (writableKeys) => holders.map((key) => writableKeys.includes(key) ? writable(key) : readonly(key));

function put(key, data, programAddress = program.address) {
	svm.setAccount({
		address: key,
		data,
		executable: false,
		lamports: lamports(svm.minimumBalanceForRentExemption(BigInt(data.length))),
		programAddress,
		space: BigInt(data.length),
	});
}

const layout = await send(payer, [probe([], words(0))]);
if (layout.failed) throw new Error(`layout: ${layout.error}`);
const sizes = sizesOf(logged(layout.logs));
const rent = svm.minimumBalanceForRentExemption(BigInt(sizes.block));
console.log(`Block ${sizes.block} bytes (pets ${10 * sizes.pet}, identities ${10 * sizes.identity}, graces ${10 * sizes.grace}, fights ${32 * sizes.fight}, listings ${10 * sizes.listing}, relationships 45) · LiteSVM default rent ${rent} lamports (${Number(rent) / 1e9} SOL) · GlobalConfig ${sizes.global} · ActContext ${sizes.context}`);

for (const name of SCENARIOS) {
	const scenario = scenarioOf(probeDirectory, name);
	const block = blockOf(sizes, scenario.pets, CLAIM_SLOT, encoder.encode(owner.address));
	const expected = withPets(block, sizes, scenario.after);
	put(POLICY, policy);
	put(CONTEXT, scenario.context);
	put(CONFIG, scenario.global);
	put(WILDS, scenario.wilds);
	put(BLOCK, block);
	console.log(`\n${scenario.header} · expected choice ${scenario.choice.join(" ")} digest 0x${scenario.digest.toString(16)}`);
	const acted = await send(payer, [limitInstruction(COMPUTE_UNIT_LIMIT), probe(gameAccounts([CONFIG, BLOCK]), words(1, scenario.engine))]);
	if (acted.failed) {
		console.log(`act: ${acted.error}`);
		console.log(acted.logs.filter((line) => line.includes("failed") || line.includes("consumed")).join("\n"));
		continue;
	}
	const digest = logged((await send(payer, [probe(gameAccounts([]), words(2))])).logs).pop();
	const blockDiffers = differing(expected, svm.getAccount(BLOCK).data);
	const globalDiffers = differing(scenario.afterGlobal, svm.getAccount(CONFIG).data);
	console.log(`act on one Block account ${acted.units} CU · choice match ${same(logged(acted.logs), scenario.choice)} · digest match ${digest === scenario.digest} · bytes differing from the host's: Block ${blockDiffers} of ${expected.length}, GlobalConfig ${globalDiffers} of ${scenario.afterGlobal.length}`);
}

console.log("\nclaim from a slot of the Block (the busiest block after its act)");
const created = await send(payer, [probe([signing(payer), writable(mint), readonly(SYSTEM_PROGRAM), readonly(TOKEN_PROGRAM_ADDRESS)], words(5))]);
console.log(`mint created: ${outcome(created)} · ${created.units} CU`);
for (const slot of [CLAIM_SLOT, CLAIM_SLOT + 1]) {
	const ledger = await send(payer, [probe([signing(payer), writable(ledgers[slot]), readonly(SYSTEM_PROGRAM)], words(6, slot))]);
	console.log(`ledger of slot ${slot}: ${outcome(ledger)} · ${ledger.units} CU`);
}
for (const [holder, tokens] of [[owner, ownerTokens], [stranger, strangerTokens]]) {
	await send(holder, [getCreateAssociatedTokenIdempotentInstruction({ payer: holder, ata: tokens, owner: holder.address, mint })]);
}
const claim = (claimer, slot, ledger = ledgers[slot], destination = ownerTokens, block = BLOCK) => send(claimer, [probe(
	[signing(claimer), readonly(block), writable(ledger), writable(mint), writable(destination), readonly(TOKEN_PROGRAM_ADDRESS)],
	words(11, slot),
)]);
async function report(label, sent) {
	const [gift, paid, amount] = logged(sent.logs);
	console.log(`${label}: ${outcome(sent)} · ${sent.units} CU${amount === undefined ? "" : ` · gift owed ${gift} paid before ${paid} paid now ${amount}`} · owner holds ${balance(ownerTokens)}`);
}
const gifted = await send(payer, [probe([writable(BLOCK)], words(4, CLAIM_SLOT, GIFT))]);
console.log(`gift ${GIFT} to slot ${CLAIM_SLOT}: ${outcome(gifted)} · ${gifted.units} CU · gift owed now ${logged(gifted.logs).pop()}`);
await report("owner claims its slot", await claim(owner, CLAIM_SLOT));
await report("owner claims again", await claim(owner, CLAIM_SLOT));
await report("stranger claims the slot into its own account", await claim(stranger, CLAIM_SLOT, ledgers[CLAIM_SLOT], strangerTokens));
await report("owner claims the neighbour slot it does not own", await claim(owner, CLAIM_SLOT + 1));
await report("owner passes the neighbour's ledger for its slot", await claim(owner, CLAIM_SLOT, ledgers[CLAIM_SLOT + 1]));
await report("owner passes the config account as the Block", await claim(owner, CLAIM_SLOT, ledgers[CLAIM_SLOT], ownerTokens, CONFIG));
const current = svm.getAccount(BLOCK).data;
await send(payer, [probe([writable(BLOCK)], words(4, CLAIM_SLOT, GIFT))]);
put(BLOCK, svm.getAccount(BLOCK).data, DELEGATION_PROGRAM);
await report(`Block delegated (owned by the delegation program on L1) with ${GIFT} more gifted`, await claim(owner, CLAIM_SLOT));
put(BLOCK, current, stranger.address);
await report("Block held by another program", await claim(owner, CLAIM_SLOT));
