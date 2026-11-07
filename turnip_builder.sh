name: Build "turnip"

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to build (example: 0.6)'
        required: true
        type: string

jobs:
  start_building_turnip:
    runs-on: ubuntu-24.04
    env:
      BUILD_VERSION: ${{ inputs.version }}

    steps:
    - name: Checkout
      uses: actions/checkout@v4

    - name: Prepare environment
      run: |
        # deb-src (может понадобиться скрипту)
        sudo sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources || true
        sudo apt update

        # ВАЖНО: НЕ ставим meson из apt (там 1.5.1, проект требует >= 1.7.0).
        # Ставим всё остальное, включая ccache (скрипт использует его в cross-файле).
        sudo apt install -y \
          build-essential flex bison glslang-tools \
          python3-pip python3-venv python3-mako python3-numpy python3-setuptools \
          libdrm-dev libx11-dev libx11-xcb-dev libxcb1-dev libxcb-dri2-0-dev \
          libxrandr-dev libxext-dev libwayland-dev libegl-dev libgles-dev \
          pkg-config git patchelf unzip zip curl ccache

        # Изолированное окружение с Meson 1.7.0 + ninja
        python3 -m venv /opt/meson-venv
        /opt/meson-venv/bin/pip install --upgrade pip
        /opt/meson-venv/bin/pip install "meson==1.7.0" ninja

        # КЛЮЧЕВОЕ: подменяем системные meson/ninja на версии из venv.
        # /usr/local/bin идёт раньше /usr/bin в PATH, поэтому и sudo, и обычный
        # вызов найдут 1.7.0. Это критично, т.к. turnip_builder.sh вызывает
        # meson напрямую (без sudo, но на всякий случай).
        sudo ln -sf /opt/meson-venv/bin/meson /usr/local/bin/meson
        sudo ln -sf /opt/meson-venv/bin/ninja /usr/local/bin/ninja

        # Отключаем защиту PEP 668 для pip (скрипт делает `pip install mako`)
        sudo mkdir -p /etc/pip
        printf '[global]\nbreak-system-packages = true\n' | sudo tee /etc/pip.conf > /dev/null

        hash -r
        which meson
        meson --version   # ожидаем 1.7.0
        ninja --version
        glslangValidator --version | head -n1
        ccache --version | head -n1

    - name: Verify toolchain
      run: |
        echo "which meson: $(which meson)"
        echo "meson version: $(meson --version)"
        echo "which ninja: $(which ninja)"
        echo "ninja version: $(ninja --version)"
        echo "which ccache: $(which ccache)"
        meson --version | grep -q '^1\.7\.' || (echo "Meson must be 1.7.x!" && exit 1)

    - name: Execute build script
      run: bash ./turnip_builder.sh

    - name: List files (debug)
      run: |
        echo "Files in /tmp:"
        ls -la /tmp/*.zip 2>/dev/null || echo "No zip files found in /tmp"
        echo ""
        echo "Files in workdir:"
        ls -la turnip_workdir/*.zip 2>/dev/null || echo "No zip files found in turnip_workdir"

    - name: Upload artifact (debug)
      uses: actions/upload-artifact@v4
      with:
        name: turnip-driver
        path: |
          /tmp/A8XX-Y*.zip
          /tmp/*.zip
          turnip_workdir/A8XX-Y*.zip
        if-no-files-found: warn
        retention-days: 7

    - name: Release "turnip"
      if: success()
      uses: softprops/action-gh-release@v2
      with:
        tag_name: tu_A8XX-Y${{ inputs.version }}
        name: A8XX-Y${{ inputs.version }}
        body: |
          Turnip TU8 — Fork of Mesa Repository with Adreno 8XX Patches

          This release is a custom fork of the original work by whitebelyashx, extended with additional patches and optimizations specifically targeted at Adreno 810/829.
          The build is still in beta testing, and stability may vary depending on the device.
          Please do not report any issues to Mesa, as this is an unofficial fork.

          💿 Interlayer:
          1) proton-10arm64ec or proton-11arm64ec
          2) Rendering mode: DXVK 2.4.1 or then gradually increase until the last / VKD3D 2.14 or VKD3D 3.0b
          3) Memory type: Autotuner, or sysmem
          4) Permission: Depends on the game

          🖥 Supported GPU
          • Full work Adreno 8xx
          • Adreno 850 expiremental
          • Adreno 840 work.
          • Adreno 830 work, recommended use sysmem, but you can try autotuner.
          • Adreno 829/825 Full working, tested (Gmem/Sysmem)
          • Adreno 810/812 Full working, tested (Gmem/Sysmem)

          Changes:

          I would like to express my gratitude to the TG group:

          https://t.me/hardwareunion

          And also special thanks to:
          Whitebeliash (Main developer) Thank you so much! You are clearly the best!
          DerixSpace (developer)
          Lebron (Project organizer)
          Whitedevil2427 P.C. We are waiting for you! (Main tester A829)
          Ikol5v (Main tester A829)
          Michael (Chief Assistant to the organizer)
          And to the driver community

          #If you encounter any banking or banking problems, please write to me:
          Telegram: @DISK_DVD
          Or find me in the Discord community: EmuCore

        files: |
          /tmp/A8XX-Y*.zip
          /tmp/*.zip
          turnip_workdir/A8XX-Y*.zip
        fail_on_unmatched_files: false
