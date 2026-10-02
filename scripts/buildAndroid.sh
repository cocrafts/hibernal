#!/bin/bash
# Build the Hibernal APK: native/androidEntry.ms (void's scene + the HUD) into android/.
# VOID_DIR is the void checkout build.ms points at; ANDROID_HOME or ANDROID_NDK finds the NDK.
set -euo pipefail
cd "$(dirname "$0")/.."

VOID_DIR="${VOID_DIR:-../void-touch}"
case "$(uname -s)" in
	Darwin) NDK_DEFAULT="$HOME/Library/Android/sdk/ndk/28.0.13004108"; HOST_TAG="darwin-x86_64" ;;
	Linux) NDK_DEFAULT="${ANDROID_HOME:-$HOME/Android/Sdk}/ndk/28.0.13004108"; HOST_TAG="linux-x86_64" ;;
	*) echo "buildAndroid.sh: unsupported host $(uname -s)" >&2; exit 1 ;;
esac
NDK="${ANDROID_NDK:-$NDK_DEFAULT}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
CC="$TOOLCHAIN/bin/aarch64-linux-android26-clang"
DEST="android/app/src/main/jniLibs/arm64-v8a"
[ -x "$CC" ] || { echo "buildAndroid.sh: no NDK clang at $CC (set ANDROID_NDK or ANDROID_HOME)" >&2; exit 1; }
mkdir -p "$DEST"

msc build native/androidEntry.ms --os=android --app=lib --cc="$CC" --output="$DEST/libVoidAndroid.so"
"$CC" -shared -fPIC android/app/src/main/jni/voidJni.c -L"$DEST" -lVoidAndroid -landroid -llog -o "$DEST/libVoidJni.so"
# libVoidAndroid.so links libc++_shared.so, which is not on the device: ship the NDK's copy.
"$TOOLCHAIN/bin/llvm-strip" --strip-unneeded -o "$DEST/libc++_shared.so" "$TOOLCHAIN/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
(cd android && ./gradlew assembleDebug -q -PvoidDir="../../$VOID_DIR")
echo "OK: android/app/build/outputs/apk/debug/app-debug.apk"
