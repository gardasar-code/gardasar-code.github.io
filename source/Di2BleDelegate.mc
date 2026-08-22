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
    // true: пишем диагностику через Di2Log в GARMIN/APPS/LOGS/*.TXT (см. doc/LOGGING.md).
    // В коммите всегда false (release); диагностическая сборка build-diag.sh патчит в true.
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

    // ── Профили серий Di2: авто-детект по GATT-имени ──────────────────────────
    // Раскладка notify-пакета 0x2ac1 зависит от серии переключателя. Вместо хардкода
    // смещения вынесены в ТАБЛИЦУ профилей: при подключении читаем GATT-имя устройства
    // и выбираем первый профиль, чей :prefix совпал с началом имени. Новая серия
    // добавляется ОДНОЙ строкой в PROFILES — логика парсинга не меняется.
    //
    // Поля профиля:
    //   :prefix — префикс GATT-имени модели (как приходит по getName());
    //   :label  — человекочитаемая метка (для diag-оверлея и краудсорса);
    //   :len    — длина пакета передач (байт);
    //   :rear   — индекс байта текущей ЗАДНЕЙ передачи;
    //   :front  — индекс байта текущей ПЕРЕДНЕЙ передачи (-1 = не выявлен).
    //
    // ПОДТВЕРЖДЕНО на железе: только XT M8250 (len 17, rear=байт5; front не выявлен,
    // тест 1x). Дорожные/гравийные серии — ГИПОТЕЗА: один и тот же шлюз D-Fly (EW-WU)
    // вещает тот же канал, поэтому раскладка предположительно совпадает. Подтверждение —
    // по фото diag-оверлея от пользователей (имя + сырой пакет). См. doc/NOTES.md.
    private const PROFILES = [
        { :prefix => "RDM8250", :label => "XT Di2 M8250",   :len => 17, :rear => 5, :front => -1 },
        // ── ниже: гипотеза, требует подтверждения по фото оверлея ──
        { :prefix => "RDM9250", :label => "XTR Di2 M9250",  :len => 17, :rear => 5, :front => -1 },
        { :prefix => "RDR9250", :label => "DURA-ACE R9250", :len => 17, :rear => 5, :front => -1 },
        { :prefix => "RDR8150", :label => "Ultegra R8150",  :len => 17, :rear => 5, :front => -1 },
        { :prefix => "RDR7150", :label => "105 R7150",      :len => 17, :rear => 5, :front => -1 },
        { :prefix => "RDRX825", :label => "GRX RX825",      :len => 17, :rear => 5, :front => -1 }
    ] as Lang.Array<Lang.Dictionary>;

    // Дефолтный профиль (XT M8250) — пока имя устройства неизвестно или не совпало
    // ни с одним префиксом. Соответствует прежним хардкод-константам PKT_*.
    private const DEFAULT_PKT_LEN  = 17;
    private const DEFAULT_REAR_IDX = 5;
    private const DEFAULT_FRONT_IDX = -1;

    // Активная раскладка пакета (из выбранного профиля). Меняется в selectProfile().
    private var _pktLen as Lang.Number = DEFAULT_PKT_LEN;
    private var _rearIdx as Lang.Number = DEFAULT_REAR_IDX;
    private var _frontIdx as Lang.Number = DEFAULT_FRONT_IDX;

    // ── Тайминги/лимиты ───────────────────────────────────────────────────────
    // Периодику гоним от onTick() (вызывается из View.compute() ~раз в секунду).
    // Toybox.Timer в Data Field недоступен — его использование роняет поле.
    // Реконнект бесконечный: связь должна восстанавливаться сама, когда переключатель
    // снова проснётся. Интервал растёт с числом неудач (RECONNECT_MIN..RECONNECT_MAX),
    // чтобы не жечь батарею непрерывным сканом, но не сдаётся никогда.
    private const RECONNECT_MIN_TICKS = 3;    // ~3 c до первой повторной попытки
    private const RECONNECT_MAX_TICKS = 30;   // потолок интервала между попытками
    private const BATTERY_POLL_TICKS  = 30;   // опрос батареи ~раз в 30 c
    private const SUB_RETRY_TICKS     = 2;    // повтор подписки ~раз в 2 c, пока не "ok"

    // ── Sticky-lock: привязка к конкретному переключателю ─────────────────────
    // Имя устройства, к которому «прилипли». Сохраняется в Storage и переживает
    // перезапуск поля: при последующих сканах подключаемся только к нему, даже если
    // рядом другой Di2 громче. Сбрасывается тогглом Forget в настройках Connect.
    // Имя — единственный персистимый дискриминатор, который даёт BLE API (адрес
    // устройства между сессиями не сохраняется). Если эфирное имя недоступно,
    // действует запасной путь «единственный кандидат» (см. onScanResults).
    private const STORAGE_LOCK    = "lockedDi2Name";
    private const PROP_FORGET     = "forgetDevice";
    // Форма описания BLE-профиля, выбранная для следующего запуска (см. registerModeProfile).
    private const STORAGE_REG_FORM = "regProfileForm";

    // ── Кэш Uuid-объектов ─────────────────────────────────────────────────────
    // stringToUuid аллоцирует объект на каждый вызов; раньше это происходило в
    // горячих путях (onCharacteristicRead, readBattery, enableNotifications).
    // Строим один раз в initialize() и переиспользуем.
    private var _advSvcUuid as Ble.Uuid?;
    private var _modeSvcUuid as Ble.Uuid?;
    private var _modeCharUuid as Ble.Uuid?;
    private var _battSvcUuid as Ble.Uuid?;
    private var _battCharUuid as Ble.Uuid?;

    // ── Зависимости/состояние ────────────────────────────────────────────────
    private var _state as Di2State;
    private var _reconnectAttempts as Lang.Number = 0;
    private var _scanning as Lang.Boolean = false;
    private var _batteryReadInFlight as Lang.Boolean = false;
    private var _reconnectCountdown as Lang.Number = -1;  // -1 = реконнект не запланирован
    private var _batteryTickCounter as Lang.Number = 0;
    private var _subRetryCounter as Lang.Number = 0;
    private var _regAttempts as Lang.Number = 0;
    private var _battProfileRequested as Lang.Boolean = false;
    private var _lockedName as Lang.String? = null;       // имя «своего» Di2 или null

    // Троттлинг лога скана: onScanResults зовётся десятки раз в секунду и заспамил
    // бы 5 КБ-файл за минуту (момент пробуждения Di2 не попадёт в окно). Логируем
    // скан только при ИЗМЕНЕНИИ числа кандидатов + редкий хартбит раз в SCAN_LOG_HB_MS.
    private const SCAN_LOG_HB_MS = 30000;
    private var _lastScanShimano as Lang.Number = -1;
    private var _lastScanLogMs as Lang.Number = 0;
    // Троттлинг лога notify: логируем пакет только при смене передачи + хартбит.
    private var _lastLoggedGear as Lang.Number = -2;   // -2 = ещё не логировали
    private var _lastNotifyLogMs as Lang.Number = 0;
    // Дошла ли текущая попытка до живого соединения (LIVE). Нужен, чтобы отличить
    // потерю установленной связи (обычный бэкофф) от сорвавшегося рукопожатия при
    // слабом сигнале (нужен мгновенный рескан, чтобы поймать следующий блик Di2).
    private var _attemptReachedLive as Lang.Boolean = false;

    function initialize(state as Di2State) {
        BleDelegate.initialize();
        _state = state;
        _advSvcUuid   = Ble.stringToUuid(ADV_SERVICE_UUID);
        _modeSvcUuid  = Ble.stringToUuid(MODE_SERVICE_UUID);
        _modeCharUuid = Ble.stringToUuid(MODE_CHAR_UUID);
        _battSvcUuid  = Ble.stringToUuid(BATT_SERVICE_UUID);
        _battCharUuid = Ble.stringToUuid(BATT_CHAR_UUID);
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
            if (DEBUG) { log("BLE init failed"); }
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
    // Привязка ставится ОДИН раз — при первом успешном коннекте. Дальше она «липкая»
    // и меняется только тоглом Forget. На чужой переключатель мы не попадём: онн
    // отбрасывается по имени в onConnected ещё до saveLock.
    private function saveLock(device as Ble.Device) as Void {
        if (_lockedName != null) {
            _state.locked = true;          // уже привязаны — не переписываем
            return;
        }
        try {
            var nm = device.getName();
            if (nm != null && nm.length() > 0) {
                _lockedName = nm;
                Application.Storage.setValue(STORAGE_LOCK, nm);
            }
            _state.locked = (_lockedName != null);
        } catch (e) {
            // имя недоступно — остаёмся без привязки (подключаемся к ближайшему)
        }
    }

    // Снять идентичность подключённого устройства: GATT-имя в state (для diag-оверлея
    // и краудсорса моделей) + авто-детект профиля раскладки пакета по имени. Имя
    // доступно только после подключения; в эфире скана его нет.
    private function captureIdentity(device as Ble.Device) as Void {
        var nm = null;
        try {
            nm = device.getName();
        } catch (e) {
            // имя недоступно — оставляем пустым
        }
        _state.dbgDeviceName = (nm != null) ? nm : "";
        selectProfile(nm);
    }

    // Выбрать профиль раскладки пакета по GATT-имени: первый профиль, чей :prefix
    // совпал с началом имени. Имя null/без совпадения → дефолт (XT M8250). Применяется
    // к смещениям парсинга (_pktLen/_rearIdx/_frontIdx) и метке модели в state.
    private function selectProfile(name as Lang.String?) as Void {
        // Старт с дефолта (XT M8250): подходит и как fallback для нераспознанной модели —
        // пробуем самую вероятную раскладку, а сырой пакет всё равно виден в diag.
        _pktLen   = DEFAULT_PKT_LEN;
        _rearIdx  = DEFAULT_REAR_IDX;
        _frontIdx = DEFAULT_FRONT_IDX;

        var p = matchProfile(name);
        if (p != null) {
            _pktLen   = p[:len] as Lang.Number;
            _rearIdx  = p[:rear] as Lang.Number;
            _frontIdx = p[:front] as Lang.Number;
            _state.dbgModel = p[:label] as Lang.String;
        } else {
            // Имя есть, но не распознано — метим "?" (по фото оверлея добавим профиль).
            _state.dbgModel = (name != null && name.length() > 0) ? "?" : "";
        }
    }

    // Найти профиль по префиксу GATT-имени (name.find(prefix)==0 → имя начинается с него).
    private function matchProfile(name as Lang.String?) as Lang.Dictionary? {
        if (name == null || name.length() == 0) {
            return null;
        }
        for (var i = 0; i < PROFILES.size(); i++) {
            var p = PROFILES[i] as Lang.Dictionary;
            var prefix = p[:prefix] as Lang.String;
            if (name.find(prefix) == 0) {
                return p;
            }
        }
        return null;
    }

    // Форма описания профиля для текущего запуска: true — с явным CCCD (дефолт).
    private function loadRegForm() as Lang.Boolean {
        var v = Application.Storage.getValue(STORAGE_REG_FORM);
        return (v instanceof Lang.Boolean) ? v : true;
    }

    // Запомнить форму для СЛЕДУЮЩЕГО запуска (в текущем перерегистрация запрещена).
    private function saveRegForm(withCccd as Lang.Boolean) as Void {
        try {
            Application.Storage.setValue(STORAGE_REG_FORM, withCccd);
        } catch (e) {
            // не сохранилось — в следующий раз просто повторим ту же форму
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

    // Результат регистрации профиля от BLE-стека. Раньше колбэк не был реализован, и
    // провал регистрации был невидим: незарегистрированный профиль означает, что стек
    // НЕ обнаруживает его сервис на устройстве (getServices отдаёт только профили,
    // зарегистрированные приложением) — то есть подписка обречена, а причина молчит.
    function onProfileRegister(uuid, status) {
        var ok = (status == Ble.STATUS_SUCCESS);
        if (uuid.equals(_modeSvcUuid)) {
            if (ok) {
                registerBatteryProfile();   // слот передач занят — можно просить второй
            } else {
                saveRegForm(!loadRegForm());   // следующий запуск пробует другую форму
            }
        }
        var tag = shortUuid(uuid) + (ok ? ":ok" : ":e" + status.toString());
        _state.dbgReg = (_state.dbgReg.length() == 0) ? tag : (_state.dbgReg + " " + tag);
        log("profile register " + tag);
    }

    // Короткая метка UUID для диагностики: "0000180f-..." -> "180F".
    private function shortUuid(uuid) as Lang.String {
        var s = uuid.toString();
        return (s.length() >= 8) ? s.substring(4, 8) : s;
    }

    // Регистрация профилей. КАЖДЫЙ вызов в своём try: Connect IQ ограничивает число
    // зарегистрированных профилей на приложение, и если первая регистрация упрётся в
    // лимит (например, поле добавлено на два экрана сразу — тогда профили просит каждый
    // экземпляр), общий try оставил бы приложение вообще без второго профиля.
    // Профиль передач регистрируем ПЕРВЫМ: он важнее батареи, и при нехватке слотов
    // потерять лучше батарею, чем передачи — ради них поле и существует.
    // Регистрация профилей. ВАЖНО (известный баг прошивки, forums.garmin.com): на ряде
    // устройств стек принимает только ПЕРВЫЙ профиль, а на каждый следующий отвечает
    // недокументированным status=2. Наблюдалось на Edge Explore 2 после обновления
    // прошивки: 180F:ok, 18EF:e2 — и передачи пропали совсем, потому что незарегистри-
    // рованный профиль стек не ищет на устройстве вовсе.
    // Поэтому регистрируем СТРОГО ПО ОДНОМУ: сначала профиль передач (ради него поле и
    // существует), а батарею — только после того, как стек подтвердил первый. Если на
    // батарею слота не хватит, поле покажет "--" вместо процента, но передачи будут.
    private function registerProfiles() as Void {
        registerModeProfile();
    }

    // Профиль батареи (Read). Регистрируется отложенно — см. registerProfiles.
    private function registerBatteryProfile() as Void {
        if (_battProfileRequested) {
            return;                    // одна попытка: слот либо есть, либо нет
        }
        _battProfileRequested = true;
        try {
            Ble.registerProfile({
                :uuid => _battSvcUuid,
                :characteristics => [
                    { :uuid => _battCharUuid }
                ]
            });
        } catch (e) {
            log("register battery profile failed");
        }
    }

    // Регистрация профиля передач (Notify через CCCD) — отдельно, чтобы её можно было
    // повторить: стек может отклонить регистрацию (наблюдался недокументированный
    // status=2), и тогда сервис 18ef не находится ни на одном устройстве. Повтор даёт
    // шанс занять слот, когда его освободит тот, кто держал.
    private function registerModeProfile() as Void {
        _regAttempts += 1;
        // Две формы описания профиля. Прошивка Edge Explore 2 отклоняет наш профиль
        // недокументированным status=2 даже когда он единственный, тогда как батарейный
        // (без :descriptors) принимается — поэтому пробуем и форму БЕЗ явного CCCD:
        // дескриптор всё равно доступен через getDescriptor() после подключения.
        // Чередуем МЕЖДУ ЗАПУСКАМИ поля (форма живёт в Storage): повторный вызов
        // registerProfile в рамках одного запуска роняет дата-филд, см. onIdleTick.
        var withCccd = loadRegForm();
        try {
            var chr = withCccd
                ? { :uuid => _modeCharUuid, :descriptors => [Ble.cccdUuid()] }
                : { :uuid => _modeCharUuid };
            Ble.registerProfile({
                :uuid => _modeSvcUuid,
                :characteristics => [chr]
            });
        } catch (e) {
            // ВНИМАНИЕ: здесь нельзя звать e.getErrorMessage() — системные ошибки
            // (не Lang.Exception) такого метода не имеют, и обработчик падает сам
            // «Failed invoking <symbol>», маскируя исходный сбой. Проверено на железе.
            _state.dbgReg = "18EF:ex";
            log("register mode profile failed");
        }
        _state.dbgRegAttempts = _regAttempts;
        _state.dbgRegForm = withCccd ? "d" : "n";   // d = с CCCD, n = без
    }

    private function startScan() as Void {
        try {
            Ble.setScanState(Ble.SCAN_STATE_SCANNING);
            _scanning = true;
        } catch (e) {
            if (DEBUG) { log("scan start failed"); }
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
        var advUuid = _advSvcUuid;
        var best = null;
        var bestRssi = -999;
        var matched = null;          // устройство с именем == _lockedName (сильнейшее)
        var matchedRssi = -999;
        var shimanoCount = 0;
        var totalCount = 0;          // всего устройств в эфире (для diag-discovery)

        for (var r = scanResults.next(); r != null; r = scanResults.next()) {
            var sr = r as Ble.ScanResult;
            totalCount += 1;
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
            // Логируем скан только при изменении числа кандидатов или раз в ~30 c.
            // Так в файл гарантированно попадёт переход shimano 0→N в момент, когда
            // Di2 проснётся и начнёт рекламироваться (если вообще начнёт).
            var nowMs = System.getTimer();
            if (shimanoCount != _lastScanShimano || (nowMs - _lastScanLogMs) >= SCAN_LOG_HB_MS) {
                Di2Log.line("scan: shimano=" + shimanoCount + " best=" + (best != null ? best.getDeviceName() : "none")
                    + " rssi=" + bestRssi + " lock=" + (_lockedName != null ? _lockedName : "none"));
                _lastScanShimano = shimanoCount;
                _lastScanLogMs = nowMs;
            }
        }

        // Diag-discovery эфира на экран: сводка последнего скана в state (см. Di2State).
        // Безусловной записи избегаем — только при включённом оверлее, чтобы в обычном
        // релизе не трогать state из горячего колбэка. Лучший RSSI берём среди shimano.
        if (_state.diagOverlay) {
            _state.dbgScanTotal = totalCount;
            _state.dbgScanShimano = shimanoCount;
            _state.dbgBestRssi = (shimanoCount > 0) ? bestRssi : -999;
        }

        // Выбор цели. ВАЖНО (подтверждено логом DI2DIAG): на этом устройстве scan-
        // результаты приходят БЕЗ имени (getDeviceName()==null), поэтому matched-по-имени
        // в эфире недостижим. Имя доступно только ПОСЛЕ подключения (GATT), там и проверяем
        // личность (см. onConnected). Здесь: при наличии привязки берём имя-совпадение, если
        // оно вдруг есть (другая прошивка/устройство), иначе — ближайшего по RSSI. Чужого
        // отбросим уже на коннекте, не вечно ждём недостижимого имени в скане.
        var target = (_lockedName != null && matched != null) ? matched : best;

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
            _attemptReachedLive = false;   // новая попытка: ещё не дошли до LIVE
            if (DEBUG) { log("pairDevice name=" + (sr.getDeviceName() != null ? sr.getDeviceName() : "?") + " rssi=" + sr.getRssi()); }
            var d = Ble.pairDevice(sr);
            // emtb: иногда onConnectedStateChanged не приходит — проверяем сразу.
            if (d != null && d.isConnected()) {
                onConnected(d);
            }
        } catch (e) {
            if (DEBUG) { log("pair failed"); }
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
        // Проверка личности: имя в эфире недоступно, но после подключения доступно по GATT.
        // Если мы привязаны и подключились к ДРУГОМУ переключателю (имя не совпало) —
        // отбрасываем его и продолжаем искать «своего». Так sticky-lock работает даже без
        // имени в скане. Если имя по GATT недоступно (null) — проверить нечем, принимаем.
        if (_lockedName != null) {
            var nm = device.getName();
            if (nm != null && nm.length() > 0 && !nm.equals(_lockedName)) {
                if (DEBUG) { log("stranger '" + nm + "' != lock '" + _lockedName + "', dropping"); }
                try {
                    Ble.unpairDevice(device);   // разрыв → onDisconnected запланирует рескан
                } catch (e) {
                    scheduleReconnect();
                }
                return;
            }
        }
        _reconnectAttempts = 0;
        _reconnectCountdown = -1;
        _attemptReachedLive = true;    // соединение установлено: разрыв отсюда — «обычный»
        _state.connected = true;
        _state.phase = CONN_LIVE;
        captureIdentity(device);       // GATT-имя + авто-детект профиля модели (для diag/парсинга)
        saveLock(device);              // «прилипаем» к этому устройству по имени (только первый раз)
        enableNotifications(device);
        readBattery();                 // одно чтение сразу; далее — по тикам в onTick()
        _batteryTickCounter = 0;
        if (DEBUG) { log("connected" + (device.getName() != null ? " " + device.getName() : "")); }
    }

    private function onDisconnected() as Void {
        _state.connected = false;
        _state.dbgSub = "-";           // подписка умерла вместе с соединением
        _state.resetLiveData();
        if (_attemptReachedLive) {
            // Потеряли установленную связь — обычный бэкофф (растущий интервал).
            if (DEBUG) { log("disconnected"); }
            scheduleReconnect();
        } else {
            // Рукопожатие сорвалось, не дойдя до LIVE (короткий блик слабого Di2).
            // Не ждём бэкофф — сразу возобновляем скан, чтобы поймать следующий блик.
            if (DEBUG) { log("connect failed before live, fast rescan"); }
            _reconnectAttempts = 0;
            _reconnectCountdown = -1;
            _state.phase = CONN_SCANNING;
            if (!_scanning) {
                startScan();
            }
        }
    }

    // Парсинг notify-пакетов передач. value — ByteArray (по контракту API не null).
    function onCharacteristicChanged(characteristic, value) {
        if (DEBUG) {
            // Троттлинг: notify сыпется ~десятки раз в секунду и забивает 5 КБ-лог
            // одинаковыми пакетами, вытесняя события связи. Логируем пакет только при
            // СМЕНЕ передачи (байт[5]) либо хартбитом раз в SCAN_LOG_HB_MS.
            var gear = (value.size() > _rearIdx) ? value[_rearIdx] : -1;
            var nowMs = System.getTimer();
            if (gear != _lastLoggedGear || (nowMs - _lastNotifyLogMs) >= SCAN_LOG_HB_MS) {
                logBytes(characteristic, value);
                _lastLoggedGear = gear;
                _lastNotifyLogMs = nowMs;
            }
        }
        // Счётчики notify ведём ВСЕГДА (два инкремента, не зависят от оверлея): именно
        // они отличают «канал молчит» от «пакеты идут, но не той длины».
        _state.dbgPktTotal += 1;
        if (value.size() == _pktLen) {
            _state.dbgPktGood += 1;
        }
        _state.dbgLastPktMs = System.getTimer();

        // Diag-overlay: сырой пакет на экран (для разбора формата чужой серии Di2,
        // у которой длина/смещения могут отличаться от профиля). Складываем ВСЕ
        // разновидности — по последнему пакету на каждую длину (см. recordPacket).
        if (_state.diagOverlay) {
            _state.dbgGearLen = value.size();
            _state.recordPacket(value.size(), toHex(value));
        }
        parseGearPacket(value);
    }

    // Ответ на requestRead батареи: байт[0] = процент 0..100.
    function onCharacteristicRead(characteristic, status, value) {
        _batteryReadInFlight = false;
        if (characteristic.getUuid().equals(_battCharUuid)) {
            if (value != null && value.size() > 0) {
                _state.battery = value[0].toNumber();
            }
        }
    }

    // ── Парсинг ───────────────────────────────────────────────────────────────

    private function parseGearPacket(value as Lang.ByteArray) as Void {
        if (value.size() == _pktLen) {
            if (_rearIdx >= 0 && _rearIdx < value.size()) {
                _state.rear = value[_rearIdx].toNumber();
            }
            // Передняя передача: только если профиль выявил её байт (_frontIdx>=0).
            // Иначе front остаётся из настроек (1x → 1; 2x/3x → "-/N", см. Di2FieldApp).
            if (_frontIdx >= 0 && _frontIdx < value.size()) {
                _state.front = value[_frontIdx].toNumber();
            }
            // frontTotal/rearTotal (число звёзд) задаются настройками (см. Di2FieldApp).
            // Сырой дамп пакета для diag-overlay снимается в onCharacteristicChanged
            // (любой длины), здесь не дублируем.
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

    // Подписка на notify: запись CCCD [0x01,0x00] на 0x2ac1.
    // КАЖДЫЙ шаг фиксируется в _state.dbgSub — раньше все отказы были молчаливыми
    // (три вложенных if без else), и «нет сервиса», «нет дескриптора» и «стек отклонил
    // запись» выглядели на экране одинаково: пакетов просто нет. Подтверждение записи
    // приходит асинхронно в onDescriptorWrite (там "wr" -> "ok"/"e<N>").
    private function enableNotifications(device as Ble.Device) as Void {
        try {
            _state.dbgSvcCount = countServices(device);   // 0 = дискавери ещё не готова
            var svc = device.getService(_modeSvcUuid);
            if (svc == null) {
                _state.dbgSub = "no-svc";
                log("subscribe: service 18ef not found");
                return;
            }
            var ch = svc.getCharacteristic(_modeCharUuid);
            if (ch == null) {
                _state.dbgSub = "no-chr";
                log("subscribe: characteristic 2ac1 not found");
                return;
            }
            var cccd = ch.getDescriptor(Ble.cccdUuid());
            if (cccd == null) {
                _state.dbgSub = "no-cccd";
                log("subscribe: cccd descriptor not found");
                return;
            }
            _state.dbgSub = "wr";              // ждём подтверждения от стека
            cccd.requestWrite([0x01, 0x00]b);  // включить notifications
            log("subscribe: cccd write requested");
        } catch (e) {
            _state.dbgSub = "ex";
            log("subscribe: exception");
        }
    }

    // Подтверждение записи CCCD от BLE-стека. Раньше колбэк не был реализован вовсе,
    // поэтому отклонённая подписка (например при протухшем бонде) была неотличима от
    // молчащего устройства. Теперь статус виден в diag-оверлее: "ok" либо "e<N>".
    function onDescriptorWrite(descriptor, status) {
        if (status == Ble.STATUS_SUCCESS) {
            _state.dbgSub = "ok";
        } else {
            _state.dbgSub = "e" + status.toString();
        }
        log("cccd write status=" + status);
    }

    // Повторная попытка подписки на активном соединении (см. onTick). Устройство берём
    // из списка спаренных — ссылки на Ble.Device мы намеренно не храним, её валидность
    // между колбэками не гарантируется.
    private function retrySubscribe() as Void {
        try {
            var d = Ble.getPairedDevices().next() as Ble.Device?;
            if (d != null && d.isConnected()) {
                logServices(d);
                // Личность снимаем заново: при той же гонке (onConnected до завершения
                // дискавери) getName() отдаёт null, профиль парсинга остаётся дефолтным,
                // и на не-XT сериях передачи разбирались бы по чужой раскладке.
                if (_state.dbgDeviceName.length() == 0) {
                    captureIdentity(d);
                }
                enableNotifications(d);
            }
        } catch (e) {
            _state.dbgSub = "ex";
        }
    }

    // Сколько сервисов видит стек на устройстве. Отличает «дискавери не завершена»
    // (0 сервисов) от «сервис реально отсутствует в прошивке» (есть другие, но не 18ef).
    private function countServices(device as Ble.Device) as Lang.Number {
        var n = 0;
        var seen = "";
        try {
            // Итератор берём ОДИН раз: повторный getServices() отдаёт новый итератор
            // и цикл вечно читал бы первый сервис.
            var it = device.getServices();
            for (var svc = it.next(); svc != null; svc = it.next()) {
                seen += shortUuid((svc as Ble.Service).getUuid()) + " ";
                n += 1;
                if (n >= 16) { break; }
            }
        } catch (e) {
            _state.dbgSvcList = "?";
            return -1;
        }
        _state.dbgSvcList = seen;   // какие именно сервисы видит стек
        return n;
    }

    // Перечислить сервисы устройства в лог: пустой список = GATT-дискавери ещё не
    // завершена, непустой без 18ef = прошивка действительно не отдаёт этот сервис.
    private function logServices(device as Ble.Device) as Void {
        if (!DEBUG) {
            return;
        }
        var n = 0;
        var line = "";
        var it = device.getServices();   // итератор берём один раз (см. countServices)
        for (var svc = it.next(); svc != null; svc = it.next()) {
            line += (svc as Ble.Service).getUuid().toString() + " ";
            n += 1;
            if (n >= 8) { break; }
        }
        Di2Log.line("services n=" + n + " [" + line + "]");
    }

    // Однократное чтение батареи. Зовётся при подключении и периодически из onTick().
    function readBattery() as Void {
        if (_batteryReadInFlight) {
            return;  // ждём предыдущий read — иначе возможен краш (см. NOTES.md)
        }
        try {
            var d = Ble.getPairedDevices().next() as Ble.Device?;
            if (d != null && d.isConnected()) {
                var svc = d.getService(_battSvcUuid);
                if (svc != null) {
                    var ch = svc.getCharacteristic(_battCharUuid);
                    if (ch != null) {
                        _batteryReadInFlight = true;
                        ch.requestRead();
                    }
                }
            }
        } catch (e) {
            _batteryReadInFlight = false;
            if (DEBUG) { log("battery read failed"); }
        }
    }

    // ── Тик-планировщик (вместо Timer; вызывается из View.compute() ~1 c) ───────

    // Heartbeat дата-филда: гоним отложенный реконнект и периодический опрос батареи.
    function onTick() as Void {
        // Кадровый счётчик для пульсации индикатора в View (одна анимация на 1 c тик).
        _state.anim += 1;

        // Счётчик секунд в фазе подключения: при слабом сигнале коннект длится до ~17 c,
        // и без индикации жёлтый кружок выглядит «зависшим». Показываем прогресс в View.
        if (_state.phase == CONN_CONNECTING) {
            _state.connSeconds += 1;
        } else {
            _state.connSeconds = 0;
        }

        // Счётчик непрерывного скана: после долгого безуспешного поиска D-Fly,
        // вероятно, в глубоком сне и не вещает — подсказываем пользователю паринг.
        if (_state.phase == CONN_SCANNING) {
            _state.scanSeconds += 1;
        } else {
            _state.scanSeconds = 0;
        }

        // Отложенный реконнект (когда не подключены).
        if (_reconnectCountdown > 0) {
            _reconnectCountdown -= 1;
            if (_reconnectCountdown == 0) {
                _reconnectCountdown = -1;
                _state.phase = CONN_SCANNING;
                if (DEBUG) { log("reconnect attempt " + _reconnectAttempts); }
                startScan();
            }
        }

        // Ретрай подписки на notify. КРИТИЧНО: onConnected может быть вызван из
        // connectTo синхронно, сразу после pairDevice — до того, как BLE-стек завершил
        // GATT-дискавери. Тогда getService(18ef) отдаёт null (sub=no-svc), а единственная
        // попытка подписки уже потрачена: соединение живое, батарея читается (её опрос
        // периодический), а передачи не приходят никогда. Поэтому повторяем подписку,
        // пока стек не подтвердит запись CCCD (dbgSub == "ok").
        if (_state.connected && !_state.dbgSub.equals("ok")) {
            _subRetryCounter += 1;
            if (_subRetryCounter >= SUB_RETRY_TICKS) {
                _subRetryCounter = 0;
                retrySubscribe();
            }
        } else {
            _subRetryCounter = 0;
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

    // Тик, не зависящий от записи активности: его гонит View.onUpdate (см. там же).
    // Нужен, чтобы подписка на notify восстанавливалась и до старта таймера — раньше
    // вся периодика висела на compute(), который система зовёт только во время записи.
    //
    // ЗДЕСЬ НЕЛЬЗЯ ПЕРЕРЕГИСТРИРОВАТЬ ПРОФИЛЬ. Повторный Ble.registerProfile роняет
    // дата-филд системной ошибкой прямо внутри вызова (CIQ_LOG: registerModeProfile,
    // строка с registerProfile). System Error не перехватывается try/catch, поэтому
    // защититься нельзя — только не вызывать. Профиль регистрируем ровно один раз
    // за запуск, см. registerProfiles/start.
    function onIdleTick() as Void {
        if (!_state.connected || _state.dbgSub.equals("ok")) {
            return;
        }
        _subRetryCounter += 1;
        if (_subRetryCounter >= SUB_RETRY_TICKS) {
            _subRetryCounter = 0;
            retrySubscribe();
        }
    }

    // Запланировать повторный скан. Интервал растёт с числом неудач до потолка,
    // но попытки не заканчиваются — связь восстановится, как только Di2 проснётся.
    private function scheduleReconnect() as Void {
        _state.phase = CONN_RETRY;
        _state.dbgReconnects += 1;
        _reconnectAttempts += 1;
        var delay = _reconnectAttempts * RECONNECT_MIN_TICKS;
        _reconnectCountdown = (delay < RECONNECT_MAX_TICKS) ? delay : RECONNECT_MAX_TICKS;
        if (DEBUG) { log("reconnect scheduled in " + _reconnectCountdown + " ticks (attempt " + _reconnectAttempts + ")"); }
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
        if (!DEBUG) {
            return;
        }
        Di2Log.line("notify char=" + characteristic.getUuid().toString() + " len=" + value.size() + " bytes=[" + toHex(value) + "]");
    }

    private function log(msg as Lang.String) as Void {
        if (DEBUG) {
            Di2Log.line(msg);
        }
    }
}
