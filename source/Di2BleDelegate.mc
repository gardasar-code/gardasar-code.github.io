using Toybox.BluetoothLowEnergy as Ble;
using Toybox.System;
using Toybox.Lang;
using Toybox.Application;

// BLE-делегат: скан -> подключение -> подписка на notify -> парсинг -> реконнект.
//
// ВАЖНО (см. doc/NOTES.md): надёжно подтверждены только BLE-«сантехника» и батарея.
// Точный байтовый формат передач дорожного Di2 в референсах отсутствует и снимается
// с реального устройства в DEBUG-режиме. Смещения парсинга вынесены в константы PKT_*.
class Di2BleDelegate extends Ble.BleDelegate {

    // ── Режим отладки ────────────────────────────────────────────────────────
    // true: System.println сырых байтов каждого notify (для отладки на симуляторе).
    private const DEBUG = true;

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
    //   байт 5 = текущая задняя передача (0x0A=10). Байт 6 ранее принимали за число
    //   задних звёзд, но теперь оно задаётся пользователем в настройках (надёжнее).
    private const PKT_GEAR_LEN = 17;
    private const PKT_REAR_IDX = 5;   // текущая задняя передача
    // Байт передней передачи не выявлен; число звёзд (front/rear) приходит из
    // настроек (frontGears/rearGears) и хранится в Di2State.

    // ── Тайминги/лимиты ───────────────────────────────────────────────────────
    // Периодику гоним от onTick() (вызывается из View.compute() ~раз в секунду).
    // Toybox.Timer в Data Field недоступен — его использование роняет поле.
    // Реконнект бесконечный: связь должна восстанавливаться сама, когда переключатель
    // снова проснётся. Интервал растёт с числом неудач (RECONNECT_MIN..RECONNECT_MAX),
    // чтобы не жечь батарею непрерывным сканом, но не сдаётся никогда.
    private const RECONNECT_MIN_TICKS = 3;    // ~3 c до первой повторной попытки
    private const RECONNECT_MAX_TICKS = 30;   // потолок интервала между попытками
    private const BATTERY_POLL_TICKS  = 30;   // опрос батареи ~раз в 30 c

    // ── Sticky-lock: привязка к конкретному переключателю ─────────────────────
    // Имя устройства, к которому «прилипли». Сохраняется в Storage и переживает
    // перезапуск поля: при последующих сканах подключаемся только к нему, даже если
    // рядом другой Di2 громче. Сбрасывается тогглом Forget в настройках Connect.
    // Имя — единственный персистимый дискриминатор, который даёт BLE API (адрес
    // устройства между сессиями не сохраняется). Если эфирное имя недоступно,
    // действует запасной путь «единственный кандидат» (см. onScanResults).
    private const STORAGE_LOCK    = "lockedDi2Name";
    private const PROP_FORGET     = "forgetDevice";

    // ── Зависимости/состояние ────────────────────────────────────────────────
    private var _state as Di2State;
    private var _reconnectAttempts as Lang.Number = 0;
    private var _scanning as Lang.Boolean = false;
    private var _batteryReadInFlight as Lang.Boolean = false;
    private var _reconnectCountdown as Lang.Number = -1;  // -1 = реконнект не запланирован
    private var _batteryTickCounter as Lang.Number = 0;
    private var _lockedName as Lang.String? = null;       // имя «своего» Di2 или null

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
            applyForgetIfRequested();          // сброс привязки, если включён Forget
            _lockedName = loadLockedName();     // подхватываем «свой» Di2 из Storage
            _state.locked = (_lockedName != null);
            _state.phase = CONN_SCANNING;
            startScan();
        } catch (e) {
            log("BLE init failed: " + e.getErrorMessage());
        }
    }

    // Останавливаем скан. Пару НЕ рвём намеренно: unpairDevice уничтожает бонд,
    // из-за чего при следующем запуске поля Di2 уже не виден (он спит и больше не
    // рекламируется), и пользователь вынужден заново вводить переключатель в паринг.
    // Сохраняя пару, даём BLE-стеку шанс переподключиться самому, когда Di2 мелькнёт
    // в эфире (см. doc/NOTES.md — проверяется в DEBUG-дампе).
    function stop() as Void {
        _reconnectCountdown = -1;
        try {
            if (_scanning) {
                Ble.setScanState(Ble.SCAN_STATE_OFF);
                _scanning = false;
            }
        } catch (e) {
            // На остановке ошибки BLE не критичны — глотаем.
        }
        _state.connected = false;
        _state.resetLiveData();
    }

    // Пользователь поменял настройки (в т.ч. тоггл Forget) в Garmin Connect.
    // Если включён Forget — снимаем привязку, рвём текущее соединение и сканируем
    // заново, чтобы «прилипнуть» к ближайшему (другому) переключателю.
    function onSettingsChanged() as Void {
        if (!forgetRequested()) {
            return;
        }
        applyForgetIfRequested();          // удалит имя из Storage + reset тоггла
        try {
            var d = Ble.getPairedDevices().next() as Ble.Device?;
            if (d != null) {
                Ble.unpairDevice(d);       // разрыв со «старым» Di2
            }
        } catch (e) {
            // разрыв не критичен — следующий скан подберёт новое устройство
        }
        _reconnectAttempts = 0;
        _reconnectCountdown = -1;
        _state.connected = false;
        _state.resetLiveData();
        _state.phase = CONN_SCANNING;
        if (!_scanning) {
            startScan();
        }
    }

    // ── Sticky-lock: хранение привязки ────────────────────────────────────────

    // Запомнить имя подключённого устройства как «своё» (в Storage и в поле).
    private function saveLock(device as Ble.Device) as Void {
        try {
            var nm = device.getName();
            if (nm != null && nm.length() > 0 && (_lockedName == null || !nm.equals(_lockedName))) {
                _lockedName = nm;
                Application.Storage.setValue(STORAGE_LOCK, nm);
            }
            _state.locked = (_lockedName != null);
        } catch (e) {
            // имя недоступно — остаёмся на запасном пути «единственный кандидат»
        }
    }

    // Прочитать сохранённое имя «своего» Di2 (null, если привязки нет).
    private function loadLockedName() as Lang.String? {
        var v = Application.Storage.getValue(STORAGE_LOCK);
        return (v instanceof Lang.String) ? v : null;
    }

    // Запрошен ли сброс привязки (тоггл Forget в настройках).
    private function forgetRequested() as Lang.Boolean {
        var v = Application.Properties.getValue(PROP_FORGET);
        return (v instanceof Lang.Boolean) ? v : false;
    }

    // Снять привязку, если включён Forget, и автоматически выключить сам тоггл,
    // чтобы он сработал однократно (как «кнопка», а не постоянный режим).
    private function applyForgetIfRequested() as Void {
        if (!forgetRequested()) {
            return;
        }
        Application.Storage.deleteValue(STORAGE_LOCK);
        _lockedName = null;
        _state.locked = false;
        try {
            Application.Properties.setValue(PROP_FORGET, false);
        } catch (e) {
            // не смогли сбросить флаг — не критично, привязка уже снята
        }
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

    // Результаты скана: фильтруем по advertised-UUID Shimano и выбираем цель.
    //   • нет привязки      → берём сильнейший по RSSI (и затем «прилипаем» к нему);
    //   • есть привязка     → только устройство с совпавшим именем (sticky-lock);
    //   • привязка есть, но совпадения нет и кандидат ровно один → берём его
    //     (эфирное имя могло не прийти; одиночный Di2 почти наверняка «свой»);
    //   • привязка есть, совпадения нет, кандидатов несколько → ждём (не хватаем чужой).
    function onScanResults(scanResults) {
        var advUuid = Ble.stringToUuid(ADV_SERVICE_UUID);
        var best = null;
        var bestRssi = -999;
        var matched = null;          // устройство с именем == _lockedName (сильнейшее)
        var matchedRssi = -999;
        var shimanoCount = 0;

        for (var r = scanResults.next(); r != null; r = scanResults.next()) {
            var sr = r as Ble.ScanResult;
            if (iterContains(sr.getServiceUuids(), advUuid)) {
                shimanoCount += 1;
                var rssi = sr.getRssi();
                if (rssi > bestRssi) {
                    bestRssi = rssi;
                    best = sr;
                }
                if (_lockedName != null) {
                    var nm = sr.getDeviceName();
                    if (nm != null && nm.equals(_lockedName) && rssi > matchedRssi) {
                        matchedRssi = rssi;
                        matched = sr;
                    }
                }
            }
        }

        if (DEBUG) {
            // Ключевой дамп для диагностики авто-реконнекта: видим ли мы рекламу Di2
            // в этом скане. Если строки появляются после пробуждения переключения
            // БЕЗ ручного паринга — устройство рекламируется само, и мы можем цепляться.
            log("scan: shimano=" + shimanoCount + " best=" + (best != null ? best.getDeviceName() : "none")
                + " rssi=" + bestRssi + " lock=" + (_lockedName != null ? _lockedName : "none"));
        }

        var target = null;
        if (_lockedName != null) {
            if (matched != null) {
                target = matched;                 // блокировка: только «свой» по имени
            } else if (shimanoCount == 1) {
                target = best;                     // единственный кандидат — берём его
            }
            // иначе несколько чужих без совпадения → продолжаем скан, не подключаемся
        } else {
            target = best;                         // нет привязки → сильнейший
        }

        if (target != null) {
            connectTo(target);
        }
    }

    // Останавливаем скан и поднимаем соединение с выбранным устройством.
    private function connectTo(sr as Ble.ScanResult) as Void {
        try {
            Ble.setScanState(Ble.SCAN_STATE_OFF);
            _scanning = false;
            _state.phase = CONN_CONNECTING;
            var d = Ble.pairDevice(sr);
            // emtb: иногда onConnectedStateChanged не приходит — проверяем сразу.
            if (d != null && d.isConnected()) {
                onConnected(d);
            }
        } catch (e) {
            log("pair failed: " + e.getErrorMessage());
            scheduleReconnect();
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
        _state.phase = CONN_LIVE;
        saveLock(device);              // «прилипаем» к этому устройству по имени
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
            // front/frontTotal/rearTotal задаются настройками (см. Di2FieldApp).
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
        // Кадровый счётчик для пульсации индикатора в View (одна анимация на 1 c тик).
        _state.anim += 1;

        // Отложенный реконнект (когда не подключены).
        if (_reconnectCountdown > 0) {
            _reconnectCountdown -= 1;
            if (_reconnectCountdown == 0) {
                _reconnectCountdown = -1;
                _state.phase = CONN_SCANNING;
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

    // Запланировать повторный скан. Интервал растёт с числом неудач до потолка,
    // но попытки не заканчиваются — связь восстановится, как только Di2 проснётся.
    private function scheduleReconnect() as Void {
        _state.phase = CONN_RETRY;
        _reconnectAttempts += 1;
        var delay = _reconnectAttempts * RECONNECT_MIN_TICKS;
        _reconnectCountdown = (delay < RECONNECT_MAX_TICKS) ? delay : RECONNECT_MAX_TICKS;
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
