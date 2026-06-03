#!/usr/bin/env bash
# Диагностическая сборка для РЕАЛЬНОГО устройства: BLE включён И System.println
# пишется в файл GARMIN/APPS/LOGS/*.TXT (для снятия лога скана/реконнекта).
#
# Почему отдельный скрипт, а не build.sh:
#   • release (-r): BLE on, но логирование в файл вырезано → лога нет.
#   • debug (F5):   логирование есть, но bleEnabled()=false → BLE off.
# Эти режимы взаимоисключающие. Здесь собираем DEBUG-сборку (логи в файле),
# но во ВРЕМЕННОЙ копии исходников форсируем BLE on и отключаем демо-цикл.
# Рабочее дерево source/ НЕ трогаем.
#
# Результат: bin/Di2App-<version>-diag.prg  (метка diag в имени — намеренно).
set -euo pipefail

cd "$(dirname "$0")"

SDK="$(tr -d '\n' < "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
MONKEYC="${SDK}bin/monkeyc"
KEY="/Volumes/WD2TB/Projects/sln_chipre/garmin/developer_key/developer_key"
DEVICE="edgeexplore2"

# Версия — источник истины manifest.xml.
VERSION="$(sed -n 's/.* version="\([0-9.]*\)".*/\1/p' manifest.xml | tail -1)"
OUT="bin/Di2App-${VERSION}-diag.prg"

SRC_TMP=".diag-src"
JUNGLE_TMP="monkey-diag.jungle"

cleanup() { rm -rf "$SRC_TMP" "$JUNGLE_TMP"; }
trap cleanup EXIT

mkdir -p bin
rm -rf "$SRC_TMP"
cp -R source "$SRC_TMP"

# Патч 1: BLE включён и в debug-сборке (на устройстве реальный стек работает).
sed -i '' 's#(:debug)   function bleEnabled() as Lang.Boolean { return false; }#(:debug)   function bleEnabled() as Lang.Boolean { return true; }  // DIAG#' \
  "$SRC_TMP/Di2FieldApp.mc"

# Патч 2: на устройстве показываем реальные BLE-данные, а не демо-цикл.
sed -i '' 's#^    function applyDebugData() as Void {$#    function applyDebugData() as Void {\n        return;  // DIAG: real BLE data, no demo#' \
  "$SRC_TMP/Di2FieldView.mc"

# Временный jungle с источниками из копии.
cat > "$JUNGLE_TMP" <<EOF
project.manifest = manifest.xml
base.sourcePath = $SRC_TMP
base.resourcePath = resources
EOF

echo "▶ diag .prg (устройство, BLE on + файловый лог), version $VERSION"
# Без -r: System.println пишется в GARMIN/APPS/LOGS/*.TXT на устройстве.
"$MONKEYC" -d "$DEVICE" -f "$JUNGLE_TMP" -o "$OUT" -y "$KEY" -w
echo "✓ $OUT — залей в GARMIN/APPS/; лог появится в GARMIN/APPS/LOGS/*.TXT"
