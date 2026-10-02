import { randomBytes } from "node:crypto";
import { AccountRole } from "@solana/kit";
import { HYDRA_PROGRAM, INSTRUCTIONS_SYSVAR, MAGIC_PROGRAM, MAGIC_VAULT, encoder, joined, pda, readonly, u32, u64, writable, writableSigner } from "./hibernal.mjs";

export async function crankAddress(seed) {
	const [crank] = await pda(HYDRA_PROGRAM, "crank", seed);
	return crank;
}

export function newCrankSeed() {
	return new Uint8Array(randomBytes(32));
}

function scheduledBytes(scheduled) {
	const size = new Uint8Array(3);
	size[0] = scheduled.accounts.length;
	new DataView(size.buffer).setUint16(1, scheduled.data.length, true);
	const parts = [size, encoder.encode(scheduled.programAddress)];
	for (const meta of scheduled.accounts) {
		const role = meta.role === AccountRole.WRITABLE || meta.role === AccountRole.WRITABLE_SIGNER ? 2 : 0;
		parts.push(Uint8Array.of(role), encoder.encode(meta.address));
	}
	parts.push(scheduled.data);
	return joined(...parts);
}

export function createCrank({ sponsor, crank, seed, startSlot, interval, remaining, computeUnits, scheduled }) {
	const data = joined(
		Uint8Array.of(0),
		seed,
		encoder.encode(sponsor.address),
		u64(startSlot),
		u64(interval),
		u64(remaining),
		u64(0),
		u32(computeUnits),
		scheduledBytes(scheduled),
	);
	return {
		programAddress: HYDRA_PROGRAM,
		accounts: [writableSigner(sponsor), writable(crank), writable(MAGIC_VAULT), readonly(MAGIC_PROGRAM)],
		data,
	};
}

export function triggerCrank({ crank, caller }) {
	return {
		programAddress: HYDRA_PROGRAM,
		accounts: [writable(crank), writableSigner(caller), readonly(INSTRUCTIONS_SYSVAR)],
		data: Uint8Array.of(1),
	};
}

export function cancelCrank({ sponsor, crank }) {
	return {
		programAddress: HYDRA_PROGRAM,
		accounts: [writableSigner(sponsor), writable(crank), writable(sponsor.address), writable(MAGIC_VAULT), readonly(MAGIC_PROGRAM)],
		data: Uint8Array.of(2),
	};
}
