# Changelog

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
