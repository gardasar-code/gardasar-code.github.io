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

    // Сырые notify-пакеты в hex — ВСЕ разновидности, а не только последний пакет.
    // D-Fly шлёт вперемешку несколько форматов (на XT M8250 это 17, 6 и 3 байта,
    // см. doc/NOTES.md), и «последний пакет» на экране почти всегда оказывался
    // коротким служебным. Поэтому храним последний пакет КАЖДОЙ встреченной длины:
    // короткие больше не затирают длинный, а неразобранные форматы наконец видны
    // целиком — их и предстоит расшифровывать по фото оверлея.
    // Списки параллельные (hex и длина), отсортированы по УБЫВАНИЮ длины: самый
    // информативный пакет рисуется первым и гарантированно попадает на экран.
    public const DBG_MAX_KINDS as Lang.Number = 4;   // потолок разновидностей (экран мал)
    public var dbgPktHex as Lang.Array<Lang.String> = [] as Lang.Array<Lang.String>;
    public var dbgPktLen as Lang.Array<Lang.Number> = [] as Lang.Array<Lang.Number>;

    // Длина ПОСЛЕДНЕГО пакета любой длины — сигнал «канал жив прямо сейчас».
    public var dbgGearLen as Lang.Number = 0;

    // ── Диагностика подписки на notify (CCCD) ─────────────────────────────────
    // Различает молчаливые отказы подписки: до этого «сервис не найден», «нет
    // характеристики», «нет дескриптора» и «запись отклонена стеком» выглядели на
    // экране одинаково (пакетов просто нет). Значения:
    //   "-"       подписка ещё не пробовалась (нет соединения)
    //   "wr"      CCCD-запись отправлена, подтверждения стека ещё нет
    //   "ok"      стек подтвердил запись CCCD (STATUS_SUCCESS)
    //   "no-svc"  device.getService(18ef) вернул null
    //   "no-chr"  service.getCharacteristic(2ac1) вернул null
    //   "no-cccd" у характеристики нет CCCD-дескриптора
    //   "ex"      исключение при подписке
    //   "e<N>"    стек вернул статус N (запись CCCD не прошла)
    public var dbgSub as Lang.String = "-";

    // Счётчики notify за сессию: всего пакетов и из них годных (длина совпала с
    // длиной активного профиля → парсинг отработал). total>0 при good=0 означает
    // «канал жив, но раскладка пакета другая» — то есть чинить профиль, а не связь.
    public var dbgPktTotal as Lang.Number = 0;
    public var dbgPktGood as Lang.Number = 0;

    // System.getTimer() последнего notify (0 = пакетов ещё не было). View считает по
    // нему возраст данных: «пакеты шли и прекратились» ≠ «их не было никогда».
    public var dbgLastPktMs as Lang.Number = 0;

    // Сколько сервисов BLE-стек видит на подключённом устройстве в момент подписки.
    // Ключ к различению двух совершенно разных причин "no-svc": 0 — GATT-дискавери
    // ещё не завершилась (наша гонка, лечится повтором подписки), >0 — сервисы
    // обнаружены, но нужного среди них нет (прошивка не отдаёт 18ef).
    public var dbgSvcCount as Lang.Number = -1;   // -1 = подписка ещё не пробовалась

    // Результаты registerProfile от стека ("180F:ok 18EF:e5"). Пусто = колбэк ещё не
    // приходил. Незарегистрированный профиль стек не ищет на устройстве вовсе, поэтому
    // ошибка здесь объясняет "no-svc" при заведомо исправном переключателе.
    public var dbgReg as Lang.String = "";

    // Какие сервисы стек реально видит на устройстве (короткие UUID через пробел).
    public var dbgSvcList as Lang.String = "";

    // Сколько раз за сессию планировался реконнект — мера нестабильности связи.
    public var dbgReconnects as Lang.Number = 0;

    // GATT-имя подключённого устройства (напр. "RDM8250S2A8"). В эфире скана имя
    // недоступно (null) — приходит только после подключения по GATT. Это единственный
    // идентификатор модели переключателя: по нему авто-детектится профиль (см.
    // Di2BleDelegate.PROFILES) и краудсорсятся новые серии Di2 по ФОТО оверлея.
    public var dbgDeviceName as Lang.String = "";
    // Метка активного профиля парсинга (модель/серия Di2), определённого по имени.
    public var dbgModel as Lang.String = "";

    function initialize() {
    }

    // Запомнить пакет для diag-оверлея: обновляет запись своей длины либо заводит
    // новую. Порядок — по убыванию длины (вставка в отсортированный список, размер
    // <= DBG_MAX_KINDS, поэтому пузырёк дешевле любой универсальной сортировки).
    // Разновидности сверх лимита отбрасываются с хвоста, то есть самые короткие.
    function recordPacket(len as Lang.Number, hex as Lang.String) as Void {
        for (var i = 0; i < dbgPktLen.size(); i++) {
            if (dbgPktLen[i] == len) {
                dbgPktHex[i] = hex;
                return;
            }
        }
        dbgPktLen.add(len);
        dbgPktHex.add(hex);
        // Продвигаем новую запись влево, пока слева пакет короче.
        for (var i = dbgPktLen.size() - 1; i > 0 && dbgPktLen[i] > dbgPktLen[i - 1]; i--) {
            var tl = dbgPktLen[i];   dbgPktLen[i] = dbgPktLen[i - 1];   dbgPktLen[i - 1] = tl;
            var th = dbgPktHex[i];   dbgPktHex[i] = dbgPktHex[i - 1];   dbgPktHex[i - 1] = th;
        }
        if (dbgPktLen.size() > DBG_MAX_KINDS) {
            dbgPktLen = dbgPktLen.slice(0, DBG_MAX_KINDS);
            dbgPktHex = dbgPktHex.slice(0, DBG_MAX_KINDS);
        }
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
