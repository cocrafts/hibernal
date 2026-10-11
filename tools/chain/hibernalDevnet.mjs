import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { address, getProgramDerivedAddress } from "@solana/kit";
import {
	accountOffsets,
	idlAt,
	ASSOCIATED_TOKEN_PROGRAM,
	SYSTEM_PROGRAM,
	TOKEN_2022_PROGRAM,
	TOKEN_PROGRAM,
	cluster,
	encoder,
	hibernal,
	instructionDiscriminator,
	json,
	keypairAt,
	read,
	readonly,
	send,
	sleep,
	writable,
	writableSigner,
} from "./hibernal.mjs";

const STAGE = process.env.STAGE ?? "setup";
const PETS = Number(process.env.PETS ?? 20);
const SEATS = 10;
const BLOCKS = Math.ceil(PETS / SEATS);
const CHUNK = 900;
const GROUP = address(process.env.GROUP ?? "6jXijzhCm1Njikk3vLTmrw1mjPzWrwKherDYvELgwCpR");

const idl = idlAt();
const blockAt = accountOffsets(idl, "Block");
const policyAt = accountOffsets(idl, "Policy");
const BLOCK_PHASE = blockAt.phase;
const BLOCK_MEMBERS = blockAt.members;
const PHASES = ["Idle", "Seeding", "Acting"];

const [programArgument, policyPath] = process.argv.slice(2);
if (!programArgument || !policyPath) {
	console.log("usage: STAGE=setup|shop|claim node tools/chain/hibernalDevnet.mjs <program id> <checkpoint>.policy (the day runs through Hydra: tools/chain/ops.mjs)");
	process.exit(2);
}
const programAddress = address(programArgument);
const STATE_PATH = `out/hibernalDevnet-${programArgument}.json`;
const { base, baseRead, ephemeral, validator } = cluster();
const authority = await keypairAt(`${process.env.HOME}/.config/solana/id.json`);
const program = hibernal(programAddress, authority);
const policy = new Uint8Array(readFileSync(policyPath));
const engine = new DataView(policy.buffer, policy.byteOffset).getBigUint64(8, true);
const mints = readFileSync("out/admission/mints.txt", "utf8").trim().split("\n").map((line) => address(line.split(" ")[1])).slice(0, PETS);
const skrMint = await keypairAt("out/devSkrMint.json");
const state = existsSync(STATE_PATH) ? JSON.parse(readFileSync(STATE_PATH, "utf8")) : {};
const save = () => writeFileSync(STATE_PATH, json(state));
const onL1 = (step, instructions, units) => send(base, baseRead, step, instructions, authority, units);
const onEr = (step, instructions, units) => send(ephemeral, ephemeral, step, instructions, authority, units);
const report = (step, sent) => console.log(`  ${step}: ${sent.units ?? "?"} CU, ${sent.elapsed} ms, fee ${sent.fee ?? "?"}`);

async function associated(owner, mint, tokenProgram) {
	const [found] = await getProgramDerivedAddress({ programAddress: ASSOCIATED_TOKEN_PROGRAM, seeds: [encoder.encode(owner), encoder.encode(tokenProgram), encoder.encode(mint)] });
	return found;
}

async function setup() {
	const config = await program.address(program.seeds.config());
	if (!(await read(baseRead, config))) {
		const genesisTimestamp = BigInt(Math.floor(Date.now() / 1000) - 86_400 + Number(process.env.FIRST_DAWN_IN_SECONDS ?? -600));
		const treasury = await program.revenueVault(skrMint.address);
		report("initialize", await onL1("initialize", [await program.openRevenueVault(authority, skrMint.address), await program.initialize({
			admissionGroup: GROUP,
			engine,
			genesisTimestamp,
			claimCapPerDay: 10_000_000n,
			resortEvery: 7n,
			validator,
			skrMint: skrMint.address,
			treasury,
			hatchFeeLamports: BigInt(process.env.HATCH_FEE_LAMPORTS ?? 20_000_000),
		})]));
		state.genesisTimestamp = genesisTimestamp;
		save();
	}
	const policyHolder = await read(baseRead, await program.address(program.seeds.policy()));
	const written = policyHolder ? Number(new DataView(policyHolder.data.buffer).getUint32(policyAt.written, true)) : 0;
	for (let offset = written; offset < policy.length; offset += CHUNK) {
		const end = Math.min(offset + CHUNK, policy.length);
		report(`policy ${offset}..${end}`, await onL1("policy", [await program.writePolicy(offset, policy.subarray(offset, end), end === policy.length)]));
	}
	for (let id = 0; id < BLOCKS; id++) {
		if (await read(baseRead, await program.address(program.seeds.block(id)))) continue;
		report(`block ${id}`, await onL1(`block ${id}`, [await program.createBlock(id)]));
	}
	for (const mint of mints) {
		if (await read(baseRead, await program.address(program.seeds.pet(mint)))) continue;
		const held = await associated(authority.address, mint, TOKEN_2022_PROGRAM);
		report(`claim ${mint}`, await onL1("claim", [await program.claim(authority, mint, held, encoder.encode(mint)[2])]));
	}
	const delegated = async (key) => (await read(baseRead, key))?.owner === "DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh";
	if (!(await delegated(await program.address(program.seeds.world())))) report("delegate world", await onL1("delegate world", [await program.delegateWorld()]));
	if (!(await delegated(await program.address(program.seeds.vrfPayer())))) report("delegate VRF payer", await onL1("delegate VRF payer", [await program.delegateVrfPayer()]));
	for (let id = 0; id < BLOCKS; id++) {
		if (await delegated(await program.address(program.seeds.block(id)))) continue;
		report(`delegate block ${id}`, await onL1("delegate block", [await program.delegateBlock(id)]));
	}
	for (const mint of mints) {
		if (await delegated(await program.address(program.seeds.pet(mint)))) continue;
		report(`delegate pet ${mint}`, await onL1("delegate pet", [await program.delegatePet(authority, mint)]));
	}
	await sleep(3000);
	for (let index = 0; index < mints.length; index++) {
		const id = Math.floor(index / SEATS);
		const block = await readWhenCloned(await program.address(program.seeds.block(id)));
		const members = membersOf(block.data);
		const pet = await program.address(program.seeds.pet(mints[index]));
		if (members.includes(pet)) continue;
		report(`place ${index} in block ${id}`, await onEr("place", [await program.place(id, mints[index])]));
	}
	for (let id = 0; id < BLOCKS; id++) {
		const block = await read(ephemeral, await program.address(program.seeds.block(id)));
		console.log(`  block ${id}: ${membersOf(block.data).filter(Boolean).length} members, phase ${PHASES[block.data[BLOCK_PHASE]]}`);
	}
}

async function readWhenCloned(key) {
	for (let attempt = 0; attempt < 30; attempt++) {
		const found = await read(ephemeral, key);
		if (found) return found;
		await sleep(1000);
	}
	throw new Error(`${key} never appeared in the ER`);
}

function membersOf(data) {
	const members = [];
	for (let seat = 0; seat < SEATS; seat++) {
		const bytes = data.subarray(BLOCK_MEMBERS + seat * 32, BLOCK_MEMBERS + seat * 32 + 32);
		members.push(bytes.every((byte) => byte === 0) ? null : decodeAddress(bytes));
	}
	return members;
}

function decodeAddress(bytes) {
	const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
	let value = BigInt("0x" + Buffer.from(bytes).toString("hex"));
	let out = "";
	while (value > 0n) {
		out = alphabet[Number(value % 58n)] + out;
		value /= 58n;
	}
	for (const byte of bytes) {
		if (byte !== 0) break;
		out = "1" + out;
	}
	return out;
}

async function shop() {
	const mint = mints[0];
	const source = await associated(authority.address, skrMint.address, TOKEN_PROGRAM);
	const treasury = await program.revenueVault(skrMint.address);
	const before = await read(ephemeral, await program.address(program.seeds.pet(mint)));
	report("buy growth tier 1 with SKR (L1)", await onL1("buy", [await program.buy(authority, mint, { item: 1, tier: 0, skrMint: skrMint.address, source, treasury })]));
	await readWhenCloned(await program.address(program.seeds.ledger(mint)));
	report("load the ledger into the owner's slots (ER)", await onEr("load", [await program.load(mint)]));
	report("load again moves nothing (ER)", await onEr("load again", [await program.load(mint)]));
	const after = await read(ephemeral, await program.address(program.seeds.pet(mint)));
	const changed = after.data.findIndex((byte, index) => byte !== before.data[index]);
	console.log(`  pet bytes changed from offset ${changed}`);
}

async function claim() {
	const mint = mints[0];
	const hbrn = await program.address(program.seeds.mint());
	const destination = await associated(authority.address, hbrn, TOKEN_PROGRAM);
	if (!(await read(baseRead, destination))) {
		await onL1("create HBRN account", [{
			programAddress: ASSOCIATED_TOKEN_PROGRAM,
			accounts: [writableSigner(authority), writable(destination), readonly(authority.address), readonly(hbrn), readonly(SYSTEM_PROGRAM), readonly(TOKEN_PROGRAM)],
			data: Uint8Array.of(1),
		}]);
	}
	report("commit the pet (ER)", await onEr("commit", [await program.commitPet(authority, mint)]));
	await sleep(8000);
	try {
		report("claim HBRN (L1)", await onL1("claim", [await program.claimReward(authority, mint, destination)]));
	} catch (error) {
		console.log(`  claim refused: ${error.message}`);
	}
}

const stages = { setup, shop, claim };
if (!stages[STAGE]) throw new Error(`unknown stage ${STAGE}`);
await stages[STAGE]();
