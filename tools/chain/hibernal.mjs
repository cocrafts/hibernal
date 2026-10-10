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
	isSolanaError,
	pipe,
	SOLANA_ERROR__JSON_RPC__SERVER_ERROR_TRANSACTION_SIGNATURE_VERIFICATION_FAILURE,
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
export const VRF_EPHEMERAL_QUEUE = address(process.env.VRF_QUEUE ?? "5hBR571xnXppuCPveTrctfTU7tJLSN94nq7kv7FRK5Tc");
export const SLOT_HASHES = address("SysvarS1otHashes111111111111111111111111111");
export const INSTRUCTIONS_SYSVAR = address("Sysvar1nstructions1111111111111111111111111");
export const HYDRA_PROGRAM = address("eHyd5BU8QffvHi4GnXwxrK4WpS7pM2x9UGKHBWii7mf");
export const MAGIC_VAULT = address("MagicVau1t999999999999999999999999999999999");
export const METADATA_PROGRAM = address("metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s");
export const SESSION_KEYS_PROGRAM = address("KeyspM2ssCJbqUhQ4k7sveSiY4WjnYsrXkC8oDbwde5");
export const COMPUTE_UNIT_LIMIT = 1_400_000;
export const CLONE_ATTEMPTS = 5;

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

export async function patiently(call, final = () => false) {
	for (let attempt = 1; ; attempt++) {
		try {
			return await call();
		} catch (error) {
			if (attempt >= 10 || final(error)) throw error;
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

export const cloneRejected = (error) => isSolanaError(error, SOLANA_ERROR__JSON_RPC__SERVER_ERROR_TRANSACTION_SIGNATURE_VERIFICATION_FAILURE);
export const cloneCancelled = (statusError) => statusError === "CommitCancelled";

export async function send(rpc, readRpc, step, instructions, feePayer, units = COMPUTE_UNIT_LIMIT, details = true) {
	for (let attempt = 1; ; attempt++) {
		const sent = await sendOnce(rpc, readRpc, step, instructions, feePayer, units, details);
		if (!sent.cloneFailed) return sent;
		if (attempt >= CLONE_ATTEMPTS) throw new Error(`${step}: ER clone failed ${attempt} times, last ${sent.signature}`);
		console.log(`${step}: ER clone failed (${sent.cloneFailed}), signing again`);
		await sleep(1000 * attempt);
	}
}

async function sendOnce(rpc, readRpc, step, instructions, feePayer, units, details) {
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
	try {
		await patiently(() => rpc.sendTransaction(getBase64EncodedWireTransaction(transaction), { encoding: "base64", skipPreflight: true }).send(), cloneRejected);
	} catch (error) {
		if (cloneRejected(error)) return { cloneFailed: "rejected at send", signature };
		throw error;
	}
	for (let attempt = 0; attempt < 240; attempt++) {
		const { value } = await patiently(() => rpc.getSignatureStatuses([signature]).send());
		const status = value[0];
		if (status && (status.confirmationStatus === "confirmed" || status.confirmationStatus === "finalized")) {
			if (cloneCancelled(status.err)) return { cloneFailed: "CommitCancelled", signature };
			const elapsed = Date.now() - started;
			const found = details || status.err ? await fetchTransaction(readRpc, signature) : null;
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

export const MEMBER_MINT_BYTES = 310n;
const POINTER_MINT_BYTES = 234n;

export function groupDiscriminator(name) {
	return new Uint8Array(createHash("sha256").update(`spl_token_group_interface:${name}`).digest().subarray(0, 8));
}

export async function admissionTicket(authority, group, owner, mint, mintRent) {
	const [held] = await getProgramDerivedAddress({
		programAddress: ASSOCIATED_TOKEN_PROGRAM,
		seeds: [encoder.encode(owner), encoder.encode(TOKEN_2022_PROGRAM), encoder.encode(mint.address)],
	});
	return [
		{
			programAddress: SYSTEM_PROGRAM,
			accounts: [writableSigner(authority), writableSigner(mint)],
			data: joined(u32(0), u64(mintRent), u64(POINTER_MINT_BYTES), encoder.encode(TOKEN_2022_PROGRAM)),
		},
		{
			programAddress: TOKEN_2022_PROGRAM,
			accounts: [writable(mint.address)],
			data: joined(Uint8Array.of(41, 0), encoder.encode(authority.address), encoder.encode(mint.address)),
		},
		{
			programAddress: TOKEN_2022_PROGRAM,
			accounts: [writable(mint.address)],
			data: joined(Uint8Array.of(20, 0), encoder.encode(authority.address), Uint8Array.of(0)),
		},
		{
			programAddress: TOKEN_2022_PROGRAM,
			accounts: [writable(mint.address), readonly(mint.address), signer(authority), writable(group), signer(authority)],
			data: groupDiscriminator("initialize_member"),
		},
		{
			programAddress: ASSOCIATED_TOKEN_PROGRAM,
			accounts: [writableSigner(authority), writable(held), readonly(owner), readonly(mint.address), readonly(SYSTEM_PROGRAM), readonly(TOKEN_2022_PROGRAM)],
			data: Uint8Array.of(1),
		},
		{
			programAddress: TOKEN_2022_PROGRAM,
			accounts: [writable(mint.address), writable(held), signer(authority)],
			data: joined(Uint8Array.of(7), u64(1)),
		},
	];
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

export async function metadataAddress(mint) {
	return (await pda(METADATA_PROGRAM, "metadata", encoder.encode(METADATA_PROGRAM), encoder.encode(mint)))[0];
}

function metadataTexts({ name, symbol, uri }) {
	return joined(...[name, symbol, uri].flatMap((value) => [u32(text(value).length), text(value)]));
}

export async function createMetadata(mint, mintAuthority, token) {
	return {
		programAddress: METADATA_PROGRAM,
		accounts: [
			writable(await metadataAddress(mint)),
			readonly(mint),
			signer(mintAuthority),
			writableSigner(mintAuthority),
			readonly(mintAuthority.address),
			readonly(SYSTEM_PROGRAM),
		],
		data: joined(u8(33), metadataTexts(token), new Uint8Array([0, 0, 0, 0, 0, 1, 0])),
	};
}

export function hibernal(programAddress, authority) {
	const call = (name, accounts, ...args) => ({ programAddress, accounts, data: joined(instructionDiscriminator(name), ...args) });
	const seeds = {
		config: () => pda(programAddress, "config"),
		policy: () => pda(programAddress, "policy"),
		world: () => pda(programAddress, "world"),
		mint: () => pda(programAddress, "mint"),
		revenue: () => pda(programAddress, "revenue"),
		resort: () => pda(programAddress, "resort"),
		vrfPayer: () => pda(programAddress, "vrf-payer"),
		block: (id) => pda(programAddress, "block", u64(id)),
		pet: (mint) => pda(programAddress, "pet", key(mint)),
		paid: (mint) => pda(programAddress, "paid", key(mint)),
		ledger: (mint) => pda(programAddress, "ledger", key(mint)),
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
	const crankOf = async (blockId, seq) => {
		const seed = joined(u64(blockId), u64(seq), encoder.encode(programAddress).subarray(0, 16));
		return await address(pda(HYDRA_PROGRAM, "crank", seed));
	};
	return {
		programAddress,
		seeds,
		address,
		crankOf,
		async startBlock(blockId, crankSeq) {
			return call("StartBlock", [
				signer(authority),
				readonly(await address(seeds.config())),
				readonly(await address(seeds.world())),
				writable(await address(seeds.block(blockId))),
				writable(await address(seeds.vrfPayer())),
				writable(await crankOf(blockId, crankSeq)),
				writable(MAGIC_VAULT),
				readonly(MAGIC_PROGRAM),
				readonly(HYDRA_PROGRAM),
			]);
		},
		async sweep(cranks) {
			return call("Sweep", [
				writable(await address(seeds.vrfPayer())),
				writable(MAGIC_VAULT),
				readonly(MAGIC_PROGRAM),
				readonly(HYDRA_PROGRAM),
				...cranks.map((crank) => writable(crank)),
			]);
		},
		async initialize({
			admissionGroup,
			engine,
			genesisTimestamp,
			claimCapPerDay,
			resortEvery,
			validator,
			skrMint,
			treasury,
			vrfQueue = VRF_EPHEMERAL_QUEUE,
			secondsPerDay = 86_400n,
			staggerSeconds = 600n,
			slotMillis = 10n,
			turnGapSlots = 100n,
		}) {
			return call("Initialize", [
				writableSigner(authority),
				writable(await address(seeds.config())),
				writable(await address(seeds.policy())),
				writable(await address(seeds.world())),
				writable(await address(seeds.mint())),
				readonly(TOKEN_PROGRAM),
				readonly(SYSTEM_PROGRAM),
			],
				key(admissionGroup),
				u64(engine),
				u64(genesisTimestamp),
				u64(claimCapPerDay),
				u64(resortEvery),
				key(validator),
				key(skrMint),
				key(treasury),
				key(vrfQueue),
				u64(secondsPerDay),
				u64(staggerSeconds),
				u64(slotMillis),
				u64(turnGapSlots),
			);
		},
		async writePolicy(offset, bytes, seal) {
			return call("WritePolicy", [
				writableSigner(authority),
				writable(await address(seeds.config())),
				writable(await address(seeds.policy())),
			], u32(offset), bool(seal), u32(bytes.length), bytes);
		},
		async createBlock(id) {
			return call("CreateBlock", [
				writableSigner(authority),
				writable(await address(seeds.config())),
				writable(await address(seeds.block(id))),
				readonly(SYSTEM_PROGRAM),
			], u32(id));
		},
		async claim(owner, mint, held, nameId) {
			return call("Claim", [
				writableSigner(owner),
				writable(await address(seeds.config())),
				readonly(mint),
				readonly(held),
				writable(await address(seeds.pet(mint))),
				writable(await address(seeds.paid(mint))),
				readonly(SYSTEM_PROGRAM),
				writable(await address(seeds.ledger(mint))),
			], u8(nameId));
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
		async delegateVrfPayer() {
			const vrfPayer = await address(seeds.vrfPayer());
			return call("DelegateVrfPayer", [writableSigner(authority), readonly(await address(seeds.config())), writable(vrfPayer), ...(await delegation(vrfPayer))]);
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
		async engage(by, mint, session = programAddress) {
			return call("Engage", [signer(by), writable(await address(seeds.pet(mint))), readonly(await address(seeds.world())), readonly(session)]);
		},
		async sessionToken(sessionSigner, owner) {
			return await address(pda(SESSION_KEYS_PROGRAM, "session_token_v2", key(programAddress), key(sessionSigner), key(owner)));
		},
		async createSession(owner, sessionSigner, feePayer, validUntil, topUpLamports = 0n) {
			const topUp = BigInt(topUpLamports) > 0n;
			return {
				programAddress: SESSION_KEYS_PROGRAM,
				accounts: [
					writable(await this.sessionToken(sessionSigner.address, owner.address)),
					writableSigner(sessionSigner),
					writableSigner(feePayer),
					signer(owner),
					readonly(programAddress),
					readonly(SYSTEM_PROGRAM),
				],
				data: joined(
					instructionDiscriminator("CreateSessionV2"),
					topUp ? joined(u8(1), u8(1)) : u8(0),
					u8(1),
					u64(validUntil),
					topUp ? joined(u8(1), u64(topUpLamports)) : u8(0),
				),
			};
		},
		async bank(owner, mint) {
			return call("Bank", [signer(owner), writable(await address(seeds.pet(mint))), readonly(await address(seeds.world()))]);
		},
		async commitPet(owner, mint) {
			const validator = process.env.VALIDATOR ?? "MAS1Dt9qreoRMQ14YQuhg8UTZMMzDdKhmkZMECCzk57";
			const [feeVault] = await pda(DELEGATION_PROGRAM, "magic-fee-vault", encoder.encode(validator));
			return call("CommitPet", [
				signer(owner),
				writable(await address(seeds.pet(mint))),
				writable(await address(seeds.vrfPayer())),
				writable(MAGIC_CONTEXT),
				writable(feeVault),
				readonly(MAGIC_PROGRAM),
			]);
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
		async revenueVault(skrMint, tokenProgram = TOKEN_PROGRAM) {
			const revenue = await address(seeds.revenue());
			return await address(pda(ASSOCIATED_TOKEN_PROGRAM, key(revenue), key(tokenProgram), key(skrMint)));
		},
		async openRevenueVault(payer, skrMint, tokenProgram = TOKEN_PROGRAM) {
			return {
				programAddress: ASSOCIATED_TOKEN_PROGRAM,
				accounts: [
					writableSigner(payer),
					writable(await this.revenueVault(skrMint, tokenProgram)),
					readonly(await address(seeds.revenue())),
					readonly(skrMint),
					readonly(SYSTEM_PROGRAM),
					readonly(tokenProgram),
				],
				data: Uint8Array.of(1),
			};
		},
		async withdrawRevenue(amount, skrMint, destination, tokenProgram = TOKEN_PROGRAM) {
			return call("WithdrawRevenue", [
				signer(authority),
				writable(await address(seeds.config())),
				readonly(await address(seeds.revenue())),
				writable(await this.revenueVault(skrMint, tokenProgram)),
				readonly(skrMint),
				writable(destination),
				readonly(tokenProgram),
			], u64(amount));
		},
		async createHbrnMetadata(token) {
			const mint = await address(seeds.mint());
			const texts = metadataTexts(token);
			return call("CreateHbrnMetadata", [
				writableSigner(authority),
				writable(await address(seeds.config())),
				readonly(mint),
				writable(await metadataAddress(mint)),
				readonly(METADATA_PROGRAM),
				readonly(SYSTEM_PROGRAM),
			], u32(texts.length), texts);
		},
		async buy(owner, mint, { item, tier, skrMint, source, treasury, tokenProgram = TOKEN_PROGRAM }) {
			return call("Buy", [
				writableSigner(owner),
				readonly(await address(seeds.config())),
				readonly(await address(seeds.pet(mint))),
				writable(await address(seeds.ledger(mint))),
				readonly(skrMint),
				writable(source),
				writable(treasury),
				readonly(tokenProgram),
				readonly(SYSTEM_PROGRAM),
			], u8(item), u8(tier));
		},
		async load(mint) {
			return call("Load", [
				writable(await address(seeds.pet(mint))),
				readonly(await address(seeds.ledger(mint))),
			]);
		},
		async resortBegin(measure, count) {
			return call("ResortBegin", [signer(authority), readonly(await address(seeds.config())), writable(await address(seeds.world())), writable(await address(seeds.resort()))], u8(measure), u64(count));
		},
		async resortClear(id, members) {
			return call("ResortClear", [
				signer(authority),
				readonly(await address(seeds.config())),
				writable(await address(seeds.world())),
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

const PRIMITIVE_SIZES = { u8: 1, i8: 1, bool: 1, u16: 2, i16: 2, u32: 4, i32: 4, u64: 8, i64: 8, pubkey: 32 };

export function idlAt(path = process.env.IDL ?? new URL("../../out/idl/hibernal.json", import.meta.url)) {
	return JSON.parse(readFileSync(path, "utf8"));
}

function sizeOfType(idl, type) {
	if (typeof type === "string") {
		if (!(type in PRIMITIVE_SIZES)) throw new Error(`IDL type ${type} has no fixed size`);
		return PRIMITIVE_SIZES[type];
	}
	if (type.array) return sizeOfType(idl, type.array[0]) * type.array[1];
	if (type.defined) return fieldsOf(idl, type.defined.name).size;
	throw new Error(`IDL type ${JSON.stringify(type)} has no fixed size`);
}

export function fieldsOf(idl, name) {
	const declared = idl.types.find((entry) => entry.name === name);
	if (!declared) throw new Error(`IDL has no type ${name}`);
	const offsets = {};
	let offset = 0;
	for (const field of declared.type.fields) {
		offsets[field.name] = offset;
		offset += sizeOfType(idl, field.type);
	}
	return { offsets, size: offset };
}

export function accountOffsets(idl, name) {
	const { offsets, size } = fieldsOf(idl, name);
	const shifted = {};
	for (const [field, offset] of Object.entries(offsets)) shifted[field] = offset + 8;
	return { ...shifted, size: size + 8 };
}
