import { address, getProgramDerivedAddress } from "@solana/kit";
import {
	DELEGATION_PROGRAM,
	MAGIC_PROGRAM,
	MAGIC_VAULT,
	SYSTEM_PROGRAM,
	cluster,
	joined,
	key,
	keypairAt,
	read,
	readonly,
	send,
	sleep,
	u64,
	writable,
	writableSigner,
} from "./hibernal.mjs";

const SPONSOR_LAMPORTS = 100_000_000n;
const WILD_BYTES = 1_936n;
const BLOCK_ID = 1n;

const [programArgument] = process.argv.slice(2);
if (!programArgument) {
	console.log("usage: node tools/chain/wildProbe.mjs <wild probe program id>");
	process.exit(2);
}
const program = address(programArgument);
const { base, baseRead, ephemeral, validator } = cluster();
const payer = await keypairAt(`${process.env.HOME}/.config/solana/id.json`);
const pda = async (owner, ...seeds) => (await getProgramDerivedAddress({ programAddress: owner, seeds }))[0];
const sponsor = await pda(program, "sponsor");
const wild = await pda(program, "wild", u64(BLOCK_ID));
const call = (discriminator, accounts, ...args) => ({ programAddress: program, accounts, data: joined(u64(discriminator), ...args) });
const transfer = (from, to, lamports) => ({
	programAddress: SYSTEM_PROGRAM,
	accounts: [writableSigner(from), writable(to)],
	data: joined(Uint8Array.of(2, 0, 0, 0), u64(lamports)),
});
const onL1 = (step, instructions) => send(base, baseRead, step, instructions, payer, 400_000);
const onEr = (step, instructions) => send(ephemeral, ephemeral, step, instructions, payer, 400_000);
const balance = (holder) => holder ? Number(holder.lamports) : null;
const counter = (holder) => holder ? new DataView(holder.data.buffer, holder.data.byteOffset).getBigUint64(0, true) : null;

if (!(await read(baseRead, sponsor))) {
	const delegated = await onL1("sponsor create + fund + delegate", [
		call(0, [writableSigner(payer), writable(sponsor), readonly(SYSTEM_PROGRAM)]),
		transfer(payer, sponsor, SPONSOR_LAMPORTS),
		call(1, [
			writableSigner(payer),
			readonly(SYSTEM_PROGRAM),
			writable(sponsor),
			readonly(program),
			writable(await pda(program, "buffer", key(sponsor))),
			writable(await pda(DELEGATION_PROGRAM, "delegation", key(sponsor))),
			writable(await pda(DELEGATION_PROGRAM, "delegation-metadata", key(sponsor))),
			readonly(DELEGATION_PROGRAM),
			readonly(validator),
		]),
	]);
	console.log(`sponsor delegated on L1: ${delegated.units} CU, fee ${delegated.fee}`);
}
for (let attempt = 0; attempt < 60 && !(await read(ephemeral, sponsor)); attempt++) await sleep(500);
const sponsorBefore = balance(await read(ephemeral, sponsor));
console.log(`sponsor on ER: ${sponsorBefore} lamports`);

const magicAccounts = () => [writable(sponsor), writable(wild), writable(MAGIC_VAULT), readonly(MAGIC_PROGRAM)];
const created = await onEr("create ephemeral wild page", [call(2, magicAccounts(), u64(BLOCK_ID), u64(WILD_BYTES))]);
const page = await read(ephemeral, wild);
const sponsorAfter = balance(await read(ephemeral, sponsor));
console.log(`created: ${created.units} CU, fee ${created.fee}; page owner ${page?.owner} bytes ${page?.data.length} lamports ${balance(page)}; sponsor paid ${sponsorBefore - sponsorAfter}`);
console.log(created.logs.filter((line) => line.includes("ephemeral") || line.includes("Created")).join("\n"));

for (const value of [7n, 35n]) {
	const written = await onEr(`write ${value}`, [call(3, [writable(wild)], u64(BLOCK_ID), u64(value))]);
	console.log(`write ${value}: ${written.units} CU, fee ${written.fee}; counter ${counter(await read(ephemeral, wild))}`);
}
console.log(`page on L1: ${(await read(baseRead, wild)) ? "PRESENT" : "absent"}`);

const closed = await onEr("close ephemeral wild page", [call(4, magicAccounts(), u64(BLOCK_ID))]);
console.log(`closed: ${closed.units} CU; page on ER ${(await read(ephemeral, wild)) ? "PRESENT" : "absent"}; sponsor refunded to ${balance(await read(ephemeral, sponsor))}`);
