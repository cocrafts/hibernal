import { LiteSVM } from "litesvm";
import {
	AccountRole,
	address,
	appendTransactionMessageInstruction,
	createKeyPairSignerFromPrivateKeyBytes,
	createSolanaRpc,
	createTransactionMessage,
	getAddressEncoder,
	lamports,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";

const MAINNET_RPC = process.env.MAINNET_RPC ?? "https://api.mainnet-beta.solana.com";
const TOKEN_2022 = address("TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb");
const LEGACY_TOKEN = address("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
const SGT_GROUP = address("GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te");
const SGT_AUTHORITY = address("GT2zuHVaZQYZSyQMgJPLzvkmyztfyXg2NJunqFp4p3A4");
const SGT_MINT = address(process.env.SGT_MINT ?? "2qmVbZc7fGpyqL1cpy5VjM3NPBJ1sDJxYY24okXz8eXb");
const CLAIM_ERRORS = ["WrongTokenProgram", "NotAMint", "WrongMintAuthority", "NoGroupMember", "MemberElsewhere", "WrongGroup", "WrongTokenMint", "WrongHolder", "NotExactlyOne"];
const encoder = getAddressEncoder();

const programPath = process.argv[2];
if (!programPath) {
	console.log("usage: node tools/chain/claimLiteSvm.mjs out/claimProbe.so");
	process.exit(2);
}
const { value: fetched } = await createSolanaRpc(MAINNET_RPC).getAccountInfo(SGT_MINT, { encoding: "base64" }).send();
if (!fetched || fetched.owner !== TOKEN_2022) {
	console.log(`SGT mint ${SGT_MINT} not readable as a Token-2022 account on ${MAINNET_RPC}`);
	process.exit(1);
}
const mintData = new Uint8Array(Buffer.from(fetched.data[0], "base64"));

function tokenAccount(mint, holder, amount) {
	const bytes = new Uint8Array(170);
	const view = new DataView(bytes.buffer);
	bytes.set(encoder.encode(mint), 0);
	bytes.set(encoder.encode(holder), 32);
	view.setBigUint64(64, BigInt(amount), true);
	bytes[108] = 2;
	bytes[165] = 2;
	view.setUint16(166, 7, true);
	return bytes;
}

function claimData(group, authority) {
	const bytes = new Uint8Array(72);
	bytes.set(encoder.encode(group), 8);
	bytes.set(encoder.encode(authority), 40);
	return bytes;
}

const svm = new LiteSVM();
const holder = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(1));
const stranger = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(2));
const program = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(3));
const held = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(4));
svm.airdrop(holder.address, lamports(10_000_000_000n));
svm.addProgramFromFile(program.address, programPath);

function place(key, data, owner) {
	svm.setAccount({ address: key, data, executable: false, lamports: lamports(1_000_000_000n), programAddress: owner, space: BigInt(data.length) });
}

async function claim(label, expected, { mint = mintData, mintOwner = TOKEN_2022, heldBy = holder.address, amount = 1, group = SGT_GROUP, authority = SGT_AUTHORITY } = {}) {
	place(SGT_MINT, mint, mintOwner);
	place(held.address, tokenAccount(SGT_MINT, heldBy, amount), TOKEN_2022);
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(holder, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash({ blockhash: svm.latestBlockhash(), lastValidBlockHeight: 1000n }, m),
		(m) => appendTransactionMessageInstruction({
			programAddress: program.address,
			accounts: [
				{ address: holder.address, role: AccountRole.WRITABLE_SIGNER, signer: holder },
				{ address: SGT_MINT, role: AccountRole.READONLY },
				{ address: held.address, role: AccountRole.READONLY },
			],
			data: claimData(group, authority),
		}, m),
	);
	const result = svm.sendTransaction(await signTransactionMessageWithSigners(message));
	svm.expireBlockhash();
	const failed = result.constructor.name === "FailedTransactionMetadata";
	const meta = failed ? result.meta() : result;
	const code = failed ? Number(/Custom(?:\(| \{ code: )(\d+)/.exec(result.err().toString())?.[1] ?? -1) : 0;
	const outcome = failed ? (CLAIM_ERRORS[code - 1] ?? result.err().toString()) : "ok";
	const member = failed ? "" : ` member ${meta.logs().find((line) => line.startsWith("Program log: 0x"))?.split(", ").pop()}`;
	const verdict = outcome === expected ? "as expected" : `EXPECTED ${expected}`;
	console.log(`${label.padEnd(34)} ${outcome}${member} · ${meta.computeUnitsConsumed()} CU · ${verdict}`);
	if (outcome !== expected) process.exitCode = 1;
}

const forgedAuthority = mintData.slice();
forgedAuthority.set(encoder.encode(stranger.address), 4);
console.log(`SGT mint ${SGT_MINT} from ${MAINNET_RPC}: ${mintData.length} bytes`);
await claim("holder of a real SGT", "ok");
await claim("SGT held by someone else", "WrongHolder", { heldBy: stranger.address });
await claim("empty token account", "NotExactlyOne", { amount: 0 });
await claim("another admission group", "WrongGroup", { group: stranger.address });
await claim("mint authority not the issuer", "WrongMintAuthority", { mint: forgedAuthority });
await claim("mint under the legacy token program", "WrongTokenProgram", { mintOwner: LEGACY_TOKEN });
