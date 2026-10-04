#!/bin/bash
# Clone void at the patches' BASE into vendor/void and apply native/voidPatches/*.patch, once,
# with the yoga void imports beside it (vendor/yoga). VOID_URL / YOGA_URL override where they
# come from (a local clone is faster).
set -euo pipefail
cd "$(dirname "$0")/.."

BASE="ea4b6205c4840eb7d97a64e8efcbe5e93d218de6"
YOGA_BASE="10279de1bd3bc55728df4f30d11eae36a2e471dc"
VOID_URL="${VOID_URL:-https://github.com/metascriptlang/void.git}"
YOGA_URL="${YOGA_URL:-https://github.com/metascriptlang/yoga.git}"
DEST="vendor/void"

if [ -d "$DEST/.git" ]; then
	echo "fetchVoid.sh: $DEST is there; delete it to fetch again"
	exit 0
fi
mkdir -p vendor
git clone --quiet --no-checkout "$VOID_URL" "$DEST"
git -C "$DEST" checkout --quiet -b hibernalPatches "$BASE"
git -C "$DEST" -c user.name=hibernal -c user.email=hibernal@localhost am --quiet "$PWD"/native/voidPatches/*.patch
# void's own C dependencies (sokol, fontstash, stb) at its pins.
sh "$DEST/setup.sh"
if [ ! -d vendor/yoga/.git ]; then
	git clone --quiet --no-checkout "$YOGA_URL" vendor/yoga
	git -C vendor/yoga checkout --quiet "$YOGA_BASE"
fi
echo "OK: $DEST at $BASE + $(ls native/voidPatches/*.patch | wc -l) patches"
