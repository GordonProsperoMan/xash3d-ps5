#!/usr/bin/env python3
"""Wrap prebuilt game-library objects into one export-table object for the
statically linked engine (same output as build_static_gamelibs.py, but takes
the object list directly: used for CMake-built game code such as
cs16-client + ReGameDLL_CS).

usage: wrap_static_gamelib.py <name> <out-dir> <obj-or-dir>...
  <name>  server_cstrike / client_cstrike / ...  -> table lib_<name>_exports
  a directory argument means every *.o below it
Environment: PS5_PAYLOAD_SDK.
"""
import os, subprocess, sys

if len(sys.argv) < 4:
    sys.exit(__doc__)
name, OUT = sys.argv[1], os.path.abspath(sys.argv[2])
SDK = os.environ['PS5_PAYLOAD_SDK']
NM, LD, OBJCOPY, CC = (os.path.join(SDK, 'bin', t) for t in ('llvm-nm', 'ld.lld', 'llvm-objcopy', 'prospero-clang'))
os.makedirs(OUT, exist_ok=True)

objs = []
for a in sys.argv[3:]:
    if os.path.isdir(a):
        for root, _, files in os.walk(a):
            objs += sorted(os.path.join(root, f) for f in files if f.endswith('.o'))
    else:
        objs.append(a)
objs = sorted(set(objs))

pre = os.path.join(OUT, f'{name}.pre.o')
subprocess.check_call([LD, '-r', '-o', pre] + objs)
syms = subprocess.check_output([NM, '--defined-only', '-g', pre], text=True).splitlines()
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
subprocess.check_call([LD, '-r', '-o', unstripped] + objs + [helper_o])
final = os.path.join(OUT, f'{name}.o')
subprocess.check_call([OBJCOPY, '-G', f'lib_{name}_exports', unstripped, final])
print(name, len(objs), 'objs,', len(exports), 'exports ->', final)
