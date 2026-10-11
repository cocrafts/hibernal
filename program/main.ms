import { ProgramError, failWith, securityTxt } from "std/solana";
import { instruction } from "std/solana";
import { Op } from "./layout";
import { createBlock, createHbrnMetadata, delegateVrfPayer, initialize, withdrawFund, withdrawRevenue, writePolicy } from "./admin";
import { claim, delegateBlock, delegatePet, delegateWorld, place, processUndelegation } from "./admission";
import { roundStart, seeded, startBlock, sweep, turn } from "./day";
import { bank, engage } from "./owner";
import { buy, load, payRebirth, rebirth } from "./shop";
import { delegateResort, resortAssign, resortBegin, resortClear, resortFinish } from "./resort";
import { claimReward, commitPet } from "./payout";

securityTxt({
	name: "Hibernal",
	projectUrl: "https://github.com/cocrafts/hibernal",
	contacts: "email:son@metacraft.studio",
	policy: "https://github.com/cocrafts/hibernal/blob/main/SECURITY.md",
	sourceCode: "https://github.com/cocrafts/hibernal",
});

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
		Op.CreateHbrnMetadata => createHbrnMetadata(),
		Op.WithdrawFund => withdrawFund(),
		Op.PayRebirth => payRebirth(),
		Op.Rebirth => rebirth(),
	};
}

export function entry(): void {
	const result = dispatch();
	if (!result.ok) { failWith(result.error); }
}

when (!testBuild) {
	entry();
}
