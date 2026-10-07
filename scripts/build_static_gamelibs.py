#!/usr/bin/env python3
"""Turn the hlsdk-portable server/client libraries into relocatable,
export-table-wrapped objects (server.o / client.o) that the Xash3D engine
links statically (XASH_STATIC_LIBS / lib_static.c): PS5 native titles have no
working dlopen().

Usage: build_static_gamelibs.py <hlsdk-dir> <out-dir> [gamedir]

With [gamedir] (e.g. gearbox, bshift) the export tables are named
lib_server_<gamedir>_exports / lib_client_<gamedir>_exports and must be
registered in XASH_EXTRA_STATIC_OBJS as "server@<gamedir>=...": the engine
picks them when that game folder is active. Without it they are the default
"server"/"client" (Half-Life, also used by mods without their own code).
Environment: PS5_PAYLOAD_SDK (ps5-payload-sdk root), PS5_OPENGL_SDK.

The script re-runs the hlsdk link step with `waf build -v` to capture the
exact object/library lists, then for each library:
  1. ld -r all objects into one relocatable object,
  2. export every global non-underscore C function (T/W) through a
     lib_<name>_exports[] table (the engine's static loader looks names up
     there instead of dlsym),
  3. hide everything except that table (objcopy -G).
"""
import ast, os, subprocess, sys

if len(sys.argv) not in (3, 4):
    sys.exit(__doc__)
HL = os.path.abspath(sys.argv[1])
OUT = os.path.abspath(sys.argv[2])
GAME = sys.argv[3] if len(sys.argv) == 4 else ''
suffix = ('_' + GAME) if GAME else ''
SDK = os.environ['PS5_PAYLOAD_SDK']
NM, LD, OBJCOPY, CC = (os.path.join(SDK, 'bin', t) for t in ('llvm-nm', 'ld.lld', 'llvm-objcopy', 'prospero-clang'))
os.makedirs(OUT, exist_ok=True)
bld = os.path.join(HL, 'build')

# force a relink and capture the two "-shared" command lines
import glob
for p in glob.glob(os.path.join(bld, 'dlls', '*.so')) + glob.glob(os.path.join(bld, 'cl_dll', '*.so')):
    os.remove(p)
log = subprocess.run([sys.executable, 'waf', 'build', '-v'], cwd=HL, capture_output=True, text=True)
if log.returncode:
    sys.exit(log.stdout + log.stderr)
cmds = []
for line in log.stdout.splitlines() + log.stderr.splitlines():
    if 'runner [' in line and "'-shared'" in line:
        cmds.append(ast.literal_eval(line[line.index('['):]))
if len(cmds) != 2:
    sys.exit('expected 2 link commands, found %d' % len(cmds))

for cmd in cmds:
    so = [a[2:] for a in cmd if a.startswith('-o')][0]
    kind = 'server' if '/dlls/' in so else 'client'
    name = kind + suffix
    objs = [os.path.join(bld, a) for a in cmd if a.endswith('.o')]
    libdirs = [os.path.join(bld, a[2:]) for a in cmd if a.startswith('-L') and a != '-L' and not a.startswith('-L/')]
    libs = [a for a in cmd if a.startswith('-l')]

    pre = os.path.join(OUT, f'{name}.pre.o')
    ldp = [LD, '-r', '-o', pre] + objs
    for d in libdirs:
        ldp += ['-L', d]
    subprocess.check_call(ldp + libs)
    syms = subprocess.check_output([NM, '--defined-only', '-g', pre], text=True).split('\n')
    exports = sorted({l.split()[2] for l in syms if len(l.split()) == 3 and l.split()[1] in 'TW'
                      and not l.split()[2].startswith('_')})

    helper = os.path.join(OUT, f'link_helper_{name}.c')
    with open(helper, 'w') as f:
        f.write('\n'.join(f'extern void {e}(void);' for e in exports))
        f.write(f'\nstruct {{const char *name;void *func;}} lib_{name}_exports[] = {{\n')
        f.write('\n'.join(f'{{ "{e}", (void*)&{e} }},' for e in exports))
        f.write('\n{0,0}\n};\n')
    helper_o = helper[:-2] + '.o'
    subprocess.check_call([CC, '-c', '-fPIC', '-O2', helper, '-o', helper_o])

    unstripped = os.path.join(OUT, f'{name}.unstripped.o')
    ld = [LD, '-r', '-o', unstripped] + objs + [helper_o]
    for d in libdirs:
        ld += ['-L', d]
    subprocess.check_call(ld + libs)
    final = os.path.join(OUT, f'{name}.o')
    subprocess.check_call([OBJCOPY, '-G', f'lib_{name}_exports', unstripped, final])
    print(name, len(objs), 'objs,', len(exports), 'exports ->', final)
