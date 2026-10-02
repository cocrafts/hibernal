import { readFileSync, writeFileSync } from "node:fs";
import { address } from "@solana/kit";
import { cluster, hibernal, keypairAt, read, readU64, send, sleep, text } from "./hibernal.mjs";
import { crankAddress, createCrank, newCrankSeed } from "./hydra.mjs";

const STAGE = process.env.STAGE ?? "clock";
const CLOCK_SYSVAR = address("SysvarC1ock11111111111111111111111111111111");
const MEMO_PROGRAM = address("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr");
const { base, baseRead, ephemeral } = cluster();
const authority = await keypairAt(`${process.env.HOME}/.config/solana/id.json`);

function signedI64(bytes, offset) {
	return new DataView(bytes.buffer, bytes.byteOffset).getBigInt64(offset, true);
}

async function clockSample() {
	const holder = await read(ephemeral, CLOCK_SYSVAR);
	const slot = await ephemeral.getSlot().send();
	return { local: Date.now(), slot: BigInt(slot), clockSlot: readU64(holder.data, 0), unix: signedI64(holder.data, 32) };
}

async function clock() {
	const samples = [];
	const minutes = Number(process.env.MINUTES ?? 3);
	const until = Date.now() + minutes * 60_000;
	while (Date.now() < until) {
		samples.push(await clockSample());
		await sleep(10_000);
	}
	const first = samples[0];
	const last = samples[samples.length - 1];
	const localSeconds = (last.local - first.local) / 1000;
	const slots = Number(last.slot - first.slot);
	const unixSeconds = Number(last.unix - first.unix);
	console.log(`samples ${samples.length} over ${localSeconds.toFixed(1)} s local`);
	console.log(`ER slots advanced ${slots}: ${(localSeconds * 1000 / slots).toFixed(3)} ms a slot by the local clock`);
	console.log(`ER Clock.unix_timestamp advanced ${unixSeconds} s (local ${localSeconds.toFixed(1)} s), offset now ${(Number(last.unix) - last.local / 1000).toFixed(1)} s`);
	console.log(`Clock sysvar slot lags getSlot by ${Number(last.slot - last.clockSlot)} slots`);
	for (const sample of samples) console.log(`  local ${new Date(sample.local).toISOString()} slot ${sample.slot} clock.slot ${sample.clockSlot} unix ${sample.unix} (unix - local ${(Number(sample.unix) - sample.local / 1000).toFixed(2)})`);
}

async function memoWorks() {
	const sent = await send(ephemeral, ephemeral, "memo on the ER", [{ programAddress: MEMO_PROGRAM, accounts: [], data: text("hibernal flow probe") }], authority);
	console.log(`memo on the ER: ${sent.units} CU, fee ${sent.fee}`);
}

async function hydra() {
	await memoWorks();
	const sponsor = await keypairAt("out/hydraSponsor.json");
	const slot = BigInt(await ephemeral.getSlot().send());
	const cranks = {};
	const overdueSeed = newCrankSeed();
	cranks.overdue = { crank: await crankAddress(overdueSeed), startSlot: slot - 500n, interval: 100n, remaining: 8n };
	await send(ephemeral, ephemeral, "crank overdue", [createCrank({ sponsor, crank: cranks.overdue.crank, seed: overdueSeed, startSlot: cranks.overdue.startSlot, interval: 100n, remaining: 8n, computeUnits: 200_000, scheduled: { programAddress: MEMO_PROGRAM, accounts: [], data: text("overdue") } })], sponsor);
	const failingSeed = newCrankSeed();
	cranks.failing = { crank: await crankAddress(failingSeed), startSlot: slot + 50n, interval: 100n, remaining: 3n };
	await send(ephemeral, ephemeral, "crank failing", [createCrank({ sponsor, crank: cranks.failing.crank, seed: failingSeed, startSlot: cranks.failing.startSlot, interval: 100n, remaining: 3n, computeUnits: 200_000, scheduled: { programAddress: MEMO_PROGRAM, accounts: [], data: Uint8Array.of(0xff, 0xfe) } })], sponsor);
	writeFileSync("out/flowProbeCranks.json", JSON.stringify({ createdAtSlot: slot.toString(), cranks: Object.fromEntries(Object.entries(cranks).map(([name, entry]) => [name, { ...entry, startSlot: entry.startSlot.toString(), interval: entry.interval.toString(), remaining: entry.remaining.toString() }])) }, null, 1));
	console.log(`created at ER slot ${slot}: overdue ${cranks.overdue.crank} (start ${cranks.overdue.startSlot}, every 100, 8 runs), failing ${cranks.failing.crank} (start ${cranks.failing.startSlot}, every 100, 3 runs)`);
}

async function commits() {
	const programAddress = address(process.env.PROGRAM);
	const program = hibernal(programAddress, authority);
	const mint = address(readFileSync("out/admission/mints.txt", "utf8").trim().split("\n")[1].split(" ")[1]);
	const pet = await program.address(program.seeds.pet(mint));
	const l1Touches = async () => (await baseRead.getSignaturesForAddress(pet, { limit: 100 }).send()).length;
	for (let index = 1; index <= Number(process.env.COMMITS ?? 12); index++) {
		const before = await l1Touches();
		try {
			const sent = await send(ephemeral, ephemeral, `commit ${index}`, [await program.commitPet(authority, mint)], authority);
			let after = before;
			for (let wait = 0; wait < 20 && after === before; wait++) {
				await sleep(1500);
				after = await l1Touches();
			}
			console.log(`commit ${index}: ER ${sent.units} CU fee ${sent.fee}; L1 transactions on the pet ${before} -> ${after}`);
		} catch (error) {
			console.log(`commit ${index}: refused (${error.message})`);
		}
	}
}

const stages = { clock, hydra, commits };
await stages[STAGE]();
