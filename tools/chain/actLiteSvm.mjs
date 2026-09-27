import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { ComputeBudget, LiteSVM } from "litesvm";
import {
	AccountRole,
	address,
	appendTransactionMessageInstructions,
	createKeyPairSignerFromPrivateKeyBytes,
	createTransactionMessage,
	lamports,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";

const COMPUTE_BUDGET_PROGRAM = address("ComputeBudget111111111111111111111111111111");
const COMPUTE_UNIT_LIMIT = 1_400_000;
const MEASURE_LIMIT = 20_000_000n;
const COSTS = ["Stats.built", "pet.stats()", "pet.combatant()", "mate.combatantFacing()", "winChanceFromTable", "attackable", "dawnHearts", "ownStats().hungerPerDay()", "legalEconomy", "legalNodes", "foodCost", "actor.combatantFacing()", "pressureBps", "log2Times32", "oddsKeyAgainst", "winChanceBps", "100 signed divisions", "100 unsigned divisions", "(setup)", "writeSelf", "attackMask", "writeTarget", "tree.summed", "writeNode"];
const SCENARIOS = ["typical", "busiest", "dawn"];
const SECTIONS = [
	"load accounts",
	"economy observe",
	"economy head",
	"economy apply",
	"tree observe self",
	"tree observe rows",
	"tree rows + head",
	"tree apply",
	"attack observe self",
	"attack observe rows",
	"attack rows + head",
	"write back",
];
const root = new URL("../../", import.meta.url);
const probeDirectory = new URL("out/actProbe/", root);

const [programPath, policyPath] = process.argv.slice(2);
if (!programPath || !policyPath) {
	console.log("usage: node tools/chain/actLiteSvm.mjs out/actProbe.so <checkpoint>.policy");
	process.exit(2);
}
const policy = new Uint8Array(readFileSync(policyPath));
mkdirSync(probeDirectory, { recursive: true });
writeFileSync(new URL("policy.txt", probeDirectory), Array.from(policy).join("\n") + "\n");
console.log(execFileSync("msc", ["run", "tools/actHost.ms"], { cwd: root, encoding: "utf8" })
	.split("\n")
	.filter((line) => /^(typical|busiest|dawn):/.test(line))
	.join("\n"));

function scenarioOf(name) {
	const fields = {};
	for (const line of readFileSync(new URL(`${name}.txt`, probeDirectory), "utf8").split("\n")) {
		const [key, ...rest] = line.split(" ");
		if (key) { fields[key] = rest; }
	}
	const bytes = (key) => Uint8Array.from(fields[key].map(Number));
	return {
		pets: bytes("pets"),
		wilds: bytes("wilds"),
		context: bytes("context"),
		global: bytes("global"),
		choice: fields.choice.map(Number),
		digest: BigInt(fields.digest[0]),
		engine: BigInt(fields.engine[0]),
		header: fields.scenario.join(" "),
	};
}

function limitData(units) {
	const bytes = new Uint8Array(5);
	const view = new DataView(bytes.buffer);
	view.setUint8(0, 2);
	view.setUint32(1, units, true);
	return bytes;
}

function actData(discriminator, engine, write) {
	const bytes = new Uint8Array(17);
	const view = new DataView(bytes.buffer);
	view.setBigUint64(0, BigInt(discriminator), true);
	view.setBigUint64(8, engine, true);
	view.setUint8(16, write ? 1 : 0);
	return bytes;
}

const unbounded = process.env.UNBOUNDED === "1";
const budget = new ComputeBudget();
budget.computeUnitLimit = MEASURE_LIMIT;
const svm = unbounded ? new LiteSVM().withComputeBudget(budget) : new LiteSVM();
console.log(unbounded ? `measuring with a ${MEASURE_LIMIT} CU budget and no SetComputeUnitLimit (above the chain maximum)` : `chain limit ${COMPUTE_UNIT_LIMIT} CU`);
const payer = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(1));
const program = await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(3));
svm.airdrop(payer.address, lamports(10_000_000_000n));
svm.addProgramFromFile(program.address, programPath);
const holders = [];
for (let index = 0; index < 14; index++) {
	holders.push((await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(32).fill(10 + index))).address);
}

function put(key, data) {
	svm.setAccount({
		address: key,
		data,
		executable: false,
		lamports: lamports(1_000_000_000n),
		programAddress: program.address,
		space: BigInt(data.length),
	});
}

function loadScenario(scenario) {
	put(holders[0], policy);
	put(holders[1], scenario.context);
	put(holders[2], scenario.global);
	put(holders[3], scenario.wilds);
	const petBytes = scenario.pets.length / 10;
	for (let slot = 0; slot < 10; slot++) {
		put(holders[4 + slot], scenario.pets.slice(slot * petBytes, (slot + 1) * petBytes));
	}
}

async function send(data) {
	const accounts = holders.map((key, index) => ({
		address: key,
		role: index === 2 || index >= 4 ? AccountRole.WRITABLE : AccountRole.READONLY,
	}));
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(payer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash({ blockhash: svm.latestBlockhash(), lastValidBlockHeight: 1000n }, m),
		(m) => appendTransactionMessageInstructions([
			...(unbounded ? [] : [{ programAddress: COMPUTE_BUDGET_PROGRAM, accounts: [], data: limitData(COMPUTE_UNIT_LIMIT) }]),
			{ programAddress: program.address, accounts, data },
		], m),
	);
	const result = svm.sendTransaction(await signTransactionMessageWithSigners(message));
	svm.expireBlockhash();
	const failed = result.constructor.name === "FailedTransactionMetadata";
	const meta = failed ? result.meta() : result;
	return { failed, error: failed ? result.err().toString() : null, units: Number(meta.computeUnitsConsumed()), logs: meta.logs() };
}

const logged = (logs) => logs.filter((line) => line.startsWith("Program log: 0x")).map((line) => BigInt(line.split(", ").pop()));
const remaining = (logs) => logs.filter((line) => line.startsWith("Program consumption:")).map((line) => Number(line.split(" ")[2]));
const same = (left, right) => left.length === right.length && left.every((value, index) => Number(value) === right[index]);

for (const name of SCENARIOS) {
	const scenario = scenarioOf(name);
	console.log(`\n${scenario.header} · expected choice ${scenario.choice.join(" ")} digest 0x${scenario.digest.toString(16)}`);
	loadScenario(scenario);
	const costs = await send(actData(4, scenario.engine, false));
	if (!costs.failed) {
		const marks = remaining(costs.logs);
		const cost = marks[0] - marks[1];
		console.log(`  one call each: ${COSTS.map((name, index) => `${name} ${marks[index + 1] - marks[index + 2] - cost}`).filter((text) => !text.startsWith("(")).join(" · ")}`);
	}
	const economyCosts = await send(actData(5, scenario.engine, false));
	if (!economyCosts.failed) {
		const marks = remaining(economyCosts.logs);
		const cost = marks[0] - marks[1];
		const legal = logged(economyCosts.logs).pop();
		console.log(`  doEconomy each (legal mask 0x${legal.toString(16)}): ${marks.slice(1, -1).map((value, index) => `${index} ${value - marks[index + 2] - cost}`).join(" · ")}`);
	}
	const split = await send(actData(0, scenario.engine, true));
	if (split.failed) {
		console.log(`split act: ${split.error}`);
		console.log(split.logs.filter((line) => line.includes("failed") || line.includes("custom")).join("\n"));
		const reached = remaining(split.logs);
		const cost = reached[0] - reached[1];
		const done = reached.slice(1).map((value, index) => index + 1 < reached.length - 1 ? `${SECTIONS[index]} ${reached[index + 1] - reached[index + 2] - cost}` : null).filter(Boolean);
		console.log(`  reached ${reached.length} compute-unit logs, remaining at the last ${reached[reached.length - 1]}: ${done.join(" · ")}`);
		continue;
	}
	const counts = remaining(split.logs);
	const values = logged(split.logs);
	const logCost = counts[0] - counts[1];
	const net = SECTIONS.map((_, index) => counts[index + 1] - counts[index + 2] - logCost);
	const [economy, node, attack, packed, digest] = values;
	const rows = { nodes: Number(packed & 0xffffffffn), targets: Number(packed >> 32n) };
	console.log(`split act ${split.units} CU (log ${logCost} CU each, subtracted) · choice ${economy} ${node} ${attack} match ${same([economy, node, attack], scenario.choice)} · digest match ${digest === scenario.digest} · node rows ${rows.nodes} target rows ${rows.targets}`);
	SECTIONS.forEach((section, index) => console.log(`  ${section.padEnd(22)} ${String(net[index]).padStart(8)} CU`));
	const observe = net[1] + net[4] + net[5] + net[8] + net[9];
	const heads = net[2] + (net[6] - net[5]) + (net[10] - net[9]);
	const apply = net[3] + net[7];
	console.log(`  observe ${observe} · heads ${heads} (tree ${net[6] - net[5]}, attack ${net[10] - net[9]}) · apply ${apply} · load ${net[0]} · write ${net[11]}`);
	loadScenario(scenario);
	const plain = await send(actData(1, scenario.engine, true));
	const plainChoice = logged(plain.logs);
	const check = await send(actData(2, scenario.engine, false));
	const written = logged(check.logs).pop();
	console.log(`plain act ${plain.failed ? plain.error : `${plain.units} CU`} · choice match ${same(plainChoice, scenario.choice)} · written digest match ${written === scenario.digest}`);
	loadScenario(scenario);
	const dry = await send(actData(1, scenario.engine, false));
	console.log(`plain act without write-back ${dry.failed ? dry.error : `${dry.units} CU`}`);
}
