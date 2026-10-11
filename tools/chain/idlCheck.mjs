import { address, generateKeyPairSigner } from "@solana/kit";
import { hibernal, idlAt } from "./hibernal.mjs";

const BUILT_ON_CHAIN = new Set(["round_start", "turn", "seeded", "process_undelegation"]);

const idl = idlAt(process.argv[2] ? new URL(process.argv[2], `file://${process.cwd()}/`) : undefined);
const authority = await generateKeyPairSigner();
const owner = await generateKeyPairSigner();
const program = hibernal(address("11111111111111111111111111111112"), authority);
const someKey = async () => (await generateKeyPairSigner()).address;
const mint = await someKey();
const skrMint = await someKey();

const built = [
	await program.initialize({ admissionGroup: await someKey(), engine: 0n, genesisTimestamp: 0n, claimCapPerDay: 0n, resortEvery: 0n, skrMint, treasury: await someKey(), validator: await someKey(), vrfQueue: await someKey(), hatchFeeLamports: 0n }),
	await program.writePolicy(0, new Uint8Array(4), false),
	await program.createBlock(0),
	await program.claim(owner, mint, await someKey(), 0),
	await program.delegatePet(authority, mint),
	await program.delegateBlock(0),
	await program.delegateWorld(),
	await program.delegateResort(),
	await program.delegateVrfPayer(),
	await program.place(0, mint),
	await program.engage(owner, mint),
	await program.bank(owner, mint),
	await program.commitPet(owner, mint),
	await program.claimReward(owner, mint, await someKey()),
	await program.withdrawRevenue(1n, skrMint, await someKey()),
	await program.createHbrnMetadata({ name: "Hibernal", symbol: "HBRN", uri: "https://example.com/hbrn.json" }),
	await program.buy(owner, mint, { item: 0, tier: 0, skrMint, source: await someKey(), treasury: await someKey() }),
	await program.load(mint),
	await program.payRebirth(owner, mint),
	await program.rebirth(mint),
	await program.withdrawFund(1n, await someKey()),
	await program.resortBegin(0, 1n),
	await program.resortClear(0, [await someKey()]),
	await program.resortAssign(1, 0n, [await someKey()]),
	await program.resortFinish(),
	await program.startBlock(0, 0n),
	await program.sweep([await someKey()]),
].flat();

const byDiscriminator = new Map(idl.instructions.map((entry) => [Buffer.from(entry.discriminator).toString("hex"), entry]));
const covered = new Set();
const failures = [];
for (const instruction of built) {
	if (instruction.programAddress !== program.programAddress) continue;
	const declared = byDiscriminator.get(Buffer.from(instruction.data.subarray(0, 8)).toString("hex"));
	if (!declared) {
		failures.push(`a built instruction has discriminator ${Buffer.from(instruction.data.subarray(0, 8)).toString("hex")}, which the IDL does not declare`);
		continue;
	}
	covered.add(declared.name);
	if (instruction.accounts.length < declared.accounts.length) {
		failures.push(`${declared.name}: client lists ${instruction.accounts.length} accounts, IDL ${declared.accounts.length}`);
		continue;
	}
	declared.accounts.forEach((account, index) => {
		const role = instruction.accounts[index].role;
		const writable = (role & 1) === 1;
		const signer = (role & 2) === 2;
		if (writable !== Boolean(account.writable)) failures.push(`${declared.name}.${account.name}: client writable ${writable}, IDL ${Boolean(account.writable)}`);
		if (signer !== Boolean(account.signer)) failures.push(`${declared.name}.${account.name}: client signer ${signer}, IDL ${Boolean(account.signer)}`);
		if (account.address && instruction.accounts[index].address !== account.address) failures.push(`${declared.name}.${account.name}: client ${instruction.accounts[index].address}, IDL fixes ${account.address}`);
	});
}
for (const entry of idl.instructions) {
	if (!covered.has(entry.name) && !BUILT_ON_CHAIN.has(entry.name)) failures.push(`${entry.name}: no client builder checked`);
}
console.log(`checked ${covered.size} instruction discriminators/account metadata against the IDL; argument ABI not checked; built on chain (Hydra template, VRF callback, delegation program), not checked here: ${[...BUILT_ON_CHAIN].join(", ")}`);
for (const failure of failures) console.log(`MISMATCH ${failure}`);
process.exit(failures.length === 0 ? 0 : 1);
