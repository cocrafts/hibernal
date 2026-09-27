import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { generateKeyPairSync, randomBytes } from "node:crypto";
import {
	AccountRole,
	address,
	appendTransactionMessageInstructions,
	createKeyPairSignerFromBytes,
	createSolanaRpc,
	createTransactionMessage,
	generateKeyPairSigner,
	getAddressEncoder,
	getBase64EncodedWireTransaction,
	getProgramDerivedAddress,
	getSignatureFromTransaction,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";

const BASE_RPC = process.env.BASE_RPC ?? "https://api.devnet.solana.com";
const BASE_READ_RPC = process.env.BASE_READ_RPC ?? BASE_RPC;
const ER_RPC = process.env.ER_RPC ?? "https://devnet-as.magicblock.app";
const ER_WS = process.env.ER_WS ?? ER_RPC.replace(/^http/, "ws");
const ROUTER_RPC = process.env.ROUTER_RPC ?? "https://devnet-router.magicblock.app";
const VALIDATOR = address(process.env.VALIDATOR ?? "MAS1Dt9qreoRMQ14YQuhg8UTZMMzDdKhmkZMECCzk57");
const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
const COMPUTE_BUDGET_PROGRAM = address("ComputeBudget111111111111111111111111111111");
const DELEGATION_PROGRAM = address("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
const MAGIC_PROGRAM = address("Magic11111111111111111111111111111111111111");
const MAGIC_CONTEXT = address("MagicContext1111111111111111111111111111111");
const COMPUTE_UNIT_LIMIT = 1_400_000;
const CHUNK_BYTES = 900;
const SCENARIOS = (process.env.SCENARIOS ?? "typical,busiest").split(",");
const BURST = Number(process.env.BURST ?? 0);
const CRANK = process.env.CRANK === "1";
const HYDRA = process.env.HYDRA === "1";
const HYDRA_PROGRAM = address("eHyd5BU8QffvHi4GnXwxrK4WpS7pM2x9UGKHBWii7mf");
const MAGIC_VAULT = address("MagicVau1t999999999999999999999999999999999");
const INSTRUCTIONS_SYSVAR = address("Sysvar1nstructions1111111111111111111111111");
const SPONSOR_LAMPORTS = 20_000_000n;
const HYDRA_WAIT_MS = Number(process.env.HYDRA_WAIT_MS ?? 60000);
const HYDRA_RUNS = Number(process.env.HYDRA_RUNS ?? 3);
const HYDRA_INTERVAL_SLOTS = Number(process.env.HYDRA_INTERVAL_SLOTS ?? 1);
const POLICY = 0;
const CONTEXT = 1;
const CONFIG = 2;
const WILDS = 3;
const FIRST_PET = 4;
const PETS = 10;
const IDS = Array.from({ length: FIRST_PET + PETS }, (_, id) => id);
const WRITTEN_BY_ACT = [CONFIG, ...Array.from({ length: PETS }, (_, slot) => FIRST_PET + slot)];
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

const [programArgument, policyPath] = process.argv.slice(2);
if (!programArgument || !policyPath) {
	console.log("usage: node tools/chain/actDevnet.mjs <program id> <checkpoint>.policy (after tools/chain/actLiteSvm.mjs wrote out/actProbe/*.txt)");
	process.exit(2);
}
const PROGRAM = address(programArgument);
const policy = new Uint8Array(readFileSync(policyPath));
const probeDirectory = new URL("../../out/actProbe/", import.meta.url);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const addressEncoder = getAddressEncoder();
const payer = await createKeyPairSignerFromBytes(Uint8Array.from(JSON.parse(readFileSync(`${process.env.HOME}/.config/solana/id.json`, "utf8"))));
const base = createSolanaRpc(BASE_RPC);
const baseRead = createSolanaRpc(BASE_READ_RPC);
const ephemeral = createSolanaRpc(ER_RPC);
const router = createSolanaRpc(ROUTER_RPC);
const holders = [];
for (const id of IDS) {
	const [key] = await getProgramDerivedAddress({ programAddress: PROGRAM, seeds: ["act", Uint8Array.of(id)] });
	const keyBytes = addressEncoder.encode(key);
	const [buffer] = await getProgramDerivedAddress({ programAddress: PROGRAM, seeds: ["buffer", keyBytes] });
	const [record] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation", keyBytes] });
	const [metadata] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation-metadata", keyBytes] });
	holders.push({ id, key, buffer, record, metadata });
}

const signerMeta = { address: payer.address, role: AccountRole.WRITABLE_SIGNER, signer: payer };
const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });
const program = (accounts, data) => ({ programAddress: PROGRAM, accounts, data });
const json = (value) => JSON.stringify(value, (_, inner) => typeof inner === "bigint" ? inner.toString() : inner);

function words(...values) {
	const bytes = new Uint8Array(8 * values.length);
	const view = new DataView(bytes.buffer);
	values.forEach((value, index) => view.setBigUint64(8 * index, BigInt(value), true));
	return bytes;
}

function joined(head, tail) {
	const bytes = new Uint8Array(head.length + tail.length);
	bytes.set(head);
	bytes.set(tail, head.length);
	return bytes;
}

function actData(discriminator, engine, write) {
	return joined(words(discriminator, engine), Uint8Array.of(write ? 1 : 0));
}

function taskInstruction(taskId, tasks) {
	const parts = [Uint8Array.of(6, 0, 0, 0), words(taskId, 1000, 1, tasks.length)];
	const outer = new Map();
	for (const { accounts, data } of tasks) {
		parts.push(addressEncoder.encode(PROGRAM), words(accounts.length));
		for (const meta of accounts) {
			parts.push(addressEncoder.encode(meta.address), Uint8Array.of(0, meta.role === AccountRole.WRITABLE ? 1 : 0));
			if (outer.get(meta.address)?.role !== AccountRole.WRITABLE) outer.set(meta.address, meta);
		}
		parts.push(words(data.length), data);
	}
	return { programAddress: MAGIC_PROGRAM, accounts: [signerMeta, ...outer.values()], data: parts.reduce(joined) };
}

function limitInstruction(units) {
	const bytes = new Uint8Array(5);
	const view = new DataView(bytes.buffer);
	view.setUint8(0, 2);
	view.setUint32(1, units, true);
	return { programAddress: COMPUTE_BUDGET_PROGRAM, accounts: [], data: bytes };
}

function scenarioOf(name) {
	const fields = {};
	for (const line of readFileSync(new URL(`${name}.txt`, probeDirectory), "utf8").split("\n")) {
		const [key, ...rest] = line.split(" ");
		if (key) { fields[key] = rest; }
	}
	const bytes = (key) => Uint8Array.from(fields[key].map(Number));
	const pets = bytes("pets");
	const petBytes = pets.length / PETS;
	const contents = [policy, bytes("context"), bytes("global"), bytes("wilds")];
	for (let slot = 0; slot < PETS; slot++) contents.push(pets.slice(slot * petBytes, (slot + 1) * petBytes));
	const after = bytes("after");
	const expected = new Map([[CONFIG, bytes("afterGlobal")]]);
	for (let slot = 0; slot < PETS; slot++) expected.set(FIRST_PET + slot, after.slice(slot * petBytes, (slot + 1) * petBytes));
	return {
		name,
		contents,
		choice: fields.choice.map(Number),
		digest: BigInt(fields.digest[0]),
		engine: BigInt(fields.engine[0]),
		header: fields.scenario.join(" "),
		actor: Number(fields.scenario[fields.scenario.length - 1]),
		expected,
	};
}

async function patiently(call) {
	for (let attempt = 1; ; attempt++) {
		try {
			return await call();
		} catch (error) {
			if (attempt >= 10) throw error;
			await sleep(2000 * attempt);
		}
	}
}

async function fetchTransaction(rpc, signature) {
	for (let attempt = 0; attempt < 30; attempt++) {
		const found = await rpc.getTransaction(signature, { maxSupportedTransactionVersion: 0, commitment: "confirmed", encoding: "json" }).send().catch(() => null);
		if (found) return found;
		await sleep(1500);
	}
	return null;
}

async function send(rpc, layer, step, instructions, feePayer = payer) {
	const { value: blockhash } = await patiently(() => rpc.getLatestBlockhash().send());
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(feePayer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstructions(instructions, m),
	);
	const transaction = await signTransactionMessageWithSigners(message);
	const signature = getSignatureFromTransaction(transaction);
	const started = Date.now();
	await patiently(() => rpc.sendTransaction(getBase64EncodedWireTransaction(transaction), { encoding: "base64", skipPreflight: true }).send());
	for (let attempt = 0; attempt < 120; attempt++) {
		const { value } = await patiently(() => rpc.getSignatureStatuses([signature]).send());
		const status = value[0];
		if (status && (status.confirmationStatus === "confirmed" || status.confirmationStatus === "finalized")) {
			const elapsed = Date.now() - started;
			const details = layer === "er" || status.err ? await fetchTransaction(rpc === base ? baseRead : rpc, signature) : null;
			const logs = details?.meta?.logMessages ?? [];
			const units = details?.meta?.computeUnitsConsumed !== undefined ? Number(details.meta.computeUnitsConsumed) : null;
			console.log(`[${layer}] ${step}: ${status.err ? "FAILED " + json(status.err) : "ok"} ${elapsed}ms ${units ?? "-"} CU ${signature}`);
			return { signature, logs, units, elapsed, err: status.err };
		}
		await sleep(500);
	}
	throw new Error(`${step}: not confirmed`);
}

async function mustSend(rpc, layer, step, instructions) {
	const sent = await send(rpc, layer, step, instructions);
	if (sent.err) {
		console.log(sent.logs.join("\n"));
		throw new Error(`${step} failed`);
	}
	return sent;
}

async function read(rpc, holder) {
	const { value } = await patiently(() => rpc.getAccountInfo(holder.key, { encoding: "base64", commitment: "confirmed" }).send());
	if (!value) return null;
	return { owner: value.owner, data: new Uint8Array(Buffer.from(value.data[0], "base64")) };
}

async function waitFor(rpc, label, holder, predicate, timeoutMs) {
	const started = Date.now();
	while (Date.now() - started < timeoutMs) {
		const state = await read(rpc, holder).catch(() => null);
		if (state && predicate(state)) return Date.now() - started;
		await sleep(2000);
	}
	throw new Error(`${label}: timed out after ${timeoutMs}ms`);
}

function differing(expected, actual) {
	return expected.reduce((count, value, position) => count + (actual[position] === value ? 0 : 1), Math.abs(expected.length - actual.length));
}

async function differingOn(rpc, scenario) {
	const { value } = await patiently(() => rpc.getMultipleAccounts(WRITTEN_BY_ACT.map((id) => holders[id].key), { encoding: "base64", commitment: "confirmed" }).send());
	return WRITTEN_BY_ACT.reduce((count, id, index) => count + differing(scenario.expected.get(id), value[index] ? new Uint8Array(Buffer.from(value[index].data[0], "base64")) : new Uint8Array()), 0);
}

function watched(key) {
	const socket = new WebSocket(ER_WS);
	const seen = [];
	const subscribed = new Promise((resolve, reject) => {
		socket.addEventListener("open", () => socket.send(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "accountSubscribe", params: [key, { encoding: "base64", commitment: "confirmed" }] })));
		socket.addEventListener("error", reject);
		socket.addEventListener("message", (event) => {
			const message = JSON.parse(event.data);
			if (message.id === 1) resolve(message.result);
			if (message.method === "accountNotification") seen.push({ at: Date.now(), data: new Uint8Array(Buffer.from(message.params.result.value.data[0], "base64")) });
		});
	});
	return { subscribed, seen, close: () => socket.close() };
}

const holds = (expected) => (state) => state.data.length === expected.length && state.data.every((value, index) => value === expected[index]);
const logged = (logs) => logs.filter((line) => line.startsWith("Program log: 0x")).map((line) => BigInt(line.split(", ").pop()));
const remaining = (logs) => logs.filter((line) => line.startsWith("Program consumption:")).map((line) => Number(line.split(" ")[2]));
const same = (left, right) => left.length === right.length && left.every((value, index) => Number(value) === right[index]);
const actAccounts = (writableIds) => holders.map((holder) => writableIds.includes(holder.id) ? writable(holder.key) : readonly(holder.key));

async function returned(holder) {
	await mustSend(ephemeral, "er", `return ${holder.id}`, [program([signerMeta, writable(holder.key), readonly(MAGIC_PROGRAM), writable(MAGIC_CONTEXT)], words(9))]);
}

async function onBase(holder) {
	return waitFor(baseRead, `account ${holder.id} back on L1`, holder, (state) => state.owner === PROGRAM, 180000);
}

async function prepared(scenario) {
	const left = [];
	for (const holder of holders) {
		const state = await read(baseRead, holder);
		if (state?.owner === DELEGATION_PROGRAM) left.push(holder);
	}
	for (const holder of left) await returned(holder);
	for (const holder of left) await onBase(holder);
	for (const holder of holders) {
		const content = scenario.contents[holder.id];
		let state = await read(baseRead, holder);
		if (state === null || state.owner === SYSTEM_PROGRAM) {
			await mustSend(base, "base", `create ${holder.id} (${content.length} bytes)`, [program([signerMeta, writable(holder.key), readonly(SYSTEM_PROGRAM)], words(7, holder.id, content.length))]);
			state = await read(baseRead, holder);
		}
		if (holds(content)(state)) continue;
		for (let offset = 0; offset < content.length; offset += CHUNK_BYTES) {
			const chunk = content.subarray(offset, Math.min(offset + CHUNK_BYTES, content.length));
			await mustSend(base, "base", `write ${holder.id} ${offset}+${chunk.length}`, [program([signerMeta, writable(holder.key)], joined(words(3, holder.id, offset), chunk))]);
		}
		await waitFor(baseRead, `account ${holder.id} written`, holder, holds(content), 60000);
	}
}

async function delegated(holder) {
	await mustSend(base, "base", `delegate ${holder.id}`, [program([
		signerMeta,
		readonly(SYSTEM_PROGRAM),
		writable(holder.key),
		readonly(PROGRAM),
		writable(holder.buffer),
		writable(holder.record),
		writable(holder.metadata),
		readonly(DELEGATION_PROGRAM),
		readonly(VALIDATOR),
	], words(8, holder.id))]);
}

async function burst(scenario, label, writableIds, ownPayers) {
	const { value: blockhash } = await patiently(() => ephemeral.getLatestBlockhash().send());
	const transactions = [];
	for (let index = 0; index < BURST; index++) {
		const feePayer = ownPayers ? await generateKeyPairSigner() : payer;
		const message = pipe(
			createTransactionMessage({ version: 0 }),
			(m) => setTransactionMessageFeePayerSigner(feePayer, m),
			(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
			(m) => appendTransactionMessageInstructions([
				limitInstruction(COMPUTE_UNIT_LIMIT - index),
				program(actAccounts(writableIds), actData(1, scenario.engine, false)),
			], m),
		);
		transactions.push(await signTransactionMessageWithSigners(message));
	}
	const signatures = transactions.map((transaction) => getSignatureFromTransaction(transaction));
	const started = Date.now();
	await Promise.all(transactions.map((transaction) => patiently(() => ephemeral.sendTransaction(getBase64EncodedWireTransaction(transaction), { encoding: "base64", skipPreflight: true }).send())));
	const sentIn = Date.now() - started;
	const landed = new Map();
	while (landed.size < BURST && Date.now() - started < 60000) {
		const { value } = await patiently(() => ephemeral.getSignatureStatuses(signatures).send());
		value.forEach((status, index) => {
			if (status && !landed.has(index) && (status.confirmationStatus === "confirmed" || status.confirmationStatus === "finalized")) {
				landed.set(index, { ms: Date.now() - started, slot: Number(status.slot), err: status.err });
			}
		});
		await sleep(40);
	}
	const results = [...landed.values()];
	const failed = results.filter((result) => result.err).length;
	const slots = new Set(results.map((result) => result.slot)).size;
	const last = Math.max(...results.map((result) => result.ms));
	const sample = results.find((result) => !result.err);
	const detail = sample ? await fetchTransaction(ephemeral, signatures[[...landed.entries()].find(([, result]) => result === sample)[0]]) : null;
	const firstError = results.find((result) => result.err)?.err;
	console.log(`burst ${label}: ${results.length}/${BURST} landed, ${failed} failed${firstError ? ` (${json(firstError)})` : ""}, sent in ${sentIn}ms, last landed ${last}ms, ${slots} slots, ${detail?.meta?.computeUnitsConsumed ?? "-"} CU each`);
}

async function cranked(scenario, label, writableIds, before = []) {
	const accounts = actAccounts(writableIds);
	const watched = holders[CONFIG].key;
	const tasks = [...before, { accounts, data: actData(1, scenario.engine, false) }];
	const scheduled = await send(ephemeral, "er", `schedule the act as a crank task, ${label}`, [taskInstruction(BigInt(Date.now()), tasks)]);
	if (scheduled.err) {
		console.log(scheduled.logs.join("\n"));
		return;
	}
	const started = Date.now();
	while (Date.now() - started < 30000) {
		const history = await patiently(() => ephemeral.getSignaturesForAddress(watched, { limit: 20 }).send());
		const after = history.slice(0, history.findIndex((entry) => entry.signature === scheduled.signature));
		const executed = after.reverse().find(() => true);
		if (executed) {
			const detail = await fetchTransaction(ephemeral, executed.signature);
			const logs = detail?.meta?.logMessages ?? [];
			const budget = logs.filter((line) => line.includes(`${PROGRAM} consumed`)).join(" · ");
			const choice = logged(logs);
			console.log(`crank act, ${label}: ${executed.err ? `FAILED ${json(executed.err)}` : "ok"} ${detail?.meta?.computeUnitsConsumed} CU · ${budget ?? "no consumption line"} · signer ${detail?.transaction?.message?.accountKeys?.[0]} · choice ${choice.length ? `${choice.join(" ")} match ${same(choice, scenario.choice)}` : "none"}`);
			if (executed.err) console.log(logs.filter((line) => line.includes("failed") || line.includes("exceeded") || line.includes("consumed")).join("\n"));
			return;
		}
		await sleep(500);
	}
	console.log(`crank act, ${label}: no execution within 30 s`);
}

function keypairAt(name) {
	const path = new URL(`../../out/${name}.json`, import.meta.url);
	if (!existsSync(path)) {
		const { privateKey, publicKey } = generateKeyPairSync("ed25519");
		writeFileSync(path, JSON.stringify([...privateKey.export({ format: "der", type: "pkcs8" }).subarray(-32), ...publicKey.export({ format: "der", type: "spki" }).subarray(-32)]));
	}
	return createKeyPairSignerFromBytes(Uint8Array.from(JSON.parse(readFileSync(path, "utf8"))));
}

function systemInstruction(index, accounts, tail) {
	return { programAddress: SYSTEM_PROGRAM, accounts, data: joined(Uint8Array.of(index, 0, 0, 0), tail) };
}

async function rpcCall(url, method, params) {
	const response = await fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) });
	return (await response.json()).result;
}

async function balanceIn(rpc, key) {
	return (await patiently(() => rpc.getBalance(key).send())).value;
}

async function walletDelegated(sponsor) {
	if ((await rpcCall(ER_RPC, "getDelegationStatus", [sponsor.address]))?.isDelegated) return;
	const sponsorBytes = addressEncoder.encode(sponsor.address);
	const [record] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation", sponsorBytes] });
	const [metadata] = await getProgramDerivedAddress({ programAddress: DELEGATION_PROGRAM, seeds: ["delegation-metadata", sponsorBytes] });
	const [buffer] = await getProgramDerivedAddress({ programAddress: SYSTEM_PROGRAM, seeds: ["buffer", sponsorBytes] });
	const rent = BigInt(await rpcCall(BASE_RPC, "getMinimumBalanceForRentExemption", [256]));
	const onL1 = await balanceIn(base, sponsor.address);
	if (onL1 < SPONSOR_LAMPORTS) {
		await mustSend(base, "base", "fund the Hydra sponsor", [systemInstruction(2, [signerMeta, writable(sponsor.address)], words(SPONSOR_LAMPORTS - onL1))]);
	}
	const sponsorMeta = { address: sponsor.address, role: AccountRole.WRITABLE_SIGNER, signer: sponsor };
	const delegateData = joined(joined(words(0), Uint8Array.of(0xff, 0xff, 0xff, 0xff, 0, 0, 0, 0, 1)), addressEncoder.encode(VALIDATOR));
	await mustSend(base, "base", "delegate the Hydra sponsor wallet", [
		systemInstruction(2, [sponsorMeta, writable(record)], words(rent)),
		systemInstruction(2, [sponsorMeta, writable(metadata)], words(rent)),
		systemInstruction(1, [sponsorMeta], addressEncoder.encode(DELEGATION_PROGRAM)),
		{ programAddress: DELEGATION_PROGRAM, accounts: [sponsorMeta, sponsorMeta, readonly(SYSTEM_PROGRAM), writable(buffer), writable(record), writable(metadata), readonly(SYSTEM_PROGRAM)], data: delegateData },
	]);
	const started = Date.now();
	while (!(await rpcCall(ER_RPC, "getDelegationStatus", [sponsor.address]))?.isDelegated) {
		if (Date.now() - started > 60000) throw new Error("the Hydra sponsor is not delegated after 60 s");
		await sleep(1000);
	}
	console.log(`Hydra sponsor ${sponsor.address} delegated, seen by the ER after ${Date.now() - started}ms`);
}

function hydraCreateData(seed, authority, startSlot, remaining, cuLimit, scheduled) {
	const head = joined(joined(Uint8Array.of(0), seed), addressEncoder.encode(authority));
	const limit = new Uint8Array(4);
	new DataView(limit.buffer).setUint32(0, cuLimit, true);
	const parts = [head, words(startSlot, HYDRA_INTERVAL_SLOTS, remaining, 0), limit];
	const size = new Uint8Array(3);
	size[0] = scheduled.accounts.length;
	new DataView(size.buffer).setUint16(1, scheduled.data.length, true);
	parts.push(size, addressEncoder.encode(scheduled.programAddress));
	for (const meta of scheduled.accounts) parts.push(Uint8Array.of(meta.role === AccountRole.WRITABLE ? 2 : 0), addressEncoder.encode(meta.address));
	parts.push(scheduled.data);
	return parts.reduce(joined);
}

async function hydraTriggered(scenario, crank, act, units) {
	const trigger = { programAddress: HYDRA_PROGRAM, accounts: [writable(crank), signerMeta, readonly(INSTRUCTIONS_SYSVAR)], data: Uint8Array.of(1) };
	const label = units ? `trigger with SetComputeUnitLimit ${units}` : "trigger without SetComputeUnitLimit";
	const sent = await send(ephemeral, "er", `Hydra ${label}`, [...(units ? [limitInstruction(units)] : []), trigger, act]);
	const budget = sent.logs.filter((line) => line.includes(`${PROGRAM} consumed`)).join(" · ");
	const choice = logged(sent.logs);
	console.log(`  ${sent.err ? `FAILED ${json(sent.err)}` : "ok"} · ${budget || "no act consumption line"} · choice ${choice.length ? `${choice.join(" ")} match ${same(choice, scenario.choice)}` : "none"}`);
	return sent;
}

async function hydraCranked(scenario, sponsor) {
	const act = program(actAccounts(WRITTEN_BY_ACT), actData(1, scenario.engine, false));
	const seed = new Uint8Array(randomBytes(32));
	const [crank] = await getProgramDerivedAddress({ programAddress: HYDRA_PROGRAM, seeds: ["crank", seed] });
	const sponsorMeta = { address: sponsor.address, role: AccountRole.WRITABLE_SIGNER, signer: sponsor };
	const slot = BigInt(await ephemeral.getSlot().send());
	const sponsorBefore = await balanceIn(ephemeral, sponsor.address);
	const payerBefore = await balanceIn(ephemeral, payer.address);
	const created = await send(ephemeral, "er", `create a Hydra crank for the act (cu_limit 1.4M, tip 0, ${HYDRA_RUNS} runs every ${HYDRA_INTERVAL_SLOTS} slots)`, [
		{ programAddress: HYDRA_PROGRAM, accounts: [sponsorMeta, writable(crank), writable(MAGIC_VAULT), readonly(MAGIC_PROGRAM)], data: hydraCreateData(seed, sponsor.address, slot, HYDRA_RUNS, COMPUTE_UNIT_LIMIT, act) },
	]);
	if (created.err) {
		console.log(created.logs.join("\n"));
		return;
	}
	const crankState = await read(ephemeral, { key: crank });
	const sponsorAfterCreate = await balanceIn(ephemeral, sponsor.address);
	console.log(`  crank ${crank}: ${crankState?.data.length} bytes owned by ${crankState?.owner} · sponsor paid ${sponsorBefore - sponsorAfterCreate} lamports`);
	const waitStarted = Date.now();
	const seen = new Map();
	let triggers = [];
	while (Date.now() - waitStarted < HYDRA_WAIT_MS && triggers.length < HYDRA_RUNS) {
		await sleep(2000);
		const history = await patiently(() => ephemeral.getSignaturesForAddress(crank, { limit: 20 }).send());
		for (const entry of history) {
			if (entry.signature === created.signature || seen.has(entry.signature)) continue;
			const detail = await fetchTransaction(ephemeral, entry.signature);
			seen.set(entry.signature, { entry, detail, trigger: (detail?.transaction?.message?.accountKeys ?? []).includes(HYDRA_PROGRAM) });
		}
		triggers = [...seen.values()].filter((item) => item.trigger);
	}
	const others = [...seen.values()].filter((item) => !item.trigger);
	console.log(`  after ${Math.round((Date.now() - waitStarted) / 1000)} s: ${triggers.length} Hydra triggers by anyone else, ${others.length} other transactions on the crank (${others.map((item) => (item.detail?.meta?.logMessages ?? []).find((line) => !line.startsWith("Program ")) ?? "no log").join("; ")})`);
	const createdSlot = Number((await fetchTransaction(ephemeral, created.signature))?.slot ?? 0);
	for (const item of triggers.sort((left, right) => Number(left.entry.slot) - Number(right.entry.slot))) {
		const logs = item.detail?.meta?.logMessages ?? [];
		const choice = logged(logs);
		console.log(`  foreign trigger at +${Number(item.entry.slot) - createdSlot} slots: ${item.entry.err ? `FAILED ${json(item.entry.err)}` : "ok"} · fee payer ${item.detail?.transaction?.message?.accountKeys?.[0]} · ${item.detail?.meta?.computeUnitsConsumed} CU · ${logs.filter((line) => line.includes(`${PROGRAM} consumed`)).join(" ")} · choice ${choice.length ? `${choice.join(" ")} match ${same(choice, scenario.choice)}` : "none"}`);
	}
	if (triggers.length === 0) {
		await hydraTriggered(scenario, crank, act, 0);
		await hydraTriggered(scenario, crank, act, COMPUTE_UNIT_LIMIT);
	}
	const sponsorAfterRuns = await balanceIn(ephemeral, sponsor.address);
	const payerAfterRuns = await balanceIn(ephemeral, payer.address);
	console.log(`  after the runs: sponsor ${sponsorAfterRuns - sponsorAfterCreate} lamports, cranker (payer) ${payerAfterRuns - payerBefore} lamports`);
	await send(ephemeral, "er", "cancel the Hydra crank", [
		{ programAddress: HYDRA_PROGRAM, accounts: [sponsorMeta, writable(crank), writable(sponsor.address), writable(MAGIC_VAULT), readonly(MAGIC_PROGRAM)], data: Uint8Array.of(2) },
	]);
	const sponsorAfterCancel = await balanceIn(ephemeral, sponsor.address);
	console.log(`  after cancel: sponsor back to ${sponsorAfterCancel} (net ${sponsorAfterCancel - sponsorBefore} lamports over create, runs and cancel)`);
}

async function walletReturned(sponsor) {
	const throwaway = await generateKeyPairSigner();
	const sponsorMeta = { address: sponsor.address, role: AccountRole.WRITABLE_SIGNER, signer: sponsor };
	await send(ephemeral, "er", "undelegate the Hydra sponsor wallet", [
		{ programAddress: MAGIC_PROGRAM, accounts: [{ address: throwaway.address, role: AccountRole.READONLY_SIGNER, signer: throwaway }, writable(MAGIC_CONTEXT), sponsorMeta], data: Uint8Array.of(2, 0, 0, 0) },
	], sponsor);
	const started = Date.now();
	while (Date.now() - started < 120000) {
		const info = (await patiently(() => baseRead.getAccountInfo(sponsor.address, { encoding: "base64" }).send())).value;
		if (info?.owner === SYSTEM_PROGRAM) {
			console.log(`Hydra sponsor back on L1 after ${Date.now() - started}ms holding ${info.lamports} lamports`);
			return;
		}
		await sleep(2000);
	}
	console.log("Hydra sponsor not back on L1 within 120 s");
}

function reportSplit(scenario, sent) {
	if (sent.err) {
		console.log(`split act: FAILED ${json(sent.err)}`);
		console.log(sent.logs.filter((line) => line.includes("failed") || line.includes("consumed")).join("\n"));
		return;
	}
	const counts = remaining(sent.logs);
	const logCost = counts[0] - counts[1];
	const net = SECTIONS.map((_, index) => counts[index + 1] - counts[index + 2] - logCost);
	const [economy, node, attack, , digest] = logged(sent.logs);
	console.log(`split act ${sent.units} CU in ${sent.elapsed}ms · choice ${economy} ${node} ${attack} match ${same([economy, node, attack], scenario.choice)} · digest match ${digest === scenario.digest}`);
	console.log(`  ${SECTIONS.map((section, index) => `${section} ${net[index]}`).join(" · ")}`);
}

const deployed = (await patiently(() => baseRead.getAccountInfo(PROGRAM, { encoding: "base64" }).send())).value;
if (!deployed?.executable) {
	console.log(`program ${PROGRAM} is not deployed on ${BASE_READ_RPC}`);
	process.exit(1);
}
const lamportsBefore = (await base.getBalance(payer.address).send()).value;
console.log(`program ${PROGRAM} payer ${payer.address} ER ${ER_RPC} validator ${VALIDATOR}`);

for (const name of SCENARIOS) {
	const scenario = scenarioOf(name);
	console.log(`\n${scenario.header} · expected choice ${scenario.choice.join(" ")} digest 0x${scenario.digest.toString(16)}`);
	await prepared(scenario);
	const onL1 = await send(base, "base", "digest on L1 before", [program(actAccounts([]), words(2))]);
	const before = logged((await fetchTransaction(baseRead, onL1.signature))?.meta?.logMessages ?? []).pop();
	console.log(`L1 accounts hold the scenario: digest ${before === undefined ? "unread" : `0x${before.toString(16)}`}`);
	for (const id of WRITTEN_BY_ACT) await delegated(holders[id]);
	if (CRANK) {
		await cranked(scenario, "act accounts writable", WRITTEN_BY_ACT);
		await cranked(scenario, "act accounts read-only", []);
		await cranked(scenario, "a digest, then the act, in one task", WRITTEN_BY_ACT, [{ accounts: actAccounts([]), data: words(2) }]);
	}
	if (HYDRA) {
		const sponsor = await keypairAt("hydraSponsor");
		await walletDelegated(sponsor);
		await hydraCranked(scenario, sponsor);
	}
	const split = await send(ephemeral, "er", "split act, no write-back", [limitInstruction(COMPUTE_UNIT_LIMIT), program(actAccounts(WRITTEN_BY_ACT), actData(0, scenario.engine, false))]);
	reportSplit(scenario, split);
	const actorId = FIRST_PET + scenario.actor;
	const watch = watched(holders[actorId].key);
	await watch.subscribed;
	const sentAt = Date.now();
	const plain = await send(ephemeral, "er", "act with write-back", [limitInstruction(COMPUTE_UNIT_LIMIT), program(actAccounts(WRITTEN_BY_ACT), actData(1, scenario.engine, true))]);
	console.log(`act ${plain.err ? `FAILED ${json(plain.err)}` : `${plain.units} CU in ${plain.elapsed}ms`} · choice match ${same(logged(plain.logs), scenario.choice)}`);
	while (watch.seen.length === 0 && Date.now() - sentAt < 5000) await sleep(20);
	watch.close();
	const note = watch.seen[0];
	console.log(`websocket ${ER_WS}: actor pet notified ${note ? `${note.at - sentAt} ms after the send, ${differing(scenario.expected.get(actorId), note.data)} of ${note.data.length} bytes differing from the host's` : "not within 5 s"}`);
	const inEr = await send(ephemeral, "er", "digest in ER", [program(actAccounts([]), words(2))]);
	console.log(`ER accounts after the act: digest match ${logged(inEr.logs).pop() === scenario.digest} · bytes differing from the host's, read from the ER ${await differingOn(ephemeral, scenario)}, through the router ${await differingOn(router, scenario)}, of ${[...scenario.expected.values()].reduce((sum, bytes) => sum + bytes.length, 0)}`);
	if (BURST > 0) {
		await burst(scenario, "act accounts writable, one fee payer", WRITTEN_BY_ACT, false);
		await burst(scenario, "act accounts read-only, one fee payer", [], false);
		await burst(scenario, "act accounts read-only, own fee payers", [], true);
		await burst(scenario, "act accounts writable, own fee payers", WRITTEN_BY_ACT, true);
	}
	const returnStarted = Date.now();
	for (const id of WRITTEN_BY_ACT) await returned(holders[id]);
	for (const id of WRITTEN_BY_ACT) await onBase(holders[id]);
	console.log(`written accounts back on L1 ${Date.now() - returnStarted}ms after the first return`);
	const landed = await send(base, "base", "digest on L1 after", [program(actAccounts([]), words(2))]);
	const after = logged((await fetchTransaction(baseRead, landed.signature))?.meta?.logMessages ?? []).pop();
	console.log(`L1 accounts after commit: digest match ${after === scenario.digest} · bytes differing from the host's ${await differingOn(baseRead, scenario)}`);
}

if (HYDRA) await walletReturned(await keypairAt("hydraSponsor"));
const lamportsAfter = (await base.getBalance(payer.address).send()).value;
console.log(`\npayer spent ${lamportsBefore - lamportsAfter} lamports on L1 during this run`);
