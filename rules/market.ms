import { BPS, HBRN_UNIT } from "./units";
import { Region } from "./stats";
import { BlockSlot, Pet, GlobalConfig } from "./layout";
import { TalentGrade, TalentKind } from "./talent";
import {
	Gear,
	GearSlot,
	Item,
	ItemSkill,
	ITEM_BONUS_PERCENT,
	ITEM_WEAR_MAX,
	gradeBonusBps,
	wornBy,
	minted,
	mintPrice,
	sellPrice,
	score,
	isEmpty,
	at,
	with,
	none,
	bare,
} from "./items";
import { PetAndGlobal, withWorkPower, born, genesis } from "./life";

export const MARKET_FEE_BPS: int32 = 500;
export const LISTING_DAYS: uint64 = 3;
export const FAIR_SCORE_BPS: int32 = 360 * ITEM_BONUS_PERCENT / 100;

export struct Listing {
	item: Item;
	price: uint64;
	seller: uint32;
	sellerBorn: uint64;
	listedEpoch: uint64;
}

export struct Listed {
	pet: Pet;
	global: GlobalConfig;
	listing: Listing;
}

export struct Purchase {
	buyer: Pet;
	global: GlobalConfig;
	proceeds: uint64;
}

export enum MarketError {
	Dead,
	NoSpareItem,
	OwnListing,
	NotWanted,
	Broke,
}

export function focusStat(this pet: Pet): TalentKind {
	if (pet.forage >= pet.might && pet.forage >= pet.grit) { return TalentKind.Forage; }
	return pet.might >= pet.grit ? TalentKind.Might : TalentKind.Grit;
}

export function usefulness(this item: Item, focus: TalentKind): int32 {
	if (item.isEmpty()) { return -1; }
	return item.stat == (focus as uint8) ? item.score() : 0;
}

export function listPrice(this item: Item): uint64 {
	const price = mintPrice(item.level as int32);
	return price * (item.score() as uint64) / (FAIR_SCORE_BPS as uint64);
}

export function spareSlot(this gear: Gear, focus: TalentKind): Result<GearSlot, MarketError> {
	let found = false;
	let best = GearSlot.Head;
	for (let ordinal = 0; ordinal <= (GearSlot.Feet as int32); ordinal++) {
		const slot = ordinal as GearSlot;
		const item = gear.at(slot);
		if (item.usefulness(focus) != 0) { continue; }
		if (!found || item.score() > gear.at(best).score()) {
			best = slot;
			found = true;
		}
	}
	if (!found) { return Result.err(MarketError.NoSpareItem); }
	return Result.ok(best);
}

export function replacedSlot(this gear: Gear, focus: TalentKind): GearSlot {
	let least = GearSlot.Head;
	for (let ordinal = 1; ordinal <= (GearSlot.Feet as int32); ordinal++) {
		const slot = ordinal as GearSlot;
		if (gear.at(slot).usefulness(focus) < gear.at(least).usefulness(focus)) { least = slot; }
	}
	return least;
}

export function listingGain(this pet: Pet, listing: Listing): int32 {
	const focus = pet.focusStat();
	if (listing.item.stat != (focus as uint8)) { return 0; }
	const replaced = pet.gear.at(pet.gear.replacedSlot(focus));
	return listing.item.score() - Math.max(replaced.usefulness(focus), 0);
}

export function listedItem(
	this pet: Pet,
	global: GlobalConfig,
	seller: uint32,
	epoch: uint64,
): Result<Listed, MarketError> {
	if (!pet.alive) { return Result.err(MarketError.Dead); }
	const slot = try pet.gear.spareSlot(pet.focusStat());
	const item = pet.gear.at(slot);
	const bare: Pet = { ...pet, gear: pet.gear.with(slot, Item.none()) };
	return Result.ok({
		pet: bare,
		global: global.withWorkPower(pet.stats().rewardWeight(), bare.stats().rewardWeight()),
		listing: {
			item: item,
			price: item.listPrice(),
			seller: seller,
			sellerBorn: pet.bornEpoch,
			listedEpoch: epoch,
		},
	});
}

export function boughtListing(
	this pet: Pet,
	listing: Listing,
	buyer: uint32,
	global: GlobalConfig,
): Result<Purchase, MarketError> {
	if (!pet.alive) { return Result.err(MarketError.Dead); }
	if (listing.seller == buyer) { return Result.err(MarketError.OwnListing); }
	if (pet.listingGain(listing) <= 0) { return Result.err(MarketError.NotWanted); }
	if (pet.burrow < listing.price) { return Result.err(MarketError.Broke); }
	const slot = pet.gear.replacedSlot(pet.focusStat());
	const displaced = pet.gear.at(slot).sellPrice();
	const geared: Pet = {
		...pet,
		burrow: pet.burrow - listing.price + displaced,
		gear: pet.gear.with(slot, listing.item),
	};
	const fee = listing.price * (MARKET_FEE_BPS as uint64) / (BPS as uint64);
	const weighed = global.withWorkPower(pet.stats().rewardWeight(), geared.stats().rewardWeight());
	return Result.ok({
		buyer: geared,
		global: { ...weighed, recycledPending: weighed.recycledPending + fee },
		proceeds: listing.price - fee,
	});
}

export function expiredAt(this listing: Listing, epoch: uint64): boolean {
	return epoch >= listing.listedEpoch + LISTING_DAYS;
}

export function sellerOf(this listing: Listing, pet: Pet): boolean {
	return pet.alive && pet.bornEpoch == listing.sellerBorn;
}

export function paidFor(
	this seller: Pet,
	listing: Listing,
	proceeds: uint64,
	global: GlobalConfig,
): PetAndGlobal {
	if (!listing.sellerOf(seller)) {
		const pot = global.recycledPending + proceeds;
		return { pet: seller, global: { ...global, recycledPending: pot } };
	}
	return { pet: { ...seller, burrow: seller.burrow + proceeds }, global: global };
}

export function boughtBack(this seller: Pet, listing: Listing): Pet {
	if (!listing.sellerOf(seller)) { return seller; }
	const price = listing.item.sellPrice();
	return { ...seller, burrow: seller.burrow + price };
}

test "a pet lists its best item off its main stat at a price that follows the item's score" {
	const newborn = Pet.born(0, BlockSlot.First, Region.Worker, 0, GlobalConfig.genesis(0));
	const might = Item.minted(TalentGrade.Epic, TalentKind.Might, ItemSkill.None, 1);
	const grit = Item.minted(TalentGrade.Common, TalentKind.Grit, ItemSkill.None, 1);
	const forage = Item.minted(TalentGrade.Rare, TalentKind.Forage, ItemSkill.None, 1);
	const worker: Pet = {
		...newborn.pet,
		gear: Gear.bare()
			.with(GearSlot.Head, might)
			.with(GearSlot.Body, grit)
			.with(GearSlot.Hands, forage),
	};
	assert worker.focusStat() == TalentKind.Forage;
	const listed = worker.listedItem(newborn.global, 3, 9);
	assert listed.ok;
	if (!listed.ok) { return; }
	assert listed.value.listing.item == might;
	assert listed.value.pet.gear.head.isEmpty();
	const epic = gradeBonusBps(TalentGrade.Epic) as uint64;
	assert listed.value.listing.price == mintPrice(1) * epic / (FAIR_SCORE_BPS as uint64);
	assert listed.value.listing.listedEpoch == 9 && !listed.value.listing.expiredAt(11);
	assert listed.value.listing.expiredAt(12);
	const focused: Pet = { ...worker, gear: Gear.bare().with(GearSlot.Hands, forage) };
	const nothing = focused.listedItem(newborn.global, 3, 9);
	assert !nothing.ok;
	if (!nothing.ok) { assert nothing.error == MarketError.NoSpareItem; }
}

test "an item bought on the market never sells back to the system for more than it cost" {
	for (let ordinal = 0; ordinal <= (TalentGrade.Mythic as int32); ordinal++) {
		const fresh = Item.minted(ordinal as TalentGrade, TalentKind.Forage, ItemSkill.None, 1);
		for (let days = 0; days < ITEM_WEAR_MAX; days += 10) {
			const item = fresh.wornBy(days);
			assert item.listPrice() >= item.sellPrice();
		}
	}
}

test "a buyer takes an item on its main stat into its least useful slot and the seller is paid" {
	const newborn = Pet.born(0, BlockSlot.First, Region.Worker, 0, GlobalConfig.genesis(0));
	const rare = Item.minted(TalentGrade.Rare, TalentKind.Forage, ItemSkill.None, 1);
	const common = Item.minted(TalentGrade.Common, TalentKind.Forage, ItemSkill.None, 1);
	const legendary = Item.minted(TalentGrade.Legendary, TalentKind.Might, ItemSkill.None, 1);
	const worker: Pet = {
		...newborn.pet,
		burrow: 5000 * HBRN_UNIT,
		gear: Gear.bare()
			.with(GearSlot.Head, rare)
			.with(GearSlot.Body, rare)
			.with(GearSlot.Hands, common)
			.with(GearSlot.Feet, legendary),
	};
	assert worker.gear.replacedSlot(TalentKind.Forage) == GearSlot.Feet;
	const epic = Item.minted(TalentGrade.Epic, TalentKind.Forage, ItemSkill.None, 1);
	const listing: Listing = {
		item: epic,
		price: 900 * HBRN_UNIT,
		seller: 5,
		sellerBorn: 0,
		listedEpoch: 1,
	};
	assert worker.listingGain(listing) == gradeBonusBps(TalentGrade.Epic);
	const bought = worker.boughtListing(listing, 2, newborn.global);
	assert bought.ok;
	if (!bought.ok) { return; }
	assert bought.value.buyer.gear.feet == epic;
	const refund = worker.gear.feet.sellPrice();
	assert bought.value.buyer.burrow == worker.burrow - listing.price + refund;
	const fee = listing.price * (MARKET_FEE_BPS as uint64) / (BPS as uint64);
	assert bought.value.proceeds == listing.price - fee;
	assert bought.value.global.recycledPending == newborn.global.recycledPending + fee;
	const own = worker.boughtListing(listing, 5, newborn.global);
	if (!own.ok) { assert own.error == MarketError.OwnListing; }
	const poor: Pet = { ...worker, burrow: 1 };
	const broke = poor.boughtListing(listing, 2, newborn.global);
	if (!broke.ok) { assert broke.error == MarketError.Broke; }
	const grit = Item.minted(TalentGrade.Epic, TalentKind.Grit, ItemSkill.None, 1);
	const offStat: Listing = { ...listing, item: grit };
	const unwanted = worker.boughtListing(offStat, 2, newborn.global);
	if (!unwanted.ok) { assert unwanted.error == MarketError.NotWanted; }
	const seller: Pet = { ...newborn.pet, burrow: 10 };
	const paid = seller.paidFor(listing, 7, newborn.global);
	assert paid.pet.burrow == 17;
	const heir: Pet = { ...seller, bornEpoch: 40 };
	const orphaned = heir.paidFor(listing, 7, newborn.global);
	assert orphaned.pet.burrow == 10;
	assert orphaned.global.recycledPending == newborn.global.recycledPending + 7;
	assert seller.boughtBack(listing).burrow == 10 + epic.sellPrice();
}
