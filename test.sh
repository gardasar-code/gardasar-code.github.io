#!/usr/bin/env bash
# Юнит-тесты чистой логики (парсер пакета, настройки, состояние, статистика).
#
# Тесты помечены (:test) и в обычные сборки не попадают — нужен флаг --unit-test.
# Запуск идёт в симуляторе: monkeydo поднимает его сам, но окно ConnectIQ.app должно
# быть доступно (GUI-сессия). BLE при этом не используется — тестируется только та
# логика, которую можно проверить без железа.
set -euo pipefail

cd "$(dirname "$0")"

SDK="$(tr -d '\n' < "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
KEY="/Volumes/WD2TB/Projects/sln_chipre/garmin/developer_key/developer_key"
DEVICE="edgeexplore2"
OUT="bin/Di2App-test.prg"

mkdir -p bin
echo "▶ сборка тестов"
"$SDK"bin/monkeyc --unit-test -d "$DEVICE" -f monkey.jungle -o "$OUT" -y "$KEY"

# Симулятор должен быть запущен — поднимаем, если ещё не открыт.
open -a "$SDK"bin/ConnectIQ.app >/dev/null 2>&1 || true
sleep 4

echo "▶ прогон"
"$SDK"bin/monkeydo "$OUT" "$DEVICE" -t
