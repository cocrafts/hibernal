import { LiteSVM } from "litesvm";
import {
	AccountRole,
	address,
	appendTransactionMessageInstruction,
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

const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const matchups = [
	[80, 50, 5, 50, 80, 5, 42n],
	[50, 50, 5, 50, 50, 5, 7n],
	[200, 200, 5, 160, 80, 5, 123456789n],
];

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

const svm = new LiteSVM();
const payer = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(1));
const program = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(3));
svm.airdrop(payer.address, lamports(10_000_000_000n));
svm.addProgramFromFile(program.address, process.argv[2]);
const [arena] = await getProgramDerivedAddress({ programAddress: program.address, seeds: ["arena", getAddressEncoder().encode(payer.address)] });
const payerMeta = { address: payer.address, role: AccountRole.WRITABLE_SIGNER, signer: payer };
const arenaMeta = { address: arena, role: AccountRole.WRITABLE };

async function send(step, accounts, data) {
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(payer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash({ blockhash: svm.latestBlockhash(), lastValidBlockHeight: 1000n }, m),
		(m) => appendTransactionMessageInstruction({ programAddress: program.address, accounts, data }, m),
	);
	const result = svm.sendTransaction(await signTransactionMessageWithSigners(message));
	svm.expireBlockhash();
	const failed = result.constructor.name === "FailedTransactionMetadata";
	const meta = failed ? result.meta() : result;
	if (failed) {
		console.log(`${step}: FAILED ${result.err().toString()}`);
		console.log(meta.logs().join("\n"));
		process.exit(1);
	}
	return { units: Number(meta.computeUnitsConsumed()), logs: meta.logs() };
}

function fightUnits(logs) {
	const remaining = logs.filter((line) => line.startsWith("Program consumption:")).map((line) => Number(line.split(" ")[2]));
	return remaining.length >= 2 ? remaining[0] - remaining[1] : null;
}

console.log(`initialize arena: ${(await send("initialize", [payerMeta, arenaMeta, { address: SYSTEM_PROGRAM, role: AccountRole.READONLY }], u64Bytes(0))).units} CU`);
for (const matchup of matchups) {
	const sent = await send("fight", [payerMeta, arenaMeta], fightData(matchup));
	const stored = svm.getAccount(arena).data;
	const view = new DataView(stored.buffer, stored.byteOffset, stored.length);
	console.log(`seed=${view.getBigUint64(8, true)} outcome=${view.getUint8(16)} rounds=${view.getUint32(20, true)} attackerHp=${view.getUint32(24, true)} defenderHp=${view.getUint32(28, true)} | fight ${fightUnits(sent.logs)} CU, instruction ${sent.units} CU, fights=${view.getBigUint64(0, true)}`);
}
