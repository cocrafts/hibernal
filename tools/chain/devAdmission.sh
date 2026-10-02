#!/bin/zsh
set -e
count=${1:?usage: devAdmission.sh <count> [group]}
group=${2:-6jXijzhCm1Njikk3vLTmrw1mjPzWrwKherDYvELgwCpR}
url=${BASE_RPC:-https://api.devnet.solana.com}
token2022=TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb
dir=$(dirname $0)/../../out/admission
mkdir -p $dir
for index in $(seq 1 $count); do
	keypair=$dir/member$index.json
	[ -f $keypair ] || solana-keygen new --no-bip39-passphrase -s -o $keypair > /dev/null
	mint=$(solana address -k $keypair)
	if ! spl-token display $mint -u $url > /dev/null 2>&1; then
		spl-token create-token --program-id $token2022 --enable-member --decimals 0 $keypair -u $url > /dev/null
		spl-token initialize-member $mint $group -u $url > /dev/null
		spl-token create-account $mint -u $url > /dev/null
		spl-token mint $mint 1 -u $url > /dev/null
	fi
	echo "$index $mint"
done
