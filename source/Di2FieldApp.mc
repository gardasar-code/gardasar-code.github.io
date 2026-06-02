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

    // Загрузка пользовательских настроек (число передних/задних звёзд) в состояние.
    private function loadSettings() as Void {
        if (_state == null) {
            return;
        }
        _state.frontTotal = readNumberProperty("frontGears", 1);
        _state.rearTotal = readNumberProperty("rearGears", 12);
        // Текущую переднюю передачу из пакета не вычислить (нет байта); для 1x она
        // всегда 1, для 2x/3x — неизвестна (покажем "-/N").
        _state.front = (_state.frontTotal == 1) ? 1 : -1;
    }

    // Безопасное чтение числового свойства с дефолтом.
    private function readNumberProperty(key as Lang.String, dflt as Lang.Number) as Lang.Number {
        var v = Application.Properties.getValue(key);
        return (v == null) ? dflt : (v as Lang.Number);
    }

    // Data Field возвращает единственный View (без InputDelegate).
    // View получает делегат, чтобы из compute() гнать его onTick() (heartbeat BLE).
    function getInitialView() {
        var view = new Di2FieldView(_state, _delegate);
        return [view];
    }
}
