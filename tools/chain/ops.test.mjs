import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

function loadFunction(file, name, next, context) {
	const source = readFileSync(new URL(file, import.meta.url), "utf8");
	const start = source.indexOf(`function ${name}(`);
	const end = source.indexOf(`function ${next}(`, start);
	assert.ok(start >= 0 && end > start);
	const declaration = source.slice(start, end).replace(/(?:export\s+)?(?:async\s+)?$/, "");
	const prefix = source.slice(start - 6, start) === "async " ? "async " : "";
	runInNewContext(`${prefix}${declaration}`, context);
	return context[name];
}

for (const at of ["not-a-date", undefined]) {
	test(`sentinel rejects ${at ?? "missing"} ops timestamp`, () => {
		const check = loadFunction("sentinel.mjs", "opsCheck", "diskCheck", {
			OPS_STATUS: "ops.json",
			OPS_STALE_SECONDS: 180,
			existsSync: () => true,
			readFileSync: () => JSON.stringify({ at }),
		});
		assert.match(check().alarm, /timestamp/);
	});
}

for (const seconds of [0, 181]) {
	test(`sentinel checks ${seconds}s old ops timestamp`, () => {
		const check = loadFunction("sentinel.mjs", "opsCheck", "diskCheck", {
			OPS_STATUS: "ops.json",
			OPS_STALE_SECONDS: 180,
			existsSync: () => true,
			readFileSync: () => JSON.stringify({ at: new Date(Date.now() - seconds * 1000).toISOString() }),
		});
		assert.equal(check().alarm === null, seconds === 0);
	});
}

test("HTTP refresh advances cranker due and retry clock without a slot stream", async () => {
	const stop = new Error("stop refresh");
	let polls = 0;
	let waits = 0;
	let fired = 0;
	const context = {
		slot: 100n,
		blockhash: null,
		sleep: async () => { if (++waits === 2) throw stop; },
		ephemeral: {
			getLatestBlockhash: () => ({ send: async () => ({ value: { blockhash: "fresh" } }) }),
			getSlot: () => ({ send: async () => 100n + BigInt(++polls) }),
		},
		console: { error: () => assert.fail("unexpected refresh error") },
		unfrozen: async () => {},
		blocks: new Map([["block", { key: "block", program: "program", crankSeq: 1n, dueSlot: 101n }]]),
		inFlight: new Map([["block", { seq: 1n, attempts: 1, retryAt: 102n }]]),
		stats: { maxLag: 0n, retried: 0, skippedSpent: 0, sent: 0, failedSends: 0 },
		sending: 0,
		MAX_IN_FLIGHT: 1,
		RETRY_SLOTS: 10n,
		MAX_BACKOFF_SLOTS: 100n,
		HYDRA_PROGRAM: "hydra",
		REMAINING_OFFSET: 80,
		programsByKey: new Map([["program", {}]]),
		crankOf: async () => "crank",
		readMany: async () => [{ owner: "hydra", data: new Uint8Array() }],
		readU64: () => 1n,
		fire: async () => { fired++; },
	};
	const tick = loadFunction("gameCranker.mjs", "tick", "refreshed", context);
	context.blockhash = { blockhash: "initial" };
	await tick();
	assert.equal(fired, 0);
	const refresh = loadFunction("gameCranker.mjs", "refreshBlockhash", "unfrozen", context);
	await assert.rejects(refresh(), error => error === stop);
	assert.equal(polls, 2);
	assert.equal(context.slot, 102n);
	await tick();
	assert.equal(fired, 1);
	assert.equal(context.stats.retried, 1);
});

test("HTTP refresh does not rewind a newer streamed slot", async () => {
	const stop = new Error("stop refresh");
	const context = {
		slot: 103n,
		blockhash: null,
		sleep: async () => { throw stop; },
		ephemeral: {
			getLatestBlockhash: () => ({ send: async () => ({ value: { blockhash: "fresh" } }) }),
			getSlot: () => ({ send: async () => 102n }),
		},
		console: { error: () => assert.fail("unexpected refresh error") },
		unfrozen: async () => {},
	};
	const refresh = loadFunction("gameCranker.mjs", "refreshBlockhash", "unfrozen", context);
	await assert.rejects(refresh(), error => error === stop);
	assert.equal(context.slot, 103n);
});

test("frozen ER slot gets one nudge burst per freeze window and a time-based slot", async () => {
	const nudged = [];
	const context = {
		slot: 100n,
		slotMillis: 50n,
		erClock: { slot: null, since: 0, burstAt: 0 },
		stats: { unfreezeBursts: 0, unfreezeSent: 0 },
		FREEZE_SECONDS: 10,
		UNFREEZE_BURST: 4,
		console: { error: () => {} },
		nudge: async (units) => { nudged.push(units); },
	};
	const unfrozen = loadFunction("gameCranker.mjs", "unfrozen", "nudge", context);
	await unfrozen(100n, 0);
	for (let second = 1; second <= 9; second++) await unfrozen(100n, second * 1000);
	assert.equal(nudged.length, 0, "no burst before FREEZE_SECONDS");
	assert.equal(context.slot, 280n, "scheduler clock follows wall time while frozen");
	await unfrozen(100n, 10_000);
	assert.deepEqual(nudged, [1000, 1001, 1002, 1003], "one burst of distinct transactions");
	await unfrozen(100n, 11_000);
	assert.equal(context.stats.unfreezeBursts, 1, "one burst per freeze window");
	await unfrozen(100n, 20_000);
	assert.equal(context.stats.unfreezeBursts, 2, "a burst that did not re-arm repeats");
	await unfrozen(101n, 21_000);
	for (let second = 22; second <= 30; second++) await unfrozen(BigInt(second + 80), second * 1000);
	assert.equal(context.stats.unfreezeBursts, 2, "no burst while the slot advances");
	assert.equal(nudged.length, 8);
});

function discoveryFixture(failure) {
	const requests = [];
	let calls = 0;
	let recovered = false;
	const context = {
		Buffer, PARALLEL: 16,
		state: { pets: {} }, process: { env: {} }, NET_DIR: "scratch",
		existsSync: () => false, configAddress: async () => "config",
		programAddress: "program", claimDiscriminator: "0000000000000000",
		sleep: async () => {},
		baseRead: {
			getSignaturesForAddress: (_, options) => ({ send: async () => {
				requests.push({ ...options });
				return options.until === "claimSignature" ? [] : [{ signature: "claimSignature", err: null }];
			} }),
			getTransaction: () => ({ send: async () => {
				calls++;
				if (!recovered) {
					if (failure === "throw") throw new Error("mock RPC unavailable");
					if (failure === "null") return null;
				}
				return { transaction: { message: {
					accountKeys: ["owner", "config", "mint", "unused", "pet", "program"],
					instructions: [{ programIdIndex: 5, accounts: [0, 1, 2, 3, 4], data: "11111111" }],
				} } };
			} }),
		},
	};
	loadFunction("ops.mjs", "inParallel", "readMany", context);
	loadFunction("ops.mjs", "base58Bytes", "allBlocks", context);
	loadFunction("hibernal.mjs", "patiently", "cluster", context);
	loadFunction("ops.mjs", "discoverPets", "base58Bytes", context);
	return { context, requests, calls: () => calls, recover: () => { recovered = true; } };
}

for (const failure of ["throw", "null"]) {
	test(`discovery retries unconsumed Claim after ${failure} transaction read`, async () => {
		const fixture = discoveryFixture(failure);
		try { await fixture.context.discoverPets(); } catch (error) {
			assert.match(error.message, /mock RPC unavailable|claim transaction .* unavailable/);
		}
		assert.equal(fixture.calls(), failure === "throw" ? 10 : 1);
		fixture.context.state = JSON.parse(JSON.stringify(fixture.context.state));
		fixture.recover();
		await fixture.context.discoverPets();
		assert.ok(fixture.context.state.pets.pet, "Claim must remain discoverable after transient failure");
		assert.equal(fixture.context.state.pets.pet.mint, "mint");
		assert.equal(fixture.context.state.claimCursor, "claimSignature");
		assert.equal(fixture.requests[1].until, undefined);
	});
}

test("successful discovery commits cursor and suppresses completed replay", async () => {
	const fixture = discoveryFixture("success");
	fixture.recover();
	await fixture.context.discoverPets();
	await fixture.context.discoverPets();
	assert.equal(fixture.context.state.pets.pet.owner, "owner");
	assert.equal(fixture.context.state.claimCursor, "claimSignature");
	assert.equal(fixture.calls(), 1);
	assert.equal(fixture.requests[1].until, "claimSignature");
});

for (const [name, refuse, capacity, pending] of [
	["refused", true, true, 1],
	["successful", false, true, 0],
	["no capacity", false, false, 1],
]) {
	test(`placement status preserves pending pets after ${name} placement`, async () => {
		const context = {
			state: {}, baseRead: {}, NO_BLOCK: 0xffffffff, SEATS: 10,
			PLACES_PER_TRANSACTION: 5, PARALLEL: 16,
			address: key => key,
			discoverPets: async () => ["pet"],
			readMany: async () => [{ owner: "delegation" }],
			delegated: holder => holder.owner === "delegation",
			readCloned: async () => [{}],
			petOf: key => ({ key, mint: "mint", blockId: 0xffffffff, alive: false, diedEpoch: 0n, level: 0 }),
			delegateBlocks: async () => {},
			allBlocks: async () => capacity ? [{ id: 0, phase: 0, members: Array(10).fill(null) }] : [],
			createBlocks: async () => {},
			program: { place: async () => ({}) },
			onEr: async () => { if (refuse) throw new Error("mock placement refused"); },
			note: () => {}, supportsRelay: () => false, save: () => {},
		};
		loadFunction("ops.mjs", "inParallel", "readMany", context);
		const place = loadFunction("ops.mjs", "blocks", "exhaustedCranks", context);
		const result = await place();
		assert.equal(result.unplacedBefore, 1);
		assert.equal(result.placed, pending === 0 ? 1 : 0);
		assert.equal(result.unplacedLeft, pending);
	});
}

test("placement seats an heir in the block with the lowest living level and never a lost pet", async () => {
	const pets = {
		veteran: { key: "veteran", mint: "veteran", blockId: 0, alive: true, diedEpoch: 0n, level: 9 },
		novice: { key: "novice", mint: "novice", blockId: 1, alive: true, diedEpoch: 0n, level: 2 },
		heir: { key: "heir", mint: "heir", blockId: 0xffffffff, alive: true, diedEpoch: 0n, level: 1 },
		lost: { key: "lost", mint: "lost", blockId: 0xffffffff, alive: false, diedEpoch: 7n, level: 4 },
	};
	const seated = [];
	const context = {
		state: {}, baseRead: {}, NO_BLOCK: 0xffffffff, SEATS: 10,
		PLACES_PER_TRANSACTION: 5, PARALLEL: 16,
		address: key => key,
		discoverPets: async () => Object.keys(pets),
		readMany: async (_, keys) => keys.map(() => ({ owner: "delegation" })),
		delegated: holder => holder.owner === "delegation",
		readCloned: async keys => keys.map(() => ({})),
		petOf: key => pets[key],
		delegateBlocks: async () => {},
		allBlocks: async () => [
			{ id: 0, phase: 0, members: ["veteran", ...Array(9).fill(null)] },
			{ id: 1, phase: 0, members: ["novice", ...Array(9).fill(null)] },
		],
		createBlocks: async () => {},
		program: { place: async (id, mint) => { seated.push([id, mint]); return {}; } },
		onEr: async () => {},
		note: () => {}, supportsRelay: () => false, save: () => {},
	};
	loadFunction("ops.mjs", "inParallel", "readMany", context);
	const place = loadFunction("ops.mjs", "blocks", "exhaustedCranks", context);
	const result = await place();
	assert.deepEqual(seated, [[1, "heir"]]);
	assert.equal(result.unplacedBefore, 1);
	assert.equal(result.placed, 1);
});

test("load is due only for a living pet whose ledger bought more than it loaded, with an owner slot free", () => {
	const readU32 = (data, at) => data[at] | (data[at + 1] << 8) | (data[at + 2] << 16) | (data[at + 3] << 24);
	const loadable = loadFunction("ops.mjs", "loadable", "loads", {
		readU32,
		ledgerAt: { bought: 32 },
		petAccountAt: { loaded: 96, pet: 128 },
		petAt: { owner_first: 10, owner_second: 11, alive: 12 },
	});
	const ledger = (food) => ({ data: Uint8Array.from({ length: 64 }, (_, at) => (at === 32 + 4 * 2 ? food : 0)) });
	const record = (food, first, second, alive = 1) => ({
		data: Uint8Array.from({ length: 160 }, (_, at) => (at === 96 + 4 * 2 ? food : at === 138 ? first : at === 139 ? second : at === 140 ? alive : 0)),
	});
	assert.equal(loadable(ledger(2), record(1, 0, 0)), true);
	assert.equal(loadable(ledger(2), record(2, 0, 0)), false);
	assert.equal(loadable(ledger(2), record(1, 3, 3)), false);
	assert.equal(loadable(ledger(2), record(1, 3, 0)), true);
	assert.equal(loadable(ledger(2), record(1, 0, 0, 0)), false);
	assert.equal(loadable(null, record(0, 0, 0)), false);
});
