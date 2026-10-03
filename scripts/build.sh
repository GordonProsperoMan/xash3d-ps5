#!/usr/bin/env bash
# XashPS5 - full build: patched sources -> signed eboot.bin -> dist/ title folder.
#
#   ./scripts/build.sh            # everything (fetch, patch, build, package)
#   SKIP_FETCH=1 ./scripts/build.sh
#
# Requirements (Linux / WSL): git, python3, clang/lld 18 toolchain used by
# ps5-native-app-boilerplate, cmake, ninja, make. See README.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$ROOT/work}"
DIST="${DIST:-$ROOT/dist/PPSA99999}"
VERSION="$(cat "$ROOT/VERSION")"
mkdir -p "$WORK"

upstream() { awk -v n="$1" '$1==n{print $2}' "$ROOT/patches/UPSTREAM_COMMITS.txt"; }

checkout() { # name url dir
	local commit; commit="$(upstream "$1")"
	if [ ! -d "$3/.git" ]; then
		git clone --recursive "$2" "$3"
	fi
	git -C "$3" fetch --quiet origin || true
	git -C "$3" checkout --quiet --force "$commit"
	git -C "$3" submodule update --init --recursive --quiet
}

if [ -z "${SKIP_FETCH:-}" ]; then
	echo "==> Fetching pinned upstream sources"
	checkout ps5-native-app-boilerplate https://github.com/blackbearreloaded/ps5-native-app-boilerplate.git "$WORK/ps5_boilerplate"
	checkout ps5-opengl   https://github.com/blackbearreloaded/ps5-opengl.git  "$WORK/ps5_opengl"
	checkout xash3d-fwgs  https://github.com/FWGS/xash3d-fwgs.git             "$WORK/xash3d-fwgs"
	git -C "$WORK/xash3d-fwgs/3rdparty/mainui" checkout --quiet --force "$(upstream mainui_cpp)"
	checkout hlsdk-portable https://github.com/FWGS/hlsdk-portable.git        "$WORK/hlsdk"
	checkout ps5-sdl      https://github.com/ps5-payload-dev/SDL.git          "$WORK/ps5_sdl"

	echo "==> Applying XashPS5 patches"
	git -C "$WORK/xash3d-fwgs"               apply --whitespace=nowarn "$ROOT/patches/xash3d-fwgs-ps5.patch"
	git -C "$WORK/xash3d-fwgs/3rdparty/mainui" apply --whitespace=nowarn "$ROOT/patches/mainui-ps5.patch"
	git -C "$WORK/hlsdk"                     apply --whitespace=nowarn "$ROOT/patches/hlsdk-portable-ps5.patch"
	git -C "$WORK/ps5_boilerplate"           apply --whitespace=nowarn "$ROOT/patches/ps5-native-app-boilerplate-ps5.patch"
fi

echo "==> ps5-native-app-boilerplate: SDK, libc runtime, host tools"
make -C "$WORK/ps5_boilerplate" deps app
SDK="$WORK/ps5_boilerplate/.deps/native/ps5-payload-sdk"
TOOL="$WORK/ps5_boilerplate/build/host/ps5-native-tool"

echo "==> ps5-opengl: GL 4.6 SDK + SDL2 bridge"
GL_SDK="$WORK/ps5_opengl/build/sdk/ps5-opengl-gl46"
SDL2_SDK="$WORK/ps5_opengl/build/native-build/sdk"
if [ ! -f "$GL_SDK/lib/libSceAgc.so" ]; then
	PS5_PAYLOAD_SDK="$SDK" make -C "$WORK/ps5_opengl" source-fetch sdk-gl46
fi
if [ ! -d "$SDL2_SDK" ]; then
	( cd "$WORK/ps5_opengl" && python3 integration/SDL2/build.py native \
		--sdl-source "$WORK/ps5_sdl" --sdk-prefix "$GL_SDK" --out build/native-build \
		--payload-sdk "$SDK" --compiler-wrapper "$WORK/ps5_boilerplate/tooling/prospero-clang18" )
fi

export PATH="$SDK/bin:$PATH" PS5_PAYLOAD_SDK="$SDK" PS5_OPENGL_SDK="$GL_SDK"
export LD="$SDK/bin/ld.lld" OBJCOPY="$SDK/bin/llvm-objcopy"

echo "==> hlsdk-portable (Half-Life game logic)"
( cd "$WORK/hlsdk" && python3 waf configure --ps5 && python3 waf build )
python3 "$ROOT/scripts/build_static_gamelibs.py" "$WORK/hlsdk" "$WORK/static_gamelibs"

echo "==> Xash3D FWGS engine (single static binary)"
export XASH_EXTRA_STATIC_OBJS="server=$WORK/static_gamelibs/server.o,client=$WORK/static_gamelibs/client.o"
( cd "$WORK/xash3d-fwgs" &&
  python3 waf configure --ps5 --sdl2="$SDL2_SDK" --enable-stbtt --static-linking=filesystem_stdio,ref_gl,menu &&
  python3 waf build )

echo "==> Packaging $DIST"
mkdir -p "$WORK/pkg" "$DIST/sce_sys" "$DIST/sce_module" "$DIST/valve"
"$TOOL" link --in "$WORK/xash3d-fwgs/build/engine/xash" --out "$WORK/pkg/eboot.elf" \
	--stub "$GL_SDK/lib/libSceAgc.so" --stub "$GL_SDK/lib/libSceAgcDriver.so" --stub-dir "$SDK/target/lib"
"$TOOL" self --sign --in "$WORK/pkg/eboot.elf" --out "$DIST/eboot.bin" --magic 0x1D3D154F
"$TOOL" self --inspect --file "$DIST/eboot.bin" | grep -q "integrity: valid"
cp "$WORK/ps5_boilerplate/runtime/libc.prx" "$DIST/sce_module/"
cp -r "$ROOT/sce_sys/." "$DIST/sce_sys/"
python3 - "$DIST/sce_sys/param.json" "$VERSION" <<'EOF'
import json, sys
p, v = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d['localizedParameters']['en-US']['titleName'] = 'XashPS5 ' + v
d['contentVersion'] = '01.000.000'
json.dump(d, open(p, 'w'), indent=2)
EOF
cp "$ROOT/configs/valve/"*.cfg "$DIST/valve/"

echo
echo "Done: $DIST"
echo "Copy your own Half-Life 'valve' folder into $DIST/valve/ (keep the two .cfg files"
echo "from this repo), then deploy with: python3 scripts/deploy.py $DIST <ps5-ip>"
