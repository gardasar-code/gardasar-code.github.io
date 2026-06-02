using Toybox.FitContributor as Fit;
using Toybox.WatchUi;
using Toybox.Lang;

// Запись передач (в зубьях), передаточного отношения и заряда D-Fly в FIT.
//   record-уровень (посекундно): зубья передней/задней звезды, ratio, заряд;
//   session-уровень (сводка за заезд): макс. ratio, мин. заряд.
// Видно в Garmin Connect (секция Connect IQ) и доступно сторонним сервисам.
class Di2FitContributor {

    private const FIELD_FRONT       = 0;
    private const FIELD_REAR        = 1;
    private const FIELD_RATIO       = 2;
    private const FIELD_BATTERY     = 3;
    private const FIELD_MAX_RATIO   = 4;
    private const FIELD_MIN_BATTERY = 5;

    private const UNIT_TEETH = "T";

    private var _frontField;
    private var _rearField;
    private var _ratioField;
    private var _batteryField;
    private var _maxRatioField;
    private var _minBatteryField;

    private var _maxRatio as Lang.Float = 0.0;
    private var _minBattery as Lang.Number = 101;

    // view — наш Data Field (наследует WatchUi.DataField), у него есть createField().
    function initialize(view as WatchUi.DataField) {
        var pct = WatchUi.loadResource(Rez.Strings.FieldBatteryUnit);

        // record-уровень (посекундно)
        _frontField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldFrontGear), FIELD_FRONT, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD, :units => UNIT_TEETH});
        _rearField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldRearGear), FIELD_REAR, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD, :units => UNIT_TEETH});
        _ratioField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldRatio), FIELD_RATIO, Fit.DATA_TYPE_FLOAT,
            {:mesgType => Fit.MESG_TYPE_RECORD});
        _batteryField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldBattery), FIELD_BATTERY, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD, :units => pct});

        // session-уровень (сводка за заезд)
        _maxRatioField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldMaxRatio), FIELD_MAX_RATIO, Fit.DATA_TYPE_FLOAT,
            {:mesgType => Fit.MESG_TYPE_SESSION});
        _minBatteryField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldMinBattery), FIELD_MIN_BATTERY, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_SESSION, :units => pct});

        _frontField.setData(0);
        _rearField.setData(0);
        _ratioField.setData(0.0);
        _batteryField.setData(0);
        _maxRatioField.setData(0.0);
        _minBatteryField.setData(100);
    }

    // Записать текущие значения за тик.
    function update(frontTeeth as Lang.Number, rearTeeth as Lang.Number,
                    ratio as Lang.Float, battery as Lang.Number) as Void {
        _frontField.setData(frontTeeth);
        _rearField.setData(rearTeeth);
        _ratioField.setData(ratio);
        _batteryField.setData(battery < 0 ? 0 : battery);

        // Сводка за заезд.
        if (ratio > _maxRatio) {
            _maxRatio = ratio;
            _maxRatioField.setData(_maxRatio);
        }
        if (battery > 0 && battery < _minBattery) {
            _minBattery = battery;
            _minBatteryField.setData(_minBattery);
        }
    }
}
