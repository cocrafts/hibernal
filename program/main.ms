import { ProgramError, failWith, selectInstruction } from "std/solana";
import { instruction } from "std/solana/macro";
import { Op } from "./layout";
import { createBlock, delegateVrfPayer, initialize, writePolicy } from "./admin";
import { claim, delegateBlock, delegatePet, delegateWorld, place, processUndelegation } from "./admission";
import { seeded, step } from "./day";
import { bank, talk } from "./owner";
import { buy, consume } from "./shop";
import { delegateResort, resortAssign, resortBegin, resortClear, resortFinish } from "./resort";
import { claimReward, commitPet } from "./payout";

export function dispatch(): Result<uint64, ProgramError> {
	return match (try instruction<Op>()) {
		Op.Initialize => initialize(),
		Op.WritePolicy => writePolicy(),
		Op.CreateBlock => createBlock(),
		Op.Claim => claim(),
		Op.DelegatePet => delegatePet(),
		Op.DelegateBlock => delegateBlock(),
		Op.DelegateWorld => delegateWorld(),
		Op.ProcessUndelegation => processUndelegation(),
		Op.Place => place(),
		Op.Step => step(),
		Op.Seeded => seeded(),
		Op.Talk => talk(),
		Op.Bank => bank(),
		Op.Buy => buy(),
		Op.Consume => consume(),
		Op.ResortBegin => resortBegin(),
		Op.ResortClear => resortClear(),
		Op.ResortAssign => resortAssign(),
		Op.ResortFinish => resortFinish(),
		Op.DelegateResort => delegateResort(),
		Op.DelegateVrfPayer => delegateVrfPayer(),
		Op.CommitPet => commitPet(),
		Op.ClaimReward => claimReward(),
	};
}

export function entry(): void {
	const result = dispatch();
	if (!result.ok) { failWith(result.error); }
}

when (!testBuild) {
	entry();
}
