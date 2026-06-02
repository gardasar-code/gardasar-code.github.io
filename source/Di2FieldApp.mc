using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Lang;

// Точка входа Data Field. Управляет жизненным циклом:
//  - создаёт разделяемое состояние Di2State,
//  - регистрирует BLE-делегат и стартует скан в onStart,
//  - отдаёт View в getInitialView,
//  - корректно отключает BLE в onStop.
class Di2FieldApp extends Application.AppBase {

    // ╔══════════════════════════════════════════════════════════════════════╗
    // ║  ПЕРЕКЛЮЧАТЕЛЬ BLE — единственное, что нужно менять для sim/device     ║
    // ║                                                                        ║
    // ║   true   → реальный Edge Explore 2 (рабочий режим, прошивка)           ║
    // ║   false  → симулятор Connect IQ (проверка UI)                          ║
    // ║                                                                        ║
    // ║  Почему: BLE в симуляторе не эмулируется и роняет его (нативный краш   ║
    // ║  в потоке ant_main на macOS 26+). На устройстве этого потока нет —     ║
    // ║  там настоящий стек BLE, краш симулятора туда не переносится.          ║
    // ╚══════════════════════════════════════════════════════════════════════╝
    private const ENABLE_BLE = true;

    private var _state as Di2State?;
    private var _delegate as Di2BleDelegate?;

    function initialize() {
        AppBase.initialize();
    }

    // Вызывается при запуске Data Field. Здесь поднимаем BLE.
    function onStart(state as Lang.Dictionary?) as Void {
        _state = new Di2State();
        if (ENABLE_BLE) {
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

    // Data Field возвращает единственный View (без InputDelegate).
    // View получает делегат, чтобы из compute() гнать его onTick() (heartbeat BLE).
    function getInitialView() {
        var view = new Di2FieldView(_state, _delegate);
        return [view];
    }
}
