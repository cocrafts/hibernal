#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
rpc="${1:?usage: cranker.sh <er rpc> <er ws> <base rpc> <keypair>}"
ws="${2:?usage: cranker.sh <er rpc> <er ws> <base rpc> <keypair>}"
base="${3:?usage: cranker.sh <er rpc> <er ws> <base rpc> <keypair>}"
keypair="${4:?usage: cranker.sh <er rpc> <er ws> <base rpc> <keypair>}"
restart="${CRANKER_RESTART_SECONDS:-300}"
child=0

stop() {
	[[ $child -ne 0 ]] && kill "$child" 2>/dev/null
	wait "$child" 2>/dev/null
	exit 0
}
trap stop TERM INT

while true; do
	RUST_LOG="${RUST_LOG:-info}" "$here/out/hydra/hydra-cranker" --ephemeral --keypair "$keypair" \
		--rpc-url "$rpc" --ws-url "$ws" --base-rpc-url "$base" &
	child=$!
	elapsed=0
	while (( elapsed < restart )) && kill -0 "$child" 2>/dev/null; do
		sleep 5
		elapsed=$(( elapsed + 5 ))
	done
	if kill -0 "$child" 2>/dev/null; then
		kill "$child" 2>/dev/null
		wait "$child" 2>/dev/null
		echo "cranker.sh: restarted after ${restart}s so the cranker reloads only live cranks"
	else
		wait "$child" 2>/dev/null
		echo "cranker.sh: cranker exited after ${elapsed}s, starting it again"
	fi
done
