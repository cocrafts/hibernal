import { randomBytes } from "node:crypto";
import { AccountRole } from "@solana/kit";
import { DELEGATION_PROGRAM, HYDRA_PROGRAM, INSTRUCTIONS_SYSVAR, MAGIC_PROGRAM, MAGIC_VAULT, SYSTEM_PROGRAM, encoder, joined, pda, readonly, u32, u64, writable, writableSigner } from "./hibernal.mjs";

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

export async function sponsorDelegated({ sponsor, funder, base, baseRead, ephemeralUrl, validator, lamports, send }) {
	const status = async () => {
		const response = await fetch(ephemeralUrl, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "getDelegationStatus", params: [sponsor.address] }) });
		return (await response.json()).result?.isDelegated === true;
	};
	if (await status()) return false;
	const sponsorBytes = encoder.encode(sponsor.address);
	const [record] = await pda(DELEGATION_PROGRAM, "delegation", sponsorBytes);
	const [metadata] = await pda(DELEGATION_PROGRAM, "delegation-metadata", sponsorBytes);
	const [buffer] = await pda(SYSTEM_PROGRAM, "buffer", sponsorBytes);
	const rent = BigInt(await base.getMinimumBalanceForRentExemption(256n).send());
	const onL1 = (await baseRead.getBalance(sponsor.address).send()).value;
	const transfer = (from, to, amount) => ({ programAddress: SYSTEM_PROGRAM, accounts: [writableSigner(from), writable(to)], data: joined(u32(2), u64(amount)) });
	if (onL1 < lamports) await send(base, baseRead, "fund the Hydra sponsor", [transfer(funder, sponsor.address, lamports - onL1)], funder);
	const delegateData = joined(u64(0), Uint8Array.of(0xff, 0xff, 0xff, 0xff, 0, 0, 0, 0, 1), encoder.encode(validator));
	await send(base, baseRead, "delegate the Hydra sponsor", [
		transfer(sponsor, record, rent),
		transfer(sponsor, metadata, rent),
		{ programAddress: SYSTEM_PROGRAM, accounts: [writableSigner(sponsor)], data: joined(u32(1), encoder.encode(DELEGATION_PROGRAM)) },
		{ programAddress: DELEGATION_PROGRAM, accounts: [writableSigner(sponsor), writableSigner(sponsor), readonly(SYSTEM_PROGRAM), writable(buffer), writable(record), writable(metadata), readonly(SYSTEM_PROGRAM)], data: delegateData },
	], funder);
	const started = Date.now();
	while (!(await status())) {
		if (Date.now() - started > 60_000) throw new Error("the Hydra sponsor is not delegated after 60 s");
		await new Promise((resolve) => setTimeout(resolve, 1000));
	}
	return true;
}
