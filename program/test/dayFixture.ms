import { writeFile } from "std/fs";
import { Clock, Pubkey } from "std/solana";
import { HostAccount, run, setClock } from "std/solana/host";
import { ACTS_PER_EPOCH, BLOCK_SLOTS, checkPolicy } from "../../rules/index";
import { engineVersion } from "../../sim/digests";
import { entry } from "../main";
import {
	TEST_DAY,
	WORLD_SEED,
	blockOf,
	currentSeq,
	dueClock,
	policyBytes,
	programKey,
	returned,
	roundStartAccounts,
	roundStartReturned,
	seededAccounts,
	seededData,
	stepData,
	turnAccounts,
	vrfIdentity,
	withNextCrank,
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
		if (!step[index].owner.equals(programKey()) || step[index].data.length == 0) { continue; }
		text = text + ` ${index}:${hexOf(step[index].data)}`;
	}
	return text + "\n";
}

function clockLine(clock: Clock): string {
	return `clock ${clock.unixTimestamp} ${clock.slot}\n`;
}

function roundStartLine(step: HostAccount[], day: uint64): string {
	const clock = dueClock(step, day);
	setClock(clock);
	const seq = currentSeq(step);
	const round = roundStartAccounts(step);
	if (run(programKey(), round, stepData("RoundStart", seq), entry).result != 0) { return ""; }
	roundStartReturned(step, round);
	return clockLine(clock) + `roundStart ${seq}\n` + stateLine("roundStart", step);
}

function seededLine(step: HostAccount[]): string {
	const request = blockOf(step).pendingRequest;
	const seeded = seededAccounts(step);
	if (run(programKey(), seeded, seededData(WORLD_SEED, request), entry).result != 0) { return ""; }
	returned(step, seeded);
	return `seeded ${request}\n` + stateLine("seeded", step);
}

function turnLine(step: HostAccount[], day: uint64, label: string): string {
	withNextCrank(step);
	const clock = dueClock(step, day);
	setClock(clock);
	const seq = currentSeq(step);
	if (run(programKey(), step, stepData("Turn", seq), entry).result != 0) { return ""; }
	return clockLine(clock) + `turn ${seq}\n` + stateLine(label, step);
}

function main(): int32 {
	const policy = policyBytes();
	if (!checkPolicy(policy, engineVersion()).ok) { return 1; }
	const world = worldBeforeDay(TEST_DAY);
	const step = turnAccounts(world, TEST_DAY, policy);
	let text = `program ${keyHex(programKey())}\nidentity ${keyHex(vrfIdentity())}\nseed ${WORLD_SEED}\n` + accountLines(step);
	for (let day = TEST_DAY; day < TEST_DAY + FIXTURE_DAYS; day++) {
		for (let round = 0; round < ACTS_PER_EPOCH; round++) {
			const started = roundStartLine(step, day);
			if (started == "") { return 2; }
			const seeded = seededLine(step);
			if (seeded == "") { return 3; }
			text = text + started + seeded;
			if (day == TEST_DAY && round == 0) {
				const dawn = turnLine(step, day, "dawn");
				if (dawn == "") { return 4; }
				text = text + dawn;
			}
			for (let turn = 0; turn < BLOCK_SLOTS; turn += 2) {
				const acted = turnLine(step, day, "act");
				if (acted == "") { return 5; }
				text = text + acted;
			}
		}
		const ended = turnLine(step, day, "dayEnd");
		if (ended == "") { return 6; }
		text = text + ended;
	}
	const saved = writeFile("out/std/dayFixture.txt", text);
	if (!saved.ok) { return 7; }
	console.log(`dayFixture: ${FIXTURE_DAYS} days from day ${TEST_DAY} written to out/std/dayFixture.txt`);
	return 0;
}

process.exit(main());
