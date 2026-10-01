import { Pubkey } from "std/solana";
import { FightRecord, Listing, Pet } from "../rules/index";

export const BLOCK_KIND: uint8 = 1;
export const BLOCK_VERSION: uint8 = 1;

export struct Identity {
	admissionMint: Pubkey;
	owner: Pubkey;
	persona: uint8;
	softSignals: uint8;
}

export struct Grace {
	admissionMint: Pubkey;
	untilEpoch: uint64;
}

export struct Block {
	kind: uint8;
	version: uint8;
	livingCount: uint8;
	fightHead: uint8;
	id: uint32;
	pets: Pet[10];
	identities: Identity[10];
	graces: Grace[10];
	fights: FightRecord[32];
	listings: Listing[10];
	relationships: int8[45];
}
