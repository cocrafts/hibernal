import { writeFile } from "std/fs";
import { Pubkey } from "std/solana";
import { HostAccount, run, setClock } from "std/solana/host";
import { ACTS_PER_EPOCH, BLOCK_SLOTS, checkPolicy } from "../../rules/index";
import { engineVersion } from "../../sim/digests";
import { entry } from "../main";
import {
	TEST_DAY,
	WORLD_SEED,
	at,
	instructionBytes,
	policyBytes,
	programKey,
	returned,
	seededAccounts,
	seededData,
	stepAccounts,
	vrfIdentity,
	worldBeforeDay,
} from "./dayWorld";

const FIXTURE_DAYS: uint64 = 3;
const HEX = "0123456789abcdef";

function hexOf(bytes: uint8[]): string {
	let text = "";
	for (const value of bytes) {
		text = text + HEX.charAt((value >> 4) as int32) + HEX.charAt((value & 15) as int32);
	}
	return text;
}

function keyHex(key: Pubkey): string {
	let text = "";
	for (let position = 0; position < 32; position++) {
		const value = key.bytes[position];
		text = text + HEX.charAt((value >> 4) as int32) + HEX.charAt((value & 15) as int32);
	}
	return text;
}

function ownerName(holder: HostAccount): string {
	if (holder.executable) { return "executable"; }
	return holder.owner.equals(programKey()) ? "program" : "system";
}

function accountLines(step: HostAccount[]): string {
	let text = "";
	for (let index = 0; index < step.length; index++) {
		const holder = step[index];
		text = text + `account ${index} ${keyHex(holder.key)} ${ownerName(holder)} ${holder.writable ? 1 : 0} ${holder.signer ? 1 : 0} ${hexOf(holder.data)}\n`;
	}
	return text;
}

function stateLine(label: string, step: HostAccount[]): string {
	let text = `expect ${label}`;
	for (let index = 0; index < step.length; index++) {
		if (!step[index].writable || step[index].data.length == 0) { continue; }
		text = text + ` ${index}:${hexOf(step[index].data)}`;
	}
	return text + "\n";
}

function main(): int32 {
	const policy = policyBytes();
	if (!checkPolicy(policy, engineVersion()).ok) { return 1; }
	const world = worldBeforeDay(TEST_DAY);
	const step = stepAccounts(world, TEST_DAY - 1, policy);
	let text = `program ${keyHex(programKey())}\nidentity ${keyHex(vrfIdentity())}\nseed ${WORLD_SEED}\n` + accountLines(step);
	let request: uint64 = 0;
	for (let day = TEST_DAY; day < TEST_DAY + FIXTURE_DAYS; day++) {
		const clock = at(day);
		setClock(clock);
		text = text + `clock ${clock.unixTimestamp}\n`;
		if (run(programKey(), step, instructionBytes("Step"), entry).result != 0) { return 2; }
		text = text + stateLine("dawn", step);
		for (let round = 0; round < ACTS_PER_EPOCH; round++) {
			request += 1;
			const seeded = seededAccounts(step);
			if (run(programKey(), seeded, seededData(WORLD_SEED, request), entry).result != 0) { return 3; }
			returned(step, seeded);
			text = text + `seeded ${request}\n` + stateLine("seeded", step);
			for (let turn = 0; turn < BLOCK_SLOTS; turn++) {
				if (run(programKey(), step, instructionBytes("Step"), entry).result != 0) { return 4; }
				text = text + stateLine("act", step);
			}
		}
		if (run(programKey(), step, instructionBytes("Step"), entry).result != 0) { return 5; }
		text = text + stateLine("dusk", step);
	}
	const saved = writeFile("out/std/dayFixture.txt", text);
	if (!saved.ok) { return 6; }
	console.log(`dayFixture: ${FIXTURE_DAYS} days from day ${TEST_DAY} written to out/std/dayFixture.txt`);
	return 0;
}

process.exit(main());
