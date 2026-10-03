# XashPS5 — Half-Life on PlayStation 5

Native PS5 homebrew port of [Xash3D FWGS](https://github.com/FWGS/xash3d-fwgs)
running Half-Life through [hlsdk-portable](https://github.com/FWGS/hlsdk-portable),
rendered with real hardware OpenGL via
[ps5-opengl](https://github.com/blackbearreloaded/ps5-opengl) and packaged with
[ps5-native-app-boilerplate](https://github.com/blackbearreloaded/ps5-native-app-boilerplate).

**Version 1.0** — title `PPSA99999`, shown as *XashPS5 V1.0* on the home screen.

> **No game data is included.** You need your own copy of Half-Life
> (the `valve` folder from Steam). Valve's files are not, and will never be,
> distributed here.

## Features

- Native PS5 title (signed `eboot.bin`), launched from the home screen like a game
- Hardware OpenGL 3.3 Core through the PS5 GPU, **locked 60 FPS** with vsync
- Half-Life single player and LAN multiplayer (game logic statically linked —
  native titles have no working `dlopen`)
- **Sound** through `sceAudioOut` (mixer at 44.1 kHz, resampled to 48 kHz)
- **DualSense**: full controller layout, **vibrations** (damage, screen shake, weapon recoil)
- On-screen keyboard (Xash built-in) for the console, player name, server name…
- **Debug menu** in the main menu: load any map, god mode, all weapons,
  full health, noclip, notarget, vibration test
- Custom home-screen icon and background

## Requirements

- PS5 with a homebrew-enabled firmware (tested with etaHEN; FTP server on port 2121,
  klog on 3232 for debugging)
- Linux or WSL build host: `git`, `python3`, `make`, `cmake`, `ninja`, `meson`,
  a host C/C++ compiler (the PS5 clang/lld toolchain is fetched by the boilerplate)
- Your own Half-Life `valve` folder

## Build

```sh
git clone https://github.com/GordonProsperoMan/xash3d-ps5.git
cd xash3d-ps5
./scripts/build.sh
```

`build.sh` clones every upstream project at the exact commit listed in
[`patches/UPSTREAM_COMMITS.txt`](patches/UPSTREAM_COMMITS.txt), applies the
XashPS5 patches, builds the payload SDK + libc runtime, the OpenGL SDK and its
SDL2 bridge, hlsdk-portable and the engine, then signs and packages the title
into `dist/PPSA99999/`. The first run takes a while (Mesa is compiled).

## Install

1. Copy your Half-Life `valve` folder into `dist/PPSA99999/valve/`
   (keep the `userconfig.cfg` and `autoexec.cfg` from this repo — they hold the
   PS5 controls and performance settings; if you already have an
   `autoexec.cfg`, just append its lines).
2. Send it to the console:
   ```sh
   python3 scripts/deploy.py dist/PPSA99999 <ps5-ip>
   # later, engine-only redeploys:
   python3 scripts/deploy.py dist/PPSA99999 <ps5-ip> --only-engine
   ```
3. Launch **XashPS5 V1.0** from the home screen.

## Controls (DualSense)

| Button | Action |
| --- | --- |
| Left stick / right stick | Move / look |
| Cross | Jump |
| Circle | Crouch |
| Square | Reload |
| Triangle | Use (doors, buttons, scientists) |
| R2 / L2 | Primary / secondary fire |
| R1 / L1 | Next / previous weapon |
| D-pad down | Last weapon |
| R3 or D-pad up | Flashlight |
| L3 | Walk |
| Options | Menu |
| Create / touchpad click | Scoreboard |

Layout lives in `valve/userconfig.cfg` (executed after Steam's `config.cfg`,
which starts with `unbindall`).

## How it works (porting notes)

| Problem on PS5 native titles | Solution |
| --- | --- |
| Payload CRT (`crt1.o`) crashes as a title | boilerplate's native CRT + custom link script |
| `dlopen` unusable | engine, renderer, menu, filesystem and Half-Life DLLs linked into one static binary (`scripts/build_static_gamelibs.py`) |
| `chdir` denied, `opendir` lists nothing | virtual cwd + `sceKernelGetdents` wrappers (`engine/platform/ps5/ps5_vcwd.c`) |
| Tiny default heap | 1 GB application heap from ps5-opengl's `app_heap.c` |
| SDL2 built without audio | `sceAudioOut` backend (`engine/platform/ps5/s_ps5.c`) |
| ~1 FPS: every immediate-mode draw was a synchronous GPU submit | fans/quads converted to indexed `GL_TRIANGLES`, client indices streamed to a buffer, world drawn through VBOs (`gl_vbo 1`) → driver batches draws, 60 FPS |
| Logs | every console line mirrored to the kernel log (`sceKernelDebugOutText`) |

## Known limitations

- The PS5 system keyboard (`sceImeDialog`) cannot be resolved from a native title
  yet; Xash's built-in on-screen keyboard is used instead.
- Internet server browser untested; LAN works.
- Debug logging (`-dev 2`, performance counters) is still enabled in this build.

## License

GPL-3.0-or-later, like the projects it is built on (Xash3D FWGS, ps5-opengl,
ps5-native-app-boilerplate). hlsdk-portable is distributed under the Half-Life
SDK license terms of its upstream. Half-Life is © Valve Corporation.
