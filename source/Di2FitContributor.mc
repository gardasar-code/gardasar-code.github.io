using Toybox.FitContributor as Fit;
using Toybox.WatchUi;
using Toybox.Lang;

// Запись передач и заряда D-Fly в FIT-файл активности.
//   record-уровень (посекундно): задняя/передняя передача, заряд;
//   session-уровень (сводка за заезд): макс. задняя передача, мин. заряд.
// Видно в Garmin Connect как developer-поля и доступно сторонним сервисам.
// Не зависит от BLE — работает и на устройстве, и в симуляторе при записи активности.
class Di2FitContributor {

    private const FIELD_REAR        = 0;
    private const FIELD_FRONT       = 1;
    private const FIELD_BATTERY     = 2;
    private const FIELD_MAX_REAR    = 3;
    private const FIELD_MIN_BATTERY = 4;

    private const UNIT_GEAR = "gear";

    private var _rearField;
    private var _frontField;
    private var _batteryField;
    private var _maxRearField;
    private var _minBatteryField;

    private var _maxRear as Lang.Number = 0;
    private var _minBattery as Lang.Number = 101;   // выше 100 → первое валидное значение перезапишет

    // view — наш Data Field (наследует WatchUi.DataField), у него есть createField().
    function initialize(view as WatchUi.DataField) {
        var pct = WatchUi.loadResource(Rez.Strings.FieldBatteryUnit);

        // record-уровень (посекундно)
        _rearField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldRearGear), FIELD_REAR, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD, :units => UNIT_GEAR});
        _frontField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldFrontGear), FIELD_FRONT, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD, :units => UNIT_GEAR});
        _batteryField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldBattery), FIELD_BATTERY, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD, :units => pct});

        // session-уровень (сводка за заезд)
        _maxRearField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldMaxRearGear), FIELD_MAX_REAR, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_SESSION, :units => UNIT_GEAR});
        _minBatteryField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldMinBattery), FIELD_MIN_BATTERY, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_SESSION, :units => pct});

        _rearField.setData(0);
        _frontField.setData(0);
        _batteryField.setData(0);
        _maxRearField.setData(0);
        _minBatteryField.setData(100);
    }

    // Записать текущие значения. Неизвестные (-1) пишем как 0 (UINT8 без отрицательных).
    function update(rear as Lang.Number, front as Lang.Number, battery as Lang.Number) as Void {
        _rearField.setData(rear < 0 ? 0 : rear);
        _frontField.setData(front < 0 ? 0 : front);
        _batteryField.setData(battery < 0 ? 0 : battery);

        // Сводка: макс. использованная задняя и минимальный заряд за заезд.
        if (rear > _maxRear) {
            _maxRear = rear;
            _maxRearField.setData(_maxRear);
        }
        if (battery > 0 && battery < _minBattery) {
            _minBattery = battery;
            _minBatteryField.setData(_minBattery);
        }
    }
}
