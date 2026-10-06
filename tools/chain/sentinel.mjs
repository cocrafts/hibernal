import { execFileSync, spawn } from "node:child_process";
import { existsSync, readFileSync, renameSync, statfsSync, writeFileSync } from "node:fs";
import { address } from "@solana/kit";
import { accountOffsets, cluster, hibernal, idlAt, json, readU32, readU64, sleep } from "./hibernal.mjs";

const NET_DIR = process.env.NET_DIR ?? "out/localnet";
const TICK_SECONDS = Number(process.env.TICK_SECONDS ?? 15);
const STALL_SECONDS = Number(process.env.STALL_SECONDS ?? 60);
const LAG_SECONDS = Number(process.env.LAG_SECONDS ?? 60);
const OPS_STALE_SECONDS = Number(process.env.OPS_STALE_SECONDS ?? 180);
const DISK_FREE_GIB = Number(process.env.DISK_FREE_GIB ?? 20);
const DISK_PATH = process.env.DISK_PATH ?? NET_DIR;
const ER_INDEX = process.env.ER_INDEX ?? null;
const ER_INDEX_PERCENT = Number(process.env.ER_INDEX_PERCENT ?? 70);
const OPS_STATUS = process.env.OPS_STATUS ?? null;
const ALERT_COMMAND = process.env.ALERT_COMMAND ?? null;
const CRANK_RENT = BigInt(process.env.CRANK_RENT ?? 32_128);
const STATUS_PATH = `${NET_DIR}/sentinelStatus.json`;

const programArgument = process.argv[2];
if (!programArgument) {
	console.log("usage: node tools/chain/sentinel.mjs <program id>  (BASE_READ_RPC, ER_RPC from env; OPS_STATUS, ER_INDEX, ALERT_COMMAND optional)");
	process.exit(2);
}
const { baseRead, ephemeral } = cluster();
const program = hibernal(address(programArgument), null);
const idl = idlAt();
const blockAt = accountOffsets(idl, "Block");
const configAt = accountOffsets(idl, "Config");
const slots = { l1: { slot: null, since: Date.now() }, er: { slot: null, since: Date.now() } };
const active = new Map();

async function readAll(rpc, keys) {
	const out = [];
	for (let start = 0; start < keys.length; start += 100) {
		const { value } = await rpc.getMultipleAccounts(keys.slice(start, start + 100), { encoding: "base64" }).send();
		out.push(...value.map((entry) => (entry ? { owner: entry.owner, lamports: BigInt(entry.lamports), data: new Uint8Array(Buffer.from(entry.data[0], "base64")) } : null)));
	}
	return out;
}

async function slotCheck(name, rpc) {
	const slot = BigInt(await rpc.getSlot().send());
	const tracked = slots[name];
	if (tracked.slot !== slot) {
		tracked.slot = slot;
		tracked.since = Date.now();
	}
	const frozenSeconds = Math.round((Date.now() - tracked.since) / 1000);
	return { slot: slot.toString(), frozenSeconds, alarm: frozenSeconds > STALL_SECONDS ? `${name} slot frozen at ${slot} for ${frozenSeconds} s` : null };
}

async function worldCheck() {
	const configKey = await program.address(program.seeds.config());
	const [config] = await readAll(baseRead, [configKey]);
	if (!config) return { alarm: `config ${configKey} missing on L1` };
	const count = readU32(config.data, configAt.blocks);
	const slotMillis = readU64(config.data, configAt.slot_millis);
	const blockKeys = await Promise.all(Array.from({ length: count }, (_, id) => program.address(program.seeds.block(id))));
	const payerKey = await program.address(program.seeds.vrfPayer());
	const holders = await readAll(ephemeral, [payerKey, ...blockKeys]);
	const [payer, ...blocks] = holders;
	const erSlot = slots.er.slot ?? 0n;
	let worstSlots = 0n;
	let overdue = 0;
	let missing = 0;
	for (const holder of blocks) {
		if (!holder || holder.owner !== programArgument) {
			missing++;
			continue;
		}
		const dueSlot = readU64(holder.data, blockAt.due_slot);
		if (readU64(holder.data, blockAt.crank_seq) === 0n || erSlot <= dueSlot) continue;
		const late = erSlot - dueSlot;
		if (late * slotMillis > BigInt(LAG_SECONDS * 1000)) overdue++;
		if (late > worstSlots) worstSlots = late;
	}
	const worstSeconds = Number(worstSlots * slotMillis / 1000n);
	const payerFloor = 2_000_000n + CRANK_RENT * BigInt(count);
	const alarms = [];
	if (missing > 0) alarms.push(`${missing} of ${count} blocks not readable in the ER`);
	if (overdue > 0) alarms.push(`${overdue} blocks more than ${LAG_SECONDS} s past their due slot, worst ${worstSeconds} s`);
	if (!payer) alarms.push(`VRF payer ${payerKey} missing in the ER`);
	else if (payer.lamports < payerFloor) alarms.push(`VRF payer at ${payer.lamports} lamports, below ${payerFloor}`);
	return {
		blocks: count,
		overdue,
		worstLagSeconds: worstSeconds,
		vrfPayerLamports: payer?.lamports.toString() ?? null,
		alarm: alarms.length > 0 ? alarms.join("; ") : null,
	};
}

function opsCheck() {
	if (!OPS_STATUS) return null;
	if (!existsSync(OPS_STATUS)) return { alarm: `ops status ${OPS_STATUS} missing` };
	const at = Date.parse(JSON.parse(readFileSync(OPS_STATUS, "utf8")).at);
	const ageSeconds = Math.round((Date.now() - at) / 1000);
	return { ageSeconds, alarm: ageSeconds > OPS_STALE_SECONDS ? `ops last wrote its status ${ageSeconds} s ago` : null };
}

function diskCheck() {
	const stats = statfsSync(DISK_PATH);
	const freeGib = Math.floor(stats.bavail * stats.bsize / 2 ** 30);
	return { path: DISK_PATH, freeGib, alarm: freeGib < DISK_FREE_GIB ? `${freeGib} GiB free on ${DISK_PATH}, below ${DISK_FREE_GIB}` : null };
}

function indexCheck() {
	if (!ER_INDEX) return null;
	const stat = execFileSync("mdb_stat", ["-e", "-f", ER_INDEX], { encoding: "utf8" });
	const used = Number(/Number of pages used: (\d+)/.exec(stat)?.[1]);
	const max = Number(/Max pages: (\d+)/.exec(stat)?.[1]);
	const free = Number(/Free pages: (\d+)/.exec(stat)?.[1]);
	if (!used || !max || Number.isNaN(free)) return { alarm: `mdb_stat on ${ER_INDEX} gave no page counts` };
	const live = used - free;
	const percent = Math.round(live * 100 / max);
	return { livePages: live, freePages: free, highWaterPages: used, maxPages: max, percent, alarm: percent > ER_INDEX_PERCENT ? `ER account index ${percent}% full (${live} live of ${max} pages, ${free} free)` : null };
}

async function checked(name, check) {
	try {
		return await check();
	} catch (error) {
		return { alarm: `${name} check failed: ${error.message}` };
	}
}

function alert(message) {
	console.error(`${new Date().toISOString()} ${message}`);
	if (!ALERT_COMMAND) return;
	const child = spawn("sh", ["-c", ALERT_COMMAND], { stdio: ["pipe", "inherit", "inherit"] });
	child.on("error", (error) => console.error(`alert command failed: ${error.message}`));
	child.stdin.end(`${message}\n`);
}

function reported(checks) {
	const now = new Map(Object.entries(checks).filter(([, result]) => result?.alarm).map(([name, result]) => [name, result.alarm]));
	for (const [name, message] of now) {
		if (!active.has(name)) alert(`ALARM ${programArgument} ${name}: ${message}`);
	}
	for (const name of active.keys()) {
		if (!now.has(name)) alert(`CLEARED ${programArgument} ${name}`);
	}
	active.clear();
	for (const [name, message] of now) active.set(name, message);
}

for (;;) {
	const started = Date.now();
	const checks = {
		l1: await checked("l1", () => slotCheck("l1", baseRead)),
		er: await checked("er", () => slotCheck("er", ephemeral)),
	};
	checks.world = await checked("world", worldCheck);
	checks.ops = await checked("ops", opsCheck);
	checks.disk = await checked("disk", diskCheck);
	checks.erIndex = await checked("erIndex", indexCheck);
	reported(checks);
	const snapshot = { at: new Date().toISOString(), program: programArgument, healthy: active.size === 0, alarms: Object.fromEntries(active), checks };
	const temporary = `${STATUS_PATH}.${process.pid}.tmp`;
	writeFileSync(temporary, json(snapshot));
	renameSync(temporary, STATUS_PATH);
	if (process.env.ONCE === "1") {
		console.log(json(snapshot));
		process.exit(active.size === 0 ? 0 : 1);
	}
	await sleep(Math.max(0, TICK_SECONDS * 1000 - (Date.now() - started)));
}
