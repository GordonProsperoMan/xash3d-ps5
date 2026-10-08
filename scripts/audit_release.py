#!/usr/bin/env python3
"""Check a release zip before publishing it.

usage: python3 scripts/audit_release.py PPSA19111.zip [TITLEID]

Fails (exit 1) when the archive contains anything outside the allowlist below,
in particular game data (maps, models, sounds, wads, saves, game DLLs), or when
the title folder / param.json / signed eboot are not what the catalog expects.
Idea taken from mpereiraesaa/ps5-xash3d-halflife (PUBLICATION_ALLOWLIST.txt).
"""
import fnmatch, json, re, sys, zipfile

ALLOW = [
    'eboot.bin',
    'sce_module/libc.prx',
    'sce_sys/param.json', 'sce_sys/icon0.png', 'sce_sys/pic0.dds',
    'sce_sys/pic1.dds', 'sce_sys/snd0.at9',
    '*/userconfig.cfg', '*/autoexec.cfg', '*/LISEZMOI_README.txt',
    'valve/extras.pk3',
]
GAME_DIRS = {'valve', 'gearbox', 'bshift', 'cstrike'}
FORBIDDEN = re.compile(r'\.(bsp|mdl|spr|wad|wav|mp3|pak|sav|hl[0-9]|dll|so|dylib|gam|res|tga|bmp)$', re.I)


def main():
    path = sys.argv[1]
    tid = sys.argv[2] if len(sys.argv) > 2 else 'PPSA19111'
    errors = []
    with zipfile.ZipFile(path) as z:
        names = [n for n in z.namelist() if not n.endswith('/')]
        for n in names:
            if not n.startswith(tid + '/'):
                errors.append(f'outside {tid}/: {n}')
                continue
            rel = n[len(tid) + 1:]
            top = rel.split('/', 1)[0]
            if FORBIDDEN.search(rel):
                errors.append(f'game data / binary not allowed: {n}')
            elif not any(fnmatch.fnmatchcase(rel, a) for a in ALLOW):
                errors.append(f'not in allowlist: {n}')
            elif '/' in rel and top not in GAME_DIRS | {'sce_sys', 'sce_module'}:
                errors.append(f'unexpected folder: {n}')
        for need in ('eboot.bin', 'sce_sys/param.json', 'sce_sys/icon0.png', 'sce_module/libc.prx'):
            if f'{tid}/{need}' not in names:
                errors.append(f'missing {tid}/{need}')
        if f'{tid}/sce_sys/param.json' in names:
            p = json.loads(z.read(f'{tid}/sce_sys/param.json'))
            if p.get('titleId') != tid:
                errors.append(f"param.json titleId is {p.get('titleId')}, expected {tid}")
            if not re.fullmatch(r'\d\d\.\d\d\d\.\d\d\d', p.get('contentVersion', '')):
                errors.append(f"bad contentVersion {p.get('contentVersion')!r}")
            print(f"param.json: {p.get('titleId')} {p.get('contentVersion')} "
                  f"\"{p.get('localizedParameters', {}).get('en-US', {}).get('titleName')}\"")
        if f'{tid}/eboot.bin' in names:
            head = z.read(f'{tid}/eboot.bin')[:4]
            if head == b'\x7fELF':
                errors.append('eboot.bin is an unsigned ELF, sign it first')
    for e in errors:
        print('ERROR:', e)
    print(f'{len(names)} files checked, {len(errors)} error(s)')
    sys.exit(1 if errors else 0)


if __name__ == '__main__':
    main()
