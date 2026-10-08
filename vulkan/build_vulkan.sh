#!/usr/bin/env bash
# XashPS5 release build, step 2: OpenGL on Vulkan (Mesa Zink on RADV, PS5_Vulkan).
#
#   ./scripts/build.sh            # first: sources, game code, engine objects, SDL2, tools
#   ./vulkan/build_vulkan.sh      # then: Mesa Zink + RADV, relink, package dist/PPSA19111
#
# Requirements on top of build.sh's: meson >= 1.4, ninja, rsync, clang-18 and
# LLVM/Clang 19 development packages for Mesa's OpenCL helper (Debian 13:
# llvm-19-dev libclang-19-dev libclang-cpp19-dev libclc-19 libclc-19-dev
# libllvmspirvlib-19-dev llvm-spirv-19), python3-mako python3-yaml python3-ply,
# glslang-tools, spirv-tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$ROOT/work}"
DIST="${DIST:-$ROOT/dist/PPSA19111}"
VERSION="$(cat "$ROOT/VERSION")"
upstream() { awk -v n="$1" '$1==n{print $2}' "$ROOT/patches/UPSTREAM_COMMITS.txt"; }

checkout() { # name url dir
	local commit; commit="$(upstream "$1")"
	[ -d "$3/.git" ] || git clone "$2" "$3"
	git -C "$3" fetch --quiet origin || true
	git -C "$3" checkout --quiet --force "$commit"
}

[ -f "$WORK/xash3d-fwgs/build/engine/xash" ] || { echo "run scripts/build.sh first" >&2; exit 2; }

echo "==> Fetching PS5_Vulkan, PS5_Mesa, PS5_PayloadSDK"
checkout PS5_Vulkan     https://github.com/mihawk-99/PS5_Vulkan.git     "$WORK/ps5_vulkan"
checkout PS5_Mesa       https://github.com/mihawk-99/PS5_Mesa.git       "$WORK/PS5_Mesa"
checkout PS5_PayloadSDK https://github.com/mihawk-99/PS5_PayloadSDK.git "$WORK/PS5_PayloadSDK"

echo "==> PS5_Vulkan native dependencies (payload SDK fork, zlib)"
( cd "$WORK/ps5_vulkan" && PS5_PAYLOAD_SDK_FORK="$WORK/PS5_PayloadSDK" bash tools/setup-native-dependencies.sh )
( cd "$WORK/ps5_vulkan" && [ -f runtime/libc.prx ] || bash tools/rebuild-libc.sh )

echo "==> Mesa source (pinned PS5_Mesa) + XashPS5 Zink patch"
VKW="$WORK/ps5_vulkan/.deps/work"
SRC="$VKW/zink-src"
MESA_REV="$(upstream PS5_Mesa)"
if [ ! -f "$SRC/.xashps5-rev" ] || [ "$(cat "$SRC/.xashps5-rev")" != "$MESA_REV" ]; then
	rm -rf "$SRC"; mkdir -p "$SRC"
	git -C "$WORK/PS5_Mesa" archive "$MESA_REV" | tar -x -C "$SRC"
	( cd "$SRC" && git init -q && git apply --whitespace=nowarn "$ROOT/patches/ps5-mesa-zink.patch" )
	echo "$MESA_REV" > "$SRC/.xashps5-rev"
fi

echo "==> Mesa host tools (mesa_clc, vtn_bindgen2) and cross build: RADV + Zink + GL"
SDK_VK="$WORK/ps5_vulkan/.deps/native/ps5-payload-sdk"
CLC_BUILD="$VKW/zink-clc-build"; CLC_BIN="$VKW/zink-clc-bin"
export PATH="/usr/lib/llvm-19/bin:$PATH"
if [ ! -f "$CLC_BUILD/build.ninja" ]; then
	meson setup "$CLC_BUILD" "$SRC" -Dbuildtype=release -Dmesa-clc=enabled -Dinstall-mesa-clc=true \
		-Dgallium-drivers= -Dvulkan-drivers= -Dplatforms= -Dglx=disabled -Degl=disabled -Dgbm=disabled \
		-Dopengl=false -Dgles1=disabled -Dgles2=disabled -Dllvm=enabled -Dshared-llvm=enabled \
		-Dbuild-tests=false -Dvalgrind=disabled -Dlibunwind=disabled -Dzstd=disabled -Dxmlconfig=disabled -Dtools=
fi
ninja -C "$CLC_BUILD" src/compiler/clc/mesa_clc src/compiler/spirv/vtn_bindgen2
mkdir -p "$CLC_BIN"
ln -sf "$CLC_BUILD/src/compiler/clc/mesa_clc" "$CLC_BIN/mesa_clc"
ln -sf "$CLC_BUILD/src/compiler/spirv/vtn_bindgen2" "$CLC_BIN/vtn_bindgen2"
export PATH="$CLC_BIN:$PATH"

BLD="$VKW/zink-build-ps5"
printf "[constants]\nsdk = '%s'\n" "$SDK_VK" > "$VKW/zink-cross-constants.ini"
if [ ! -f "$BLD/build.ninja" ]; then
	meson setup "$BLD" "$SRC" --cross-file "$VKW/zink-cross-constants.ini" \
		--cross-file "$WORK/ps5_vulkan/tooling/radv/ps5-cross.ini" \
		-Dvulkan-drivers=amd -Dgallium-drivers=zink -Dplatforms= -Dradv-winsys=ps5 \
		-Dllvm=disabled -Damd-use-llvm=false -Dvideo-codecs= -Dbuildtype=release -Db_ndebug=true \
		-Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=true -Dgles1=disabled -Dgles2=disabled \
		-Dvalgrind=disabled -Dlibunwind=disabled -Dzstd=disabled -Dzlib=enabled --force-fallback-for=zlib \
		-Dexpat=disabled -Dxmlconfig=disabled -Dshader-cache=enabled -Dbuild-tests=false \
		-Dvulkan-layers= -Dtools= -Dmesa-clc=system -Dgallium-va=disabled -Dgallium-rusticl=false \
		-Dradv-build-id="$MESA_REV"
fi
ninja -C "$BLD" src/amd/vulkan/libvulkan_radeon.a src/gallium/drivers/zink/libzink.a \
	src/gallium/frontends/ps5egl/libps5zinkegl.a src/mesa/libmesa.a src/mesa/libmesa_sse41.a \
	src/gallium/auxiliary/libgallium.a src/gallium/auxiliary/libgalliumvl_stub.a \
	src/mesa/glapi/shared-glapi/libglapi.a src/mesa/glapi/glapi/libglapi_bridge.a \
	src/compiler/glsl/libglsl.a src/compiler/glsl/glcpp/libglcpp.a src/compiler/glsl/libglsl_util.a \
	src/gallium/winsys/zink/drm/libzinkwinsys.a

# Zink carries its own copy of vk_dispatch_table.c, which RADV's archive (linked
# whole) already contains: drop it.
( cd "$BLD/src/gallium/drivers/zink" && rm -f libzink_ps5.a &&
  llvm-ar t libzink.a | grep -v vk_dispatch_table.c.o > members.txt &&
  llvm-ar qcs libzink_ps5.a $(cat members.txt) )

echo "==> Engine link line (waf) -> relink on Zink + RADV"
( cd "$WORK/xash3d-fwgs" && rm -f build/engine/xash &&
  python3 waf build -v 2>&1 | grep -E "runner \[.*-o.*engine/xash'" | tail -1 > build/xash_link_cmd.txt )
python3 - "$WORK/xash3d-fwgs/build" <<'EOF'
import ast, json, sys
b = sys.argv[1]; s = open(b + '/xash_link_cmd.txt').read()
args = ast.literal_eval(s[s.index("runner [") + 7:s.rindex(']') + 1])
json.dump(args, open(b + '/xash_link_args.json', 'w'))
EOF
PS5_CLANG="${PS5_CLANG:-$(command -v clang-18 || command -v clang)}" \
	python3 "$ROOT/vulkan/link_xash_zink.py" "$WORK" "$WORK/vulkan-build"

echo "==> Packaging $DIST"
mkdir -p "$DIST/sce_sys" "$DIST/sce_module"
cp "$WORK/vulkan-build/xash_zink.bin" "$DIST/eboot.bin"
cp "$WORK/ps5_vulkan/runtime/libc.prx" "$DIST/sce_module/libc.prx"
cp -r "$ROOT/sce_sys/." "$DIST/sce_sys/"
python3 - "$DIST/sce_sys/param.json" "$VERSION" <<'EOF2'
import json, sys
p, v = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d['localizedParameters']['en-US']['titleName'] = 'XashPS5 ' + v
json.dump(d, open(p, 'w'), indent=2)
EOF2
for g in valve gearbox bshift cstrike; do mkdir -p "$DIST/$g" && cp "$ROOT/configs/$g/"*.cfg "$DIST/$g/"; done
cp "$WORK/xash3d-fwgs/build/3rdparty/extras/extras.pk3" "$DIST/valve/"   # menu graphics
cp "$WORK/cs16-client/build-ps5/extras.pk3" "$DIST/cstrike/"            # cs16-client data
echo "==> Done: $DIST (add your own game folders, see README.md)"
