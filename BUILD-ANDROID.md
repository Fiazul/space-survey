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
- `window/handheld/orientation = 4` (Sensor Landscape) in Godot 4.6. Value `5` is Sensor Portrait. Keep the flight HUD in landscape.
- Touch controls (`scripts/flight/touch_controls.gd`), auto-enabled on mobile. Drag empty space to steer; buttons: **THRUST** (toggle auto-fly), **BOOST**, **FIRE**, **CAP** (capture/survey, hold), **INTERACT** (F — wormholes/dock), **MAP** (M), **HOME** (H emergency return).
- `Android` export preset (arm64-v8a, package `com.fiazul.astryx`, `builds/android/Astryx.apk`).

You can preview the touch layout on desktop right now:
```
godot -- --touch     # forces touch mode; drag with the mouse, click the buttons
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
- **Touch sizing + docking (2026-09-27)**: `scripts/ui/hud_scale.gd` (`HudScale`) is the one
  place touch sizes come from. `touch_scale()` = how much a canvas unit must grow for a
  48-unit target to reach 7.6 mm (Android's 48 dp) from `screen_get_dpi()`/`screen_get_size()`,
  clamped 1.0–1.6, always 1.0 off-mobile. The overlay uses `TouchControls.overlay_scale()`
  (that wish cut down so the right cluster stays out of the 45 % joystick zone and under
  the SYSTEMS/TELEPORT buttons — ~1.25 on a 20:9 phone); the hangar uses it capped at 1.35.
  `HudScale.safe_insets()` turns `DisplayServer.get_display_safe_area()` (notch/cutout)
  into canvas-unit insets for both. On touch, `hud.gd::_touch_layout()` re-docks every
  1280×720-authored widget onto the real canvas on each `size_changed` (right-edge widgets
  keep their right gap, bottom widgets follow the true bottom, centre text re-centres); the
  toast/scan/prompt column moved to a top-centre band out of the joystick zone. Overlay
  buttons hide while docked; the touch hangar is two columns (ships | colour + finish +
  MK1/MK2 segmented toggles) with an UNDOCK button, scrolling only if the canvas is too short.
  Desktop (no `--touch`) layout is unchanged. Preview a phone on desktop:
  `TOUCH_SCALE=1.6 SAFE_INSET=60,0,0,0 SHOT_HANGAR=1 xvfb-run -a -s "-screen 0 2400x1080x24" godot --path . res://tools/render_touch_hud.tscn -- --touch`
  (the xvfb screen size IS the resolution — the project is fullscreen, `--resolution` alone is ignored).
- None of the touch feel could be tested off-device — expect to adjust `LOOK_SENS` and button sizes after the first run.

## September 23 prerelease

The flight screen has a visible **TELEPORT** button beside **SYSTEMS**. It opens the Sol planet/landmark picker without enabling DEV; large destination rows and a **CLOSE** button work by touch. The keyboard shortcut remains Ctrl+P.

`test-2026-09-23` uses version `0.12.0-dev.20260923` (Android version code `2026092301`), sensor landscape and the Mobile renderer. The APK is a signed debug build for sideload testing. Weapon defaults are 32× speed and damage, with one thin additive ray and stable converging gun aim.
