using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Lang;

// Точка входа Data Field. Управляет жизненным циклом:
//  - создаёт разделяемое состояние Di2State,
//  - регистрирует BLE-делегат и стартует скан в onStart,
//  - отдаёт View в getInitialView,
//  - корректно отключает BLE в onStop.
class Di2FieldApp extends Application.AppBase {

    private var _state as Di2State?;
    private var _delegate as Di2BleDelegate?;

    function initialize() {
        AppBase.initialize();
    }

    // Включён ли BLE — определяется ТИПОМ сборки через встроенные аннотации:
    //   :release (publish / device, -r) → true  : настоящий стек BLE на устройстве
    //   :debug   (F5 / симулятор)       → false : эмулятор BLE симулятора нестабилен
    //                                             (нативный краш в ant_main на macOS 26+)
    // Компилятор оставляет ровно одно определение в зависимости от флага -r.
    (:release) function bleEnabled() as Lang.Boolean { return true; }
    (:debug)   function bleEnabled() as Lang.Boolean { return false; }

    // Вызывается при запуске Data Field. Здесь поднимаем BLE.
    function onStart(state as Lang.Dictionary?) as Void {
        _state = new Di2State();
        loadSettings();
        if (bleEnabled()) {
            _delegate = new Di2BleDelegate(_state);
            _delegate.start();
        }
    }

    // Вызывается при остановке. Освобождаем BLE-ресурсы.
    function onStop(state as Lang.Dictionary?) as Void {
        if (_delegate != null) {
            _delegate.stop();
            _delegate = null;
        }
    }

    // Пользователь поменял настройки в Garmin Connect Mobile — перечитываем.
    // Делегат обрабатывает тоггл Forget (сброс sticky-lock и рескан).
    function onSettingsChanged() as Void {
        loadSettings();
        if (_delegate != null) {
            _delegate.onSettingsChanged();
        }
        WatchUi.requestUpdate();
    }

    // Загрузка пользовательских настроек в состояние.
    // Число звёзд — из селекторов (авторитет для отображения), зубья — из текстовых
    // полей (для передаточного отношения и FIT). Несоответствие длины не критично:
    // отсутствующие зубья → 0 (ratio там не считается).
    private function loadSettings() as Void {
        if (_state == null) {
            return;
        }
        _state.batteryMode = readNumberProperty("batteryDisplay", BAT_BOTH);
        _state.displayMode = readNumberProperty("displayMode", DISP_BOTH);
        _state.diagOverlay = readBooleanProperty("diagOverlay", false);

        // Зубья и число звёзд: пресет (популярная конфигурация Shimano) имеет приоритет
        // над ручным вводом. Непустой пресет задаёт и зубья, и число звёзд (по длине).
        var frontPreset = presetTeeth(FRONT_PRESETS, readNumberProperty("frontTeethPreset", 0));
        if (frontPreset != null) {
            _state.frontTeeth = parseTeethString(frontPreset, _state.DEFAULT_FRONT_TEETH);
            _state.frontTotal = _state.frontTeeth.size();
        } else {
            _state.frontTeeth = readTeeth("frontTeeth", _state.DEFAULT_FRONT_TEETH);
            _state.frontTotal = readNumberProperty("frontChainrings", 1);
        }

        var rearPreset = presetTeeth(REAR_PRESETS, readNumberProperty("rearTeethPreset", 0));
        if (rearPreset != null) {
            _state.rearTeeth = parseTeethString(rearPreset, _state.DEFAULT_REAR_TEETH);
            _state.rearTotal = _state.rearTeeth.size();
        } else {
            _state.rearTeeth = readTeeth("rearTeeth", _state.DEFAULT_REAR_TEETH);
            _state.rearTotal = readNumberProperty("rearCogs", 12);
        }

        // Текущую переднюю позицию из пакета не вычислить; для 1x она всегда 1,
        // для 2x/3x — неизвестна (покажем "-/N").
        _state.front = (_state.frontTotal == 1) ? 1 : -1;
    }

    // Безопасное чтение числового свойства с дефолтом.
    private function readNumberProperty(key as Lang.String, dflt as Lang.Number) as Lang.Number {
        var v = Application.Properties.getValue(key);
        return (v instanceof Lang.Number) ? v : dflt;
    }

    // Безопасное чтение булева свойства с дефолтом.
    private function readBooleanProperty(key as Lang.String, dflt as Lang.Boolean) as Lang.Boolean {
        var v = Application.Properties.getValue(key);
        return (v instanceof Lang.Boolean) ? v : dflt;
    }

    // Таблицы пресетов зубьев (популярные конфигурации Shimano). Индекс = значение
    // селектора в settings.xml; индекс 0 = Custom (ручной ввод). Раскладки кассет
    // сверены по ki2 (doc/ki2 RearTeethPattern). Зубья — от меньшей звезды к большей.
    private const FRONT_PRESETS as Lang.Array<Lang.String> = [
        "",            // 0 — Custom
        "50,34",       // 1 — Compact
        "52,36",       // 2 — Semi-compact
        "53,39",       // 3 — Standard
        "54,40",       // 4
        "48,31",       // 5 — GRX
        "46,30",       // 6 — GRX
        "38,28",       // 7 — MTB 2x
        "40,30,22"     // 8 — 3x
    ];
    private const REAR_PRESETS as Lang.Array<Lang.String> = [
        "",                                       // 0 — Custom
        "10,12,14,16,18,21,24,28,33,39,45,51",    // 1 — 12sp 10-51
        "11,12,13,14,15,17,19,21,24,27,30,34",    // 2 — 12sp 11-34
        "11,12,13,14,15,16,17,19,21,24,27,30",    // 3 — 12sp 11-30
        "11,12,13,14,15,17,19,21,24,28,32,36",    // 4 — 12sp 11-36
        "11,12,13,14,15,16,17,18,19,21,24,28",    // 5 — 12sp 11-28
        "11,13,15,17,19,21,23,25,27,30,34",       // 6 — 11sp 11-34
        "11,12,13,14,16,18,20,22,25,28,32",       // 7 — 11sp 11-32
        "11,13,15,17,19,21,24,28,32,37,46",       // 8 — 11sp 11-46
        "11,12,13,14,15,17,19,21,23,25,28",       // 9 — 11sp 11-28
        "11,13,15,17,19,21,24,27,31,35,40",       // 10 — 11sp 11-40
        "11,13,15,17,20,23,26,30,36,43",          // 11 — 10sp 11-43
        "11,13,15,17,20,23,28,34,41,48"           // 12 — 10sp 11-48
    ];

    // Строка зубьев для выбранного пресета или null (Custom/вне диапазона → ручной ввод).
    private function presetTeeth(table as Lang.Array<Lang.String>, idx as Lang.Number) as Lang.String? {
        if (idx <= 0 || idx >= table.size()) {
            return null;
        }
        var s = table[idx];
        return (s.length() > 0) ? s : null;
    }

    // Прочитать строковое свойство и распарсить в список чисел (зубья).
    private function readTeeth(key as Lang.String, dflt as Lang.Array<Lang.Number>) as Lang.Array<Lang.Number> {
        var v = Application.Properties.getValue(key);
        if (!(v instanceof Lang.String)) {
            return dflt;
        }
        return parseTeethString(v as Lang.String, dflt);
    }

    // Распарсить строку зубьев в список чисел (общая логика для ручного ввода и пресетов).
    // Любой нецифровой символ — разделитель. Пустой/битый ввод → дефолт.
    private function parseTeethString(s as Lang.String, dflt as Lang.Array<Lang.Number>) as Lang.Array<Lang.Number> {
        var out = [] as Lang.Array<Lang.Number>;
        var cur = "";
        var digits = "0123456789";
        var chars = s.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var ch = chars[i].toString();
            if (digits.find(ch) != null) {
                cur += ch;
            } else if (cur.length() > 0) {
                out.add(cur.toNumber());
                cur = "";
            }
        }
        if (cur.length() > 0) {
            out.add(cur.toNumber());
        }
        return (out.size() > 0) ? out : dflt;
    }

    // Data Field возвращает единственный View (без InputDelegate).
    // View получает делегат, чтобы из compute() гнать его onTick() (heartbeat BLE).
    function getInitialView() {
        var view = new Di2FieldView(_state, _delegate);
        return [view];
    }
}
