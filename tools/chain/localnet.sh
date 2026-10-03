#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
state="${LOCALNET_DIR:-$here/out/localnet}"
magicblock="${MAGICBLOCK_VALIDATOR:-$HOME/projects/magicblock-validator}"
vrfRepository="${EPHEMERAL_VRF:-$HOME/projects/ephemeral-vrf}"
devnet="${DEVNET_RPC:-https://rpc.magicblock.app/devnet}"
wallet="${WALLET:-$HOME/.config/solana/id.json}"
l1Port="${L1_PORT:-18899}"
erPort="${ER_PORT:-17799}"

programs=(
	delegation:DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh
	committor:ComtrB2KEaWgXsW1dhr1xYL4Ht4Bjj3gXnnL6KMdABq
	hydra:eHyd5BU8QffvHi4GnXwxrK4WpS7pM2x9UGKHBWii7mf
	noop:noopb9bkMVfRPU8AsbpTUg8AQkHtKwMYZiFUjNRtMmV
	token2022:TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb
)

accounts=(
	mAGicPQYBMvcYveUZA5F5UNNwyHvfYh5xkLS2Fr1mev:validator-authority.json
	EpJnX7ueXk7fKojBymqmVuCuwyhDQsYcLVL1XMsBbvDX:validator-fees-vault.json
	7JrkjmZPprHwtuvtuGTXp9hwfGYFAQLnLeFM52kqAgXg:protocol-fees-vault.json
	8wdZfgo66d6hMMRrcYBDW2K9WtDe2mEG47ynhnYxrAFp:magic-fee-vault.json
)

dumpPrograms() {
	mkdir -p "$state/programs"
	for entry in "${programs[@]}"; do
		local name="${entry%%:*}" id="${entry#*:}"
		[[ -s "$state/programs/$name.so" ]] || solana program dump -u "$devnet" "$id" "$state/programs/$name.so" >/dev/null
	done
}

l1() {
	dumpPrograms
	local args=(--reset --ledger "$state/l1Ledger" --rpc-port "$l1Port" --mint "$(solana address -k "$wallet")" --faucet-port "$((l1Port + 1001))" --limit-ledger-size 10000000)
	local authority
	authority="$(solana address -k "$wallet")"
	for entry in "${programs[@]}"; do
		local name="${entry%%:*}" id="${entry#*:}"
		args+=(--upgradeable-program "$id" "$state/programs/$name.so" "$authority")
	done
	args+=(--upgradeable-program Vrf1RNUjXmQGjmQrQLvJHs9SNkvDJEsRVFPkfSQUwGz "$vrfRepository/target/deploy/solana_vrf_program.so" "$authority")
	for entry in "${accounts[@]}"; do
		args+=(--account "${entry%%:*}" "$magicblock/test-integration/configs/accounts/${entry#*:}")
	done
	local record
	record="$(jq -r .pubkey "$magicblock/test-integration/configs/accounts/magic-fee-vault-delegation-record.json")"
	args+=(--account "$record" "$magicblock/test-integration/configs/accounts/magic-fee-vault-delegation-record.json")
	exec solana-test-validator "${args[@]}"
}

er() {
	rm -rf "$state/erStorage"
	mkdir -p "$state"
	cat > "$state/er.toml" <<-EOF
	lifecycle = "ephemeral"
	remotes = ["http://127.0.0.1:$l1Port", "ws://127.0.0.1:$((l1Port + 1))"]
	storage = "$state/erStorage"

	[aperture]
	listen = "127.0.0.1:$erPort"

	[metrics]
	address = "127.0.0.1:$((erPort + 2201))"

	[accountsdb]
	database-size = 3_221_225_472
	index-size = 134_217_728
	reset = true

	[ledger]
	block-time = "10ms"
	reset = true

	[task-scheduler]
	reset = true
	EOF
	exec "$magicblock/target/release/magicblock-validator" "$state/er.toml"
}

seed() {
	local url="http://127.0.0.1:$l1Port" token2022=TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb
	local skr="$here/out/devSkrMint.json" treasury="$here/out/devTreasury.json" group="$state/admissionGroup.json"
	if ! spl-token display "$(solana address -k "$skr")" -u "$url" >/dev/null 2>&1; then
		spl-token create-token --decimals 6 "$skr" -u "$url" >/dev/null
		spl-token create-account "$(solana address -k "$skr")" -u "$url" >/dev/null
		spl-token mint "$(solana address -k "$skr")" 1000 -u "$url" >/dev/null
		spl-token create-account "$(solana address -k "$skr")" --owner "$(solana address -k "$treasury")" --fee-payer "$wallet" -u "$url" >/dev/null
	fi
	[[ -f "$group" ]] || solana-keygen new --no-bip39-passphrase -s -o "$group" >/dev/null
	if ! spl-token display "$(solana address -k "$group")" -u "$url" >/dev/null 2>&1; then
		spl-token create-token --program-id "$token2022" --enable-group --decimals 0 "$group" -u "$url" >/dev/null
		spl-token initialize-group "$(solana address -k "$group")" 1000 -u "$url" >/dev/null
	fi
	BASE_RPC="$url" "$here/tools/chain/devAdmission.sh" "${PETS:-20}" "$(solana address -k "$group")" > "$state/mints.txt"
	echo "group $(solana address -k "$group"), $(wc -l < "$state/mints.txt" | tr -d ' ') members, SKR $(solana address -k "$skr")"
}

base58Of() {
	python3 -c '
import json, sys
raw = bytes(json.load(open(sys.argv[1])))
alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
number, text = int.from_bytes(raw, "big"), ""
while number:
	number, digit = divmod(number, 58)
	text = alphabet[digit] + text
print("1" * (len(raw) - len(raw.lstrip(b"\0"))) + text)
' "$1"
}

vrfSetup() {
	local url="http://127.0.0.1:$l1Port" cli="$vrfRepository/target/release/vrf-cli"
	local admin identity vrfKey queue
	admin="$(base58Of "$wallet")"
	RPC_URL="$url" KEYPAIR_BASE58="$admin" "$cli" initialize
	identity="$(RPC_URL="$url" "$cli" derive-pubkey | sed -n 's/^Using signer: //p')"
	vrfKey="$(RPC_URL="$url" "$cli" derive-pubkey | sed -n 's/^Derived pubkey for .*: //p')"
	solana transfer --allow-unfunded-recipient "$identity" 10 -u "$url" >/dev/null
	RPC_URL="$url" KEYPAIR_BASE58="$admin" "$cli" add-oracle --identity "$identity" --oracle-pubkey "$vrfKey"
	RPC_URL="$url" "$cli" initialize-oracle-queue --identity "$identity" --index 1
	queue="$(RPC_URL="$url" "$cli" list-queue | sed -n 's/^Queue address: \([^,]*\), .*index: 1,.*/\1/p')"
	RPC_URL="$url" "$cli" delegate-oracle-queue --queue "$queue"
	echo "$queue" > "$state/vrfQueue.txt"
	echo "oracle $identity, VRF key $vrfKey, queue $queue"
}

vrfOracle() {
	RPC_URL="http://127.0.0.1:$erPort" WEBSOCKET_URL="ws://127.0.0.1:$((erPort + 1))" RUST_LOG="${RUST_LOG:-info}" exec "$vrfRepository/target/release/vrf-oracle"
}

hydraCranker() {
	local cranker="$here/out/hydraCranker.json"
	solana transfer --allow-unfunded-recipient "$(solana address -k "$cranker")" 1 -u "http://127.0.0.1:$l1Port" >/dev/null
	RUST_LOG="${RUST_LOG:-info}" exec "$here/out/hydra/hydra-cranker" --ephemeral --keypair "$cranker" \
		--rpc-url "http://127.0.0.1:$erPort" --ws-url "ws://127.0.0.1:$((erPort + 1))" --base-rpc-url "http://127.0.0.1:$l1Port"
}

launch() {
	local name="$1"
	nohup "${BASH_SOURCE[0]}" "$name" > "$state/$name.log" 2>&1 &
	echo $! > "$state/$name.pid"
}

waitForRpc() {
	local port="$1"
	for _ in $(seq 1 60); do
		local slot
		slot="$(curl -s -X POST -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' "http://127.0.0.1:$port" | sed -n 's/.*"result":\([0-9]*\).*/\1/p' || true)"
		[[ -n "$slot" && "$slot" -ge 2 ]] && return 0
		sleep 1
	done
	echo "no RPC on port $port after 60 s" >&2
	exit 1
}

down() {
	for name in hydra-cranker vrf-oracle er l1; do
		[[ -f "$state/$name.pid" ]] || continue
		kill "$(cat "$state/$name.pid")" 2>/dev/null || true
		while kill -0 "$(cat "$state/$name.pid")" 2>/dev/null; do sleep 0.2; done
		rm "$state/$name.pid"
	done
}

up() {
	down
	mkdir -p "$state"
	launch l1
	waitForRpc "$l1Port"
	seed
	vrfSetup
	launch er
	waitForRpc "$erPort"
	launch vrf-oracle
	launch hydra-cranker
	cat > "$state/env.sh" <<-EOF
	export BASE_RPC=http://127.0.0.1:$l1Port BASE_READ_RPC=http://127.0.0.1:$l1Port ER_RPC=http://127.0.0.1:$erPort
	export VALIDATOR=mAGicPQYBMvcYveUZA5F5UNNwyHvfYh5xkLS2Fr1mev
	export GROUP=$(solana address -k "$state/admissionGroup.json") VRF_QUEUE=$(cat "$state/vrfQueue.txt")
	EOF
	echo "localnet up: L1 $l1Port, ER $erPort; source $state/env.sh"
}

case "${1:-}" in
	up) up ;;
	down) down ;;
	l1) l1 ;;
	er) er ;;
	seed) seed ;;
	vrf-setup) vrfSetup ;;
	vrf-oracle) vrfOracle ;;
	hydra-cranker) hydraCranker ;;
	*) echo "usage: localnet.sh up|down|l1|er|seed|vrf-setup|vrf-oracle|hydra-cranker" >&2; exit 2 ;;
esac
