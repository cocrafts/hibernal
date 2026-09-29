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
	getMintDecoder,
	getTokenDecoder,
} from "@solana-program/token";

const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const DELEGATION_PROGRAM = address("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
const PET_EARNED = 32;
const SECONDS_PER_DAY = 86_400n;

const [programPath] = process.argv.slice(2);
if (!programPath) {
	console.log("usage: node tools/chain/payoutLiteSvm.mjs out/payoutProbe.so");
	process.exit(2);
}
const svm = new LiteSVM();
const signerOf = (fill) => createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(fill));
const payer = await signerOf(1);
const owner = await signerOf(2);
const program = await signerOf(3);
const stranger = await signerOf(4);
for (const wallet of [payer, owner, stranger]) svm.airdrop(wallet.address, lamports(1_000_000_000n));
svm.addProgramFromFile(program.address, programPath);
const encoder = getAddressEncoder();
const pda = async (...seeds) => (await getProgramDerivedAddress({ programAddress: program.address, seeds }))[0];
const mint = await pda("mint");
const pets = [await pda("pet", Uint8Array.of(0)), await pda("pet", Uint8Array.of(1))];
const ledgers = [await pda("paid", Uint8Array.of(0)), await pda("paid", Uint8Array.of(1))];
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
const balance = (key) => { const found = svm.getAccount(key); return found ? getTokenDecoder().decode(found.data).amount : 0n; };
const outcome = (sent) => sent.failed ? `refused (${sent.error.replace(/\s+/g, " ").slice(0, 90)})` : "accepted";

const claim = (claimer, id, pet = pets[id], ledger = ledgers[id], destination = ownerTokens) => send(claimer, [{
	programAddress: program.address,
	accounts: [signing(claimer), readonly(pet), writable(ledger), writable(mint), writable(destination), readonly(TOKEN_PROGRAM_ADDRESS)],
	data: words(6, id),
}]);
const earn = (id, amount) => send(payer, [{ programAddress: program.address, accounts: [writable(pets[id])], data: words(3, amount) }]);

async function report(label, sent) {
	const [earned, paid, amount] = logged(sent.logs);
	console.log(`${label}: ${outcome(sent)} · ${sent.units} CU${amount === undefined ? "" : ` · earned ${earned} paid before ${paid} paid now ${amount}`} · owner holds ${balance(ownerTokens)}`);
}

const created = await send(payer, [{ programAddress: program.address, accounts: [signing(payer), writable(mint), readonly(SYSTEM_PROGRAM), readonly(TOKEN_PROGRAM_ADDRESS)], data: words(0) }]);
const minted = getMintDecoder().decode(svm.getAccount(mint).data);
console.log(`mint created by the program: ${outcome(created)} · ${created.units} CU · decimals ${minted.decimals} · supply ${minted.supply} · mint authority ${minted.mintAuthority.value === mint ? "the mint PDA itself" : minted.mintAuthority.value} · freeze authority ${minted.freezeAuthority.__option}`);
for (const [id, holder] of [[0, owner], [1, stranger]]) {
	const sent = await send(payer, [{ programAddress: program.address, accounts: [signing(payer), writable(pets[id]), writable(ledgers[id]), readonly(SYSTEM_PROGRAM)], data: new Uint8Array([...words(1, id), ...encoder.encode(holder.address)]) }]);
	console.log(`pet ${id} created for ${holder === owner ? "the owner" : "the stranger"}: ${outcome(sent)} · pet account holds ${svm.getAccount(pets[id]).lamports} lamports of rent and no key`);
}
for (const [holder, tokens] of [[owner, ownerTokens], [stranger, strangerTokens]]) {
	await send(holder, [getCreateAssociatedTokenIdempotentInstruction({ payer: holder, ata: tokens, owner: holder.address, mint })]);
}

await report("earn 3,000,000 signed by the game's payer (not the owner)", await earn(0, 3_000_000));
await report("owner claims", await claim(owner, 0));
await report("owner claims again", await claim(owner, 0));
await report("stranger claims pet 0 into its own account", await claim(stranger, 0, pets[0], ledgers[0], strangerTokens));
await report("stranger claims pet 0 into the owner's account", await claim(stranger, 0));
await report("owner passes pet 1 as pet 0", await claim(owner, 0, pets[1], ledgers[0]));
await report("owner passes pet 1's ledger as pet 0's", await claim(owner, 0, pets[0], ledgers[1]));
await earn(0, 20_000_000);
await report("earn 20,000,000 more, owner claims (cap 10,000,000 a day)", await claim(owner, 0));
await report("owner claims again the same day", await claim(owner, 0));

const petBytes = svm.getAccount(pets[0]);
const forged = new Uint8Array(petBytes.data);
new DataView(forged.buffer).setBigUint64(PET_EARNED, 999_000_000n, true);
svm.setAccount({ address: pets[0], data: forged, executable: false, lamports: petBytes.lamports, programAddress: stranger.address, space: BigInt(forged.length) });
const clock = svm.getClock();
clock.unixTimestamp = clock.unixTimestamp + SECONDS_PER_DAY;
svm.setClock(clock);
await report("next day, pet 0 held by another program with 999,000,000 earned", await claim(owner, 0));
const delegated = new Uint8Array(petBytes.data);
new DataView(delegated.buffer).setBigUint64(PET_EARNED, 40_000_000n, true);
svm.setAccount({ address: pets[0], data: delegated, executable: false, lamports: petBytes.lamports, programAddress: DELEGATION_PROGRAM, space: BigInt(delegated.length) });
await report("next day, pet 0 delegated (owned by the delegation program on L1) with 40,000,000 committed", await claim(owner, 0));
await report("owner claims again that day", await claim(owner, 0));

const direct = await send(payer, [{ programAddress: TOKEN_PROGRAM_ADDRESS, accounts: [writable(mint), writable(strangerTokens), { address: payer.address, role: AccountRole.WRITABLE_SIGNER, signer: payer }], data: Uint8Array.of(7, ...words(1_000_000)) }]);
console.log(`the game's payer calls MintTo on the token program directly: ${outcome(direct)}`);
const supply = getMintDecoder().decode(svm.getAccount(mint).data).supply;
console.log(`supply ${supply} · owner holds ${balance(ownerTokens)} · stranger holds ${balance(strangerTokens)} · ledger paid ${new DataView(svm.getAccount(ledgers[0]).data.buffer).getBigUint64(0, true)}`);
