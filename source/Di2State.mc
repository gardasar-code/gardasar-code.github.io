using Toybox.Lang;

// Фазы установления BLE-связи — для наглядной индикации в UI.
// Точка-индикатор и центральный статус-текст рисуются по этому значению.
enum {
    CONN_SCANNING = 0,   // ищем устройство в эфире
    CONN_CONNECTING,     // нашли, поднимаем соединение/подписку
    CONN_LIVE,           // подключены, данные идут
    CONN_RETRY           // связь потеряна, ждём следующей попытки
}

// Режим показа батареи (настройка batteryDisplay / Di2State.batteryMode).
enum {
    BAT_PCT = 0,         // только процент
    BAT_ICON,            // только иконка
    BAT_BOTH             // иконка + процент
}

// Режим показа задней передачи (настройка displayMode / Di2State.displayMode).
enum {
    DISP_NUM = 0,        // цифры
    DISP_GRAPH,          // график (визуальная кассета)
    DISP_BOTH            // оба (кассета сверху, цифры снизу)
}

// Разделяемое состояние между BLE-делегатом (писатель) и View (читатель).
// Один экземпляр создаётся в Di2FieldApp и передаётся обоим.
// Значение -1 означает «нет данных» (рисуем "---").
class Di2State {

    public var connected as Lang.Boolean = false;  // есть ли активное BLE-соединение
    public var phase as Lang.Number = CONN_SCANNING;  // фаза связи (см. enum выше)
    public var anim as Lang.Number = 0;            // монотонный счётчик кадров для пульсации
    public var locked as Lang.Boolean = false;     // sticky-lock активен (привязаны к «своему» Di2)
    public var connSeconds as Lang.Number = 0;     // секунд в фазе CONNECTING (для индикации прогресса)
    public var scanSeconds as Lang.Number = 0;     // секунд непрерывного скана (для подсказки про паринг)
    public var rear as Lang.Number = -1;            // текущая задняя передача (1-based)
    public var rearTotal as Lang.Number = -1;       // число задних передач
    public var front as Lang.Number = -1;           // текущая передняя передача (1-based)
    public var frontTotal as Lang.Number = -1;      // число передних передач
    public var battery as Lang.Number = -1;         // заряд D-Fly, % (0..100)
    public var batteryMode as Lang.Number = BAT_PCT;   // показ батареи (см. enum BAT_*)
    public var displayMode as Lang.Number = DISP_NUM;  // показ передачи (см. enum DISP_*)

    // Дефолтная конфигурация звёзд — единый источник правды (дублировалась в
    // Di2FieldApp.loadSettings и properties.xml). Ссылка делится только для чтения:
    // парсер настроек (readTeeth) при валидном вводе создаёт новый массив.
    public const DEFAULT_FRONT_TEETH as Lang.Array<Lang.Number> = [32];
    public const DEFAULT_REAR_TEETH  as Lang.Array<Lang.Number> = [10, 12, 14, 16, 18, 21, 24, 28, 33, 39, 45, 51];

    // Зубья из настроек: передние звёзды и кассета (от меньшей к большей).
    // Длина списков задаёт frontTotal/rearTotal.
    public var frontTeeth as Lang.Array<Lang.Number> = DEFAULT_FRONT_TEETH;
    public var rearTeeth as Lang.Array<Lang.Number> = DEFAULT_REAR_TEETH;

    // ── Диагностика на экране (diagOverlay) ───────────────────────────────────
    // Включается настройкой diagOverlay. Работает в обычной store-сборке (это
    // рисование в onUpdate, а не System.println, который в release не пишет файл),
    // поэтому любой пользователь может прислать ФОТО экрана для разбора проблем
    // подключения на неподдержанном устройстве. См. doc/LOGGING.md.
    public var diagOverlay as Lang.Boolean = false;

    // Сводка последнего скана (discovery эфира): сколько устройств видит BLE-стек
    // всего и сколько из них с Shimano-маркером (ADV_SERVICE_UUID), лучший RSSI.
    // dev>0 & shi=0 → в эфире есть BLE, но Di2 не под нашим маркером (другая серия).
    public var dbgScanTotal as Lang.Number = 0;
    public var dbgScanShimano as Lang.Number = 0;
    public var dbgBestRssi as Lang.Number = -999;   // -999 = нет shimano-кандидатов

    // Сырой последний notify-пакет: hex и длина. Заполняется при diagOverlay для
    // ЛЮБОЙ длины (не только PKT_GEAR_LEN) — чтобы увидеть формат чужой серии Di2.
    public var dbgGear as Lang.String = "";
    public var dbgGearLen as Lang.Number = 0;

    // GATT-имя подключённого устройства (напр. "RDM8250S2A8"). В эфире скана имя
    // недоступно (null) — приходит только после подключения по GATT. Это единственный
    // идентификатор модели переключателя: по нему авто-детектится профиль (см.
    // Di2BleDelegate.PROFILES) и краудсорсятся новые серии Di2 по ФОТО оверлея.
    public var dbgDeviceName as Lang.String = "";
    // Метка активного профиля парсинга (модель/серия Di2), определённого по имени.
    public var dbgModel as Lang.String = "";

    function initialize() {
    }

    // Зубья текущей передней звезды (0, если позиция неизвестна).
    function currentFrontTeeth() as Lang.Number {
        if (front >= 1 && front <= frontTeeth.size()) {
            return frontTeeth[front - 1];
        }
        return 0;
    }

    // Зубья текущей задней звезды (0, если нет данных).
    function currentRearTeeth() as Lang.Number {
        if (rear >= 1 && rear <= rearTeeth.size()) {
            return rearTeeth[rear - 1];
        }
        return 0;
    }

    // Передаточное отношение (front/rear), 0.0 если данных нет.
    function gearRatio() as Lang.Float {
        var ft = currentFrontTeeth();
        var rt = currentRearTeeth();
        if (ft > 0 && rt > 0) {
            return ft.toFloat() / rt.toFloat();
        }
        return 0.0;
    }

    // Сбросить «живые» данные (при потере соединения): задняя передача и батарея.
    // Не трогаем front/frontTotal/rearTotal/зубья — это конфигурация, переживает реконнект.
    function resetLiveData() as Void {
        rear = -1;
        battery = -1;
    }
}
