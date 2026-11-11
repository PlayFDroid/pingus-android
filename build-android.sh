#!/usr/bin/env bash
# ==============================================================================
# Modern Android Packaging & Build Pipeline for Pingus (PlayFDroid Edition)
#
# Builds native 64-bit binaries (arm64-v8a, x86_64), strips debug symbols,
# applies mobile UI scaling and 16 KB page-size alignment.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
SRC_DIR="${BUILD_DIR}/pingus-src"
DEPS_DIR="${BUILD_DIR}/deps"
OUTPUT_DIR="${BUILD_DIR}/output"
STAGING_DIR="${BUILD_DIR}/staging"

PINGUS_VERSION="${1:-0.8.0-android1}"
PINGUS_COMMIT="${PINGUS_COMMIT:-ffe3851f1f9f9f5c245887d89ab4a56399c13769}"
TARGET_ABIS="${TARGET_ABIS:-arm64-v8a x86_64}"

echo "======================================================================"
echo " Building Pingus for Android: version ${PINGUS_VERSION}"
echo " Target ABIs: ${TARGET_ABIS}"
echo "======================================================================"

# ------------------------------------------------------------------------------
# 1. Environment & Toolchain Resolution
# ------------------------------------------------------------------------------
if [ -z "${ANDROID_HOME:-}" ]; then
  if [ -d "${HOME}/android-sdk" ]; then
    export ANDROID_HOME="${HOME}/android-sdk"
  elif [ -d "/usr/local/lib/android/sdk" ]; then
    export ANDROID_HOME="/usr/local/lib/android/sdk"
  else
    echo "error: ANDROID_HOME is not set and could not be detected." >&2
    exit 1
  fi
fi

resolve_ndk() {
  if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -x "${ANDROID_NDK_HOME}/ndk-build" ]; then
    printf '%s' "${ANDROID_NDK_HOME}"
    return
  fi
  if [ -x "${ANDROID_HOME}/ndk-bundle/ndk-build" ]; then
    printf '%s' "${ANDROID_HOME}/ndk-bundle"
    return
  fi
  if [ -d "${ANDROID_HOME}/ndk" ]; then
    local newest=""
    for d in "${ANDROID_HOME}/ndk"/*; do
      [ -x "$d/ndk-build" ] || continue
      newest="$d"
    done
    if [ -n "$newest" ]; then
      printf '%s' "$newest"
      return
    fi
  fi
  echo "error: ndk-build not found under ANDROID_HOME=${ANDROID_HOME}" >&2
  exit 1
}

NDK_DIR="$(resolve_ndk)"
echo "==> Using Android NDK: ${NDK_DIR}"

resolve_build_tools() {
  local bt_dir="${ANDROID_HOME}/build-tools"
  local latest=""
  for d in "${bt_dir}"/*; do
    [ -x "$d/zipalign" ] || continue
    latest="$(basename "$d")"
  done
  printf '%s' "$latest"
}

BUILD_TOOLS_VERSION="${BUILD_TOOLS_VERSION:-$(resolve_build_tools)}"
BT="${ANDROID_HOME}/build-tools/${BUILD_TOOLS_VERSION}"
echo "==> Using Build-Tools: ${BT}"

PACKAGE_PLATFORM=35
PACKAGE_JAR="${ANDROID_HOME}/platforms/android-${PACKAGE_PLATFORM}/android.jar"
if [ ! -f "${PACKAGE_JAR}" ]; then
  # Fallback to any existing platform android.jar
  PACKAGE_JAR="$(find "${ANDROID_HOME}/platforms" -name "android.jar" | sort -V | tail -1)"
  PACKAGE_PLATFORM="$(basename "$(dirname "${PACKAGE_JAR}")" | sed 's/android-//')"
fi
echo "==> Using Platform JAR: ${PACKAGE_JAR} (API ${PACKAGE_PLATFORM})"

LLVM_STRIP="$(find "${NDK_DIR}/toolchains/llvm/prebuilt" -name "llvm-strip" 2>/dev/null | head -1)"

# ------------------------------------------------------------------------------
# 2. Prepare Source Tree & Apply Patches
# ------------------------------------------------------------------------------
mkdir -p "${BUILD_DIR}" "${DEPS_DIR}" "${OUTPUT_DIR}"

if [ ! -d "${SRC_DIR}/.git" ]; then
  echo "==> Cloning upstream Pingus repository..."
  git clone https://github.com/Pingus/pingus.git "${SRC_DIR}"
  ( cd "${SRC_DIR}" && git checkout "${PINGUS_COMMIT}" )
else
  echo "==> Upstream source already present at ${SRC_DIR}"
fi

echo "==> Applying PlayFDroid modernization & UI scaling patches..."
(
  cd "${SRC_DIR}"
  git checkout -- . 2>/dev/null || true
  for p in "${SCRIPT_DIR}/patches"/*.patch; do
    [ -f "$p" ] || continue
    echo "    Applying: $(basename "$p")"
    git apply "$p"
  done
)

if [ -d "${SCRIPT_DIR}/res" ]; then
  echo "==> Staging classic Pingus launcher icons..."
  cp -a "${SCRIPT_DIR}/res"/mipmap-* "${SRC_DIR}/mk/android/app/res/"
fi

# ------------------------------------------------------------------------------
# 3. Download & Stage Dependencies
# ------------------------------------------------------------------------------
SDL_VERSION="2.30.12"
OPENAL_VERSION="1.23.1"
MODPLUG_VERSION="0.8.9.0"

if [ ! -d "${DEPS_DIR}/SDL2-${SDL_VERSION}" ]; then
  if [ -f "${HOME}/STA/deps/SDL2-${SDL_VERSION}.tar.gz" ]; then
    cp "${HOME}/STA/deps/SDL2-${SDL_VERSION}.tar.gz" "${DEPS_DIR}/"
  else
    echo "==> Downloading SDL2 ${SDL_VERSION}..."
    curl -L -o "${DEPS_DIR}/SDL2-${SDL_VERSION}.tar.gz" \
      "https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VERSION}/SDL2-${SDL_VERSION}.tar.gz"
  fi
  tar -xzf "${DEPS_DIR}/SDL2-${SDL_VERSION}.tar.gz" -C "${DEPS_DIR}"
fi

if [ ! -d "${DEPS_DIR}/openal-soft-${OPENAL_VERSION}" ]; then
  if [ ! -f "${DEPS_DIR}/openal-soft-${OPENAL_VERSION}.tar.gz" ]; then
    if [ -f "${HOME}/pingus-deps/openal-soft-${OPENAL_VERSION}.tar.gz" ]; then
      cp "${HOME}/pingus-deps/openal-soft-${OPENAL_VERSION}.tar.gz" "${DEPS_DIR}/"
    else
      echo "==> Downloading OpenAL Soft ${OPENAL_VERSION}..."
      curl -L -o "${DEPS_DIR}/openal-soft-${OPENAL_VERSION}.tar.gz" \
        "https://github.com/kcat/openal-soft/archive/refs/tags/${OPENAL_VERSION}.tar.gz"
    fi
  fi
  tar -xzf "${DEPS_DIR}/openal-soft-${OPENAL_VERSION}.tar.gz" -C "${DEPS_DIR}"
fi

if [ ! -d "${DEPS_DIR}/libmodplug-${MODPLUG_VERSION}" ]; then
  if [ ! -f "${DEPS_DIR}/libmodplug-${MODPLUG_VERSION}.tar.gz" ]; then
    if [ -f "${HOME}/pingus-deps/libmodplug-${MODPLUG_VERSION}.tar.gz" ]; then
      cp "${HOME}/pingus-deps/libmodplug-${MODPLUG_VERSION}.tar.gz" "${DEPS_DIR}/"
    else
      echo "==> Downloading libmodplug ${MODPLUG_VERSION}..."
      curl -L -o "${DEPS_DIR}/libmodplug-${MODPLUG_VERSION}.tar.gz" \
        "https://downloads.sourceforge.net/project/modplug-xmms/libmodplug/${MODPLUG_VERSION}/libmodplug-${MODPLUG_VERSION}.tar.gz"
    fi
  fi
  tar -xzf "${DEPS_DIR}/libmodplug-${MODPLUG_VERSION}.tar.gz" -C "${DEPS_DIR}"
fi

if [ ! -f "${DEPS_DIR}/stb_image.h" ]; then
  if [ -f "${HOME}/pingus-deps/stb_image.h" ]; then
    cp "${HOME}/pingus-deps/stb_image.h" "${DEPS_DIR}/"
  else
    echo "==> Downloading stb_image.h..."
    curl -L -o "${DEPS_DIR}/stb_image.h" \
      "https://raw.githubusercontent.com/nothings/stb/refs/heads/master/stb_image.h"
  fi
fi

GLM_INC="/usr/include"
if [ ! -d "${GLM_INC}/glm" ]; then
  if [ -d "/usr/local/include/glm" ]; then
    GLM_INC="/usr/local/include"
  elif [ -d "${DEPS_DIR}/glm/glm" ]; then
    GLM_INC="${DEPS_DIR}/glm"
  else
    echo "==> Downloading GLM headers..."
    mkdir -p "${DEPS_DIR}/glm"
    curl -L -o "${DEPS_DIR}/glm.tar.gz" "https://github.com/g-truc/glm/archive/refs/tags/1.0.1.tar.gz"
    tar -xzf "${DEPS_DIR}/glm.tar.gz" -C "${DEPS_DIR}/glm" --strip-components=1
    GLM_INC="${DEPS_DIR}/glm"
  fi
fi

# ------------------------------------------------------------------------------
# 4. Build SDL2 Native Libraries & Java Classes
# ------------------------------------------------------------------------------
SDL_BUILD_DIR="${BUILD_DIR}/sdl-build"
SDL_OUT_DIR="${BUILD_DIR}/sdl-out"
mkdir -p "${SDL_BUILD_DIR}" "${SDL_OUT_DIR}"

cat > "${SDL_BUILD_DIR}/Application.mk" <<EOF
APP_STL := c++_shared
APP_ABI := ${TARGET_ABIS}
APP_PLATFORM := android-24
APP_CPPFLAGS := -std=c++23 -D_LIBCPP_ENABLE_EXPERIMENTAL=1
EOF

cat > "${SDL_BUILD_DIR}/Android.mk" <<'EOF'
include $(call all-subdir-makefiles)
EOF

echo "==> Building SDL2 libraries for ${TARGET_ABIS}..."
(
  cd "${SDL_BUILD_DIR}"
  export ANDROID_HOME="${ANDROID_HOME}"
  export BUILD_TOOLS_VERSION="${BUILD_TOOLS_VERSION}"
  export COMPILE_PLATFORM="${PACKAGE_PLATFORM}"
  export PACKAGE_PLATFORM="24"
  export SDL_SRC="${DEPS_DIR}/SDL2-${SDL_VERSION}"
  export APPLICATION_MK="${SDL_BUILD_DIR}/Application.mk"
  export TOP_ANDROID_MK="${SDL_BUILD_DIR}/Android.mk"
  export NIX_BUILD_CORES="$(nproc)"

  bash "${SRC_DIR}/mk/android/scripts/build-sdl-libs.sh"

  export out="${SDL_OUT_DIR}"
  export TARGET_ABIS="${TARGET_ABIS}"
  bash "${SRC_DIR}/mk/android/scripts/install-sdl-libs.sh"
)

# ------------------------------------------------------------------------------
# 5. Build Audio Libraries (OpenAL Soft & libmodplug)
# ------------------------------------------------------------------------------
AUDIO_OUT_DIR="${BUILD_DIR}/audio-out"
mkdir -p "${AUDIO_OUT_DIR}"

echo "==> Building audio libraries (OpenAL Soft & libmodplug) for ${TARGET_ABIS}..."
(
  export ANDROID_HOME="${ANDROID_HOME}"
  export PACKAGE_PLATFORM="24"
  export TARGET_ABIS="${TARGET_ABIS}"
  export OPENAL_SRC="${DEPS_DIR}/openal-soft-${OPENAL_VERSION}"
  export MODPLUG_SRC="${DEPS_DIR}/libmodplug-${MODPLUG_VERSION}"
  export OUT_DIR="${AUDIO_OUT_DIR}"

  bash "${SRC_DIR}/mk/android/scripts/build-audio-libs.sh"
)

# ------------------------------------------------------------------------------
# 6. Build Pingus C++ Engine & Package APK
# ------------------------------------------------------------------------------
APK_BUILD_DIR="${BUILD_DIR}/apk-build"
rm -rf "${APK_BUILD_DIR}"
mkdir -p "${APK_BUILD_DIR}"

cat > "${APK_BUILD_DIR}/SDL2-prebuilt-Android.mk" <<EOF
LOCAL_PATH := \$(call my-dir)
include \$(CLEAR_VARS)
LOCAL_MODULE := SDL2
LOCAL_SRC_FILES := ${SDL_OUT_DIR}/lib/\$(TARGET_ARCH_ABI)/libSDL2.so
include \$(PREBUILT_SHARED_LIBRARY)
EOF

KEYSTORE="${SRC_DIR}/mk/android/keystore/debug.keystore"

echo "==> Compiling Pingus engine and packaging APK..."
(
  cd "${APK_BUILD_DIR}"
  export ANDROID_HOME="${ANDROID_HOME}"
  export BUILD_TOOLS_VERSION="${BUILD_TOOLS_VERSION}"
  export PACKAGE_PLATFORM="${PACKAGE_PLATFORM}"
  export TARGET_ABIS="${TARGET_ABIS}"
  export APP_NAME="pingus"
  export APP_DIR="${SRC_DIR}/mk/android/app"
  export GAME_SRC_DIR="${SRC_DIR}/src"
  export GAME_EXTERNAL_DIR="${SRC_DIR}/external"
  export GAME_DATA_DIR="${SRC_DIR}/data"
  export APPLICATION_MK="${SDL_BUILD_DIR}/Application.mk"
  export TOP_ANDROID_MK="${SDL_BUILD_DIR}/Android.mk"
  export SDL_PREBUILT_MK="${APK_BUILD_DIR}/SDL2-prebuilt-Android.mk"
  export SDL_ANDROID_LIBS="${SDL_OUT_DIR}"
  export AUDIO_ANDROID_LIBS="${AUDIO_OUT_DIR}"
  export KEYSTORE="${KEYSTORE}"
  export STB_IMAGE_H="${DEPS_DIR}/stb_image.h"
  export GLM_INCLUDE_DIR="${GLM_INC}"
  export PINGUS_VERSION="${PINGUS_VERSION}"

  bash "${SRC_DIR}/mk/android/scripts/build-apk.sh"
)

# ------------------------------------------------------------------------------
# 7. Strip Native Binaries, Align & Re-sign
# ------------------------------------------------------------------------------
FINAL_APK="${OUTPUT_DIR}/pingus.apk"
TEMP_APK="${BUILD_DIR}/temp.apk"
ALIGNED_APK="${BUILD_DIR}/aligned.apk"
rm -f "${FINAL_APK}" "${TEMP_APK}" "${ALIGNED_APK}"

cp -a "${APK_BUILD_DIR}/out/base.apk" "${TEMP_APK}"

if [ -n "${LLVM_STRIP}" ] && [ -x "${LLVM_STRIP}" ]; then
  echo "==> Stripping unneeded debug symbols from native binaries..."
  for abi in ${TARGET_ABIS}; do
    for so in "${APK_BUILD_DIR}/src/libs/${abi}"/*.so; do
      [ -f "$so" ] || continue
      "${LLVM_STRIP}" --strip-unneeded "$so"
    done
  done
fi

# Re-pack lib/ with stripped binaries
mkdir -p "${BUILD_DIR}/stage_lib"
for abi in ${TARGET_ABIS}; do
  mkdir -p "${BUILD_DIR}/stage_lib/lib/${abi}"
  cp -a "${APK_BUILD_DIR}/src/libs/${abi}"/*.so "${BUILD_DIR}/stage_lib/lib/${abi}/"
done
( cd "${BUILD_DIR}/stage_lib" && zip -u -0 "${TEMP_APK}" lib/*/*.so )
rm -rf "${BUILD_DIR}/stage_lib"

echo "==> Aligning APK to 16 KB page-size boundaries (-P 16 4)..."
"${BT}/zipalign" -f -P 16 4 "${TEMP_APK}" "${ALIGNED_APK}"

echo "==> Signing APK..."
if [ -n "${KEYSTORE_FILE:-}" ] && [ -f "${KEYSTORE_FILE}" ]; then
  echo "    Using release keystore: ${KEYSTORE_FILE}"
  "${BT}/apksigner" sign \
    --ks "${KEYSTORE_FILE}" \
    --ks-key-alias "${KEY_ALIAS:-playfdroid}" \
    --ks-pass "pass:${KEYSTORE_PASSWORD}" \
    --key-pass "pass:${KEY_PASSWORD:-${KEYSTORE_PASSWORD}}" \
    --out "${FINAL_APK}" \
    "${ALIGNED_APK}"
else
  echo "    Using debug keystore: ${KEYSTORE}"
  "${BT}/apksigner" sign \
    --ks "${KEYSTORE}" \
    --ks-pass pass:android \
    --key-pass pass:android \
    --out "${FINAL_APK}" \
    "${ALIGNED_APK}"
fi

# ------------------------------------------------------------------------------
# 8. Verification & Summary
# ------------------------------------------------------------------------------
echo "==> Verifying APK alignments and signature..."
"${BT}/zipalign" -c -v -P 16 4 "${FINAL_APK}" | grep "Verification"
"${BT}/apksigner" verify --verbose "${FINAL_APK}" | grep -E "Verifies|Verified"

FINAL_SIZE="$(du -h "${FINAL_APK}" | awk '{print $1}')"
echo "======================================================================"
echo " Pingus Android APK Build Complete!"
echo " Location : ${FINAL_APK}"
echo " Size     : ${FINAL_SIZE}"
echo " ABIs     : ${TARGET_ABIS}"
echo "======================================================================"
