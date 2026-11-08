#!/bin/bash -e

green='\033[0;32m'
red='\033[0;31m'
yellow='\033[1;33m'
nocolor='\033[0m'

deps="git meson ninja patchelf unzip curl pip3 flex bison zip glslangValidator ccache clang"
workdir="$(pwd)/turnip_workdir"
ndkver="android-ndk-r29"
ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
sdkver="34"
mesasrc="https://github.com/ВАШ_ЮЗЕР/ВАШ_РЕПО.git"   # <-- подставь свой форк
srcfolder="A8XX"
driver_name="A8XX-Y"

if [ -z "$BUILD_VERSION" ]; then
    echo -e "${red}Ошибка: переменная BUILD_VERSION не установлена!${nocolor}"
    echo "Пример: export BUILD_VERSION=1.0.0"
    exit 1
fi

clear || true

show_banner(){
    echo -e "${green}== A8XX-Y Vulkan Driver Builder v${BUILD_VERSION} ==${nocolor}"
    echo ""
}

check_deps(){
    echo -e "${yellow}Проверка системных зависимостей...${nocolor}"
    deps_missing=0
    for deps_chk in $deps; do
        if command -v "$deps_chk" >/dev/null 2>&1 ; then
            echo -e "$green ✓ $deps_chk найдено $nocolor"
        else
            echo -e "$red ✗ $deps_chk не найдено! $nocolor"
            deps_missing=1
        fi
    done
    if [ "$deps_missing" == "1" ]; then
        echo -e "${red}Установите недостающие зависимости${nocolor}"
        echo "Ubuntu: sudo apt install git meson ninja-build patchelf unzip curl python3-pip flex bison zip glslang-tools ccache clang lld"
        exit 1
    fi
    pip3 install mako pyyaml --break-system-packages &> /dev/null \
        || echo -e "${yellow}Предупреждение: не удалось поставить mako через pip${nocolor}"
    echo ""
}

prepare_workdir(){
    echo -e "${yellow}Подготовка рабочей директории...${nocolor}"
    mkdir -p "$workdir"
    cd "$workdir"

    echo -e "${yellow}Загрузка Android NDK...${nocolor}"
    if [ ! -f "$ndkver-linux.zip" ]; then
        curl -L -# "https://dl.google.com/android/repository/${ndkver}-linux.zip" --output "${ndkver}-linux.zip"
    fi
    if [ ! -d "$ndkver" ]; then
        unzip -q "${ndkver}-linux.zip"
    fi

    echo -e "${yellow}Загрузка исходников Mesa...${nocolor}"
    if [ ! -d "$srcfolder" ]; then
        git clone "$mesasrc" --depth=1 --no-single-branch "$srcfolder"
    else
        (cd "$srcfolder" && git fetch --all)
    fi
    cd "$srcfolder"

    echo "#define TUGEN8_DRV_VERSION \"v$BUILD_VERSION\"" > ./src/freedreno/vulkan/tu_version.h
}

build_lib_for_android(){
    echo -e "${yellow}==== Сборка Mesa на ветке $1 ====${nocolor}"
    git checkout --force "origin/$1"

    export PATH="$ndk:$PATH"

    cat > android-aarch64.txt <<CROSS
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
CROSS

    cat > native.txt <<NATIVE
[binaries]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
NATIVE

    rm -rf build-android-aarch64

    meson setup build-android-aarch64 \
        --cross-file android-aarch64.txt \
        --native-file native.txt \
        --prefix "/tmp/turnip-$1" \
        -Dbuildtype=release \
        -Dstrip=true \
        -Dplatforms=android \
        -Dvideo-codecs= \
        -Dplatform-sdk-version=36 \
        -Dandroid-stub=true \
        -Dgallium-drivers= \
        -Dvulkan-drivers=freedreno \
        -Dvulkan-beta=true \
        -Dfreedreno-kmds=kgsl \
        -Degl=disabled \
        -Dandroid-libbacktrace=disabled

    ninja -C build-android-aarch64 install

    if [ ! -f "/tmp/turnip-$1/lib/libvulkan_freedreno.so" ]; then
        echo -e "${red}❌ Сборка не удалась!${nocolor}"
        exit 1
    fi

    cd "/tmp/turnip-$1/lib"

    cat > meta.json <<META
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
META

    ZIP_NAME="/tmp/${driver_name}-v${BUILD_VERSION}.zip"
    rm -f "$ZIP_NAME"
    zip -q "$ZIP_NAME" libvulkan_freedreno.so meta.json
    cp "$ZIP_NAME" "$workdir/"

    echo -e "${green}✅ Архив создан: $ZIP_NAME ($(du -h "$ZIP_NAME" | cut -f1))${nocolor}"
}

show_banner
check_deps
prepare_workdir
build_lib_for_android A8XX
