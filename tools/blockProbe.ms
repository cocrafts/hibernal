@include("runtime/solana/solana.h");
import {
	Account,
	Bytes,
	Instruction,
	ProgramError,
	Pubkey,
	Seeds,
	account,
	accountCount,
	signerAccount,
	instructionData,
	programId,
	createProgramAccount,
	clock,
	failWith,
	logU64,
} from "std/solana";
import {
	DelegationAccounts,
	DelegationConfig,
	anyValidator,
	onValidator,
	delegate,
	delegationProgram,
	commit,
	commitAndUndelegate,
	undelegate,
	isUndelegateCallback,
} from "std/solana/magicblock";
import { BLOCK_SLOTS, FightRecord, GlobalConfig, Listing, Pet, checkPolicy } from "../rules/index";
import { POLICY_BLOB_BYTES, PolicyBlob, buffersMatchPolicy } from "./policyBench";
import { ActContext, BlockPets, actTicked, buffersMatchRules, digestOf } from "./actBench";
import { BLOCK_KIND, BLOCK_VERSION, Block, Grace, Identity } from "./blockLayout";

const POLICY_ACCOUNT: int32 = 0;
const CONTEXT_ACCOUNT: int32 = 1;
const CONFIG_ACCOUNT: int32 = 2;
const WILDS_ACCOUNT: int32 = 3;
const BLOCK_ACCOUNT: int32 = 4;
const HOLDER_IDS: uint64 = 5;
const MINT_BYTES: uint64 = 82;
const PAID_BYTES: uint64 = 24;
const PAID_TOTAL: uint64 = 0;
const PAID_DAY: uint64 = 8;
const PAID_TODAY: uint64 = 16;
const HBRN_DECIMALS: uint8 = 6;
const CLAIM_CAP_PER_DAY: uint64 = 10_000_000;
const SECONDS_PER_DAY: int64 = 86_400;
const INITIALIZE_MINT: uint8 = 20;
const MINT_TO: uint8 = 7;

enum ProbeError {
	Layout,
	Policy,
	Unticked,
	WrongHolder,
	WrongLedger,
	WrongMint,
	WrongTokenProgram,
	NotTheOwner,
	BlockNotOurs,
	NoSuchSlot,
}

function failed(error: ProbeError): ProgramError {
	return ProgramError.custom(200 + (error as uint32));
}

function tokenProgram(): Pubkey {
	return {
		word0: 0x93a165d7e1f6dd06,
		word1: 0xac79ebce46e1cbd9,
		word2: 0x91375b5fed85b41c,
		word3: 0xa900ff7e85f58c3a,
	};
}

function holderSeeds(id: uint8): Seeds {
	return Seeds.empty(2).addText("block").addU8(id);
}

function paidSeeds(slot: uint8): Seeds {
	return Seeds.empty(2).addText("paid").addU8(slot);
}

function mintSeeds(): Seeds {
	return Seeds.empty(1).addText("mint");
}

function bumpOf(holder: Account, seeds: Seeds, error: ProbeError): Result<uint8, ProgramError> {
	const expected = try seeds.findProgramAddress(programId());
	if (!expected.key.equals(holder.key())) { return Result.err(failed(error)); }
	return Result.ok(expected.bump);
}

function sized(holder: Account, bytes: uint64): Result<uint64, ProgramError> {
	if (holder.dataLength() != bytes) { return Result.err(failed(ProbeError.Layout)); }
	return Result.ok(holder.data().address);
}

function blockIn(holder: Account): Result<Ptr<Block>, ProgramError> {
	const block = (try sized(holder, sizeof Block as uint64)) as Ptr<Block>;
	if (block.kind != BLOCK_KIND || block.version != BLOCK_VERSION) { return Result.err(failed(ProbeError.Layout)); }
	return Result.ok(block);
}

function slotIn(data: Bytes, offset: uint64): Result<int32, ProgramError> {
	const slot = try data.readU64(offset);
	if (slot >= BLOCK_SLOTS as uint64) { return Result.err(failed(ProbeError.NoSuchSlot)); }
	return Result.ok(slot as int32);
}

function loaded(raw: Ptr<GlobalConfig>): GlobalConfig {
	return {
		genesisTimestamp: raw.genesisTimestamp,
		rewardPerWorkPower: raw.rewardPerWorkPower,
		rewardEpoch: raw.rewardEpoch,
		totalWorkPower: raw.totalWorkPower,
		recycledPending: raw.recycledPending,
		protocolPending: raw.protocolPending,
		burned: raw.burned,
		livingPets: raw.livingPets,
		floorSlots: raw.floorSlots,
	};
}

function stored(raw: Ptr<GlobalConfig>, global: GlobalConfig): void {
	raw.genesisTimestamp = global.genesisTimestamp;
	raw.rewardPerWorkPower = global.rewardPerWorkPower;
	raw.rewardEpoch = global.rewardEpoch;
	raw.totalWorkPower = global.totalWorkPower;
	raw.recycledPending = global.recycledPending;
	raw.protocolPending = global.protocolPending;
	raw.burned = global.burned;
	raw.livingPets = global.livingPets;
	raw.floorSlots = global.floorSlots;
}

function contextAt(): Result<ActContext, ProgramError> {
	const holder = try account(CONTEXT_ACCOUNT);
	const raw = (try sized(holder, sizeof ActContext as uint64)) as Ptr<ActContext>;
	return Result.ok({
		epoch: raw.epoch,
		round: raw.round,
		actor: raw.actor,
		persona: raw.persona,
		robber: raw.robber,
		market: raw.market,
		economySeed: raw.economySeed,
		trader: raw.trader,
	});
}

function ticked(this context: ActContext, pets: Span<Pet>): boolean {
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		if (pets[slot].alive && pets[slot].lastTickEpoch < context.epoch) { return false; }
	}
	return true;
}

function layoutLogged(): Result<uint64, ProgramError> {
	logU64(sizeof Block as uint64);
	logU64(sizeof Pet as uint64);
	logU64(sizeof Identity as uint64);
	logU64(sizeof Grace as uint64);
	logU64(sizeof FightRecord as uint64);
	logU64(sizeof Listing as uint64);
	logU64(sizeof GlobalConfig as uint64);
	logU64(sizeof ActContext as uint64);
	logU64(sizeof BlockPets as uint64);
	return Result.ok(sizeof Block as uint64);
}

function acted(engine: uint64): Result<uint64, ProgramError> {
	const policyHolder = try account(POLICY_ACCOUNT);
	const blob = (try sized(policyHolder, POLICY_BLOB_BYTES as uint64)) as Ptr<PolicyBlob>;
	if (!buffersMatchPolicy() || !buffersMatchRules()) { return Result.err(failed(ProbeError.Layout)); }
	if (!checkPolicy(blob.bytes, engine).ok) { return Result.err(failed(ProbeError.Policy)); }
	const context = try contextAt();
	const config = (try sized(try account(CONFIG_ACCOUNT), sizeof GlobalConfig as uint64)) as Ptr<GlobalConfig>;
	const wilds = (try sized(try account(WILDS_ACCOUNT), sizeof BlockPets as uint64)) as Ptr<BlockPets>;
	const block = try blockIn(try account(BLOCK_ACCOUNT));
	if (!context.ticked(block.pets)) { return Result.err(failed(ProbeError.Unticked)); }
	const outcome = context.actTicked(blob.bytes, block.pets, wilds.pets, loaded(config));
	stored(config, outcome.global);
	logU64(outcome.choice.economy as uint64);
	logU64(outcome.choice.node as uint64);
	logU64(outcome.choice.attack as uint64);
	return Result.ok(0);
}

function digestLogged(): Result<uint64, ProgramError> {
	const config = (try sized(try account(CONFIG_ACCOUNT), sizeof GlobalConfig as uint64)) as Ptr<GlobalConfig>;
	const block = try blockIn(try account(BLOCK_ACCOUNT));
	const digest = digestOf(block.pets, loaded(config));
	logU64(digest);
	return Result.ok(digest);
}

function gifted(data: Bytes): Result<uint64, ProgramError> {
	const holder = try account(0);
	if (!holder.isOwnedBy(programId())) { return Result.err(failed(ProbeError.BlockNotOurs)); }
	const block = try blockIn(holder);
	const slot = try slotIn(data, 8);
	const amount = try data.readU64(16);
	const before = block.pets[slot].giftOwed;
	if (amount > 0xffffffffffffffff - before) { return Result.err(ProgramError.arithmeticOverflow()); }
	block.pets[slot].giftOwed = before + amount;
	logU64(block.pets[slot].giftOwed);
	return Result.ok(0);
}

function idIn(data: Bytes): Result<uint8, ProgramError> {
	const id = try data.readU64(8);
	if (id >= HOLDER_IDS) { return Result.err(ProgramError.invalidArgument()); }
	return Result.ok(id as uint8);
}

function initialized(data: Bytes): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const holder = try account(1);
	const id = try idIn(data);
	const size = try data.readU64(16);
	const bump = try bumpOf(holder, holderSeeds(id), ProbeError.WrongHolder);
	if (holder.lamports() == 0) {
		const _created = try createProgramAccount(payer, holder, size, programId(), holderSeeds(id).withBump(bump));
	}
	return Result.ok(holder.dataLength());
}

function written(data: Bytes): Result<uint64, ProgramError> {
	const _payer = try signerAccount(0);
	const holder = try account(1);
	const id = try idIn(data);
	const _bump = try bumpOf(holder, holderSeeds(id), ProbeError.WrongHolder);
	if (!holder.isOwnedBy(programId())) { return Result.err(ProgramError.illegalOwner()); }
	const offset = try data.readU64(16);
	const chunk = try data.range(24, data.length - 24);
	const target = try holder.data().range(offset, chunk.length);
	return target.copyFrom(chunk);
}

function delegated(data: Bytes): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const systemProgram = try account(1);
	const holder = try account(2);
	const ownerProgram = try account(3);
	const buffer = try account(4);
	const delegationRecord = try account(5);
	const delegationMetadata = try account(6);
	const id = try idIn(data);
	const bump = try bumpOf(holder, holderSeeds(id), ProbeError.WrongHolder);
	let config = DelegationConfig.anyValidator();
	if (accountCount() > 8) {
		const validator = try account(8);
		config = DelegationConfig.onValidator(validator.key());
	}
	const accounts: DelegationAccounts = {
		payer: payer,
		delegated: holder,
		ownerProgram: ownerProgram,
		buffer: buffer,
		delegationRecord: delegationRecord,
		delegationMetadata: delegationMetadata,
		systemProgram: systemProgram,
	};
	return delegate(accounts, holderSeeds(id), bump, config);
}

function committed(undelegating: boolean): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const holder = try account(1);
	const magicContext = try account(3);
	if (undelegating) { return commitAndUndelegate(payer, holder, magicContext); }
	return commit(payer, holder, magicContext);
}

function undelegated(data: Bytes): Result<uint64, ProgramError> {
	const holder = try account(0);
	const buffer = try account(1);
	const payer = try account(2);
	return undelegate(holder, buffer, payer, programId(), data);
}

function mintCreated(): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const mint = try account(1);
	const tokens = try account(3);
	if (!tokens.key().equals(tokenProgram())) { return Result.err(failed(ProbeError.WrongTokenProgram)); }
	const bump = try bumpOf(mint, mintSeeds(), ProbeError.WrongMint);
	const _created = try createProgramAccount(payer, mint, MINT_BYTES, tokenProgram(), mintSeeds().withBump(bump));
	return Instruction.forProgram(tokenProgram(), 1, 35)
		.addWritable(mint)
		.appendU8(INITIALIZE_MINT)
		.appendU8(HBRN_DECIMALS)
		.appendPubkey(mint.key())
		.appendU8(0)
		.invoke();
}

function ledgerCreated(data: Bytes): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const paid = try account(1);
	const slot = try slotIn(data, 8);
	const bump = try bumpOf(paid, paidSeeds(slot as uint8), ProbeError.WrongLedger);
	return createProgramAccount(payer, paid, PAID_BYTES, programId(), paidSeeds(slot as uint8).withBump(bump));
}

function claimed(data: Bytes): Result<uint64, ProgramError> {
	const owner = try signerAccount(0);
	const holder = try account(1);
	const paid = try account(2);
	const mint = try account(3);
	const destination = try account(4);
	const tokens = try account(5);
	const slot = try slotIn(data, 8);
	const _blockBump = try bumpOf(holder, holderSeeds(BLOCK_ACCOUNT as uint8), ProbeError.WrongHolder);
	if (!holder.isOwnedBy(programId()) && !holder.isOwnedBy(Pubkey.delegationProgram())) {
		return Result.err(failed(ProbeError.BlockNotOurs));
	}
	const block = try blockIn(holder);
	const _paidBump = try bumpOf(paid, paidSeeds(slot as uint8), ProbeError.WrongLedger);
	if (!paid.isOwnedBy(programId())) { return Result.err(failed(ProbeError.WrongLedger)); }
	const mintBump = try bumpOf(mint, mintSeeds(), ProbeError.WrongMint);
	if (!tokens.key().equals(tokenProgram())) { return Result.err(failed(ProbeError.WrongTokenProgram)); }
	if (!block.identities[slot].owner.equals(owner.key())) { return Result.err(failed(ProbeError.NotTheOwner)); }
	const giftTotal = block.pets[slot].giftOwed;
	const paidTotal = try paid.data().readU64(PAID_TOTAL);
	const owed = giftTotal > paidTotal ? giftTotal - paidTotal : 0;
	const today = (clock().unixTimestamp / SECONDS_PER_DAY) as uint64;
	const paidDay = try paid.data().readU64(PAID_DAY);
	const storedToday = try paid.data().readU64(PAID_TODAY);
	const paidToday = paidDay == today ? storedToday : 0;
	const room = CLAIM_CAP_PER_DAY - paidToday;
	const amount = owed < room ? owed : room;
	logU64(giftTotal);
	logU64(paidTotal);
	logU64(amount);
	if (amount == 0) { return Result.ok(0); }
	const _minted = try Instruction.forProgram(tokenProgram(), 3, 9)
		.addWritable(mint)
		.addWritable(destination)
		.addReadonlySigner(mint)
		.appendU8(MINT_TO)
		.appendU64(amount)
		.invokeSigned(mintSeeds().withBump(mintBump));
	const _total = try paid.data().writeU64(PAID_TOTAL, paidTotal + amount);
	const _day = try paid.data().writeU64(PAID_DAY, today);
	return paid.data().writeU64(PAID_TODAY, paidToday + amount);
}

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	if (isUndelegateCallback(data)) { return undelegated(data); }
	const discriminator = try data.readU64(0);
	return match (discriminator) {
		0 => layoutLogged(),
		1 => {
			const engine = try data.readU64(8);
			return acted(engine);
		},
		2 => digestLogged(),
		3 => written(data),
		4 => gifted(data),
		5 => mintCreated(),
		6 => ledgerCreated(data),
		7 => initialized(data),
		8 => delegated(data),
		9 => committed(false),
		10 => committed(true),
		11 => claimed(data),
		_ => Result.err(ProgramError.invalidInstructionData()),
	};
}

function main(): void {
	const outcome = dispatch();
	if (!outcome.ok) { failWith(outcome.error); }
}

main();
