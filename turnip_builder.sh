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
