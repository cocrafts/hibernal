import { Discriminator, ProgramError, Pubkey, instructionDiscriminator, unchecked } from "std/solana";
import { HostAccount, run, setClock } from "std/solana/host";
import { BlockSlot, GlobalConfig, Pet, Region, born } from "../../rules/index";
import { HibernalError, PetAccount, hibernalError, petSeeds } from "../layout";
import { entry } from "../main";


function keyOf(seed: uint8): Pubkey {
	let key = Pubkey.zero();
	key.bytes[0] = seed;
	key.bytes[1] = 0x5a;
	return key;
}

function programKey(): Pubkey { return keyOf(200); }

const owner = keyOf(1);
const stranger = keyOf(2);
const mint = keyOf(3);

const stagedPets: PetAccount[] = [];
const seenPets: PetAccount[] = [];

function overlay(): uint64 {
	const holder = unchecked(0);
	return holder.ok ? holder.value.data().address + 8 : 0;
}

function stagePetEntry(): void {
	const at = overlay() as Ptr<PetAccount>;
	at[] = stagedPets[stagedPets.length - 1];
}

function seePetEntry(): void {
	const at = overlay() as Ptr<PetAccount>;
	seenPets.push(at[]);
}

function blankData(tag: Discriminator, size: uint64): uint8[] {
	const bytes: uint8[] = [];
	for (let i = 0; i < 8; i++) { bytes.push(tag.bytes[i]); }
	for (let offset: uint64 = 0; offset < size; offset++) { bytes.push(0); }
	return bytes;
}

function scratch(data: uint8[]): HostAccount[] {
	return [{
		key: keyOf(250),
		owner: programKey(),
		lamports: 1,
		data: data,
		signer: false,
		writable: true,
		executable: false,
	}];
}

function petBytes(record: PetAccount): uint8[] {
	stagedPets.push(record);
	const holder = scratch(blankData(PetAccount.discriminator(), sizeof(PetAccount) as uint64));
	run(programKey(), holder, [], stagePetEntry);
	return holder[0].data;
}

function petRecordOf(data: uint8[]): PetAccount {
	run(programKey(), scratch(data), [], seePetEntry);
	return seenPets[seenPets.length - 1];
}

function petKey(): Pubkey {
	const found = petSeeds(mint).findProgramAddress(programKey());
	return found.ok ? found.value.key : Pubkey.zero();
}

function petBump(): uint8 {
	const found = petSeeds(mint).findProgramAddress(programKey());
	return found.ok ? found.value.bump : 0;
}

function newborn(): Pet {
	return Pet.born(0, BlockSlot.First, Region.Worker, 1, GlobalConfig.genesis(0)).pet;
}

function record(pet: Pet): PetAccount {
	return {
		owner: owner,
		mint: mint,
		ordinal: 0,
		persona: 0,
		bump: petBump(),
		pad: 0,
		claimedEpoch: 1,
		diedEpoch: 0,
		pet: pet,
	};
}

function petHolder(pet: Pet): HostAccount {
	return {
		key: petKey(),
		owner: programKey(),
		lamports: 1000000,
		data: petBytes(record(pet)),
		signer: false,
		writable: true,
		executable: false,
	};
}

function signerOf(key: Pubkey): HostAccount {
	return {
		key: key,
		owner: Pubkey.systemProgram(),
		lamports: 1000000000,
		data: [],
		signer: true,
		writable: false,
		executable: false,
	};
}

function instructionData(name: string): uint8[] {
	const discriminator = instructionDiscriminator(name);
	const bytes: uint8[] = [];
	for (let i = 0; i < 8; i++) { bytes.push(discriminator.bytes[i]); }
	return bytes;
}

function petOf(holder: HostAccount): Pet {
	return petRecordOf(holder.data).pet;
}

function code(error: HibernalError): uint64 {
	return hibernalError(error).code;
}

function noon(seconds: int64): void {
	setClock({ slot: 1, epochStartTimestamp: 0, epoch: 1, leaderScheduleEpoch: 1, unixTimestamp: seconds });
}

test "only the pet's owner can act on it" {
	const accounts = [signerOf(stranger), petHolder({ ...newborn(), hearts: 1 })];
	assert run(programKey(), accounts, instructionData("Talk"), entry).result == ProgramError.constraintHasOne().code;
	const unsigned: HostAccount[] = [{ ...signerOf(owner), signer: false }, petHolder(newborn())];
	assert run(programKey(), unsigned, instructionData("Talk"), entry).result ==
		ProgramError.accountNotSigner().code;
}

test "talking bonds twice a day" {
	const accounts = [signerOf(owner), petHolder(newborn())];
	assert run(programKey(), accounts, instructionData("Talk"), entry).result == 0;
	assert run(programKey(), accounts, instructionData("Talk"), entry).result == 0;
	assert petOf(accounts[1]).talksToday == 2;
	assert run(programKey(), accounts, instructionData("Talk"), entry).result == code(HibernalError.TalkedOut);
}

test "banking moves half the harvest to the burrow, then cools down" {
	noon(1_000_000);
	const rich: Pet = { ...newborn(), harvest: 1000, burrow: 0 };
	const accounts = [signerOf(owner), petHolder(rich)];
	assert run(programKey(), accounts, instructionData("Bank"), entry).result == 0;
	const banked = petOf(accounts[1]);
	assert banked.harvest == 500 && banked.burrow == 500 && banked.ownerBankedAt == 1_000_000;
	assert run(programKey(), accounts, instructionData("Bank"), entry).result == code(HibernalError.CoolingDown);
	const empty = [signerOf(owner), petHolder({ ...newborn(), harvest: 0 })];
	assert run(programKey(), empty, instructionData("Bank"), entry).result == code(HibernalError.EmptyHarvest);
}

test "a dead pet cannot be talked to" {
	const accounts = [signerOf(owner), petHolder({ ...newborn(), alive: false, hearts: 0 })];
	assert run(programKey(), accounts, instructionData("Talk"), entry).result == code(HibernalError.Dead);
}
