import { existsSync, readFileSync } from "node:fs";
import { AccountRole, address, appendTransactionMessageInstructions, createTransactionMessage, getBase64EncodedWireTransaction, getProgramDerivedAddress, getSignatureFromTransaction, pipe, setTransactionMessageFeePayerSigner, setTransactionMessageLifetimeUsingBlockhash, signTransactionMessageWithSigners } from "@solana/kit";
import { SYSTEM_PROGRAM, cluster, encoder, joined, keypairAt, patiently, read, send, sleep, u32, u64 } from "./hibernal.mjs";

const LOADER = address("BPFLoaderUpgradeab1e11111111111111111111111");
const RENT = address("SysvarRent111111111111111111111111111111111");
const CLOCK = address("SysvarC1ock11111111111111111111111111111111");
const CHUNK = 950;
const BUFFER_HEADER = 37;
const PARALLEL = Number(process.env.PARALLEL ?? 32);
const HEADROOM = Number(process.env.HEADROOM ?? 1.2);

const [soPath, programKeyPath, bufferKeyPath] = process.argv.slice(2);
if (!soPath || !programKeyPath || !bufferKeyPath || !existsSync(bufferKeyPath)) {
	console.log("usage: node tools/chain/deploy.mjs <program.so> <program keypair> <buffer keypair (solana-keygen new -o …)>");
	process.exit(2);
}
const elf = new Uint8Array(readFileSync(soPath));
const { base, baseRead } = cluster();
const payer = await keypairAt(`${process.env.HOME}/.config/solana/id.json`);
const programKey = await keypairAt(programKeyPath);
const bufferKey = await keypairAt(bufferKeyPath);
const [programData] = await getProgramDerivedAddress({ programAddress: LOADER, seeds: [encoder.encode(programKey.address)] });
const signerOf = (keypair) => ({ address: keypair.address, role: AccountRole.WRITABLE_SIGNER, signer: keypair });
const rentFor = async (space) => BigInt(await base.getMinimumBalanceForRentExemption(BigInt(space)).send());
const createAccount = (target, lamports, space, owner) => ({
	programAddress: SYSTEM_PROGRAM,
	accounts: [signerOf(payer), signerOf(target)],
	data: joined(u32(0), u64(lamports), u64(space), encoder.encode(owner)),
});
const quiet = async (step, instructions) => {
	for (let attempt = 1; attempt <= 6; attempt++) {
		try {
			return await send(base, baseRead, step, instructions, payer, 200_000, false);
		} catch (error) {
			if (attempt === 6) throw error;
			await sleep(2000 * attempt);
		}
	}
};

const existing = await read(baseRead, bufferKey.address);
if (!existing) {
	const space = BUFFER_HEADER + elf.length;
	await quiet("create buffer", [
		createAccount(bufferKey, await rentFor(space), space, LOADER),
		{ programAddress: LOADER, accounts: [{ address: bufferKey.address, role: AccountRole.WRITABLE }, { address: payer.address, role: AccountRole.READONLY }], data: u32(0) },
	]);
	console.log(`buffer ${bufferKey.address} created for ${elf.length} bytes`);
}
const written = existing ? existing.data.subarray(BUFFER_HEADER) : new Uint8Array(elf.length);
const offsets = [];
for (let offset = 0; offset < elf.length; offset += CHUNK) {
	const end = Math.min(offset + CHUNK, elf.length);
	const same = written.length >= end && written.subarray(offset, end).every((byte, index) => byte === elf[offset + index]);
	if (!same) offsets.push(offset);
}
console.log(`${offsets.length} of ${Math.ceil(elf.length / CHUNK)} chunks to write, ${PARALLEL} at a time`);
const started = Date.now();
const writeOf = (offset) => {
	const chunk = elf.subarray(offset, Math.min(offset + CHUNK, elf.length));
	return {
		programAddress: LOADER,
		accounts: [{ address: bufferKey.address, role: AccountRole.WRITABLE }, { address: payer.address, role: AccountRole.READONLY_SIGNER, signer: payer }],
		data: joined(u32(1), u32(offset), u64(chunk.length), chunk),
	};
};
let pending = offsets;
for (let round = 1; pending.length > 0; round++) {
	const { value: blockhash } = await patiently(() => base.getLatestBlockhash().send());
	const sent = [];
	for (let start = 0; start < pending.length; start += PARALLEL) {
		const batch = pending.slice(start, start + PARALLEL);
		const signed = await Promise.all(batch.map(async (offset) => {
			const message = pipe(
				createTransactionMessage({ version: 0 }),
				(m) => setTransactionMessageFeePayerSigner(payer, m),
				(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
				(m) => appendTransactionMessageInstructions([writeOf(offset)], m),
			);
			const transaction = await signTransactionMessageWithSigners(message);
			return { offset, transaction, signature: getSignatureFromTransaction(transaction) };
		}));
		await Promise.all(signed.map(({ transaction }) => base.sendTransaction(getBase64EncodedWireTransaction(transaction), { encoding: "base64", skipPreflight: true }).send().catch(() => null)));
		sent.push(...signed);
		await sleep(Number(process.env.PAUSE_MS ?? 1000));
	}
	await sleep(8000);
	const confirmed = new Set();
	for (let start = 0; start < sent.length; start += 200) {
		const slice = sent.slice(start, start + 200);
		const { value } = await patiently(() => baseRead.getSignatureStatuses(slice.map((entry) => entry.signature)).send());
		value.forEach((status, index) => { if (status && !status.err && status.confirmationStatus) confirmed.add(slice[index].offset); });
	}
	pending = pending.filter((offset) => !confirmed.has(offset));
	console.log(`round ${round}: ${confirmed.size} confirmed, ${pending.length} left (${Math.round((Date.now() - started) / 1000)} s)`);
}
console.log("");
const check = await read(baseRead, bufferKey.address);
const mismatch = check.data.subarray(BUFFER_HEADER).findIndex((byte, index) => byte !== elf[index]);
if (mismatch !== -1) throw new Error(`buffer differs from the ELF at byte ${mismatch}; run again to rewrite`);
const deployed = await read(baseRead, programKey.address);
if (!deployed) {
	const maxLength = Math.ceil(elf.length * HEADROOM);
	await quiet("deploy", [
		createAccount(programKey, await rentFor(36), 36, LOADER),
		{
			programAddress: LOADER,
			accounts: [signerOf(payer), { address: programData, role: AccountRole.WRITABLE }, { address: programKey.address, role: AccountRole.WRITABLE }, { address: bufferKey.address, role: AccountRole.WRITABLE }, { address: RENT, role: AccountRole.READONLY }, { address: CLOCK, role: AccountRole.READONLY }, { address: SYSTEM_PROGRAM, role: AccountRole.READONLY }, { address: payer.address, role: AccountRole.READONLY_SIGNER, signer: payer }],
			data: joined(u32(2), u64(maxLength)),
		},
	]);
	console.log(`deployed ${programKey.address} (programData ${programData}, room for ${maxLength} bytes)`);
} else {
	await quiet("upgrade", [{
		programAddress: LOADER,
		accounts: [{ address: programData, role: AccountRole.WRITABLE }, { address: programKey.address, role: AccountRole.WRITABLE }, { address: bufferKey.address, role: AccountRole.WRITABLE }, { address: payer.address, role: AccountRole.WRITABLE }, { address: RENT, role: AccountRole.READONLY }, { address: CLOCK, role: AccountRole.READONLY }, { address: payer.address, role: AccountRole.READONLY_SIGNER, signer: payer }],
		data: u32(3),
	}]);
	console.log(`upgraded ${programKey.address}`);
}
