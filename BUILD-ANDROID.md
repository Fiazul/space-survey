# Building Astryx for Android (APK)

The project is **APK-ready** as of v0.9.0: a mobile (Vulkan) renderer, on-screen touch
controls, and an `Android` export preset are all in place. What's left is a one-time
**toolchain setup** on your machine — Godot can't build an Android APK without the Android
SDK + a JDK + the export templates. This walks you through it end to end.

> Target check: OnePlus Nord CE 5 (Dimensity 8350, Mali-G615) supports Vulkan 1.3, so the
> `mobile` renderer is fine. If you ever see GPU glitches, switch
> `rendering/renderer/rendering_method.mobile` to `gl_compatibility` in Project Settings.

## What's already done (no action needed)
- `rendering/renderer/rendering_method.mobile = "mobile"` (Vulkan) + `scaling_3d/scale.mobile = 0.75` (phone perf). Desktop is unchanged.
- `window/handheld/orientation = 5` (Sensor Landscape) in `project.godot`, set 2026-09-09.
  It was `4` (Sensor, all four rotations): in portrait the whole HUD, authored in a fixed
  1280×720 top-left space, squeezed into the top quarter of the tall canvas because
  `canvas_items`+`expand` only adds canvas height. The touch overlay itself is now
  viewport-relative and does not overlap in any orientation (verified by capture); the rest
  of the HUD is landscape-only by design.
- Touch controls (`scripts/flight/touch_controls.gd`), auto-enabled on mobile. Drag empty space to steer; buttons: **THRUST** (toggle auto-fly), **BOOST**, **FIRE**, **CAP** (capture/survey, hold), **INTERACT** (F — wormholes/dock), **MAP** (M), **HOME** (H emergency return).
- `Android` export preset (arm64-v8a, package `com.fiazul.astryx`, `builds/android/Astryx.apk`).

You can preview the touch layout on desktop right now:
```
godot --touch        # forces touch mode; drag with the mouse, click the buttons
```

## One-time toolchain setup
1. **JDK 17** (Android builds need exactly 17):
   - `sudo apt install openjdk-17-jdk`  → confirm `java -version` shows 17.
2. **Android SDK** (command-line tools are enough; Android Studio also works):
   - Download "Command line tools only" from the Android developer site, unzip to e.g. `~/Android/Sdk/cmdline-tools/latest/`.
   - Install the needed packages:
     ```
     cd ~/Android/Sdk/cmdline-tools/latest/bin
     ./sdkmanager --sdk_root=$HOME/Android/Sdk "platform-tools" "build-tools;34.0.0" "platforms;android-34" "cmdline-tools;latest"
     ./sdkmanager --sdk_root=$HOME/Android/Sdk --licenses     # accept all
     ```
3. **Godot Android export templates** (must match your editor, 4.6.x):
   - Godot editor → **Editor → Manage Export Templates → Download and Install**.
4. **Point Godot at the SDK/JDK**: Godot → **Editor → Editor Settings → Export → Android**:
   - `Java SDK Path` → your JDK 17 home (e.g. `/usr/lib/jvm/java-17-openjdk-amd64`).
   - `Android SDK Path` → `~/Android/Sdk`.
5. **Debug keystore** (to sign debug APKs). Godot can auto-create one, or make it manually:
   ```
   keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android \
     -keystore ~/.android/debug.keystore -storepass android \
     -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
   ```
   Set it in **Editor Settings → Export → Android → Debug Keystore** (user `androiddebugkey`, pass `android`).

## Build the APK
**From the editor:** Project → Export → select **Android** → *Export Project* → save to `builds/android/Astryx.apk` (debug is fine to start). Or *Export Project (Debug)*.

**From the command line** (once the above is set):
```
godot --headless --export-debug "Android" builds/android/Astryx.apk
```
(use `--export-release "Android"` for a release build — needs a release keystore configured).

## Install on the phone
- Enable **Developer options → USB debugging** on the Nord CE 5.
- `adb install -r builds/android/Astryx.apk`  (or copy the APK over and tap it).

## Tuning notes (on-device)
- **Look sensitivity**: `LOOK_SENS` in `scripts/flight/touch_controls.gd`.
- **Performance**: lower `scaling_3d/scale.mobile` (e.g. 0.6) if the frame rate drags; raise toward 1.0 if it's smooth.
- **Button layout/size**: `touch_controls.gd::_add()` calls in `_build()` — each button is
  described as a margin from the left or right true screen edge plus a distance up from
  the true bottom edge (`_layout()` turns these into an actual `Rect2` from the current
  viewport size, and re-runs on `get_viewport().size_changed`, e.g. a device rotation).
  2026-09-09: this replaced fixed `Rect2(...)` values authored for a 1280×720 canvas,
  which overlapped hud.gd's own bottom-left (KILLS/NAV/MAP/CODEX) and bottom-right
  (TELEPORT EARTH) widgets and drifted off the true screen edges under the project's
  `canvas_items`+`expand` stretch at non-16:9 aspect ratios (reported as "hud buttons
  controller/joystick circle missing, everything missing or messed up").
- A translucent joystick ring now draws at the finger's touch-down point while
  steer-dragging (`TouchControls._draw_steer_ring`) — there was previously no visual at
  all for the steer zone, only the invisible drag-to-look behavior.
- None of the touch feel could be tested off-device — expect to adjust `LOOK_SENS` and button sizes after the first run.
