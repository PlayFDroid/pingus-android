# Pingus for Android (PlayFDroid Edition)

This repository provides an automated, reproducible packaging and modernization pipeline for porting [Pingus](https://pingus.github.io/) to contemporary Android devices (Android 14/15/16/17+).

## Features & Improvements

- **Mobile UI Auto-Scaling**: Interfaces, blackboards, menus, and playfield elements automatically scale up to maintain comfortable readability and touch targets on high-DPI displays (with custom scaling choices `Auto`, `1.0x`, `1.5x`, `2.0x`, `2.5x`, `3.0x` in the Options menu).
- **Native 64-bit Architecture**: Optimized builds for `arm64-v8a` and `x86_64` (and `armeabi-v7a` / `x86`).
- **16 KB ELF Page-Size Alignment**: Fully aligned (`-Wl,-z,max-page-size=16384`, `zipalign -P 16 4`) to run smoothly on contemporary Android 15/16+ Linux kernels.
- **Touch-Optimized Controls**: Drag empty areas to scroll across large levels, and tap penguins directly to assign actions.
- **Complete Audio Support**: In-game tracker music and sound effects powered by OpenAL Soft with OpenSL ES output and libmodplug.
- **Privacy & Libre Compliance**: 100% tracker-free, zero advertisements, and licensed under the GNU General Public License v3.0+.

## Building Locally

### Prerequisites

- Android SDK (build-tools 35+, platform android-35)
- Android NDK (r27 or r28+)
- JDK 17 or 21
- CMake, Ninja, GLM (`sudo apt install libglm-dev`), zip, unzip

### Build Command

```bash
./build-android.sh 0.8.0-android1
```

The resulting signed and aligned package will be located at `build/output/pingus.apk`.

## Upstream & Credits

- Upstream Project: [Pingus on GitHub](https://github.com/Pingus/pingus)
- Original Author: Ingo Ruhnke and the Pingus contributors
- License: GNU General Public License v3.0 or later (GPL-3.0-or-later)
