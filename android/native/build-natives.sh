#!/usr/bin/env bash
# Builds the native libraries OpenRA needs on Android (arm64-v8a) with the Android NDK,
# and copies SDL's Java sources into the app project.
#
#   libSDL2.so      window, input, GL ES context     (SDL2-CS binds "SDL2")
#   libsoft_oal.so  OpenAL Soft audio                (OpenAL-CS binds "soft_oal")
#   libfreetype6.so font rendering                   (OpenRA binds "freetype6")
#   liblua51.so     Lua 5.1 for map scripts          (Eluant binds "lua51")
#   libmain.so      SDL_main bridge into .NET        (android/native/main.c)
set -euo pipefail

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-}}"
if [ -z "$NDK" ] || [ ! -d "$NDK" ]; then
	echo "Set ANDROID_NDK_HOME to an Android NDK (r26 or newer)" >&2
	exit 1
fi

API=24
ABI=arm64-v8a
SDL_TAG=release-2.32.10
OPENAL_TAG=1.24.3
FREETYPE_TAG=VER-2-13-3
LUA_VERSION=5.1.5

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${WORK:-$ROOT/build/native}"
OUT="$ROOT/android/OpenRA.Android/libs/$ABI"
JAVA_OUT="$ROOT/android/OpenRA.Android/java/org/libsdl/app"
CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android${API}-clang"
LDFLAGS_16K="-Wl,-z,max-page-size=16384"

TOOLCHAIN=(
	-G Ninja
	-DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake"
	-DANDROID_ABI=$ABI
	-DANDROID_PLATFORM=android-$API
	-DANDROID_STL=c++_static
	-DCMAKE_BUILD_TYPE=Release
	-DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS_16K"
)

mkdir -p "$WORK" "$OUT" "$JAVA_OUT"
cd "$WORK"

# Copies the real (non-symlink) shared library matching a pattern and fixes its soname.
install_lib() {
	local search_dir="$1" pattern="$2" target="$3"
	local found
	found="$(find "$search_dir" -maxdepth 2 -name "$pattern" -type f | head -n1)"
	if [ -z "$found" ]; then
		echo "Could not find $pattern in $search_dir" >&2
		find "$search_dir" -maxdepth 2 -name '*.so*' >&2 || true
		exit 1
	fi
	cp "$found" "$OUT/$target"
	patchelf --set-soname "$target" "$OUT/$target"
	echo "Installed $target (from $found)"
}

echo "=== SDL2 $SDL_TAG"
[ -d SDL ] || git clone --depth 1 --branch "$SDL_TAG" https://github.com/libsdl-org/SDL.git SDL
cmake -S SDL -B SDL/build "${TOOLCHAIN[@]}" -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF -DSDL_HIDAPI=ON
cmake --build SDL/build
install_lib SDL/build 'libSDL2*.so*' libSDL2.so
cp SDL/android-project/app/src/main/java/org/libsdl/app/*.java "$JAVA_OUT/"

echo "=== OpenAL Soft $OPENAL_TAG"
[ -d openal-soft ] || git clone --depth 1 --branch "$OPENAL_TAG" https://github.com/kcat/openal-soft.git openal-soft
cmake -S openal-soft -B openal-soft/build "${TOOLCHAIN[@]}" \
	-DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF -DALSOFT_INSTALL=OFF \
	-DALSOFT_BACKEND_OPENSL=ON -DALSOFT_REQUIRE_OPENSL=ON \
	-DCMAKE_CXX_FLAGS="-include cstdlib"
cmake --build openal-soft/build
install_lib openal-soft/build 'libopenal.so*' libsoft_oal.so

echo "=== FreeType $FREETYPE_TAG"
[ -d freetype ] || git clone --depth 1 --branch "$FREETYPE_TAG" https://github.com/freetype/freetype.git freetype
cmake -S freetype -B freetype/build "${TOOLCHAIN[@]}" -DBUILD_SHARED_LIBS=ON \
	-DFT_DISABLE_ZLIB=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON
cmake --build freetype/build
install_lib freetype/build 'libfreetype.so*' libfreetype6.so

echo "=== Lua $LUA_VERSION"
if [ ! -d "lua-$LUA_VERSION" ]; then
	curl -fsSL "https://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz" -o lua.tar.gz
	tar -xzf lua.tar.gz
fi
LUA_SOURCES=$(ls "lua-$LUA_VERSION"/src/*.c | grep -v -E '/(lua|luac|print)\.c$')
# shellcheck disable=SC2086
"$CC" -shared -fPIC -O2 -DLUA_USE_POSIX -DLUA_USE_DLOPEN $LDFLAGS_16K -Wl,-soname,liblua51.so \
	-o "$OUT/liblua51.so" $LUA_SOURCES -lm -ldl
echo "Installed liblua51.so"

echo "=== libmain (SDL_main bridge)"
"$CC" -shared -fPIC -O2 $LDFLAGS_16K -Wl,-soname,libmain.so \
	-o "$OUT/libmain.so" "$ROOT/android/native/main.c" -llog
echo "Installed libmain.so"

echo "=== Stripping debug info"
"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" --strip-unneeded "$OUT"/*.so

ls -la "$OUT"
