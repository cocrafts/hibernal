import { createHash, randomBytes } from "node:crypto";
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { address, createKeyPairSignerFromPrivateKeyBytes, createSolanaRpc, getAddressDecoder, getProgramDerivedAddress } from "@solana/kit";
import {
	ASSOCIATED_TOKEN_PROGRAM,
	MEMBER_MINT_BYTES,
	SYSTEM_PROGRAM,
	TOKEN_2022_PROGRAM,
	TOKEN_PROGRAM,
	accountOffsets,
	admissionTicket,
	cluster,
	encoder,
	hibernal,
	idlAt,
	joined,
	keypairAt,
	read,
	readonly,
	send,
	u32,
	u64,
	writable,
	writableSigner,
} from "./hibernal.mjs";

const SGT_GROUP = "GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te";
const SGT_MINT_AUTHORITY = "GT2zuHVaZQYZSyQMgJPLzvkmyztfyXg2NJunqFp4p3A4";
const SKR_DECIMALS = 1_000_000n;
const PORT = Number(process.env.PORT ?? 8787);
const GIFT_SKR = BigInt(process.env.GIFT_SKR ?? 200);
const GIFT_LAMPORTS = BigInt(process.env.GIFT_LAMPORTS ?? 20_000_000);
const NET_DIR = process.env.NET_DIR ?? "out/devnet";
const SEED_PATH = process.env.TICKET_SEED ?? `${NET_DIR}/ticketSeed.hex`;
const LOG_PATH = process.env.TICKET_LOG ?? `${NET_DIR}/tickets.jsonl`;

const programAddress = address(process.env.PROGRAM ?? process.argv[2] ?? "");
const mainnet = createSolanaRpc(process.env.MAINNET_RPC ?? "https://api.mainnet-beta.solana.com");
const { base, baseRead } = cluster();
const wallet = await keypairAt(process.env.AUTHORITY ?? `${process.env.HOME}/.config/solana/id.json`);
const group = (await keypairAt(process.env.GROUP_KEYPAIR ?? "out/devGroupMint.json")).address;
if (!existsSync(SEED_PATH)) writeFileSync(SEED_PATH, randomBytes(32).toString("hex"));
const seed = Buffer.from(readFileSync(SEED_PATH, "utf8").trim(), "hex");
const program = hibernal(programAddress);
const configAt = accountOffsets(idlAt(), "Config");
const configHolder = await read(baseRead, await program.address(program.seeds.config()));
const skrMint = getAddressDecoder().decode(configHolder.data.subarray(configAt.skr_mint, configAt.skr_mint + 32));
const ticketRent = BigInt(await base.getMinimumBalanceForRentExemption(MEMBER_MINT_BYTES).send());
const inFlight = new Map();

async function seekerGenesisMint(owner) {
	const { value: accounts } = await mainnet.getTokenAccountsByOwner(owner, { programId: TOKEN_2022_PROGRAM }, { encoding: "jsonParsed" }).send();
	const held = accounts.map((entry) => entry.account.data.parsed.info).filter((info) => info.tokenAmount.amount === "1").map((info) => info.mint);
	if (held.length === 0) return null;
	const { value: mints } = await mainnet.getMultipleAccounts(held, { encoding: "jsonParsed" }).send();
	const index = mints.findIndex((mint) => {
		const info = mint?.data?.parsed?.info;
		const member = info?.extensions?.find((extension) => extension.extension === "tokenGroupMember")?.state;
		return mint?.owner === TOKEN_2022_PROGRAM && info.mintAuthority === SGT_MINT_AUTHORITY && member?.group === SGT_GROUP;
	});
	return index === -1 ? null : held[index];
}

async function ticketFor(sgtMint) {
	const bytes = createHash("sha256").update(seed).update("ticket").update(encoder.encode(address(sgtMint))).digest();
	return await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(bytes));
}

async function gifts(owner) {
	const [skrAccount] = await getProgramDerivedAddress({
		programAddress: ASSOCIATED_TOKEN_PROGRAM,
		seeds: [encoder.encode(owner), encoder.encode(TOKEN_PROGRAM), encoder.encode(skrMint)],
	});
	return [
		{
			programAddress: ASSOCIATED_TOKEN_PROGRAM,
			accounts: [writableSigner(wallet), writable(skrAccount), readonly(owner), readonly(skrMint), readonly(SYSTEM_PROGRAM), readonly(TOKEN_PROGRAM)],
			data: Uint8Array.of(1),
		},
		{
			programAddress: TOKEN_PROGRAM,
			accounts: [writable(skrMint), writable(skrAccount), writableSigner(wallet)],
			data: joined(Uint8Array.of(7), u64(GIFT_SKR * SKR_DECIMALS)),
		},
		{ programAddress: SYSTEM_PROGRAM, accounts: [writableSigner(wallet), writable(owner)], data: joined(u32(2), u64(GIFT_LAMPORTS)) },
	];
}

async function admit(owner) {
	const sgt = await seekerGenesisMint(owner);
	if (!sgt) return { code: 403, body: { error: "NoSeekerGenesisToken", owner } };
	const ticket = await ticketFor(sgt);
	if (await read(baseRead, ticket.address)) return { code: 200, body: { status: "already", owner, sgt, ticket: ticket.address } };
	const instructions = [...(await admissionTicket(wallet, group, owner, ticket, ticketRent)), ...(await gifts(owner))];
	const sent = await send(base, baseRead, "admit", instructions, wallet, 200_000, false);
	appendFileSync(LOG_PATH, JSON.stringify({ at: new Date().toISOString(), owner, sgt, ticket: ticket.address, signature: sent.signature }) + "\n");
	return { code: 200, body: { status: "issued", owner, sgt, ticket: ticket.address, signature: sent.signature, skr: String(GIFT_SKR), lamports: String(GIFT_LAMPORTS) } };
}

function admitOnce(owner) {
	if (!inFlight.has(owner)) inFlight.set(owner, admit(owner).finally(() => inFlight.delete(owner)));
	return inFlight.get(owner);
}

async function bodyOf(request) {
	let raw = "";
	for await (const chunk of request) {
		raw += chunk;
		if (raw.length > 1024) throw new Error("body too large");
	}
	return JSON.parse(raw);
}

const server = createServer(async (request, response) => {
	const reply = (code, body) => {
		response.writeHead(code, { "content-type": "application/json" });
		response.end(JSON.stringify(body));
	};
	if (request.method === "GET" && request.url === "/health") return reply(200, { ok: true, program: programAddress, group, skrMint });
	if (request.method !== "POST" || request.url !== "/admit") return reply(404, { error: "NotFound" });
	let owner;
	try {
		owner = address((await bodyOf(request)).owner);
	} catch {
		return reply(400, { error: "BadOwner" });
	}
	try {
		const { code, body } = await admitOnce(owner);
		console.log(`${new Date().toISOString()} ${owner} ${code} ${body.status ?? body.error}`);
		reply(code, body);
	} catch (error) {
		console.log(`${new Date().toISOString()} ${owner} 500 ${error.message}`);
		reply(500, { error: "AdmitFailed", detail: error.message });
	}
});
server.listen(PORT, () => console.log(`admission service on :${PORT}, program ${programAddress}, group ${group}, skr ${skrMint}, gift ${GIFT_SKR} SKR + ${GIFT_LAMPORTS} lamports`));
