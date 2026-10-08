# XashPS5 — Half-Life on PlayStation 5

Native PS5 homebrew port of [Xash3D FWGS](https://github.com/FWGS/xash3d-fwgs)
running Half-Life, Opposing Force, Blue Shift and Counter-Strike, rendered on the
PS5 GPU through Vulkan: OpenGL translated by Mesa **Zink**, executed by the
**RADV** driver of [PS5_Vulkan](https://github.com/mihawk-99/PS5_Vulkan).
Packaged with [ps5-native-app-boilerplate](https://github.com/blackbearreloaded/ps5-native-app-boilerplate).

**Version 1.3**: title `PPSA19111`, shown as *XashPS5 V1.3* on the home screen.

> **120 FPS: turn it on in the game.** XashPS5 starts in 4K at 60 Hz. On a
> 120 Hz display (HDMI 2.1), open **Options → Video → Video modes** and tick
> **120 Hz**: the game restarts and runs at up to 120 FPS. The console must also
> allow 120 Hz output (Settings → Screen and Video → Video Output → 120 Hz Output).

> **No game data is included.** You need your own copy of Half-Life
> (the `valve` folder from Steam), and of the expansions you want to play.
> Valve's files are not, and will never be, distributed here.

## Features

- Native PS5 title (signed `eboot.bin`), launched from the home screen like a game
- **Vulkan rendering** (Zink on RADV): **4K by default**, steady 60 FPS in busy
  scenes, and **120 FPS** on 120 Hz displays once *120 Hz* is ticked in
  Options → Video → Video modes (off by default)
- Render resolution **4K / 1440p / 1080p** from the same menu
- Half-Life single player and LAN multiplayer
- **Opposing Force** (`gearbox`), **Blue Shift** (`bshift`) and **Counter-Strike**
  (`cstrike`), switchable from the main menu with *Change game*
- Counter-Strike with its own client, server and menus
  ([cs16-client](https://github.com/Velaron/cs16-client) and ReGameDLL_CS):
  team selection, buy menu, MOTD, and a *Change team* button in the pause menu
- In-game VGUI windows (MOTD, team menus) usable with the gamepad: Cross = OK,
  Circle / Options = close
- **DualSense**: full layout, vibration, right-stick aim curve, **toggle crouch**
  (Options → Gamepad, on by default)
- **USB keyboard and mouse** (or a wireless USB receiver): WASD/arrows by key
  position on any layout, mouse look, buttons and wheel, mouse cursor in the menus.
  Typed text uses the QWERTY layout by default: `ps5_kb_layout fr` switches to AZERTY
- **PS5 system keyboard** for text fields (console, player name, chat)
- **Sound** through `sceAudioOut`
- **Debug menu** in the main menu: load any map, god mode, all weapons,
  full health, noclip, notarget, vibration test
- A notification explains what is missing when the game files aren't installed
- Custom home-screen icon and background

## Requirements

- PS5 with a homebrew-enabled firmware (tested with etaHEN; FTP server on port 2121,
  klog on 3232 for debugging)
- Linux build host (tested on Debian 13): `git`, `python3`, `make`, `cmake`,
  `ninja`, `meson`, `rsync`, `clang-18`, LLVM/Clang 19 development packages for
  Mesa (see [`vulkan/README.md`](vulkan/README.md))
- Your own game folders

## Build

```sh
git clone https://github.com/GordonProsperoMan/xash3d-ps5.git
cd xash3d-ps5
./scripts/build.sh          # sources, game code (HL, OF, BS, CS), engine
./vulkan/build_vulkan.sh    # Mesa Zink + RADV, relink, package dist/PPSA19111
```

Every upstream project is cloned at the exact commit listed in
[`patches/UPSTREAM_COMMITS.txt`](patches/UPSTREAM_COMMITS.txt) and patched with
the files in [`patches/`](patches). `build.sh` also leaves an OpenGL (G19) build
in `dist/gl/PPSA19111` for comparison. How the Vulkan path works is explained in
[`vulkan/README.md`](vulkan/README.md). The first run takes a while (Mesa is
compiled twice).

## Install

1. Copy your own game folders into `dist/PPSA19111/`: `valve/` (required) and,
   if you own them, `gearbox/`, `bshift/`, `cstrike/`. Keep the `.cfg` files and
   `extras.pk3` from this build in each folder (controls, menu graphics,
   Counter-Strike menus). If you already have an `autoexec.cfg`, just append
   its lines.
   The release zip doesn't ship `cstrike/extras.pk3` (it contains game sounds and
   maps): take it from the `cstrike` folder of `CS16Client-Linux-x86_64.tar.gz`
   in [cs16-client's releases](https://github.com/Velaron/cs16-client/releases).
2. Send it to the console:
   ```sh
   python3 scripts/deploy.py dist/PPSA19111 <ps5-ip>
   # later, engine-only redeploys:
   python3 scripts/deploy.py dist/PPSA19111 <ps5-ip> --only-engine
   ```
3. Launch **XashPS5 V1.3** from the home screen. The first launch takes a little
   longer while the shader cache is built.
4. For 120 FPS, tick **120 Hz** in Options → Video → Video modes (see above).

## Controls

### DualSense

| Button | Action |
| --- | --- |
| Left stick / right stick | Move / look |
| Cross | Jump |
| Circle | Crouch (toggle) |
| Square | Reload |
| Triangle | Use (doors, buttons, scientists) |
| R2 / L2 | Primary / secondary fire |
| R1 / L1 | Next / previous weapon |
| D-pad down | Last weapon |
| R3 | Flashlight |
| D-pad up | Flashlight (Counter-Strike: buy menu) |
| L3 | Walk |
| Options | Menu |
| Touchpad click | Scoreboard |

Layouts live in each game's `userconfig.cfg` (executed after Steam's
`config.cfg`, which starts with `unbindall`).

### Keyboard and mouse

Half-Life's PC defaults: WASD (by key position), mouse look, left/right click to
fire, wheel for weapons, Escape for the menu. Rebind them in Options → Keyboard.

## How it works (porting notes)

| Problem on PS5 native titles | Solution |
| --- | --- |
| Payload CRT (`crt1.o`) crashes as a title | boilerplate's native CRT + custom link script |
| `dlopen` unusable | engine, renderer, menus, filesystem and every game's code linked into one static binary (`scripts/build_static_gamelibs.py`, `scripts/wrap_static_gamelib.py`); the engine picks `server@<game>` / `client@<game>` / `menu@<game>` by game folder |
| `chdir` denied, `opendir` lists nothing | virtual cwd + `sceKernelGetdents` wrappers (`engine/platform/ps5/ps5_vcwd.c`) |
| Tiny default heap | 1 GB application heap from ps5-opengl's `app_heap.c` |
| The PS5 OpenGL driver submits draws one by one (40–50 ms per frame in busy scenes, even after batching to indexed triangle lists) | Mesa Zink records whole frames into Vulkan command buffers for RADV: about 2 ms of draws (see `vulkan/README.md`) |
| 120 Hz | the title declares high-frame-rate output; VideoOut is opened at 119.88 Hz only when the player ticks *120 Hz* |
| SDL2 built without audio | `sceAudioOut` backend (`engine/platform/ps5/s_ps5.c`) |
| System keyboard: `sceImeDialog*` never resolved through `sceKernelDlsym` | `sceCommonDialogInitialize` + `sceSysmoduleLoadModule(ImeDialog)` with regular imports and a link-only `libSceCommonDialog` stub, as in BlackBearReloaded's ProsperoTV |
| USB keyboard and mouse | `libSceKeyboard` / `libSceMouse` loaded through their sysmodules, batched reads of HID records (`engine/platform/ps5/kbm_ps5.c`), following BlackBearReloaded's ps5-native-gamepad-input-research; the menus get a drawn cursor (no system cursor) |
| `dup()` is a raw syscall (crash when a file inside a `.pk3` is opened) | the filesystem reopens the archive instead |
| ReGameDLL_CS loads the filesystem with `dlopen` | it gets the engine's statically linked filesystem interface |
| `exit()` raises SIGSYS in a native title | *Quit* closes the app through `sceSystemServiceLoadExec("exit")` |
| Logs | every console line mirrored to the kernel log and to `/data/xash_log.txt`; the previous run is kept as `/data/xash_log_previous.txt`. Create `/data/xash_debug.txt` for verbose output |

## Known limitations

- Counter-Strike bots (YaPB) are not included yet: play LAN or alone.
- Internet server browser untested; LAN works.
- Accented characters are not typed from a USB keyboard yet.

## Thanks

- [Mihawk](https://github.com/mihawk-99): PS5_Vulkan, PS5_Mesa and
  PS5_PayloadSDK, the RADV Vulkan driver this build renders with.
- [BlackBearReloaded](https://github.com/blackbearreloaded): ps5-opengl,
  ps5-native-app-boilerplate, ProsperoTV (system keyboard sequence) and
  ps5-native-gamepad-input-research (keyboard and mouse).
- [Velaron](https://github.com/Velaron) and contributors:
  [cs16-client](https://github.com/Velaron/cs16-client), and the
  [ReGameDLL_CS](https://github.com/rehlds/ReGameDLL_CS) team.
- [mpereiraesaa/ps5-xash3d-halflife](https://github.com/mpereiraesaa/ps5-xash3d-halflife),
  another native PS5 Xash3D port: right-stick aim curve and its tuning, and the
  release allowlist check.
- [FWGS](https://github.com/FWGS): Xash3D FWGS, hlsdk-portable, mainui_cpp.

## License

GPL-3.0-or-later, like the projects it is built on (Xash3D FWGS, ps5-opengl,
ps5-native-app-boilerplate). Mesa, ReGameDLL_CS and YaPB are MIT-licensed;
cs16-client is GPL-2.0-or-later with the Half-Life exception. hlsdk-portable is
distributed under the Half-Life SDK license terms of its upstream. Half-Life and
Counter-Strike are © Valve Corporation.
