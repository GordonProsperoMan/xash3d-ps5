# Changelog

## V1.3

### New
- **Vulkan rendering by default**: OpenGL runs on Mesa Zink over the RADV Vulkan driver of PS5_Vulkan (Mihawk). Whole frames go to the GPU in command buffers instead of one submit per draw: steady 60 FPS in 4K in the heaviest scenes.
- **4K by default** on a fresh install (1440p / 1080p still selectable in Options → Video → Video modes).
- **120 Hz / 120 FPS**: off by default, tick *120 Hz* in Options → Video → Video modes on a compatible display (frame cap raised to 120).
- **Counter-Strike** (your own `cstrike` folder): cs16-client and ReGameDLL_CS built into the eboot, with cs16-client's menus (team selection, buy menu, MOTD), the resolution picker, the Debug menu and a *Change team* button in the pause menu. D-pad up opens the buy menu.
- **USB keyboard and mouse**: keys by physical position, mouse look, buttons and wheel, a cursor in the menus. Typed text in QWERTY by default (`ps5_kb_layout fr` for AZERTY). Works alongside the DualSense.
- **Toggle crouch** (Circle), with a checkbox in Options → Gamepad, on by default.
- Right-stick aim curve: one circular deadzone for the whole stick plus a response curve (`joy_aim_curve`, `joy_aim_deadzone`, `joy_aim_exponent`), with look speeds 140 (yaw) / 105 (pitch). Idea and tuning from [mpereiraesaa/ps5-xash3d-halflife](https://github.com/mpereiraesaa/ps5-xash3d-halflife).
- A system notification explains what to copy when the game files are missing, instead of closing silently.
- The previous run's log is kept as `/data/xash_log_previous.txt`.
- `scripts/audit_release.py`: checks a release zip against an allowlist (no game data, correct title ID, signed eboot). Idea from mpereiraesaa/ps5-xash3d-halflife.

### Changed
- Release builds no longer run with verbose developer output or print performance counters; create `/data/xash_debug.txt` on the console to turn them back on.
- Build: `scripts/build.sh` then `vulkan/build_vulkan.sh` (Mesa Zink + RADV). The OpenGL build is still produced in `dist/gl/` for comparison.

### Fixes
- The PS5 system keyboard no longer stays disabled when an older build had saved the built-in keyboard as the fallback.
- No more crash when a file inside a `.pk3` archive is opened (`dup()` is not available to PS5 titles).

### Upgrading from 1.2
- Same title (`PPSA19111`): your game folders and saves stay in place.

## V1.2

### New
- PS5 system keyboard: text fields (console, player name, server name, chat) open the system keyboard; Xash's built-in keyboard remains as a fallback
- New permanent title ID **PPSA19111** (the boilerplate's `PPSA99999` is reserved), so XashPS5 can be listed on homebrew.page

### Upgrading from 1.0 / 1.1
- PPSA19111 is a separate title: copy your game folders (and `valve/SAVE` for your saves) from `PPSA99999`, then delete the old title

## V1.1

### New
- Opposing Force (`gearbox`) and Blue Shift (`bshift`) game code built into the eboot, selectable from the main menu with *Change game*
- Render resolution 1080p / 1440p / 4K from Options → Video (ps5-opengl SDK 1.0.0); pressing Cross on a resolution applies it and restarts the game
- In-game VGUI windows (MOTD, team menus, map briefings) usable with the gamepad: Cross = OK, Circle / Options = close

### Fixes
- *Quit Game* no longer crashes: the app closes through the system instead of `exit()` (SIGSYS)
- Menu sliders, checkboxes and arrows visible again (`extras.pk3` now shipped)

### Performance
- Character and weapon models: one draw per mesh instead of one per triangle strip
- Triangle strips, decals, sprites and particles converted to indexed triangles, the only path the PS5 OpenGL driver batches

## V1.0
- First release: Half-Life on PS5, 60 FPS, sound, DualSense with vibration, LAN, Debug menu
