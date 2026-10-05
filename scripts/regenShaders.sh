#!/bin/bash
# Regenerate hibernal's sokol-shdc shader headers with void's pinned sokol-shdc (vendor/void),
# the same languages void3d builds for. Run after editing a .glsl; buildAndroid.sh runs it too.
set -euo pipefail
cd "$(dirname "$0")/.."

case "$(uname -s)-$(uname -m)" in
	Darwin-arm64) SHDC="vendor/void/deps/sokol-tools-bin/bin/osx_arm64/sokol-shdc" ;;
	Darwin-*) SHDC="vendor/void/deps/sokol-tools-bin/bin/osx/sokol-shdc" ;;
	Linux-aarch64) SHDC="vendor/void/deps/sokol-tools-bin/bin/linux_arm64/sokol-shdc" ;;
	Linux-*) SHDC="vendor/void/deps/sokol-tools-bin/bin/linux/sokol-shdc" ;;
	*) echo "regenShaders.sh: no sokol-shdc for $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
[ -x "$SHDC" ] || { echo "regenShaders.sh: no sokol-shdc at $SHDC (scripts/fetchVoid.sh fetches void)" >&2; exit 1; }

"$SHDC" -i native/hud/hudPost.glsl -o native/hud/hudPost.glsl.h -l "metal_macos:metal_ios:metal_sim:glsl300es:wgsl:hlsl5" -f sokol
