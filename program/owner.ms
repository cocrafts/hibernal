import {
	Mutable,
	Owned,
	ProgramError,
	Signer,
	clock,
	expectHasOne,
	pdaWithBump,
	readArgs,
	selectInstruction,
} from "std/solana";
import { accounts } from "std/solana/macro";
import {
	OwnerError,
	ownerBanked,
	talkedTo,
} from "../rules/index";
import {
	HibernalError,
	PetAccount,
	World,
	gameSecondsAt,
	hibernalError,
	petSeeds,
} from "./layout";

export struct OwnerAccounts {
	owner: Signer;
	pet: Mutable<PetAccount>;
	world: Owned<World>;
}

export function ownerFailure(error: OwnerError): ProgramError {
	const mapped: HibernalError = match (error) {
		OwnerError.Dead => HibernalError.Dead,
		OwnerError.Refused => HibernalError.Refused,
		OwnerError.Full => HibernalError.Full,
		OwnerError.FedToday => HibernalError.FedToday,
		OwnerError.TalkedOut => HibernalError.TalkedOut,
		OwnerError.Insured => HibernalError.Insured,
		OwnerError.NoSuchTier => HibernalError.Illegal,
		OwnerError.EmptyHarvest => HibernalError.EmptyHarvest,
		OwnerError.CoolingDown => HibernalError.CoolingDown,
	};
	return hibernalError(mapped);
}

function ownedPet(owner: Signer, pet: Mutable<PetAccount>): Result<Ptr<PetAccount>, ProgramError> {
	const record = pet.data();
	const _owner = try expectHasOne(record.owner, owner.key());
	const _seeds = try pdaWithBump(pet, petSeeds(record.mint), record.bump);
	return Result.ok(record);
}

export function talk(): Result<uint64, ProgramError> {
	const x = try accounts<OwnerAccounts>();
	const record = try ownedPet(x.owner, x.pet);
	const talked = record.pet.talkedTo();
	if (!talked.ok) { return Result.err(ownerFailure(talked.error)); }
	record.pet = talked.value;
	return Result.ok(0);
}

export function bank(): Result<uint64, ProgramError> {
	const x = try accounts<OwnerAccounts>();
	const record = try ownedPet(x.owner, x.pet);
	const world = x.world.data();
	const now = gameSecondsAt(world.global.genesisTimestamp, world.secondsPerDay, clock().unixTimestamp);
	const banked = record.pet.ownerBanked(now);
	if (!banked.ok) { return Result.err(ownerFailure(banked.error)); }
	record.pet = banked.value;
	return Result.ok(0);
}

