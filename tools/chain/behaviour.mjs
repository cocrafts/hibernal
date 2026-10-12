import { createHash } from "node:crypto";
import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import {
	address,
	appendTransactionMessageInstructions,
	createKeyPairSignerFromPrivateKeyBytes,
	createTransactionMessage,
	getBase64EncodedWireTransaction,
	getProgramDerivedAddress,
	getSignatureFromTransaction,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";
import {
	ASSOCIATED_TOKEN_PROGRAM,
	CLONE_ATTEMPTS,
	SYSTEM_PROGRAM,
	TOKEN_PROGRAM,
	accountOffsets,
	cloneCancelled,
	cloneRejected,
	cluster,
	computeLimit,
	encoder,
	fieldsOf,
	hibernal,
	idlAt,
	joined,
	json,
	keypairAt,
	read,
	readU32,
	readU64,
	readonly,
	sleep,
	u32,
	u64,
	writable,
	writableSigner,
} from "./hibernal.mjs";

const STAGE = process.env.STAGE ?? "run";
const PETS = Number(process.env.PETS ?? 20);
const SEED = BigInt(process.env.SEED ?? 3);
const POLL_MS = Number(process.env.POLL_MS ?? 3000);
const RESEND_EVERY_POLLS = 8;
const COMMIT_WAIT_SECONDS = 30;
const MINUTES = Number(process.env.MINUTES ?? 22);
const PARALLEL = Number(process.env.PARALLEL ?? 8);
const BLOCK_PARALLEL = Number(process.env.BLOCK_PARALLEL ?? 1);
const ONRAMP_SKR = BigInt(process.env.ONRAMP_SKR ?? 10_000);
const STATUS_PATH = process.env.STATUS ?? "out/localnet/behaviourStatus.json";
const MASK = (1n << 64n) - 1n;
const BPS = 10_000n;
const SKR_DECIMALS = 1_000_000n;
const FOOD_SKR = [1n, 2n, 3n];
const GROWTH_SKR_PER_STEP = 2n;
const INSURANCE_SKR = 20n;
const LEDGER_SETTLE_MS = 1000;
const ITEM = { Food: 0, Growth: 1, Insurance: 2 };

const HABITS = {
	Devoted: { visitPercent: 70n, opensPercent: 30n, feedBelowBps: 7000n, foodTier: 2, growthPercent: 30n, growthSteps: 3, insurePercent: 100n },
	Casual: { visitPercent: 25n, opensPercent: 5n, feedBelowBps: 5000n, foodTier: 1, growthPercent: 10n, growthSteps: 1, insurePercent: 5n },
	Absent: { visitPercent: 5n, opensPercent: 0n, feedBelowBps: 0n, foodTier: 0, growthPercent: 0n, growthSteps: 1, insurePercent: 0n },
};

const [programArgument] = process.argv.slice(2);
if (!programArgument) {
	console.log("usage: STAGE=onramp|run node tools/chain/behaviour.mjs <program id>");
	process.exit(2);
}
const programAddress = address(programArgument);
const { base, baseRead, ephemeral } = cluster();
const wallet = await keypairAt(`${process.env.HOME}/.config/solana/id.json`);
const program = hibernal(programAddress, wallet);
const idl = idlAt();
const petAt = accountOffsets(idl, "PetAccount");
const petFields = fieldsOf(idl, "Pet");
const petTypes = Object.fromEntries(idl.types.find((entry) => entry.name === "Pet").type.fields.map((field) => [field.name, field.type]));
const blockAt = accountOffsets(idl, "Block");
const configAt = accountOffsets(idl, "Config");
const ledgerAt = accountOffsets(idl, "Ledger");
const paidAt = accountOffsets(idl, "Paid");
const REBIRTH_HEADROOM_LAMPORTS = 1_000_000n;
const errorNames = Object.fromEntries(idl.errors.map((entry) => [entry.code, entry.name]));

function splitmix(state) {
	let mixed = (state + 11400714819323198485n) & MASK;
	mixed = ((mixed ^ (mixed >> 30n)) * 13787848793156543929n) & MASK;
	mixed = ((mixed ^ (mixed >> 27n)) * 10723151780598845931n) & MASK;
	return mixed ^ (mixed >> 31n);
}

function mixSeeds(first, second) {
	return splitmix(first ^ splitmix(second));
}

function ownerKindFor(seed, index) {
	const draw = splitmix(mixSeeds(seed, BigInt(index) + 104729n)) % 100n;
	if (draw < 25n) return "Devoted";
	if (draw < 70n) return "Casual";
	return "Absent";
}

const rolled = (draw, salt, percent) => splitmix(draw ^ salt) % 100n < percent;
const visitDraw = (seed, index, epoch) => mixSeeds(mixSeeds(seed, BigInt(index) + 130363n), epoch);
const openDraw = (seed, index, epoch, round) => mixSeeds(visitDraw(seed, index, epoch), BigInt(round));

function fieldOf(data, name) {
	const offset = petAt.pet + petFields.offsets[name];
	const view = new DataView(data.buffer, data.byteOffset);
	switch (petTypes[name]) {
		case "u64": return view.getBigUint64(offset, true);
		case "u32": return BigInt(view.getUint32(offset, true));
		case "u16": return BigInt(view.getUint16(offset, true));
		case "u8": return BigInt(view.getUint8(offset));
		case "i8": return BigInt(view.getInt8(offset));
		case "bool": return view.getUint8(offset) !== 0 ? 1n : 0n;
		default: throw new Error(`pet field ${name} has type ${JSON.stringify(petTypes[name])}`);
	}
}

async function derivedSigner(master, domain, index) {
	const bytes = createHash("sha256").update(master).update(domain).update(u64(index)).digest();
	return await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(bytes));
}

function masterSeed() {
	return Buffer.from(readFileSync(process.env.MASTER ?? "out/localnet/playersMaster.hex", "utf8").trim(), "hex");
}

async function ownerAt(master, index) {
	const owner = await derivedSigner(master, "player", index);
	const mint = await derivedSigner(master, "mint", index);
	return { index, owner, mint: mint.address, kind: ownerKindFor(SEED, index) };
}

async function ownersOf() {
	const owners = [];
	if (process.env.PLAYERS) {
		const [first, count] = process.env.PLAYERS.split(":").map(Number);
		const master = masterSeed();
		for (let index = first; index < first + count; index++) owners.push(await ownerAt(master, index));
		return owners;
	}
	const lines = readFileSync("out/admission/mints.txt", "utf8").trim().split("\n").slice(0, PETS);
	for (const [index, line] of lines.entries()) {
		owners.push({ index, owner: wallet, mint: address(line.split(" ")[1]), kind: ownerKindFor(SEED, index) });
	}
	return owners;
}

async function associated(owner, mint, tokenProgram = TOKEN_PROGRAM) {
	const [found] = await getProgramDerivedAddress({ programAddress: ASSOCIATED_TOKEN_PROGRAM, seeds: [encoder.encode(owner), encoder.encode(tokenProgram), encoder.encode(mint)] });
	return found;
}

function createAssociated(payer, owner, mint, account) {
	return {
		programAddress: ASSOCIATED_TOKEN_PROGRAM,
		accounts: [writableSigner(payer), writable(account), readonly(owner), readonly(mint), readonly(SYSTEM_PROGRAM), readonly(TOKEN_PROGRAM)],
		data: Uint8Array.of(1),
	};
}

function mintTo(mint, destination, authority, amount) {
	return { programAddress: TOKEN_PROGRAM, accounts: [writable(mint), writable(destination), writableSigner(authority)], data: joined(Uint8Array.of(7), u64(amount)) };
}

function decodedError(error) {
	if (!error) return null;
	const inner = error.InstructionError?.[1];
	if (inner && typeof inner === "object" && "Custom" in inner) {
		const code = Number(inner.Custom);
		return errorNames[code] ?? `Custom ${code}`;
	}
	if (inner) return typeof inner === "string" ? inner : json(inner);
	return json(error);
}

async function submit(rpc, instructions, feePayer, units = 400_000) {
	for (let attempt = 1; ; attempt++) {
		const outcome = await submitOnce(rpc, instructions, feePayer, units);
		if (!outcome.cloneFailed || attempt >= CLONE_ATTEMPTS) return { ...outcome, retries: attempt - 1 };
		await sleep(1000 * attempt);
	}
}

async function submitOnce(rpc, instructions, feePayer, units) {
	const { value: blockhash } = await rpc.getLatestBlockhash().send();
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(feePayer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstructions([computeLimit(units), ...instructions], m),
	);
	const transaction = await signTransactionMessageWithSigners(message);
	const signature = getSignatureFromTransaction(transaction);
	const wire = getBase64EncodedWireTransaction(transaction);
	try {
		await rpc.sendTransaction(wire, { encoding: "base64", skipPreflight: true }).send();
	} catch (error) {
		return { ok: false, error: `send: ${error.message}`, signature, cloneFailed: cloneRejected(error) };
	}
	for (let attempt = 0; attempt < 120; attempt++) {
		if (attempt > 0 && attempt % RESEND_EVERY_POLLS === 0) await rpc.sendTransaction(wire, { encoding: "base64", skipPreflight: true }).send().catch(() => {});
		const { value } = await rpc.getSignatureStatuses([signature]).send();
		const status = value[0];
		if (status && (status.confirmationStatus === "confirmed" || status.confirmationStatus === "finalized")) {
			return status.err ? { ok: false, error: decodedError(status.err), signature, cloneFailed: cloneCancelled(status.err) } : { ok: true, signature };
		}
		await sleep(250);
	}
	return { ok: false, error: "unconfirmed", signature };
}

async function inParallel(items, work, parallel = PARALLEL) {
	let next = 0;
	await Promise.all(Array.from({ length: Math.min(parallel, items.length) }, async () => {
		while (next < items.length) await work(items[next++]);
	}));
}

const status = existsSync(STATUS_PATH) ? JSON.parse(readFileSync(STATUS_PATH, "utf8")) : { days: {}, failures: [] };
status.program = programArgument;
const dayOf = (epoch) => (status.days[epoch] ??= { visits: 0, opens: 0, actions: {}, skrSpent: 0, hbrnClaimed: "0", cloneRetries: 0 });
const save = () => {
	const temporary = `${STATUS_PATH}.${process.pid}.tmp`;
	writeFileSync(temporary, json(status));
	renameSync(temporary, STATUS_PATH);
};

function recorded(epoch, kind, outcome) {
	const day = dayOf(epoch);
	const entry = (day.actions[kind] ??= { ok: 0, refused: {} });
	day.cloneRetries = (day.cloneRetries ?? 0) + (outcome.retries ?? 0);
	if (outcome.ok) entry.ok += 1;
	else {
		entry.refused[outcome.error] = (entry.refused[outcome.error] ?? 0) + 1;
		if (!["Full", "FedToday", "EngagedOut", "EngagedThisRound", "CoolingDown", "EmptyHarvest", "Insured", "Refused", "NothingOwed", "OverCap", "Dead"].includes(outcome.error)) {
			status.failures.push({ at: new Date().toISOString(), epoch: String(epoch), kind, error: outcome.error, signature: outcome.signature });
		}
	}
	return outcome;
}

async function readConfig() {
	const holder = await read(baseRead, await program.address(program.seeds.config()));
	const view = (offset) => readU64(holder.data, offset);
	const keyAt = (offset) => address(encoderBase58(holder.data.subarray(offset, offset + 32)));
	return {
		genesis: view(configAt.genesis_timestamp),
		secondsPerDay: view(configAt.seconds_per_day),
		skrMint: keyAt(configAt.skr_mint),
		treasury: keyAt(configAt.treasury),
		hbrnMint: keyAt(configAt.hbrn_mint),
		hatchFeeLamports: view(configAt.hatch_fee_lamports),
	};
}

function encoderBase58(bytes) {
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

async function tokenBalance(account) {
	const holder = await read(baseRead, account);
	return holder ? readU64(holder.data, 64) : 0n;
}

async function onramp(owners, config) {
	const distinct = [...new Map(owners.map((entry) => [entry.owner.address, entry.owner])).values()];
	const target = ONRAMP_SKR * SKR_DECIMALS;
	let toppedUp = 0;
	await inParallel(distinct, async (owner) => {
		const source = await associated(owner.address, config.skrMint);
		const balance = await tokenBalance(source);
		if (balance * 2n >= target) return;
		const instructions = [];
		if (!(await read(baseRead, source))) instructions.push(createAssociated(wallet, owner.address, config.skrMint, source));
		instructions.push(mintTo(config.skrMint, source, wallet, target - balance));
		const sent = await submit(base, instructions, wallet);
		if (!sent.ok) throw new Error(`onramp ${owner.address}: ${sent.error}; signature ${sent.signature}`);
		toppedUp += 1;
	});
	console.log(`onramp: ${toppedUp} of ${distinct.length} owners topped up to ${ONRAMP_SKR} SKR`);
}

async function petState(entry, rpc = ephemeral) {
	const holder = await read(rpc, await program.address(program.seeds.pet(entry.mint)));
	if (!holder) return null;
	const field = (name) => fieldOf(holder.data, name);
	return {
		alive: field("alive") === 1n,
		hearts: field("hearts"),
		maxHearts: field("max_hearts"),
		insurance: field("insurance"),
		harvest: field("harvest"),
		giftOwed: field("gift_owed"),
		bonding: Number(field("bonding")),
		burrow: field("burrow"),
		lineage: field("lineage_generation"),
		diedEpoch: readU64(holder.data, petAt.died_epoch),
		slotsFree: (field("owner_first") === 0n ? 1 : 0) + (field("owner_second") === 0n ? 1 : 0),
		blockId: Number(field("block_id")),
	};
}

async function readWhenCloned(key) {
	for (let attempt = 0; attempt < 40; attempt++) {
		if (await read(ephemeral, key)) return true;
		await sleep(500);
	}
	return false;
}

async function bought(entry, config, epoch, item, tier, wholeSkr, label) {
	const source = await associated(entry.owner.address, config.skrMint);
	const order = { item, tier, skrMint: config.skrMint, source, treasury: config.treasury };
	const buy = recorded(epoch, `buy:${label}`, await submit(base, [await program.buy(entry.owner, entry.mint, order)], entry.owner));
	if (!buy.ok) return;
	dayOf(epoch).skrSpent += Number(wholeSkr);
	if (!(await readWhenCloned(await program.address(program.seeds.ledger(entry.mint))))) {
		recorded(epoch, `load:${label}`, { ok: false, error: "ledger never cloned" });
		return;
	}
	await sleep(LEDGER_SETTLE_MS);
	recorded(epoch, `load:${label}`, await submit(ephemeral, [await program.load(entry.mint)], entry.owner));
}

async function paidTotal(entry) {
	const paid = await read(baseRead, await program.address(program.seeds.paid(entry.mint)));
	return paid ? readU64(paid.data, paidAt.total) : 0n;
}

async function committedOnL1(entry, paid) {
	for (let wait = 0; wait < COMMIT_WAIT_SECONDS; wait++) {
		if (((await petState(entry, baseRead))?.giftOwed ?? 0n) > paid) return true;
		await sleep(1000);
	}
	return false;
}

async function claimed(entry, config, epoch) {
	const paid = await paidTotal(entry);
	if (((await petState(entry))?.giftOwed ?? 0n) <= paid) return;
	recorded(epoch, "commit", await submit(ephemeral, [await program.commitPet(entry.owner, entry.mint)], entry.owner));
	if (!(await committedOnL1(entry, paid))) {
		recorded(epoch, "claim", { ok: false, error: `commit not on L1 after ${COMMIT_WAIT_SECONDS} s` });
		return;
	}
	const destination = await associated(entry.owner.address, config.hbrnMint);
	const before = await tokenBalance(destination);
	const instructions = [];
	if (!(await read(baseRead, destination))) instructions.push(createAssociated(entry.owner, entry.owner.address, config.hbrnMint, destination));
	instructions.push(await program.claimReward(entry.owner, entry.mint, destination));
	const outcome = recorded(epoch, "claim", await submit(base, instructions, entry.owner));
	if (outcome.ok) {
		const gained = (await tokenBalance(destination)) - before;
		dayOf(epoch).hbrnClaimed = String(BigInt(dayOf(epoch).hbrnClaimed) + gained);
	}
}

async function fundPaid(epoch, owner, lamports) {
	const fund = await program.address(program.seeds.revenue());
	const pooled = (await baseRead.getBalance(fund).send()).value;
	const kept = await baseRead.getMinimumBalanceForRentExemption(0n).send();
	if (pooled < kept + lamports) return false;
	return recorded(epoch, "rebirth:fund", await submit(base, [await program.withdrawFund(lamports, owner)], wallet)).ok;
}

async function reborn(entry, config, epoch, pet) {
	const ledger = await read(baseRead, await program.address(program.seeds.ledger(entry.mint)));
	if (ledger && BigInt(readU32(ledger.data, ledgerAt.rebirths)) > pet.lineage) return;
	const balance = (await baseRead.getBalance(entry.owner.address).send()).value;
	const needed = config.hatchFeeLamports + REBIRTH_HEADROOM_LAMPORTS;
	if (balance < needed && !(await fundPaid(epoch, entry.owner.address, needed - balance))) {
		const topUp = { programAddress: SYSTEM_PROGRAM, accounts: [writableSigner(wallet), writable(entry.owner.address)], data: joined(u32(2), u64(needed - balance)) };
		const funded = recorded(epoch, "rebirth:topUp", await submit(base, [topUp], wallet));
		if (!funded.ok) return;
	}
	const committed = recorded(epoch, "rebirth:commit", await submit(ephemeral, [await program.commitPet(entry.owner, entry.mint)], entry.owner));
	if (!committed.ok) return;
	let onBase = await petState(entry, baseRead);
	for (let wait = 0; wait < 24 && !(onBase && !onBase.alive && onBase.diedEpoch > 0n); wait++) {
		await sleep(1000);
		onBase = await petState(entry, baseRead);
	}
	recorded(epoch, "rebirth", await submit(base, [await program.payRebirth(entry.owner, entry.mint)], entry.owner));
}

async function visit(entry, config, epoch) {
	const habit = HABITS[entry.kind];
	const draw = visitDraw(SEED, entry.index, epoch);
	if (!rolled(draw, 0n, habit.visitPercent)) return;
	const pet = await petState(entry);
	if (pet && !pet.alive && pet.diedEpoch > 0n) return await reborn(entry, config, epoch, pet);
	if (!pet || !pet.alive) return;
	dayOf(epoch).visits += 1;
	recorded(epoch, "bank", await submit(ephemeral, [await program.bank(entry.owner, entry.mint)], entry.owner));
	recorded(epoch, "engage", await submit(ephemeral, [await program.engage(entry.owner, entry.mint)], entry.owner));
	let slotsFree = pet.slotsFree;
	if (slotsFree > 0 && pet.hearts * BPS < pet.maxHearts * habit.feedBelowBps) {
		await bought(entry, config, epoch, ITEM.Food, habit.foodTier, FOOD_SKR[habit.foodTier], "food");
		slotsFree -= 1;
	}
	if (slotsFree > 0 && rolled(draw, 1n, habit.growthPercent)) {
		const growthSkr = GROWTH_SKR_PER_STEP * BigInt(habit.growthSteps);
		await bought(entry, config, epoch, ITEM.Growth, habit.growthSteps - 1, growthSkr, "growth");
	}
	if (pet.insurance === 0n && rolled(draw, 2n, habit.insurePercent)) {
		await bought(entry, config, epoch, ITEM.Insurance, 0, INSURANCE_SKR, "insurance");
	}
	if (pet.giftOwed > 0n) await claimed(entry, config, epoch);
}

async function opened(entry, epoch, round) {
	const habit = HABITS[entry.kind];
	if (!rolled(openDraw(SEED, entry.index, epoch, round), 3n, habit.opensPercent)) return;
	dayOf(epoch).opens += 1;
	recorded(epoch, "open:engage", await submit(ephemeral, [await program.engage(entry.owner, entry.mint)], entry.owner));
	recorded(epoch, "open:bank", await submit(ephemeral, [await program.bank(entry.owner, entry.mint)], entry.owner));
}

async function blockState(id) {
	const holder = await read(ephemeral, await program.address(program.seeds.block(id)));
	if (!holder) return null;
	return { phase: holder.data[blockAt.phase], round: holder.data[blockAt.round], epoch: readU64(holder.data, blockAt.epoch) };
}

async function joinedOwners(owners) {
	const registry = process.env.PETS_FILE;
	if (!registry || !process.env.PLAYERS || !existsSync(registry)) return [];
	const listed = JSON.parse(readFileSync(registry, "utf8")).length;
	const next = owners[owners.length - 1].index + 1;
	const master = masterSeed();
	const joined = [];
	for (let index = next; index < listed; index++) joined.push(await ownerAt(master, index));
	return joined;
}

async function run(owners, config) {
	const kinds = owners.reduce((count, entry) => ({ ...count, [entry.kind]: (count[entry.kind] ?? 0) + 1 }), {});
	status.owners = kinds;
	const byBlock = new Map();
	const placeInto = async (candidates) => {
		const unplaced = [];
		await inParallel(candidates, async (entry) => {
			const pet = await petState(entry);
			if (!pet || pet.blockId === 0xffffffff) {
				unplaced.push(entry);
				return;
			}
			if (!byBlock.has(pet.blockId)) byBlock.set(pet.blockId, []);
			byBlock.get(pet.blockId).push(entry);
		}, BLOCK_PARALLEL);
		return unplaced;
	};
	let unplaced = await placeInto(owners);
	console.log(`owners ${owners.length}: ${json(kinds)}; day ${config.secondsPerDay} s; ${unplaced.length} pets not in a block yet`);
	status.handled ??= {};
	const until = Date.now() + MINUTES * 60_000;
	while (Date.now() < until) {
		const joined = await joinedOwners(owners);
		if (joined.length > 0) {
			await onramp(joined, config);
			owners.push(...joined);
			unplaced.push(...joined);
			console.log(`${new Date().toISOString()} ${joined.length} owners joined to fill a real player's block, ${owners.length} in all`);
		}
		if (unplaced.length > 0) {
			const waiting = unplaced.length;
			unplaced = await placeInto(unplaced);
			if (unplaced.length < waiting) console.log(`${new Date().toISOString()} ${waiting - unplaced.length} pets found in blocks, ${unplaced.length} still waiting`);
		}
		await inParallel([...byBlock], async ([id, entries]) => {
			const block = await blockState(id);
			if (!block || block.phase !== 0) return;
			const key = `${block.epoch}:${block.round}`;
			if (status.handled[id] === key) return;
			status.handled[id] = key;
			const started = Date.now();
			if (block.round === 0) {
				await onramp(entries, config);
				await inParallel(entries, (entry) => visit(entry, config, block.epoch));
			} else await inParallel(entries, (entry) => opened(entry, block.epoch, block.round));
			console.log(`${new Date().toISOString()} block ${id} before epoch ${block.epoch} round ${block.round}: ${block.round === 0 ? "visits" : "opens"} done in ${((Date.now() - started) / 1000).toFixed(1)} s`);
			save();
		}, BLOCK_PARALLEL);
		await sleep(POLL_MS);
	}
	save();
}

async function commits(owners) {
	const entry = owners[Number(process.env.COMMIT_PET ?? 2)];
	const pet = await program.address(program.seeds.pet(entry.mint));
	const payer = await program.address(program.seeds.vrfPayer());
	const landed = async () => (await baseRead.getSignaturesForAddress(pet, { limit: 200 }).send()).filter((found) => found.err === null).length;
	const payerLamports = async () => (await read(ephemeral, payer))?.lamports ?? 0n;
	const startLamports = await payerLamports();
	const results = [];
	for (let index = 1; index <= Number(process.env.COMMITS ?? 27); index++) {
		const before = await landed();
		const lamportsBefore = await payerLamports();
		const sent = await submit(ephemeral, [await program.commitPet(entry.owner, entry.mint)], entry.owner);
		let after = before;
		for (let wait = 0; sent.ok && wait < 24 && after === before; wait++) {
			await sleep(1000);
			after = await landed();
		}
		const charged = lamportsBefore - (await payerLamports());
		results.push({ commit: index, er: sent.ok ? "ok" : sent.error, landedOnL1: after > before, payerCharged: String(charged) });
		console.log(`commit ${index}: ER ${sent.ok ? "ok" : sent.error}; L1 successful transactions on the pet ${before} -> ${after}; vrf-payer charged ${charged}`);
	}
	status.commitCap = { pet: entry.mint, results, payerSpent: String(startLamports - (await payerLamports())) };
	save();
}

async function bankcheck(owners) {
	const entry = owners[Number(process.env.BANK_PET ?? 0)];
	const harvest = async () => (await petState(entry)).harvest;
	const banked = async (label) => {
		const before = await harvest();
		const outcome = await submit(ephemeral, [await program.bank(entry.owner, entry.mint)], entry.owner);
		const result = { label, at: new Date().toISOString(), outcome: outcome.ok ? "ok" : outcome.error, harvestBefore: String(before), harvestAfter: String(await harvest()) };
		console.log(json(result));
		return result;
	};
	const results = [await banked("first"), await banked("immediately again")];
	const waitSeconds = Number(process.env.BANK_WAIT_SECONDS ?? 405);
	await sleep(waitSeconds * 1000);
	results.push(await banked(`after ${waitSeconds} s`));
	status.bankCooldown = { pet: entry.mint, results };
	save();
}

async function gift(owners, config) {
	const entry = owners.find((owner) => owner.index === Number(process.env.GIFT_PET ?? 0));
	let stockedEpoch = -1n;
	for (;;) {
		const epoch = (BigInt(Math.floor(Date.now() / 1000)) - config.genesis) / config.secondsPerDay;
		const pet = await petState(entry);
		if (!pet?.alive) throw new Error(`gift: pet ${entry.mint} is not alive`);
		console.log(`${new Date().toISOString()} epoch ${epoch} bonding ${pet.bonding} burrow ${pet.burrow} gift ${pet.giftOwed} slots free ${pet.slotsFree}`);
		if (pet.giftOwed > 0n) {
			await claimed(entry, config, epoch);
			console.log(json({ pet: entry.mint, owner: entry.owner.address, day: dayOf(epoch) }));
			save();
			return;
		}
		recorded(epoch, "engage", await submit(ephemeral, [await program.engage(entry.owner, entry.mint)], entry.owner));
		if (stockedEpoch !== epoch && pet.slotsFree === 2) {
			await bought(entry, config, epoch, ITEM.Growth, 0, GROWTH_SKR_PER_STEP, "growth");
			await bought(entry, config, epoch, ITEM.Food, 2, FOOD_SKR[2], "food");
			stockedEpoch = epoch;
		}
		save();
		await sleep(60_000);
	}
}

const owners = await ownersOf();
const config = await readConfig();
if (STAGE === "commits") await commits(owners);
else if (STAGE === "bankcheck") await bankcheck(owners);
else if (STAGE === "onramp") await onramp(owners, config);
else if (STAGE === "gift") await gift(owners, config);
else if (STAGE === "run") {
	await onramp(owners, config);
	await run(owners, config);
} else throw new Error(`unknown stage ${STAGE}`);
