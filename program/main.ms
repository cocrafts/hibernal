import { ProgramError, failWith, selectInstruction } from "std/solana";
import { instruction } from "std/solana";
import { Op } from "./layout";
import { createBlock, delegateVrfPayer, initialize, withdrawRevenue, writePolicy } from "./admin";
import { claim, delegateBlock, delegatePet, delegateWorld, place, processUndelegation } from "./admission";
import { roundStart, seeded, startBlock, sweep, turn } from "./day";
import { bank, engage } from "./owner";
import { buy, load } from "./shop";
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
		Op.Seeded => seeded(),
		Op.Engage => engage(),
		Op.Bank => bank(),
		Op.Buy => buy(),
		Op.Load => load(),
		Op.ResortBegin => resortBegin(),
		Op.ResortClear => resortClear(),
		Op.ResortAssign => resortAssign(),
		Op.ResortFinish => resortFinish(),
		Op.DelegateResort => delegateResort(),
		Op.DelegateVrfPayer => delegateVrfPayer(),
		Op.CommitPet => commitPet(),
		Op.ClaimReward => claimReward(),
		Op.StartBlock => startBlock(),
		Op.RoundStart => roundStart(),
		Op.Turn => turn(),
		Op.Sweep => sweep(),
		Op.WithdrawRevenue => withdrawRevenue(),
	};
}

export function entry(): void {
	const result = dispatch();
	if (!result.ok) { failWith(result.error); }
}

when (!testBuild) {
	entry();
}
