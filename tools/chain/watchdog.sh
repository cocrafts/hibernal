#!/usr/bin/env bash
set -euo pipefail

ROOT=${ROOT:-/opt/hibernal}
STATUS=${STATUS:-$ROOT/out/devnet/opsStatus.json}
STATE=${STATE:-/var/lib/hibernal-watchdog/problems}
CHANNEL=${CHANNEL:?discord channel id}
TOKEN_FILE=${TOKEN_FILE:-/root/.hermes/.env}
RPC=${RPC:-https://api.devnet.solana.com}
WALLET=${WALLET:-H2WrdjUvmXgc1hNqMJiZG8T1Qbc8cMNGLVmwEbjSiZKr}
STALE_SECONDS=${STALE_SECONDS:-300}
OVERDUE_SLOTS=${OVERDUE_SLOTS:-3000}
MIN_DISK_PERCENT=${MIN_DISK_PERCENT:-10}
MIN_WALLET_LAMPORTS=${MIN_WALLET_LAMPORTS:-500000000}
UNITS=${UNITS:-hibernal-admission hibernal-ops hibernal-cranker}

problems=()

for unit in $UNITS; do
	systemctl is-active --quiet "$unit" || problems+=("$unit is not running")
done

curl -sf -m 10 http://127.0.0.1:8787/health >/dev/null || problems+=("admission /health does not answer")

if [[ -f $STATUS ]]; then
	while IFS= read -r line; do [[ -n $line ]] && problems+=("$line"); done < <(python3 - "$STATUS" "$STALE_SECONDS" "$OVERDUE_SLOTS" <<'EOF'
import json, sys, datetime
status = json.load(open(sys.argv[1]))
stale, overdue = int(sys.argv[2]), int(sys.argv[3])
age = (datetime.datetime.now(datetime.timezone.utc) - datetime.datetime.fromisoformat(status["at"].replace("Z", "+00:00"))).total_seconds()
if age > stale: print(f"ops status older than {stale} s")
watch = status.get("lastWatchdog", {})
if int(watch.get("stuck", 0)) > 0: print("blocks stuck")
if int(watch.get("maxOverdue", 0)) > overdue: print(f"a block over {overdue} slots overdue")
EOF
)
else
	problems+=("ops status file missing")
fi

free=$((100 - $(df --output=pcent / | tail -1 | tr -dc 0-9)))
((free >= MIN_DISK_PERCENT)) || problems+=("disk under ${MIN_DISK_PERCENT}% free")

lamports=$(curl -s -m 10 "$RPC" -H 'content-type: application/json' -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getBalance\",\"params\":[\"$WALLET\"]}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["value"])' 2>/dev/null || echo unknown)
if [[ $lamports != unknown ]] && ((lamports < MIN_WALLET_LAMPORTS)); then
	problems+=("admission wallet under $((MIN_WALLET_LAMPORTS / 1000000)) mSOL")
fi

mkdir -p "$(dirname "$STATE")"
touch "$STATE" "$STATE.alerted"
printf '%s\n' "${problems[@]+"${problems[@]}"}" | sed '/^$/d' | sort > "$STATE.now"
comm -12 "$STATE" "$STATE.now" > "$STATE.confirmed"
raised=$(comm -13 "$STATE.alerted" "$STATE.confirmed")
cleared=$(comm -23 "$STATE.alerted" "$STATE.now")

send() {
	local token
	token=$(grep '^DISCORD_BOT_TOKEN=' "$TOKEN_FILE" | cut -d= -f2- | tr -d '"')
	python3 -c 'import json,sys; print(json.dumps({"content": sys.argv[1][:1900]}))' "$1" |
		curl -sf -m 10 -X POST "https://discord.com/api/v10/channels/$CHANNEL/messages" \
			-H "Authorization: Bot $token" -H 'content-type: application/json' --data @- >/dev/null
}

if [[ -n $raised ]]; then send "Hibernal devnet DOWN on $(hostname):"$'\n'"$(sed 's/^/- /' <<<"$raised")"; fi
if [[ -n $cleared ]]; then send "Hibernal devnet recovered on $(hostname):"$'\n'"$(sed 's/^/- /' <<<"$cleared")"; fi

comm -23 "$STATE.alerted" <(printf '%s\n' "$cleared" | sed '/^$/d') | sort -u - <(printf '%s\n' "$raised" | sed '/^$/d') > "$STATE.next"
mv "$STATE.next" "$STATE.alerted"
mv "$STATE.now" "$STATE"
