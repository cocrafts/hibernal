import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { rootNodeFromAnchor } from "@codama/nodes-from-anchor";
import { createFromRoot } from "codama";

const STAGE = process.env.STAGE ?? "convert";
const ANCHOR_IDL = process.env.ANCHOR_IDL ?? "out/idl/hibernal.json";
const CODAMA_IDL = process.env.CODAMA_IDL ?? "out/idl/hibernal.codama.json";
const programAddress = process.argv[2];
if (!programAddress || !["convert", "publish", "fetch"].includes(STAGE)) {
	console.log("usage: STAGE=convert|publish|fetch node tools/codama/publish.mjs <program id>  (BASE_RPC from env; KEYPAIR = the program's upgrade authority, default ~/.config/solana/id.json)");
	process.exit(2);
}
const cli = new URL("./node_modules/.bin/program-metadata", import.meta.url).pathname;
const rpc = process.env.BASE_RPC ?? "https://api.devnet.solana.com";
const keypair = process.env.KEYPAIR ?? `${process.env.HOME}/.config/solana/id.json`;

if (STAGE === "fetch") {
	execFileSync(cli, ["--rpc", rpc, "fetch", "idl", programAddress], { stdio: "inherit" });
	process.exit(0);
}
const anchorIdl = JSON.parse(readFileSync(ANCHOR_IDL, "utf8"));
anchorIdl.address = programAddress;
const root = rootNodeFromAnchor(anchorIdl);
const { program } = root;
writeFileSync(CODAMA_IDL, createFromRoot(root).getJson());
console.log(`${CODAMA_IDL}: program ${program.publicKey}, ${program.instructions.length} instructions, ${program.accounts.length} accounts, ${program.definedTypes.length} types, ${program.errors?.length ?? 0} errors, ${program.pdas?.length ?? 0} PDAs`);
if (STAGE === "publish") {
	execFileSync(cli, ["--rpc", rpc, "--keypair", keypair, "write", "idl", programAddress, CODAMA_IDL], { stdio: "inherit" });
}
