using Toybox.FitContributor as Fit;
using Toybox.WatchUi;
using Toybox.Lang;

// Запись данных Di2 в FIT-файл активности (секция Connect IQ в Garmin Connect).
//   record (посекундно): передача по индексу (зад/перёд), зубья (зад/перёд),
//                        передаточное отношение, заряд D-Fly;
//   session (сводка):    макс. задняя передача, макс. ratio, мин. заряд.
class Di2FitContributor {

    private const FIELD_REAR_GEAR   = 0;   // индекс задней (1..N)
    private const FIELD_FRONT_GEAR  = 1;   // индекс передней (1..N)
    private const FIELD_REAR_TEETH  = 2;   // зубья задней
    private const FIELD_FRONT_TEETH = 3;   // зубья передней
    private const FIELD_RATIO       = 4;   // передаточное (float)
    private const FIELD_BATTERY     = 5;   // заряд %
    private const FIELD_MAX_REAR    = 6;   // session: макс. задняя (индекс)
    private const FIELD_MAX_RATIO   = 7;   // session: макс. ratio
    private const FIELD_MIN_BATTERY = 8;   // session: мин. заряд %

    private const UNIT_GEAR  = "gear";
    private const UNIT_TEETH = "T";

    private var _rearGearField;
    private var _frontGearField;
    private var _rearTeethField;
    private var _frontTeethField;
    private var _ratioField;
    private var _batteryField;
    private var _maxRearField;
    private var _maxRatioField;
    private var _minBatteryField;

    private var _maxRear as Lang.Number = 0;
    private var _maxRatio as Lang.Float = 0.0;
    private var _minBattery as Lang.Number = 101;

    // view — наш Data Field (наследует WatchUi.DataField), у него есть createField().
    function initialize(view as WatchUi.DataField) {
        var pct = WatchUi.loadResource(Rez.Strings.FieldBatteryUnit);

        // ── record-уровень (посекундно) ──
        _rearGearField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldRearGear), FIELD_REAR_GEAR, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD, :units => UNIT_GEAR});
        _frontGearField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldFrontGear), FIELD_FRONT_GEAR, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD, :units => UNIT_GEAR});
        _rearTeethField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldRearTeeth), FIELD_REAR_TEETH, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD, :units => UNIT_TEETH});
        _frontTeethField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldFrontTeeth), FIELD_FRONT_TEETH, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD, :units => UNIT_TEETH});
        _ratioField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldRatio), FIELD_RATIO, Fit.DATA_TYPE_FLOAT,
            {:mesgType => Fit.MESG_TYPE_RECORD});
        _batteryField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldBattery), FIELD_BATTERY, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_RECORD, :units => pct});

        // ── session-уровень (сводка за заезд) ──
        _maxRearField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldMaxRearGear), FIELD_MAX_REAR, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_SESSION, :units => UNIT_GEAR});
        _maxRatioField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldMaxRatio), FIELD_MAX_RATIO, Fit.DATA_TYPE_FLOAT,
            {:mesgType => Fit.MESG_TYPE_SESSION});
        _minBatteryField = view.createField(
            WatchUi.loadResource(Rez.Strings.FieldMinBattery), FIELD_MIN_BATTERY, Fit.DATA_TYPE_UINT8,
            {:mesgType => Fit.MESG_TYPE_SESSION, :units => pct});

        _rearGearField.setData(0);
        _frontGearField.setData(0);
        _rearTeethField.setData(0);
        _frontTeethField.setData(0);
        _ratioField.setData(0.0);
        _batteryField.setData(0);
        _maxRearField.setData(0);
        _maxRatioField.setData(0.0);
        _minBatteryField.setData(100);
    }

    // Записать текущие значения за тик. Неизвестные (-1) пишем как 0.
    function update(rearGear as Lang.Number, frontGear as Lang.Number,
                    rearTeeth as Lang.Number, frontTeeth as Lang.Number,
                    ratio as Lang.Float, battery as Lang.Number) as Void {
        _rearGearField.setData(rearGear < 0 ? 0 : rearGear);
        _frontGearField.setData(frontGear < 0 ? 0 : frontGear);
        _rearTeethField.setData(rearTeeth);
        _frontTeethField.setData(frontTeeth);
        _ratioField.setData(ratio);
        _batteryField.setData(battery < 0 ? 0 : battery);

        // Сводка за заезд.
        if (rearGear > _maxRear) {
            _maxRear = rearGear;
            _maxRearField.setData(_maxRear);
        }
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
