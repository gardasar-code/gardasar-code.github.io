#!/usr/bin/env bash
# Сборка Di2 Field. Без аргумента — release-сборка для устройства (BLE on).
#
#   ./build.sh           release .prg для устройства  -> bin/Di2App.prg
#   ./build.sh store     публикационный .iq           -> bin/Di2App.iq
#   ./build.sh debug     debug .prg (BLE off, симулятор) -> bin/Di2App-debug.prg
#
# Требует: установленный Connect IQ SDK и ключ разработчика.
set -euo pipefail

cd "$(dirname "$0")"

# Текущий SDK из конфига SDK Manager (путь с завершающим слэшем).
SDK="$(tr -d '\n' < "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
MONKEYC="${SDK}bin/monkeyc"
KEY="/Volumes/WD2TB/Projects/sln_chipre/garmin/developer_key/developer_key"
DEVICE="edgeexplore2"

mkdir -p bin

case "${1:-release}" in
  release)
    echo "▶ release .prg (устройство, BLE on)"
    "$MONKEYC" -d "$DEVICE" -f monkey.jungle -o bin/Di2App.prg -y "$KEY" -r -w
    echo "✓ bin/Di2App.prg — залей через OpenMTP в GARMIN/APPS/"
    ;;
  store)
    echo "▶ store .iq (все продукты/языки)"
    "$MONKEYC" -e -o bin/Di2App.iq -f monkey.jungle -y "$KEY" -r -w
    echo "✓ bin/Di2App.iq — загрузи на apps.garmin.com"
    ;;
  debug)
    echo "▶ debug .prg (симулятор, BLE off)"
    "$MONKEYC" -d "$DEVICE" -f monkey.jungle -o bin/Di2App-debug.prg -y "$KEY" -w
    echo "✓ bin/Di2App-debug.prg"
    ;;
  *)
    echo "usage: ./build.sh [release|store|debug]" >&2; exit 1 ;;
esac
