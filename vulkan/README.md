# XashPS5 — Vulkan rendering (Zink + RADV)

Since **V1.3**, XashPS5 renders **OpenGL translated to Vulkan** by Mesa **Zink**,
executed by the **RADV** Vulkan driver from
[PS5_Vulkan](https://github.com/mihawk-99/PS5_Vulkan). This page explains why
and how. The OpenGL build through ps5-opengl ("G19" driver) is still produced by
`scripts/build.sh` in `dist/gl/` for comparison.

| Build | Output | Rendering |
| --- | --- | --- |
| **Release** | **`dist/PPSA19111`** | OpenGL 4.6 → Zink → Vulkan 1.4 → RADV → PS5 GPU |
| Comparison | `dist/gl/PPSA19111` | Native OpenGL 3.3 (ps5-opengl, G19 driver) |

> **No game data is included** (no `valve`, `gearbox`, `bshift` or `cstrike`).
> You need your own copy of Half-Life and its expansions.

---

## 1. Why a Vulkan build?

The OpenGL build held 60 FPS in quiet scenes but dropped to **14–35 FPS** as soon
as characters, bullet impacts or effects were on screen. The `PS5PERF` counters
in the logs showed the **GPU was not the bottleneck**:

- one model draw cost **0.1–0.4 ms of CPU** inside the G19 driver;
- at 900–1,800 draws per frame, that meant **40–50 ms per frame**;
- the G19 driver only batches indexed `GL_TRIANGLES` draws whose data already
  lives in GPU memory. Everything else is submitted to the GPU one draw at a
  time, with a wait each time.

V1.x already works around this as far as it can: triangle fans and strips are
converted to indexed lists, models are merged into one draw per mesh, and the
world is drawn from VBOs. The per-draw cost of the driver remains the limit.

**Zink** records a whole frame into Vulkan command buffers and submits them in
bulk. **RADV**, Mesa's AMD Vulkan driver ported to the PS5 by PS5_Vulkan
(validated against the Khronos CTS, used by vkQuake and RetroArch), executes
those command buffers.

### Measured on console

Measured in **4K (3840×2160)** on map `c1a4f`, same engine and same game:

| | V1.x (OpenGL G19) | **Zink + RADV** |
| --- | --- | --- |
| Menu | 59–60 FPS | 60 FPS, 0.6 ms of draws |
| Busy scene (~1,700 draws) | 40–50 ms of draws → 14–30 FPS | **2.2 ms of draws → 56–60 FPS** |
| In-game average | varies | **59.3 FPS**, min 54 |

Most of the remaining frame time is spent waiting for vsync: the GPU has
headroom, even in 4K.

---

## 2. Architecture

```
Half-Life (hlsdk-portable, statically linked)
        │
Xash3D FWGS (ref_gl, gl2shim) ── same as V1.x, no engine change
        │  OpenGL calls
SDL2 (ps5-opengl "G19" video driver) ── unchanged: it calls EGL
        │  eglInitialize / eglCreateWindowSurface / eglSwapBuffers …
ps5_zink_egl.c ── NEW: small EGL 1.4 frontend (same subset as G19)
        │
Mesa 26.2: OpenGL state tracker (st/mesa) + GLSL → NIR
        │
Zink (Gallium → Vulkan) ── patched: RADV linked statically + PS5 display
        │  Vulkan 1.4
RADV + ACO (PS5_Mesa, "ps5" winsys) ── AGC submissions, direct memory
        │  VK_KHR_display on VideoOut
PS5 GPU
```

Everything is linked into **one signed `eboot.bin` of about 48 MB**. A native PS5
title has no usable `dlopen`, so there is no Vulkan loader and no `.so`.

---

## 3. What was changed (and why)

The Mesa/Zink changes are in
[`patches/ps5-mesa-zink.patch`](../patches/ps5-mesa-zink.patch). It applies on
PS5_Mesa `0b2d6d1`, the exact RADV revision PS5_Vulkan uses.

### 3.1 Zink calls RADV directly (`zink_screen.c`, `meson.build`)

Normally Zink does `dlopen("libvulkan.so.1")` and asks the Vulkan loader for
`vkGetInstanceProcAddr`. The PS5 has neither `dlopen` nor a loader. With
`ZINK_PS5_STATIC_RADV` (enabled automatically when `radv-winsys=ps5`), Zink
takes RADV's ICD entry points straight from the same binary:
`vk_icdGetInstanceProcAddr` and `vk_common_GetDeviceProcAddr`. This is the
same approach as PS5_Vulkan's own `radv_smoke`.

### 3.2 PS5 display support in Zink (`zink_kopper.c/.h`, `zink_instance.py`, `kopper_interface.h`)

Zink's "kopper" swapchain layer only knew X11, Wayland and Win32. The patch adds
a `KOPPER_PS5` type:

- the `VK_KHR_display` instance extension is enabled;
- the surface is created with `vkCreateDisplayPlaneSurfaceKHR` on the single
  VideoOut display exposed by PS5_Vulkan's WSI (`wsi_common_videoout.c`), the
  same path vkQuake uses;
- the generic `kopper_vk_surface_create_storage` is enlarged so it can hold a
  `VkDisplaySurfaceCreateInfoKHR`.

### 3.3 EGL frontend (`src/gallium/frontends/ps5egl/ps5_zink_egl.c`)

ps5-opengl's SDL2 ("G19" driver) talks EGL. Rather than modifying SDL and the
engine, this branch provides an EGL implementation of the same functions:
`eglGetDisplay`, `eglInitialize`, `eglChooseConfig`, `eglCreateWindowSurface`,
`eglCreateContext`, `eglMakeCurrent`, `eglSwapBuffers`, `eglSwapInterval`,
`eglQuerySurface`, `eglGetProcAddress`, `eglTerminate`… plus the
`eglSetDisplayModePS5` extension used by the 1080p/1440p/4K choice in the
Video menu.

Key points:

- **The swapchain is always 3840×2160.** RADV's VideoOut WSI exposes a single
  mode: 4K. The game renders into a back buffer at its own resolution (1080p,
  1440p or 4K). Just before presenting, a GPU `pipe->blit` scales that buffer
  (linear filter) into the swapchain image.
  - Without this, a 1080p frame only filled a quarter of the screen (bottom
    left), and the rest showed uninitialised memory that flickered.
- **Presentation**: `flush_frontbuffer` → `zink_kopper_present_queue`, like
  Mesa's DRI "kopper" frontend.
- **Logging**: frontend messages and Mesa/RADV output (`stderr`, redirected
  with `ps5_klog_capture_stderr`) go to the console's klog (port 3232 with
  etaHEN).

### 3.4 Linking (`vulkan/link_xash_zink.py`)

The engine is **not recompiled**. The script reuses the objects produced by
`scripts/build.sh` (waf's own link line) and links them against SDL2,
`libps5zinkegl`, Mesa/Zink and RADV, following PS5_Vulkan's link recipe
(`tools/radv-link.sh`). Each adjustment below was found on real hardware:

| Problem | Fix |
| --- | --- |
| Zink and RADV both contain `vk_dispatch_table.c` (duplicate symbols) | that object is removed from the Zink archive (`libzink_ps5.a`) |
| `_ZTH23_mesa_glapi_tls_Context` (C++ TLS wrapper) stays undefined, and the native tool refuses to link | defined (empty) in `ps5_zink_egl.c` |
| **Crash at launch** (jump to address `0x300` while loading the palette): `strcasestr`, `isatty` and `mkstemp` were resolved from `libScePosixForWebKit`, which is not loaded in a game process | local implementations in [`xash_zink_shims.c`](xash_zink_shims.c), kept internal by [`xash_zink_local.map`](xash_zink_local.map) |
| `getpwuid` missing from the system libc | stub: the engine falls back to its default player name |
| Memory heap | PS5_Vulkan's platform heap (growable arenas in direct memory) replaces ps5-opengl's `app_heap.c` |
| Xash's virtual cwd (`ps5_vcwd.c`) wraps `access/opendir/readdir/closedir`, which the platform also redirects | both are kept: `__wrap_*` (Xash) → `ps5_*` (platform) |

---

## 4. Building

You need a Linux host (tested on Debian 13).

```sh
git clone https://github.com/GordonProsperoMan/xash3d-ps5.git
cd xash3d-ps5

# 1) Pinned sources + patches, SDKs, game code (HL/OF/BS/CS), engine objects
./scripts/build.sh

# 2) Vulkan build: PS5_Vulkan + PS5_Mesa + PS5_PayloadSDK, Mesa (RADV+Zink+GL), relink, package
sudo apt install meson ninja-build rsync clang-18 llvm-19-dev libclang-19-dev \
     libclang-cpp19-dev libclc-19 libclc-19-dev libllvmspirvlib-19-dev llvm-spirv-19 \
     python3-mako python3-yaml python3-ply glslang-tools spirv-tools
./vulkan/build_vulkan.sh
```

Output: `dist/PPSA19111/` (`eboot.bin`, `sce_module/libc.prx`, `sce_sys/`, the
`.cfg` files of each game folder, `valve/extras.pk3` and `cstrike/extras.pk3`).

Every upstream revision is pinned in
[`patches/UPSTREAM_COMMITS.txt`](../patches/UPSTREAM_COMMITS.txt):

| Project | Revision |
| --- | --- |
| xash3d-fwgs / mainui_cpp | `1414fc2` / `64b3ed5` |
| hlsdk-portable (HL / opfor / bshift) | `6c168fc` / `172aec8` / `1cd7ae9` |
| ps5-native-app-boilerplate / ps5-opengl / SDL | `4f531c4` / `dce7491` / `8c56053` |
| **PS5_Vulkan / PS5_Mesa / PS5_PayloadSDK** | **`3f3ee69` / `0b2d6d1` / `95c08f2`** |
| cs16-client (ReGameDLL_CS, mainui_cpp fork) | `e30e27c` |

Rough timings on 8 cores: RADV + Zink + Mesa GL ≈ 2 min, relink ≈ 1 min.

## 5. Installing

1. Copy **your own** game folders into `dist/PPSA19111/`: `valve/` (required)
   and, depending on what you own, `gearbox/` (Opposing Force), `bshift/` (Blue
   Shift) and `cstrike/`. Keep this repo's `userconfig.cfg` / `autoexec.cfg` in
   each folder: they hold the DualSense controls and settings.
2. Send everything to the console (etaHEN FTP, port 2121):
   ```sh
   python3 scripts/deploy.py dist/PPSA19111 <ps5-ip>
   ```
3. Launch **XashPS5 V1.3** from the home screen.

On first launch, Zink and RADV compile their shaders and cache them in
`radv-shader-cache/` inside the title folder. Later launches are faster.

## 6. Status and known limitations

Tested on console:

- boot, full-screen menu, loading a save, gameplay in 1080p and in 4K;
- switching resolution from the Video menu;
- performance (see §1).

- Half-Life, Opposing Force, Blue Shift and Counter-Strike, sound, DualSense,
  vibration, PS5 system keyboard, USB keyboard and mouse;
- **120 Hz**: with *120 Hz* ticked in Video modes, VideoOut is opened at
  119.88 Hz (the title declares high-frame-rate output in `param.json`
  `attribute3`) and the frame cap goes to 120. Verified at 120 FPS in 4K.

Notes:

- `vkEnumerateInstanceLayerProperties failed` in the log is harmless: there are
  no Vulkan layers on the PS5;
- RADV's pipeline cache is read and written in the title folder; it can be
  deleted safely;
- verbose logging (`-dev 2`, `PS5PERF`) is off unless `/data/xash_debug.txt` exists;
- `scripts/build.sh` and `vulkan/build_vulkan.sh` have not yet been run from a
  completely clean checkout. The console builds were made from the same
  patches and the same commands, step by step.

## 7. Credits

- [Xash3D FWGS](https://github.com/FWGS/xash3d-fwgs),
  [hlsdk-portable](https://github.com/FWGS/hlsdk-portable),
  [mainui_cpp](https://github.com/FWGS/mainui_cpp)
- [PS5_Vulkan](https://github.com/mihawk-99/PS5_Vulkan),
  [PS5_Mesa](https://github.com/mihawk-99/PS5_Mesa),
  [PS5_PayloadSDK](https://github.com/mihawk-99/PS5_PayloadSDK) — Mihawk-99 (RADV for PS5)
- [ps5-opengl](https://github.com/blackbearreloaded/ps5-opengl),
  [ps5-native-app-boilerplate](https://github.com/blackbearreloaded/ps5-native-app-boilerplate) — BlackBearReloaded
- [cs16-client](https://github.com/Velaron/cs16-client) — Velaron, and
  [ReGameDLL_CS](https://github.com/rehlds/ReGameDLL_CS)
- [Mesa](https://gitlab.freedesktop.org/mesa/mesa) (Zink, RADV, ACO)
- [ps5-payload-dev SDK / SDL](https://github.com/ps5-payload-dev)

License: GPL-3.0-or-later (see `LICENSE`). Mesa is MIT-licensed, and so is the
`ps5_zink_egl.c` frontend. Half-Life is © Valve Corporation; no game files are
distributed here.
