using Toybox.BluetoothLowEnergy as Ble;
using Toybox.System;
using Toybox.Lang;

// BLE-делегат: скан -> подключение -> подписка на notify -> парсинг -> реконнект.
//
// ВАЖНО (см. doc/NOTES.md): надёжно подтверждены только BLE-«сантехника» и батарея.
// Точный байтовый формат передач дорожного Di2 в референсах отсутствует и снимается
// с реального устройства в DEBUG-режиме. Смещения парсинга вынесены в константы PKT_*.
class Di2BleDelegate extends Ble.BleDelegate {

    // ── Режим отладки ────────────────────────────────────────────────────────
    // true: System.println сырых байтов каждого notify (для отладки на симуляторе).
    private const DEBUG = false;

    // ── UUIDs (подтверждены по emtb/source/emtbDelegate.mc) ───────────────────
    // Advertised-маркер Shimano — используем как фильтр скана.
    private const ADV_SERVICE_UUID  = "000018ff-5348-494d-414e-4f5f424c4500";
    // Сервис/характеристика нотификаций (mode/gear), CCCD-подписка.
    private const MODE_SERVICE_UUID = "000018ef-5348-494d-414e-4f5f424c4500";
    private const MODE_CHAR_UUID    = "00002ac1-5348-494d-414e-4f5f424c4500";
    // Стандартный сервис батареи (Read).
    private const BATT_SERVICE_UUID = "0000180f-0000-1000-8000-00805f9b34fb";
    private const BATT_CHAR_UUID    = "00002a19-0000-1000-8000-00805f9b34fb";

    // ── Смещения байтов в notify-пакете 0x2ac1 (подтверждены на реальном Di2) ──
    // Пакет 17 байт; пример: 00 00 03 FF FF 0A 0C 80 80 80 FF EE 12 FF FF 15 00
    //   байт 5 = текущая задняя (0x0A=10), байт 6 = число задних звёзд (0x0C=12).
    private const PKT_GEAR_LEN      = 17;
    private const PKT_REAR_IDX      = 5;   // текущая задняя передача
    private const PKT_REARTOTAL_IDX = 6;   // число задних передач (кассета)

    // Число передних звёзд. 1x → передней передачи нет, показываем 1/1.
    // Для 2x: определи байт передней (переключи звезду, найди меняющийся байт) и
    // парси его в parseGearPacket вместо фиксированного значения.
    private const FRONT_CHAINRINGS = 1;

    // ── Тайминги/лимиты ───────────────────────────────────────────────────────
    // Периодику гоним от onTick() (вызывается из View.compute() ~раз в секунду).
    // Toybox.Timer в Data Field недоступен — его использование роняет поле.
    private const RECONNECT_DELAY_TICKS = 3;    // ~3 c до повторного скана
    private const MAX_RECONNECT         = 10;
    private const BATTERY_POLL_TICKS    = 30;   // опрос батареи ~раз в 30 c

    // ── Зависимости/состояние ────────────────────────────────────────────────
    private var _state as Di2State;
    private var _reconnectAttempts as Lang.Number = 0;
    private var _scanning as Lang.Boolean = false;
    private var _batteryReadInFlight as Lang.Boolean = false;
    private var _reconnectCountdown as Lang.Number = -1;  // -1 = реконнект не запланирован
    private var _batteryTickCounter as Lang.Number = 0;

    function initialize(state as Di2State) {
        BleDelegate.initialize();
        _state = state;
    }

    // ── Публичный API (вызывается из App) ─────────────────────────────────────

    // Регистрируем профили, ставим делегат, запускаем скан.
    // Всё под защитой: если BLE недоступен (нет железа/прав, симулятор без BLE),
    // поле не падает, а остаётся в состоянии «нет данных» (UI рисует "---").
    function start() as Void {
        try {
            Ble.setDelegate(self);
            registerProfiles();
            _reconnectAttempts = 0;
            startScan();
        } catch (e) {
            log("BLE init failed: " + e.getErrorMessage());
        }
    }

    // Останавливаем скан, отключаем устройство.
    function stop() as Void {
        _reconnectCountdown = -1;
        try {
            if (_scanning) {
                Ble.setScanState(Ble.SCAN_STATE_OFF);
                _scanning = false;
            }
            var d = Ble.getPairedDevices().next() as Ble.Device?;
            if (d != null) {
                Ble.unpairDevice(d);
            }
        } catch (e) {
            // На остановке ошибки BLE не критичны — глотаем.
        }
        _state.connected = false;
        _state.resetLiveData();
    }

    // ── Регистрация профилей и скан ───────────────────────────────────────────

    private function registerProfiles() as Void {
        // Профиль батареи (Read).
        Ble.registerProfile({
            :uuid => Ble.stringToUuid(BATT_SERVICE_UUID),
            :characteristics => [
                { :uuid => Ble.stringToUuid(BATT_CHAR_UUID) }
            ]
        });
        // Профиль нотификаций (Notify через CCCD).
        Ble.registerProfile({
            :uuid => Ble.stringToUuid(MODE_SERVICE_UUID),
            :characteristics => [
                {
                    :uuid => Ble.stringToUuid(MODE_CHAR_UUID),
                    :descriptors => [Ble.cccdUuid()]
                }
            ]
        });
    }

    private function startScan() as Void {
        try {
            Ble.setScanState(Ble.SCAN_STATE_SCANNING);
            _scanning = true;
        } catch (e) {
            log("scan start failed: " + e.getErrorMessage());
        }
    }

    // ── BLE callbacks ─────────────────────────────────────────────────────────

    // Результаты скана: фильтруем по advertised-UUID, подключаемся к сильнейшему RSSI.
    function onScanResults(scanResults) {
        var advUuid = Ble.stringToUuid(ADV_SERVICE_UUID);
        var best = null;
        var bestRssi = -999;

        for (var r = scanResults.next(); r != null; r = scanResults.next()) {
            var sr = r as Ble.ScanResult;
            if (iterContains(sr.getServiceUuids(), advUuid)) {
                var rssi = sr.getRssi();
                if (rssi > bestRssi) {
                    bestRssi = rssi;
                    best = sr;
                }
            }
        }

        if (best != null) {
            // Нашли устройство — скан больше не нужен, подключаемся.
            try {
                Ble.setScanState(Ble.SCAN_STATE_OFF);
                _scanning = false;
                var d = Ble.pairDevice(best);
                // emtb: иногда onConnectedStateChanged не приходит — проверяем сразу.
                if (d != null && d.isConnected()) {
                    onConnected(d);
                }
            } catch (e) {
                log("pair failed: " + e.getErrorMessage());
                scheduleReconnect();
            }
        }
    }

    function onConnectedStateChanged(device, state) {
        if (state == Ble.CONNECTION_STATE_CONNECTED) {
            onConnected(device);
        } else {
            onDisconnected();
        }
    }

    // Подписываемся на notify и читаем батарею.
    private function onConnected(device as Ble.Device) as Void {
        _reconnectAttempts = 0;
        _reconnectCountdown = -1;
        _state.connected = true;
        enableNotifications(device);
        readBattery();                 // одно чтение сразу; далее — по тикам в onTick()
        _batteryTickCounter = 0;
        log("connected");
    }

    private function onDisconnected() as Void {
        _state.connected = false;
        _state.resetLiveData();
        log("disconnected");
        scheduleReconnect();
    }

    // Парсинг notify-пакетов передач. value — ByteArray (по контракту API не null).
    function onCharacteristicChanged(characteristic, value) {
        if (DEBUG) {
            logBytes(characteristic, value);
        }
        parseGearPacket(value);
    }

    // Ответ на requestRead батареи: байт[0] = процент 0..100.
    function onCharacteristicRead(characteristic, status, value) {
        _batteryReadInFlight = false;
        if (characteristic.getUuid().equals(Ble.stringToUuid(BATT_CHAR_UUID))) {
            if (value != null && value.size() > 0) {
                _state.battery = value[0].toNumber();
            }
        }
    }

    // ── Парсинг ───────────────────────────────────────────────────────────────

    private function parseGearPacket(value as Lang.ByteArray) as Void {
        if (value.size() == PKT_GEAR_LEN) {
            if (PKT_REAR_IDX < value.size()) {
                _state.rear = value[PKT_REAR_IDX].toNumber();
            }
            if (PKT_REARTOTAL_IDX < value.size()) {
                _state.rearTotal = value[PKT_REARTOTAL_IDX].toNumber();
            }
            // 1x: передняя зафиксирована (в пакете отдельного байта передней нет).
            _state.front = 1;
            _state.frontTotal = FRONT_CHAINRINGS;
            // Калибровочный дамп gear-пакета на экран (для будущей настройки 2x).
            _state.dbgGear = toHex(value);
        }
    }

    // Hex-строка байтов: "00 11 22 ...".
    private function toHex(value as Lang.ByteArray) as Lang.String {
        var s = "";
        for (var i = 0; i < value.size(); i++) {
            s += value[i].format("%02X") + " ";
        }
        return s;
    }

    // ── Вспомогательное BLE ───────────────────────────────────────────────────

    private function enableNotifications(device as Ble.Device) as Void {
        try {
            var svc = device.getService(Ble.stringToUuid(MODE_SERVICE_UUID));
            if (svc != null) {
                var ch = svc.getCharacteristic(Ble.stringToUuid(MODE_CHAR_UUID));
                if (ch != null) {
                    var cccd = ch.getDescriptor(Ble.cccdUuid());
                    if (cccd != null) {
                        cccd.requestWrite([0x01, 0x00]b);  // включить notifications
                    }
                }
            }
        } catch (e) {
            log("enable notify failed: " + e.getErrorMessage());
        }
    }

    // Однократное чтение батареи. Зовётся при подключении и периодически из onTick().
    function readBattery() as Void {
        if (_batteryReadInFlight) {
            return;  // ждём предыдущий read — иначе возможен краш (см. NOTES.md)
        }
        try {
            var d = Ble.getPairedDevices().next() as Ble.Device?;
            if (d != null && d.isConnected()) {
                var svc = d.getService(Ble.stringToUuid(BATT_SERVICE_UUID));
                if (svc != null) {
                    var ch = svc.getCharacteristic(Ble.stringToUuid(BATT_CHAR_UUID));
                    if (ch != null) {
                        _batteryReadInFlight = true;
                        ch.requestRead();
                    }
                }
            }
        } catch (e) {
            _batteryReadInFlight = false;
            log("battery read failed: " + e.getErrorMessage());
        }
    }

    // ── Тик-планировщик (вместо Timer; вызывается из View.compute() ~1 c) ───────

    // Heartbeat дата-филда: гоним отложенный реконнект и периодический опрос батареи.
    function onTick() as Void {
        // Отложенный реконнект (когда не подключены).
        if (_reconnectCountdown > 0) {
            _reconnectCountdown -= 1;
            if (_reconnectCountdown == 0) {
                _reconnectCountdown = -1;
                log("reconnect attempt " + _reconnectAttempts);
                startScan();
            }
        }

        // Периодический опрос батареи (когда подключены).
        if (_state.connected) {
            _batteryTickCounter += 1;
            if (_batteryTickCounter >= BATTERY_POLL_TICKS) {
                _batteryTickCounter = 0;
                readBattery();
            }
        }
    }

    // Запланировать повторный скан через RECONNECT_DELAY_TICKS тиков.
    private function scheduleReconnect() as Void {
        if (_reconnectAttempts >= MAX_RECONNECT) {
            log("reconnect attempts exhausted");
            return;
        }
        _reconnectAttempts += 1;
        _reconnectCountdown = RECONNECT_DELAY_TICKS;
    }

    // ── Утилиты ───────────────────────────────────────────────────────────────

    private function iterContains(iter as Ble.Iterator, target as Ble.Uuid) as Lang.Boolean {
        for (var u = iter.next(); u != null; u = iter.next()) {
            if ((u as Ble.Uuid).equals(target)) {
                return true;
            }
        }
        return false;
    }

    private function logBytes(characteristic as Ble.Characteristic, value as Lang.ByteArray) as Void {
        var hex = "";
        for (var i = 0; i < value.size(); i++) {
            hex += value[i].format("%02X") + " ";
        }
        System.println("[Di2] char=" + characteristic.getUuid().toString() + " len=" + value.size() + " bytes=[" + hex + "]");
    }

    private function log(msg as Lang.String) as Void {
        if (DEBUG) {
            System.println("[Di2] " + msg);
        }
    }
}
