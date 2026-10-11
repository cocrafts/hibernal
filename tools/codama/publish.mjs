import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { rootNodeFromAnchor } from "@codama/nodes-from-anchor";
import { createFromRoot } from "codama";

const STAGE = process.env.STAGE ?? "convert";
const ANCHOR_IDL = process.env.ANCHOR_IDL ?? "out/idl/hibernal.json";
const CODAMA_IDL = process.env.CODAMA_IDL ?? "out/idl/hibernal.codama.json";
const PUBLISHED_IDL = process.env.PUBLISHED_IDL ?? "out/idl/hibernal.published.json";
const programAddress = process.argv[2];
if (!programAddress || !["convert", "publish", "fetch"].includes(STAGE)) {
	console.log("usage: STAGE=convert|publish|fetch node tools/codama/publish.mjs <program id>  (BASE_RPC from env; KEYPAIR = the program's upgrade authority, default ~/.config/solana/id.json)");
	process.exit(2);
}
const cli = new URL("./node_modules/.bin/program-metadata", import.meta.url).pathname;
const rpc = process.env.BASE_RPC ?? "https://api.devnet.solana.com";
const keypair = process.env.KEYPAIR ?? `${process.env.HOME}/.config/solana/id.json`;
const websocket = process.env.BASE_WS ?? rpc.replace(/^http/, "ws").replace(/:(\d+)$/, (_, port) => `:${Number(port) + 1}`);
const home = mkdtempSync(join(tmpdir(), "programMetadata-"));
mkdirSync(join(home, ".config", "solana", "cli"), { recursive: true });
writeFileSync(join(home, ".config", "solana", "cli", "config.yml"), `json_rpc_url: "${rpc}"\nwebsocket_url: "${websocket}"\nkeypair_path: "${keypair}"\n`);
const run = (args) => execFileSync(cli, ["--rpc", rpc, ...args], { stdio: "inherit", env: { ...process.env, HOME: home } });

if (STAGE === "fetch") {
	run(["fetch", "idl", programAddress]);
	process.exit(0);
}
const anchorIdl = JSON.parse(readFileSync(ANCHOR_IDL, "utf8"));
anchorIdl.address = programAddress;
const root = rootNodeFromAnchor(anchorIdl);
const { program } = root;
writeFileSync(CODAMA_IDL, createFromRoot(root).getJson());
console.log(`${CODAMA_IDL}: program ${program.publicKey}, ${program.instructions.length} instructions, ${program.accounts.length} accounts, ${program.definedTypes.length} types, ${program.errors?.length ?? 0} errors, ${program.pdas?.length ?? 0} PDAs`);
if (STAGE === "publish") {
	writeFileSync(PUBLISHED_IDL, JSON.stringify(anchorIdl));
	run(["--keypair", keypair, "write", "idl", programAddress, PUBLISHED_IDL]);
}
