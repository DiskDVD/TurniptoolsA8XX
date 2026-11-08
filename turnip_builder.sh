#!/bin/bash -e

green='\033[0;32m'
red='\033[0;31m'
yellow='\033[1;33m'
nocolor='\033[0m'

# ---------- Настройки ----------
mesasrc="https://github.com/DiskDVD/MesaA8XX.git"
branch="A8XX"
srcfolder="A8XX"
driver_name="A8XX-Y"
ndkver="android-ndk-r29"
sdkver="34"
platform_sdk="36"

workdir="$(pwd)/turnip_workdir"
ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
# -------------------------------

if [ -z "$BUILD_VERSION" ]; then
    echo -e "${red}Ошибка: BUILD_VERSION не задана (пример: export BUILD_VERSION=1.0)${nocolor}"
    exit 1
fi

case "$mesasrc" in
    *ВАШ_*)
        echo -e "${red}Ошибка: в mesasrc стоит заглушка, укажи URL своего форка Mesa${nocolor}"
        exit 1
        ;;
esac

# meson и ninja ставит workflow, здесь только проверка
for tool in git meson ninja patchelf unzip curl flex bison zip ccache clang glslangValidator pkg-config; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo -e "${red}Не найдено: $tool${nocolor}"
        exit 1
    fi
done
echo "meson: $(meson --version), ninja: $(ninja --version)"

pip3 install mako pyyaml --break-system-packages >/dev/null 2>&1 || true

echo -e "${green}== $driver_name v$BUILD_VERSION ==${nocolor}"

# ---------- Подготовка ----------
mkdir -p "$workdir"
cd "$workdir"

if [ ! -f "$ndkver-linux.zip" ]; then
    echo -e "${yellow}Загрузка NDK...${nocolor}"
    curl -L -# "https://dl.google.com/android/repository/${ndkver}-linux.zip" -o "${ndkver}-linux.zip"
fi
if [ ! -d "$ndkver" ]; then
    unzip -q "${ndkver}-linux.zip"
fi

if [ ! -d "$srcfolder" ]; then
    echo -e "${yellow}Клонирование Mesa...${nocolor}"
    git clone "$mesasrc" --depth=1 --branch "$branch" "$srcfolder"
fi
cd "$srcfolder"
git checkout --force "$branch"

printf '#define TUGEN8_DRV_VERSION "v%s"\n' "$BUILD_VERSION" > src/freedreno/vulkan/tu_version.h

# ---------- Сборка ----------
export PATH="$ndk:$PATH"

cat > android-aarch64.txt <<CROSS_END
[binaries]
ar = '$ndk/llvm-ar'
c = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang']
cpp = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = '$ndk/ld.lld'
cpp_ld = '$ndk/ld.lld'
strip = '$ndk/llvm-strip'
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=$ndk/pkg-config', '/usr/bin/pkg-config']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
CROSS_END

cat > native.txt <<NATIVE_END
[binaries]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
NATIVE_END

rm -rf build-android-aarch64

meson setup build-android-aarch64 \
    --cross-file android-aarch64.txt \
    --native-file native.txt \
    --prefix /tmp/turnip-out \
    -Dbuildtype=release \
    -Dstrip=true \
    -Dplatforms=android \
    -Dvideo-codecs= \
    -Dplatform-sdk-version="$platform_sdk" \
    -Dandroid-stub=true \
    -Dgallium-drivers= \
    -Dvulkan-drivers=freedreno \
    -Dvulkan-beta=true \
    -Dfreedreno-kmds=kgsl \
    -Degl=disabled \
    -Dandroid-libbacktrace=disabled

ninja -C build-android-aarch64 install

if [ ! -f /tmp/turnip-out/lib/libvulkan_freedreno.so ]; then
    echo -e "${red}Сборка не удалась: libvulkan_freedreno.so не найден${nocolor}"
    exit 1
fi

# ---------- Упаковка ----------
cd /tmp/turnip-out/lib

cat > meta.json <<META_END
{
  "schemaVersion": 1,
  "name": "${driver_name} v${BUILD_VERSION}",
  "description": "A8XX Vulkan Driver для Android",
  "author": "whitebelyash / DVD",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "Vulkan 1.4.335",
  "minApi": 28,
  "libraryName": "libvulkan_freedreno.so"
}
META_END

zip_name="${driver_name}-v${BUILD_VERSION}.zip"
rm -f "$workdir/$zip_name"
zip -q "$workdir/$zip_name" libvulkan_freedreno.so meta.json

echo -e "${green}Готово: $workdir/$zip_name ($(du -h "$workdir/$zip_name" | cut -f1))${nocolor}"
