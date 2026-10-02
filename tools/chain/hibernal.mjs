import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import {
	AccountRole,
	address,
	appendTransactionMessageInstructions,
	createKeyPairSignerFromBytes,
	createSolanaRpc,
	createTransactionMessage,
	getAddressEncoder,
	getBase64EncodedWireTransaction,
	getProgramDerivedAddress,
	getSignatureFromTransaction,
	pipe,
	setTransactionMessageFeePayerSigner,
	setTransactionMessageLifetimeUsingBlockhash,
	signTransactionMessageWithSigners,
} from "@solana/kit";

export const SYSTEM_PROGRAM = address("11111111111111111111111111111111");
export const TOKEN_PROGRAM = address("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
export const TOKEN_2022_PROGRAM = address("TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb");
export const ASSOCIATED_TOKEN_PROGRAM = address("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL");
export const COMPUTE_BUDGET_PROGRAM = address("ComputeBudget111111111111111111111111111111");
export const DELEGATION_PROGRAM = address("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
export const MAGIC_PROGRAM = address("Magic11111111111111111111111111111111111111");
export const MAGIC_CONTEXT = address("MagicContext1111111111111111111111111111111");
export const VRF_PROGRAM = address("Vrf1RNUjXmQGjmQrQLvJHs9SNkvDJEsRVFPkfSQUwGz");
export const VRF_EPHEMERAL_QUEUE = address("5hBR571xnXppuCPveTrctfTU7tJLSN94nq7kv7FRK5Tc");
export const SLOT_HASHES = address("SysvarS1otHashes111111111111111111111111111");
export const INSTRUCTIONS_SYSVAR = address("Sysvar1nstructions1111111111111111111111111");
export const HYDRA_PROGRAM = address("eHyd5BU8QffvHi4GnXwxrK4WpS7pM2x9UGKHBWii7mf");
export const MAGIC_VAULT = address("MagicVau1t999999999999999999999999999999999");
export const COMPUTE_UNIT_LIMIT = 1_400_000;

export const encoder = getAddressEncoder();
export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
export const readonly = (key) => ({ address: key, role: AccountRole.READONLY });
export const writable = (key) => ({ address: key, role: AccountRole.WRITABLE });
export const signer = (keypair) => ({ address: keypair.address, role: AccountRole.READONLY_SIGNER, signer: keypair });
export const writableSigner = (keypair) => ({ address: keypair.address, role: AccountRole.WRITABLE_SIGNER, signer: keypair });
export const json = (value) => JSON.stringify(value, (_, inner) => typeof inner === "bigint" ? inner.toString() : inner);
export const pda = async (programAddress, ...seeds) => await getProgramDerivedAddress({ programAddress, seeds });
export const text = (value) => new TextEncoder().encode(value);

export function snakeCase(name) {
	return name.replace(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase();
}

export function instructionDiscriminator(name) {
	return new Uint8Array(createHash("sha256").update("global:" + snakeCase(name)).digest().subarray(0, 8));
}

export function accountDiscriminator(name) {
	return new Uint8Array(createHash("sha256").update("account:" + name).digest().subarray(0, 8));
}

export function joined(...parts) {
	const out = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
	let offset = 0;
	for (const part of parts) {
		out.set(part, offset);
		offset += part.length;
	}
	return out;
}

export function u8(value) {
	return Uint8Array.of(Number(value));
}

export function u32(value) {
	const bytes = new Uint8Array(4);
	new DataView(bytes.buffer).setUint32(0, Number(value), true);
	return bytes;
}

export function u64(value) {
	const bytes = new Uint8Array(8);
	new DataView(bytes.buffer).setBigUint64(0, BigInt(value), true);
	return bytes;
}

export function readU64(bytes, offset) {
	return new DataView(bytes.buffer, bytes.byteOffset).getBigUint64(offset, true);
}

export function readU32(bytes, offset) {
	return new DataView(bytes.buffer, bytes.byteOffset).getUint32(offset, true);
}

export async function keypairAt(path) {
	return await createKeyPairSignerFromBytes(Uint8Array.from(JSON.parse(readFileSync(path, "utf8"))));
}

export function computeLimit(units) {
	return { programAddress: COMPUTE_BUDGET_PROGRAM, accounts: [], data: joined(u8(2), u32(units)) };
}

export async function patiently(call) {
	for (let attempt = 1; ; attempt++) {
		try {
			return await call();
		} catch (error) {
			if (attempt >= 10) throw error;
			await sleep(2000 * attempt);
		}
	}
}

export function cluster() {
	return {
		base: createSolanaRpc(process.env.BASE_RPC ?? "https://api.devnet.solana.com"),
		baseRead: createSolanaRpc(process.env.BASE_READ_RPC ?? "https://rpc.magicblock.app/devnet"),
		ephemeral: createSolanaRpc(process.env.ER_RPC ?? "https://devnet-as.magicblock.app"),
		validator: address(process.env.VALIDATOR ?? "MAS1Dt9qreoRMQ14YQuhg8UTZMMzDdKhmkZMECCzk57"),
	};
}

async function fetchTransaction(rpc, signature) {
	for (let attempt = 0; attempt < 30; attempt++) {
		const found = await rpc.getTransaction(signature, { maxSupportedTransactionVersion: 0, commitment: "confirmed", encoding: "json" }).send().catch(() => null);
		if (found) return found;
		await sleep(1000);
	}
	return null;
}

export async function send(rpc, readRpc, step, instructions, feePayer, units = COMPUTE_UNIT_LIMIT) {
	const { value: blockhash } = await patiently(() => rpc.getLatestBlockhash().send());
	const message = pipe(
		createTransactionMessage({ version: 0 }),
		(m) => setTransactionMessageFeePayerSigner(feePayer, m),
		(m) => setTransactionMessageLifetimeUsingBlockhash(blockhash, m),
		(m) => appendTransactionMessageInstructions([computeLimit(units), ...instructions], m),
	);
	const transaction = await signTransactionMessageWithSigners(message);
	const signature = getSignatureFromTransaction(transaction);
	const started = Date.now();
	await patiently(() => rpc.sendTransaction(getBase64EncodedWireTransaction(transaction), { encoding: "base64", skipPreflight: true }).send());
	for (let attempt = 0; attempt < 240; attempt++) {
		const { value } = await patiently(() => rpc.getSignatureStatuses([signature]).send());
		const status = value[0];
		if (status && (status.confirmationStatus === "confirmed" || status.confirmationStatus === "finalized")) {
			const elapsed = Date.now() - started;
			const found = await fetchTransaction(readRpc, signature);
			const logs = found?.meta?.logMessages ?? [];
			if (status.err) {
				console.log(`${step}: FAILED ${json(status.err)} ${signature}\n${logs.slice(-12).join("\n")}`);
				throw new Error(`${step} failed`);
			}
			return { signature, elapsed, logs, units: found?.meta?.computeUnitsConsumed !== undefined ? Number(found.meta.computeUnitsConsumed) : null, fee: found?.meta?.fee !== undefined ? Number(found.meta.fee) : null };
		}
		await sleep(250);
	}
	throw new Error(`${step}: not confirmed ${signature}`);
}

export async function read(rpc, key) {
	const { value } = await patiently(() => rpc.getAccountInfo(key, { encoding: "base64", commitment: "confirmed" }).send());
	if (!value) return null;
	return { owner: value.owner, lamports: BigInt(value.lamports), data: new Uint8Array(Buffer.from(value.data[0], "base64")) };
}

export function bool(value) {
	return Uint8Array.of(value ? 1 : 0);
}

export function key(value) {
	return encoder.encode(value);
}

export function hibernal(programAddress, authority) {
	const call = (name, accounts, ...args) => ({ programAddress, accounts, data: joined(instructionDiscriminator(name), ...args) });
	const seeds = {
		config: () => pda(programAddress, "config"),
		policy: () => pda(programAddress, "policy"),
		world: () => pda(programAddress, "world"),
		mint: () => pda(programAddress, "mint"),
		resort: () => pda(programAddress, "resort"),
		block: (id) => pda(programAddress, "block", u64(id)),
		pet: (mint) => pda(programAddress, "pet", key(mint)),
		paid: (mint) => pda(programAddress, "paid", key(mint)),
	};
	const address = async (derived) => (await derived)[0];
	const delegation = async (delegated) => [
		readonly(programAddress),
		writable(await address(pda(programAddress, "buffer", key(delegated)))),
		writable(await address(pda(DELEGATION_PROGRAM, "delegation", key(delegated)))),
		writable(await address(pda(DELEGATION_PROGRAM, "delegation-metadata", key(delegated)))),
		readonly(DELEGATION_PROGRAM),
		readonly(SYSTEM_PROGRAM),
	];
	return {
		programAddress,
		seeds,
		address,
		async initialize({ admissionGroup, engine, genesisTimestamp, claimCapPerDay, resortEvery, validator, skrMint, treasury }) {
			return call("Initialize", [
				writableSigner(authority),
				writable(await address(seeds.config())),
				writable(await address(seeds.policy())),
				writable(await address(seeds.world())),
				writable(await address(seeds.mint())),
				readonly(TOKEN_PROGRAM),
				readonly(SYSTEM_PROGRAM),
			], key(admissionGroup), u64(engine), u64(genesisTimestamp), u64(claimCapPerDay), u64(resortEvery), key(validator), key(skrMint), key(treasury));
		},
		async writePolicy(offset, bytes, seal) {
			return call("WritePolicy", [
				writableSigner(authority),
				writable(await address(seeds.config())),
				writable(await address(seeds.policy())),
			], u32(offset), u32(bytes.length), bool(seal), bytes);
		},
		async createBlock(id) {
			return call("CreateBlock", [
				writableSigner(authority),
				writable(await address(seeds.config())),
				writable(await address(seeds.block(id))),
				readonly(SYSTEM_PROGRAM),
			], u32(id));
		},
		async claim(owner, mint, held) {
			return call("Claim", [
				writableSigner(owner),
				writable(await address(seeds.config())),
				readonly(mint),
				readonly(held),
				writable(await address(seeds.pet(mint))),
				writable(await address(seeds.paid(mint))),
				readonly(SYSTEM_PROGRAM),
			]);
		},
		async delegatePet(payer, mint) {
			const pet = await address(seeds.pet(mint));
			return call("DelegatePet", [writableSigner(payer), readonly(await address(seeds.config())), writable(pet), ...(await delegation(pet))]);
		},
		async delegateBlock(id) {
			const block = await address(seeds.block(id));
			return call("DelegateBlock", [writableSigner(authority), readonly(await address(seeds.config())), writable(block), ...(await delegation(block))]);
		},
		async delegateWorld() {
			const world = await address(seeds.world());
			return call("DelegateWorld", [writableSigner(authority), readonly(await address(seeds.config())), writable(world), ...(await delegation(world))]);
		},
		async delegateResort() {
			const resort = await address(seeds.resort());
			return call("DelegateResort", [writableSigner(authority), readonly(await address(seeds.config())), writable(resort), ...(await delegation(resort))]);
		},
		async place(id, mint) {
			return call("Place", [
				writableSigner(authority),
				readonly(await address(seeds.config())),
				writable(await address(seeds.world())),
				writable(await address(seeds.block(id))),
				writable(await address(seeds.pet(mint))),
			]);
		},
		async talk(owner, mint) {
			return call("Talk", [signer(owner), writable(await address(seeds.pet(mint)))]);
		},
		async bank(owner, mint) {
			return call("Bank", [signer(owner), writable(await address(seeds.pet(mint)))]);
		},
		async commitPet(owner, mint) {
			return call("CommitPet", [signer(owner), writable(await address(seeds.pet(mint))), writable(MAGIC_CONTEXT), readonly(MAGIC_PROGRAM)]);
		},
		async claimReward(owner, mint, destination) {
			return call("ClaimReward", [
				writableSigner(owner),
				readonly(await address(seeds.config())),
				readonly(await address(seeds.pet(mint))),
				writable(await address(seeds.paid(mint))),
				writable(await address(seeds.mint())),
				writable(destination),
				readonly(TOKEN_PROGRAM),
				readonly(SYSTEM_PROGRAM),
			]);
		},
		async receipt(mint, nonce) {
			return await address(pda(programAddress, "receipt", key(await address(seeds.pet(mint))), u64(nonce)));
		},
		async buy(owner, mint, { item, tier, nonce, skrMint, source, treasury, tokenProgram = TOKEN_PROGRAM }) {
			const receipt = await this.receipt(mint, nonce);
			const delegated = await delegation(receipt);
			return call("Buy", [
				writableSigner(owner),
				readonly(await address(seeds.config())),
				readonly(await address(seeds.pet(mint))),
				readonly(skrMint),
				writable(source),
				writable(treasury),
				writable(receipt),
				...delegated.slice(0, 5),
				readonly(tokenProgram),
				readonly(SYSTEM_PROGRAM),
			], u8(item), u8(tier), u64(nonce));
		},
		async consume(mint, nonce) {
			return call("Consume", [
				writable(await this.receipt(mint, nonce)),
				writable(await address(seeds.pet(mint))),
				readonly(await address(seeds.world())),
			]);
		},
		async resortBegin(measure, count) {
			return call("ResortBegin", [signer(authority), readonly(await address(seeds.config())), writable(await address(seeds.world())), writable(await address(seeds.resort()))], u8(measure), u64(count));
		},
		async resortClear(id, members) {
			return call("ResortClear", [
				signer(authority),
				readonly(await address(seeds.config())),
				readonly(await address(seeds.world())),
				writable(await address(seeds.resort())),
				writable(await address(seeds.block(id))),
				...members.map((member) => writable(member)),
			]);
		},
		async resortAssign(id, previousId, offset, pets) {
			return call("ResortAssign", [
				signer(authority),
				readonly(await address(seeds.config())),
				writable(await address(seeds.resort())),
				writable(await address(seeds.block(id))),
				readonly(await address(seeds.block(previousId))),
				...pets.map((pet) => writable(pet)),
			], u64(offset));
		},
		async resortFinish() {
			return call("ResortFinish", [signer(authority), readonly(await address(seeds.config())), writable(await address(seeds.world())), readonly(await address(seeds.resort()))]);
		},
	};
}
