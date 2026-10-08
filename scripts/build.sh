#!/usr/bin/env bash
# XashPS5 - step 1 of the build: patched sources, game code (Half-Life, Opposing
# Force, Blue Shift, Counter-Strike), engine objects, plus an OpenGL (G19) eboot
# in dist/gl/ for comparison. The release eboot (Zink/Vulkan) is made by step 2:
#
#   ./scripts/build.sh            # everything (fetch, patch, build, package)
#   ./vulkan/build_vulkan.sh      # Mesa Zink + RADV, relink -> dist/PPSA19111
#   SKIP_FETCH=1 ./scripts/build.sh
#
# Requirements (Linux / WSL): git, python3, clang/lld 18 toolchain used by
# ps5-native-app-boilerplate, cmake, ninja, make. See README.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$ROOT/work}"
DIST="${DIST_GL:-$ROOT/dist/gl/PPSA19111}"
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
	checkout hlsdk-portable-opfor  https://github.com/FWGS/hlsdk-portable.git "$WORK/hlsdk_opfor"
	checkout hlsdk-portable-bshift https://github.com/FWGS/hlsdk-portable.git "$WORK/hlsdk_bshift"
	checkout ps5-sdl      https://github.com/ps5-payload-dev/SDL.git          "$WORK/ps5_sdl"
	checkout cs16-client  https://github.com/Velaron/cs16-client.git          "$WORK/cs16-client"

	echo "==> Applying XashPS5 patches"
	git -C "$WORK/xash3d-fwgs"               apply --whitespace=nowarn "$ROOT/patches/xash3d-fwgs-ps5.patch"
	git -C "$WORK/xash3d-fwgs/3rdparty/mainui" apply --whitespace=nowarn "$ROOT/patches/mainui-ps5.patch"
	for h in hlsdk hlsdk_opfor hlsdk_bshift; do
		git -C "$WORK/$h" apply --whitespace=nowarn "$ROOT/patches/hlsdk-portable-ps5.patch"
	done
	git -C "$WORK/ps5_opengl"                apply --whitespace=nowarn "$ROOT/patches/ps5-opengl-sdl2-display-modes.patch"
	git -C "$WORK/ps5_boilerplate"           apply --whitespace=nowarn "$ROOT/patches/ps5-native-app-boilerplate-ps5.patch"
	git -C "$WORK/cs16-client"               apply --whitespace=nowarn "$ROOT/patches/cs16/cs16-client-ps5.patch"
	git -C "$WORK/cs16-client/3rdparty/ReGameDLL_CS" apply --whitespace=nowarn "$ROOT/patches/cs16/regamedll-ps5.patch"
	git -C "$WORK/cs16-client/3rdparty/yapb/ext/crlib" apply --whitespace=nowarn "$ROOT/patches/cs16/yapb-crlib-ps5.patch"
	git -C "$WORK/cs16-client/3rdparty/mainui_cpp" apply --whitespace=nowarn "$ROOT/patches/cs16/mainui_cpp-cs16-ps5.patch"
fi

echo "==> ps5-native-app-boilerplate: SDK, libc runtime, host tools"
make -C "$WORK/ps5_boilerplate" deps app
SDK="$WORK/ps5_boilerplate/.deps/native/ps5-payload-sdk"
TOOL="$WORK/ps5_boilerplate/build/host/ps5-native-tool"

echo "==> ps5-opengl SDK 1.0.0 (official release: runtime 1080p/1440p/4K display modes) + SDL2 bridge"
GL_SDK="$WORK/ps5-opengl-sdk-1.0.0/sdk"
SDL2_SDK="$WORK/ps5_opengl/build/native-build/sdk"
if [ ! -f "$GL_SDK/lib/libSceAgc.so" ]; then
	( cd "$WORK" && curl -fsSLO https://github.com/blackbearreloaded/ps5-opengl/releases/download/v1.0.0/ps5-opengl-sdk-1.0.0.tar.gz &&
	  curl -fsSLO https://github.com/blackbearreloaded/ps5-opengl/releases/download/v1.0.0/ps5-opengl-sdk-1.0.0.tar.gz.sha256 &&
	  sha256sum -c ps5-opengl-sdk-1.0.0.tar.gz.sha256 && tar xzf ps5-opengl-sdk-1.0.0.tar.gz )
fi
if [ ! -d "$SDL2_SDK" ]; then
	( cd "$WORK/ps5_opengl" && python3 integration/SDL2/build.py native \
		--sdl-source "$WORK/ps5_sdl" --sdk-prefix "$GL_SDK" --out build/native-build \
		--payload-sdk "$SDK" --compiler-wrapper "$WORK/ps5_boilerplate/tooling/prospero-clang18" )
fi

export PATH="$SDK/bin:$PATH" PS5_PAYLOAD_SDK="$SDK" PS5_OPENGL_SDK="$GL_SDK"
export LD="$SDK/bin/ld.lld" OBJCOPY="$SDK/bin/llvm-objcopy"

echo "==> hlsdk-portable: Half-Life, Opposing Force (gearbox), Blue Shift (bshift) game logic"
SG="$WORK/static_gamelibs"
( cd "$WORK/hlsdk" && python3 waf configure --ps5 && python3 waf build )
python3 "$ROOT/scripts/build_static_gamelibs.py" "$WORK/hlsdk" "$SG"
for g in opfor:gearbox bshift:bshift; do
	src=${g%%:*}; dir=${g##*:}
	( cd "$WORK/hlsdk_$src" && python3 waf configure --ps5 && python3 waf build )
	python3 "$ROOT/scripts/build_static_gamelibs.py" "$WORK/hlsdk_$src" "$SG" "$dir"
done

echo "==> Counter-Strike: cs16-client (client + its menu with the team/buy menus) + ReGameDLL_CS (server)"
# only the objects are used: the .so links of this CMake project fail on PS5 (-k 0)
( cd "$WORK/cs16-client" &&
  prospero-cmake -S . -B build-ps5 -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_MAINUI=ON -DMAINUI_USE_STB=ON \
	-DENABLE_YY_THUNKS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON &&
  ( ninja -C build-ps5 -k 0 || true ) )
CSB="$WORK/cs16-client/build-ps5"
python3 "$ROOT/scripts/wrap_static_gamelib.py" server_cstrike "$SG" "$CSB/3rdparty/ReGameDLL_CS/regamedll/CMakeFiles/regamedll.dir"
python3 "$ROOT/scripts/wrap_static_gamelib.py" client_cstrike "$SG" "$CSB/cl_dll/CMakeFiles/client.dir"
python3 "$ROOT/scripts/wrap_static_gamelib.py" menu_cstrike   "$SG" "$CSB/3rdparty/mainui_cpp/CMakeFiles/menu.dir"

echo "==> Link-only stubs for system modules missing from the public SDK: CommonDialog (PS5 keyboard), Mouse"
for m in common_dialog:CommonDialog mouse:Mouse; do
	src=${m%%:*}; lib=${m##*:}
	"$SDK/bin/prospero-clang" -O2 -fPIC -c "$WORK/xash3d-fwgs/scripts/ps5_stubs/${src}_link_stub.c" -o "$WORK/${src}_link_stub.o"
	"$SDK/bin/prospero-lld" --shared -soname "libSce$lib.sprx" \
		-o "$WORK/xash3d-fwgs/scripts/ps5_stubs/libSce$lib.so" "$WORK/${src}_link_stub.o"
done

echo "==> Xash3D FWGS engine (single static binary)"
export XASH_EXTRA_STATIC_OBJS="server=$SG/server.o,client=$SG/client.o,server@gearbox=$SG/server_gearbox.o,client@gearbox=$SG/client_gearbox.o,server@bshift=$SG/server_bshift.o,client@bshift=$SG/client_bshift.o,server@cstrike=$SG/server_cstrike.o,client@cstrike=$SG/client_cstrike.o,menu@cstrike=$SG/menu_cstrike.o"
( cd "$WORK/xash3d-fwgs" &&
  python3 waf configure --ps5 --sdl2="$SDL2_SDK" --enable-stbtt --static-linking=filesystem_stdio,ref_gl,menu &&
  python3 waf build )

echo "==> Packaging $DIST"
mkdir -p "$WORK/pkg" "$DIST/sce_sys" "$DIST/sce_module" "$DIST/valve"
"$TOOL" link --in "$WORK/xash3d-fwgs/build/engine/xash" --out "$WORK/pkg/eboot.elf" \
	--stub "$GL_SDK/lib/libSceAgc.so" --stub "$GL_SDK/lib/libSceAgcDriver.so" \
	--stub "$WORK/xash3d-fwgs/scripts/ps5_stubs/libSceCommonDialog.so" \
	--stub "$WORK/xash3d-fwgs/scripts/ps5_stubs/libSceMouse.so" --stub-dir "$SDK/target/lib"
"$TOOL" self --sign --in "$WORK/pkg/eboot.elf" --out "$DIST/eboot.bin" --magic 0x1D3D154F
"$TOOL" self --inspect --file "$DIST/eboot.bin" | grep -q "integrity: valid"
cp "$WORK/ps5_boilerplate/runtime/libc.prx" "$DIST/sce_module/"
cp -r "$ROOT/sce_sys/." "$DIST/sce_sys/"
python3 - "$DIST/sce_sys/param.json" "$VERSION" <<'EOF'
import json, sys
p, v = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d['localizedParameters']['en-US']['titleName'] = 'XashPS5 ' + v
json.dump(d, open(p, 'w'), indent=2)
EOF
cp "$ROOT/configs/valve/"*.cfg "$DIST/valve/"
cp "$WORK/xash3d-fwgs/build/3rdparty/extras/extras.pk3" "$DIST/valve/"   # menu graphics (sliders, checkboxes)
for g in gearbox bshift cstrike; do mkdir -p "$DIST/$g" && cp "$ROOT/configs/$g/"*.cfg "$DIST/$g/"; done
cp "$CSB/extras.pk3" "$DIST/cstrike/extras.pk3"   # cs16-client data: menus, sounds, bot navigation

echo
echo "Done: $DIST"
echo "Copy your own Half-Life 'valve' folder into $DIST/valve/ (keep the two .cfg files"
echo "from this repo), then deploy with: python3 scripts/deploy.py $DIST <ps5-ip>"
