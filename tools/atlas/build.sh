#!/bin/sh
set -e
cd "$(dirname "$0")/../.."
mkdir -p out/atlas
msc build tools/atlas/atlas.ms --target=js --split --output=out/atlas/build
cp tools/atlas/index.html out/atlas/index.html
