#!/usr/bin/env python3
"""Deploy a XashPS5 title folder to a PS5 over FTP (etaHEN / ftpsrv).

  python3 scripts/deploy.py dist/PPSA99999 192.168.1.14 [--port 2121] [--only-engine]

Uploads every file to /data/homebrew/<TITLE_ID>/ with an atomic
STOR-to-temp + RENAME, eboot.bin and param.json last. --only-engine uploads
just eboot.bin, sce_sys/ and the two XashPS5 .cfg files (fast redeploy when
the game data is already on the console).
"""
import argparse
from ftplib import FTP, error_perm
from pathlib import Path
from posixpath import dirname, join


def ensure_dir(ftp, path):
    cur = ''
    for part in path.strip('/').split('/'):
        cur += '/' + part
        try:
            ftp.mkd(cur)
        except error_perm:
            pass


def upload(ftp, local, remote):
    ensure_dir(ftp, dirname(remote))
    tmp = join(dirname(remote), '.' + remote.rsplit('/', 1)[-1] + '.upload')
    with local.open('rb') as f:
        ftp.storbinary('STOR ' + tmp, f, blocksize=256 * 1024)
    try:
        ftp.sendcmd('DELE ' + remote)
    except error_perm:
        pass
    ftp.rename(tmp, remote)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('folder', type=Path)
    ap.add_argument('host')
    ap.add_argument('--port', type=int, default=2121)
    ap.add_argument('--user', default='anonymous')
    ap.add_argument('--password', default='')
    ap.add_argument('--only-engine', action='store_true')
    a = ap.parse_args()

    title = a.folder.resolve().name
    critical = [a.folder / 'eboot.bin', a.folder / 'sce_sys' / 'param.json']
    if a.only_engine:
        files = sorted((a.folder / 'sce_sys').rglob('*')) + [
            a.folder / 'valve' / 'userconfig.cfg', a.folder / 'valve' / 'autoexec.cfg']
        files = [p for p in files if p.is_file() and p not in critical]
    else:
        files = sorted(p for p in a.folder.rglob('*') if p.is_file() and p not in critical)
    files += critical

    root = '/data/homebrew/' + title
    with FTP() as ftp:
        ftp.connect(a.host, a.port, timeout=15)
        ftp.login(a.user, a.password)
        for i, p in enumerate(files, 1):
            rel = p.relative_to(a.folder).as_posix()
            print(f'[{i}/{len(files)}] {rel}', flush=True)
            upload(ftp, p, join(root, rel))
    print('Deployed to', root)


if __name__ == '__main__':
    main()
