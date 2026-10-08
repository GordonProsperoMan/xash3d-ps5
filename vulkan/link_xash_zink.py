#!/usr/bin/env python3
"""XashPS5 Vulkan build (default renderer since V1.3): relink the Xash3D objects already built by
scripts/build.sh against Mesa Zink (OpenGL on Vulkan) + RADV (PS5_Vulkan)
instead of the G19 ps5-opengl driver.

    python3 vulkan/link_xash_zink.py <work-dir> <out-dir>

<work-dir> is scripts/build.sh's WORK (xash3d-fwgs, ps5_opengl, ps5_boilerplate
checkouts) plus ps5_vulkan/ prepared by vulkan/build_vulkan.sh. The engine
objects are unchanged: SDL2's G19 video driver calls the EGL subset that
ps5_zink_egl.c (patches/ps5-mesa-zink.patch) provides.
Produces <out-dir>/xash_zink.bin (signed eboot).
"""
import json, os, subprocess, sys, shlex

HERE = os.path.dirname(os.path.abspath(__file__))
W = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, '..', 'work')
WORK = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.join(W, 'vulkan-build')
VK = W + '/ps5_vulkan'
BLD = VK + '/.deps/work/zink-build-ps5'
SDK = VK + '/.deps/native/ps5-payload-sdk'          # PS5_Vulkan's pinned SDK fork
NATIVE = VK + '/tooling/native'
XB = W + '/xash3d-fwgs/build'
TOOL = W + '/ps5_boilerplate/build/host/ps5-native-tool'
SDL2 = W + '/ps5_opengl/build/native-build/sdk/lib/libSDL2.a'
os.makedirs(WORK + '/obj', exist_ok=True)

args = json.load(open(XB + '/xash_link_args.json'))  # written by build_vulkan.sh

# --- engine objects / static libs from waf's link line (paths relative to build/)
objs, libdirs, libs = [], [], []
skip_objs = ('app_crt.o', 'app_cpp_runtime.o', 'engine/platform/ps5/app_heap.c.2.o')
i = 0
in_static = False
while i < len(args):
    a = args[i]
    if a.endswith('.o'):
        if not a.endswith(skip_objs):
            objs.append(a if os.path.isabs(a) else os.path.normpath(os.path.join(XB, a)))
    elif a == '-Wl,-Bstatic':
        in_static = True
    elif a == '-Wl,-Bdynamic':
        in_static = False
    elif in_static and a.startswith('-L'):
        libdirs.append(os.path.join(XB, a[2:]))
    elif in_static and a.startswith('-l'):
        libs.append(a[2:])
    i += 1

static_archives = []
for l in libs:
    for d in libdirs:
        p = os.path.join(d, 'lib%s.a' % l)
        if os.path.exists(p):
            static_archives.append(p)
            break
    else:
        sys.exit('missing static lib ' + l)

sdl = SDL2

# --- RADV link recipe (PS5_Vulkan tools/radv-link.sh), evaluated by bash
recipe = subprocess.run(['bash', '-c', '''
source "$1/tools/radv-link.sh"
radv_link_recipe "$1" "$2" "$3" >&2 || exit 2
printf '%s\\0' "${#radv_linker_script[@]}" "${radv_linker_script[@]}" \
   "${#radv_link_flags[@]}" "${radv_link_flags[@]}" "${radv_link_inputs[@]}"
''', '_', VK, SDK, BLD + '/src/amd/vulkan/libvulkan_radeon.a'],
    capture_output=True, env=dict(os.environ, PS5_CLANG='/usr/bin/clang-18'))
if recipe.returncode:
    sys.exit(recipe.stderr.decode())
parts = recipe.stdout.decode().split('\0')[:-1]
n = int(parts[0]); script = parts[1:1 + n]; rest = parts[1 + n:]
m = int(rest[0]); flags = rest[1:1 + m]; inputs = rest[1 + m:]

# Xash keeps its own path wrappers (virtual cwd) but takes malloc from the
# platform heap (RADV's recipe wraps the whole malloc family itself).
xash_wraps = ['chdir', 'getcwd', 'open', 'stat', 'lstat', 'access', 'mkdir', 'unlink', 'rename',
              'remove', 'utime', 'opendir', 'readdir', 'closedir', 'fopen', 'freopen', 'realpath']
# the platform layer defsyms access/opendir/readdir/closedir to ps5_*; Xash's
# ps5_vcwd wraps those names too: keep Xash's (it calls __real_*, which then
# resolves to the libc symbol) by dropping the conflicting defsyms
# Xash's ps5_vcwd wraps access/opendir/readdir/closedir (virtual cwd) and the
# platform defsyms the same names to ps5_*: keep both, so __wrap_X (Xash) ->
# __real_X -> X -> ps5_X. The system opendir/readdir crash on this runtime.


def cc(src, out, lang='c++'):
    std = '-std=c++20' if lang == 'c++' else '-std=c11'
    extra = ['-fno-exceptions', '-fno-rtti'] if lang == 'c++' else []
    subprocess.check_call(['sh', VK + '/tooling/prospero-clang18', std, '-O2'] + extra + [ '-ffunction-sections', '-fdata-sections', '-c', src, '-o', out],
                          env=dict(os.environ, PS5_PAYLOAD_SDK=SDK))
cc(NATIVE + '/app_crt.cpp', WORK + '/obj/app_crt.o')
cc(NATIVE + '/app_cpp_runtime.cpp', WORK + '/obj/app_cpp_runtime.o')
cc(HERE + '/xash_zink_shims.c', WORK + '/obj/xash_zink_shims.o', 'c')

stubs = WORK + '/stubs'
os.makedirs(stubs, exist_ok=True)
for lib, src in (('libSceAgc', 'agc_canary_link_stub.c'), ('libSceAgcDriver', 'agc_driver_canary_link_stub.c')):
    cc_obj = WORK + '/obj/' + lib + '_stub.o'
    subprocess.check_call(['sh', VK + '/tooling/prospero-clang18', '-std=c11', '-O2', '-fPIC', '-c',
                           VK + '/vendor/ps5/sdk/stubs/' + src, '-o', cc_obj], env=dict(os.environ, PS5_PAYLOAD_SDK=SDK))
    subprocess.check_call([SDK + '/bin/prospero-lld', '--shared', '-soname', lib + '.prx', '-o', stubs + '/' + lib + '.so', cc_obj])
# link-only facades for system modules the public SDK has no stub for (built by
# scripts/build.sh): CommonDialog (PS5 keyboard), Mouse (USB mouse)
sys_stubs = [W + '/xash3d-fwgs/scripts/ps5_stubs/libSceCommonDialog.so',
             W + '/xash3d-fwgs/scripts/ps5_stubs/libSceMouse.so']
mesa = [BLD + p for p in (
    '/src/gallium/frontends/ps5egl/libps5zinkegl.a', '/src/mesa/libmesa.a',
    '/src/gallium/drivers/zink/libzink_ps5.a', '/src/gallium/winsys/zink/drm/libzinkwinsys.a',
    '/src/gallium/auxiliary/libgallium.a', '/src/mesa/glapi/glapi/libglapi_bridge.a',
    '/src/mesa/glapi/shared-glapi/libglapi.a', '/src/compiler/glsl/libglsl.a',
    '/src/compiler/glsl/glcpp/libglcpp.a', '/src/compiler/glsl/libglsl_util.a',
    '/src/mesa/libmesa_sse41.a', '/src/gallium/auxiliary/libgalliumvl_stub.a')]

pie = WORK + '/xash_zink-pie.elf'
cmd = [SDK + '/bin/prospero-lld'] + script + ['--eh-frame-hdr'] + flags + \
      ['--wrap=' + w for w in xash_wraps] + \
      ['--version-script', NATIVE + '/app-symbols.map', '--version-script', HERE + '/xash_zink_local.map', '--exclude-libs=ALL',
       '-e', '_start', '-o', pie, '-u', '_ZTH23_mesa_glapi_tls_Context',
       WORK + '/obj/app_crt.o', WORK + '/obj/app_cpp_runtime.o', WORK + '/obj/xash_zink_shims.o'] + objs + \
      [stubs + '/libSceAgc.so', stubs + '/libSceAgcDriver.so'] + sys_stubs + [
       '--start-group'] + static_archives + [sdl] + mesa + ['--end-group'] + inputs + \
      ['--as-needed'] + sorted(SDK + '/target/lib/' + f for f in os.listdir(SDK + '/target/lib') if f.endswith('.so'))
open(WORK + '/xash_zink_link.sh', 'w').write(' '.join(shlex.quote(c) for c in cmd) + '\n')
r = subprocess.run(cmd, capture_output=True, text=True)
errs = [l for l in r.stderr.splitlines() if 'warning' not in l]
print('\n'.join(errs[:60]))
if r.returncode:
    sys.exit('link failed')
subprocess.check_call([TOOL, 'link', '--in', pie, '--out', WORK + '/xash_zink.elf',
                       '--stub-dir', SDK + '/target/lib', '--stub', stubs + '/libSceAgc.so',
                       '--stub', stubs + '/libSceAgcDriver.so', '--module-sdk', '0x02000009',
                       '--stub', sys_stubs[0], '--stub', sys_stubs[1],
                       '--companion-sdk', '0x08050001', '--file-name', 'eboot.elf'])
subprocess.check_call([TOOL, 'self', '--sign', '--in', WORK + '/xash_zink.elf',
                       '--out', WORK + '/xash_zink.bin', '--magic', '0x1D3D154F'])
out = subprocess.run([TOOL, 'self', '--inspect', '--file', WORK + '/xash_zink.bin'],
                     capture_output=True, text=True).stdout
print([l for l in out.splitlines() if 'integrity' in l])
