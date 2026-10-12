#!/usr/bin/env bash
# Builds a signed debug APK for DEADLAND: AFTER ZERO with Godot (headless).
# Works on GitHub Actions (ubuntu) and GitHub Codespaces. Fails loudly at the first real problem.
set -Eeuo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.4.1}"
GODOT_RELEASE="${GODOT_RELEASE:-stable}"
PRESET_NAME="Android"                      # must match name= in export_presets.cfg
TAG="${GODOT_VERSION}-${GODOT_RELEASE}"     # 4.4.1-stable  (GitHub release tag)
TPL_VERSION="${GODOT_VERSION}.${GODOT_RELEASE}"   # 4.4.1.stable (templates folder / version.txt)
SETTINGS_VERSION="${GODOT_VERSION%.*}"      # 4.4 (editor_settings-4.4.tres)

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE_DIR="${GODOT_CACHE:-$HOME/godot-cache}"
BUILD_DIR="$PROJECT_DIR/build"
APK="$BUILD_DIR/deadland-after-zero-debug.apk"
TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/$TPL_VERSION"
CONFIG_DIR="$HOME/.config/godot"
KEYSTORE="$HOME/.android/debug.keystore"
BASE_URL="https://github.com/godotengine/godot/releases/download/$TAG"
EDITOR_BIN="Godot_v${TAG}_linux.x86_64"

die() { echo "::error::$*" >&2; exit 1; }
step() { echo; echo "==== $* ===="; }

step "1/7 Project checks"
[[ -f "$PROJECT_DIR/project.godot" ]] || die "project.godot not found in $PROJECT_DIR (it must be at the repo root)."
[[ -f "$PROJECT_DIR/export_presets.cfg" ]] || die "export_presets.cfg missing at repo root."
grep -q "^name=\"$PRESET_NAME\"" "$PROJECT_DIR/export_presets.cfg" || die "Preset \"$PRESET_NAME\" not in export_presets.cfg."
grep -q '^platform="Android"' "$PROJECT_DIR/export_presets.cfg" || die "No Android preset in export_presets.cfg."
grep -q 'import_etc2_astc=true' "$PROJECT_DIR/project.godot" || die "rendering/textures/vram_compression/import_etc2_astc must be true for Android."
mkdir -p "$CACHE_DIR" "$BUILD_DIR" "$CONFIG_DIR" "$(dirname "$KEYSTORE")"

step "2/7 Godot $TAG editor"
if [[ ! -x "$CACHE_DIR/$EDITOR_BIN" ]]; then
  curl -fL --retry 3 -o "$CACHE_DIR/editor.zip" "$BASE_URL/${EDITOR_BIN}.zip"
  unzip -o -q "$CACHE_DIR/editor.zip" -d "$CACHE_DIR"
  rm -f "$CACHE_DIR/editor.zip"
  chmod +x "$CACHE_DIR/$EDITOR_BIN"
fi
GODOT="$CACHE_DIR/$EDITOR_BIN"
"$GODOT" --headless --version

step "3/7 Export templates -> $TEMPLATES_DIR"
if [[ ! -f "$TEMPLATES_DIR/android_debug.apk" ]]; then
  TPZ="$CACHE_DIR/Godot_v${TAG}_export_templates.tpz"
  [[ -f "$TPZ" ]] || curl -fL --retry 3 -o "$TPZ" "$BASE_URL/Godot_v${TAG}_export_templates.tpz"
  rm -rf "$CACHE_DIR/tpl" && unzip -q "$TPZ" -d "$CACHE_DIR/tpl"
  mkdir -p "$TEMPLATES_DIR"
  cp -r "$CACHE_DIR/tpl/templates/." "$TEMPLATES_DIR/"
  rm -rf "$CACHE_DIR/tpl" "$TPZ"
fi
[[ -f "$TEMPLATES_DIR/android_debug.apk" ]] || die "android_debug.apk template missing."
[[ "$(tr -d '[:space:]' < "$TEMPLATES_DIR/version.txt")" == "$TPL_VERSION" ]] || die "Template version mismatch (want $TPL_VERSION)."

step "4/7 Java + Android SDK"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
[[ -n "$SDK" && -d "$SDK" ]] || die "ANDROID_HOME / ANDROID_SDK_ROOT not set."
[[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]] || die "JAVA_HOME not set to a JDK 17."
"$JAVA_HOME/bin/java" -version
[[ -x "$SDK/platform-tools/adb" ]] || die "platform-tools/adb missing in $SDK."
APKSIGNER="$(ls -1 "$SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -n1 || true)"
[[ -n "$APKSIGNER" ]] || die "No build-tools/*/apksigner in $SDK."
echo "SDK=$SDK"; echo "apksigner=$APKSIGNER"

step "5/7 Debug keystore + editor settings"
if [[ ! -f "$KEYSTORE" ]]; then
  "$JAVA_HOME/bin/keytool" -genkeypair -v -keystore "$KEYSTORE" -storepass android \
    -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US"
fi
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"
for f in "editor_settings-$SETTINGS_VERSION.tres" "editor_settings-4.tres"; do
  cat > "$CONFIG_DIR/$f" <<SETTINGS
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$SDK"
export/android/java_sdk_path = "$JAVA_HOME"
export/android/debug_keystore = "$KEYSTORE"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
SETTINGS
done

step "6/7 Import project (also compiles every GDScript)"
set +e
"$GODOT" --headless --path "$PROJECT_DIR" --import 2>&1 | tee "$BUILD_DIR/import.log"
set -e
if grep -E "SCRIPT ERROR|Parse Error|Failed to load script|Animation .* doesn't exist" "$BUILD_DIR/import.log"; then
  die "Import reported script/resource errors (see lines above)."
fi

step "7/7 Export \"$PRESET_NAME\" -> $APK"
rm -f "$APK"
set +e
"$GODOT" --headless --path "$PROJECT_DIR" --export-debug "$PRESET_NAME" "$APK" 2>&1 | tee "$BUILD_DIR/export.log"
EXPORT_STATUS=${PIPESTATUS[0]}
set -e
[[ -s "$APK" ]] || die "Godot exited with $EXPORT_STATUS and produced no APK. Read build/export.log."
"$APKSIGNER" verify --verbose "$APK"
unzip -l "$APK" | grep -q "lib/arm64-v8a/libgodot_android.so" || die "APK has no arm64 Godot library."
ls -lh "$APK"
echo "APK OK: $APK"
