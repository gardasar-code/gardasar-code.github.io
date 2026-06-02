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
    function onSettingsChanged() as Void {
        loadSettings();
        WatchUi.requestUpdate();
    }

    // Загрузка пользовательских настроек (зубья звёзд) в состояние.
    // Число передач выводится из длины списков зубьев.
    private function loadSettings() as Void {
        if (_state == null) {
            return;
        }
        _state.frontTeeth = readTeeth("frontTeeth", [32]);
        _state.rearTeeth = readTeeth("rearTeeth", [10, 12, 14, 16, 18, 21, 24, 28, 33, 39, 45, 51]);
        _state.frontTotal = _state.frontTeeth.size();
        _state.rearTotal = _state.rearTeeth.size();
        // Текущую переднюю позицию из пакета не вычислить; для 1x она всегда 1,
        // для 2x/3x — неизвестна (покажем "-/N").
        _state.front = (_state.frontTotal == 1) ? 1 : -1;
    }

    // Прочитать строковое свойство и распарсить в список чисел (зубья).
    // Любой нецифровой символ — разделитель. Пустой/битый ввод → дефолт.
    private function readTeeth(key as Lang.String, dflt as Lang.Array<Lang.Number>) as Lang.Array<Lang.Number> {
        var v = Application.Properties.getValue(key);
        if (!(v instanceof Lang.String)) {
            return dflt;
        }
        var out = [] as Lang.Array<Lang.Number>;
        var cur = "";
        var digits = "0123456789";
        var chars = (v as Lang.String).toCharArray();
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
