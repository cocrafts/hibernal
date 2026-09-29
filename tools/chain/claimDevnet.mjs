import { readFileSync } from "node:fs";
import {
	AccountRole,
	address,
	appendTransactionMessageInstruction,
	createKeyPairSignerFromBytes,
	createSolanaRpc,
	createTransactionMessage,
	getAddressEncoder,
	getBase64EncodedWireTransaction,
	getSignatureFromTransaction,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";

const BASE_RPC = process.env.BASE_RPC ?? "https://rpc.magicblock.app/devnet";
const BASE_READ_RPC = process.env.BASE_READ_RPC ?? BASE_RPC;
const SGT_GROUP = address("GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te");
const CLAIM_ERRORS = ["WrongTokenProgram", "NotAMint", "WrongMintAuthority", "NoGroupMember", "MemberElsewhere", "WrongGroup", "WrongTokenMint", "WrongHolder", "NotExactlyOne"];

const [programArgument, groupArgument, mintArgument, heldArgument] = process.argv.slice(2);
if (!heldArgument) {
	console.log("usage: node tools/chain/claimDevnet.mjs <program id> <group mint> <member mint> <member token account>");
	process.exit(2);
}
const PROGRAM = address(programArgument);
const GROUP = address(groupArgument);
const MINT = address(mintArgument);
const HELD = address(heldArgument);
const encoder = getAddressEncoder();
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const payer = await createKeyPairSignerFromBytes(Uint8Array.from(JSON.parse(readFileSync(`${process.env.HOME}/.config/solana/id.json`, "utf8"))));
const base = createSolanaRpc(BASE_RPC);
const baseRead = createSolanaRpc(BASE_READ_RPC);

function claimData(group, authority) {
	const bytes = new Uint8Array(72);
	bytes.set(encoder.encode(group), 8);
	bytes.set(encoder.encode(authority), 40);
	return bytes;
}

async function claim(label, expected, group) {
	const { value: blockhash } = await base.getLatestBlockhash().send();
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(payer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstruction({
			programAddress: PROGRAM,
			accounts: [
				{ address: payer.address, role: AccountRole.WRITABLE_SIGNER, signer: payer },
				{ address: MINT, role: AccountRole.READONLY },
				{ address: HELD, role: AccountRole.READONLY },
			],
			data: claimData(group, payer.address),
		}, m),
	);
	const transaction = await signTransactionMessageWithSigners(message);
	const signature = getSignatureFromTransaction(transaction);
	await base.sendTransaction(getBase64EncodedWireTransaction(transaction), { encoding: "base64", skipPreflight: true }).send();
	for (let attempt = 0; attempt < 60; attempt++) {
		await sleep(1000);
		const { value } = await base.getSignatureStatuses([signature]).send();
		const status = value[0];
		if (!status || (status.confirmationStatus !== "confirmed" && status.confirmationStatus !== "finalized")) continue;
		let details = null;
		for (let read = 0; read < 20 && !details; read++) {
			details = await baseRead.getTransaction(signature, { maxSupportedTransactionVersion: 0, commitment: "confirmed", encoding: "json" }).send().catch(() => null);
			if (!details) await sleep(1500);
		}
		const code = status.err ? Number(/"Custom":(\d+)/.exec(JSON.stringify(status.err, (_, v) => typeof v === "bigint" ? Number(v) : v))?.[1] ?? -1) : 0;
		const outcome = status.err ? (CLAIM_ERRORS[code - 1] ?? JSON.stringify(status.err)) : "ok";
		const member = details?.meta?.logMessages?.find((line) => line.startsWith("Program log: 0x"))?.split(", ").pop() ?? "";
		const units = details?.meta?.computeUnitsConsumed ?? "?";
		console.log(`${label.padEnd(28)} ${outcome}${member ? ` member ${member}` : ""} · ${units} CU · ${outcome === expected ? "as expected" : `EXPECTED ${expected}`} · ${signature}`);
		if (outcome !== expected) process.exitCode = 1;
		return;
	}
	console.log(`${label}: not confirmed ${signature}`);
	process.exitCode = 1;
}

console.log(`program ${PROGRAM} group ${GROUP} member mint ${MINT} held in ${HELD} by ${payer.address}`);
await claim("member of the devnet group", "ok", GROUP);
await claim("same member, SGT group", "WrongGroup", SGT_GROUP);
