using Toybox.FitContributor as Fit;
using Toybox.WatchUi;
using Toybox.Lang;

// Запись передач и заряда D-Fly в FIT-файл активности (record-уровень, посекундно).
// Видно в Garmin Connect как developer-поля/графики и доступно сторонним сервисам.
// Не зависит от BLE — работает и на устройстве, и в симуляторе при записи активности.
class Di2FitContributor {

    private const FIELD_REAR    = 0;
    private const FIELD_FRONT   = 1;
    private const FIELD_BATTERY = 2;

    private var _rearField;
    private var _frontField;
    private var _batteryField;

    // view — наш Data Field (наследует WatchUi.DataField), у него есть createField().
    function initialize(view as WatchUi.DataField) {
        _rearField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldRearGear), FIELD_REAR, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD});
        _frontField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldFrontGear), FIELD_FRONT, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD});
        _batteryField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldBattery), FIELD_BATTERY, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD, :units => WatchUi.loadResource(Rez.Strings.FieldBatteryUnit)});

        _rearField.setData(0);
        _frontField.setData(0);
        _batteryField.setData(0);
    }

    // Записать текущие значения. Неизвестные (-1) пишем как 0 (UINT8 без отрицательных).
    function update(rear as Lang.Number, front as Lang.Number, battery as Lang.Number) as Void {
        _rearField.setData(rear < 0 ? 0 : rear);
        _frontField.setData(front < 0 ? 0 : front);
        _batteryField.setData(battery < 0 ? 0 : battery);
    }
}
