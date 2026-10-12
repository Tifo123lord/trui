# DEADLAND: AFTER ZERO (Godot 4.4.1, Android)

## Repo layout (everything at the repository ROOT)
```
project.godot                 Godot 4.4 project, Compatibility renderer, ETC2/ASTC on, landscape
export_presets.cfg            preset "Android" -> build/deadland-after-zero-debug.apk (no Gradle)
icon.png
.github/workflows/build-android.yml   CI: JDK 17 + Android SDK + Godot 4.4.1 + templates -> APK artifact
tools/ci/build_android.sh     the actual build (also runs in GitHub Codespaces)
scenes/   main.tscn (level), player.tscn, zombie.tscn
scripts/  main.gd, player.gd, zombie.gd
resources/player_frames.tres  SpriteFrames: idle walk run jump crouch melee shoot hurt
assets/sprites/player/*.png   8 transparent poses, feet aligned at bottom-center
assets/sprites/zombies/*.png  walker runner screamer tank crawler
assets/ui/*.png               touch buttons, 192px launcher icon
source_art/                   original sheets (.gdignore: not imported, not exported)
```

## Build the APK on GitHub
1. Push this layout to `main` (or Actions > Build Android APK > Run workflow).
2. When the run is green: open the run > Artifacts > `deadland-after-zero-apk` > unzip > install the APK.
3. If it fails, the step that failed prints an `::error::` line saying exactly why; `build-logs` artifact has import.log / export.log.

## Run locally (optional)
Godot 4.4.1 > Import > `project.godot` > F5.
Keys: A/D or arrows move, W/Space jump, S crouch, Shift run, J melee, K shoot, R reload.

## Known limitations (honest)
- The supplied art has ONE pose per action, not multi-frame strips. Each state shows its own pose;
  walk/run add a procedural step-bob, zombies a speed-driven sway. True frame-by-frame leg cycles need new sprite strips.
- No audio files exist in the project yet, so there is no sound.
- Inventory/crafting/save from the web prototype are not in this Godot build yet.
- Debug-signed APK (fine for sideloading, not for Play Store).
