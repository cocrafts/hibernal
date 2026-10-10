import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { address, createKeyPairSignerFromPrivateKeyBytes, generateKeyPairSigner } from "@solana/kit";
import {
	SESSION_KEYS_PROGRAM,
	SYSTEM_PROGRAM,
	accountOffsets,
	cluster,
	fieldsOf,
	hibernal,
	idlAt,
	instructionDiscriminator,
	json,
	read,
	readonly,
	send,
	signer,
	u64,
	writable,
} from "./hibernal.mjs";

const [programArgument, playerArgument] = process.argv.slice(2);
if (!programArgument) {
	console.log("usage: [MASTER=out/localnet/playersMaster.hex] node tools/chain/sessionProbe.mjs <program id> [player index]  (BASE_RPC, BASE_READ_RPC, ER_RPC from env)");
	process.exit(2);
}
const { base, baseRead, ephemeral } = cluster();
const master = Buffer.from(readFileSync(process.env.MASTER ?? "out/localnet/playersMaster.hex", "utf8").trim(), "hex");
const derived = async (domain, index) =>
	await createKeyPairSignerFromPrivateKeyBytes(new Uint8Array(createHash("sha256").update(master).update(domain).update(u64(index)).digest()));
const index = Number(playerArgument ?? 0);
const owner = await derived("player", index);
const mint = (await derived("mint", index)).address;
const program = hibernal(address(programArgument), owner);
const idl = idlAt();
const petAt = accountOffsets(idl, "PetAccount").pet;
const engagedToday = fieldsOf(idl, "Pet").offsets.engaged_today;
const petKey = await program.address(program.seeds.pet(mint));
const engagedNow = async () => (await read(ephemeral, petKey)).data[petAt + engagedToday];

async function refused(step, rpc, instructions, feePayer) {
	try {
		await send(rpc, rpc, step, instructions, feePayer, 400_000, false);
		return "accepted";
	} catch (error) {
		return error.message;
	}
}

const sessionSigner = await generateKeyPairSigner();
const token = await program.sessionToken(sessionSigner.address, owner.address);
const validUntil = BigInt(Math.floor(Date.now() / 1000) + 3600);
const created = await send(base, baseRead, "create session", [await program.createSession(owner, sessionSigner, owner, validUntil, 10_000_000n)], owner, 200_000, true);
const before = await engagedNow();
const engaged = await send(ephemeral, ephemeral, "engage by session key", [await program.engage(sessionSigner, mint, token)], sessionSigner, 400_000, true);
const after = await engagedNow();
const stranger = await generateKeyPairSigner();
const borrowed = await refused("engage by a stranger holding the token", ephemeral, [await program.engage(stranger, mint, token)], sessionSigner);
const revoke = {
	programAddress: SESSION_KEYS_PROGRAM,
	accounts: [writable(token), writable(owner.address), signer(owner), readonly(SYSTEM_PROGRAM)],
	data: instructionDiscriminator("RevokeSessionV2"),
};
const revoked = await send(base, baseRead, "revoke session", [revoke], owner, 200_000, true);
console.log(json({
	pet: petKey,
	token,
	createUnits: created.units,
	engageUnits: engaged.units,
	engageFee: engaged.fee,
	engagedToday: { before, after },
	stranger: borrowed,
	revokeUnits: revoked.units,
	tokenAfterRevoke: (await read(baseRead, token)) === null ? "closed" : "still open",
}));
