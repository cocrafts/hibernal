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
	const refresh = loadFunction("gameCranker.mjs", "refreshBlockhash", "report", context);
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
	};
	const refresh = loadFunction("gameCranker.mjs", "refreshBlockhash", "report", context);
	await assert.rejects(refresh(), error => error === stop);
	assert.equal(context.slot, 103n);
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
			petOf: key => ({ key, mint: "mint", blockId: 0xffffffff }),
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
