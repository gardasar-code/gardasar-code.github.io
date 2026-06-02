using Toybox.FitContributor as Fit;
using Toybox.WatchUi;
using Toybox.Lang;

// Запись данных Di2 в FIT (секция Connect IQ в Garmin Connect).
//   record (посекундно): передача по индексу (зад/перёд), зубья (зад/перёд),
//                        передаточное отношение, заряд D-Fly;
//   session (сводка):    макс/средн. ratio, мин. заряд, число переключений
//                        (перёд/зад), самая/редкая комбинация + доля времени,
//                        топ-3 самых используемых задних звёзд.
class Di2FitContributor {

    private const F_REAR_GEAR        = 0;
    private const F_FRONT_GEAR       = 1;
    private const F_REAR_TEETH       = 2;
    private const F_FRONT_TEETH      = 3;
    private const F_RATIO            = 4;
    private const F_BATTERY          = 5;
    private const F_MAX_REAR         = 6;
    private const F_MAX_RATIO        = 7;
    private const F_MIN_BATTERY      = 8;
    private const F_AVG_RATIO        = 9;
    private const F_FRONT_SHIFTS     = 10;
    private const F_REAR_SHIFTS      = 11;
    private const F_MOST_COMBO       = 12;
    private const F_MOST_COMBO_TIME  = 13;
    private const F_LEAST_COMBO      = 14;
    private const F_LEAST_COMBO_TIME = 15;
    private const F_REAR_TOP1        = 16;
    private const F_REAR_TOP2        = 17;
    private const F_REAR_TOP3        = 18;

    private const UNIT_GEAR  = "gear";
    private const UNIT_TEETH = "T";

    private var _stats as Di2RideStats;

    // record
    private var _rearGearField;
    private var _frontGearField;
    private var _rearTeethField;
    private var _frontTeethField;
    private var _ratioField;
    private var _batteryField;
    // session
    private var _maxRearField;
    private var _maxRatioField;
    private var _minBatteryField;
    private var _avgRatioField;
    private var _frontShiftsField;
    private var _rearShiftsField;
    private var _mostComboField;
    private var _mostComboTimeField;
    private var _leastComboField;
    private var _leastComboTimeField;
    private var _rearTop1Field;
    private var _rearTop2Field;
    private var _rearTop3Field;

    private var _maxRear as Lang.Number = 0;
    private var _minBattery as Lang.Number = 101;

    function initialize(view as WatchUi.DataField) {
        _stats = new Di2RideStats();

        var pct   = WatchUi.loadResource(Rez.Strings.FieldBatteryUnit);
        var ratio = WatchUi.loadResource(Rez.Strings.FieldRatioUnit);
        var shift = WatchUi.loadResource(Rez.Strings.FieldShiftUnit);
        var sprk  = WatchUi.loadResource(Rez.Strings.FieldSprocketUnit);

        var REC = Fit.MESG_TYPE_RECORD;
        var SES = Fit.MESG_TYPE_SESSION;

        // ── record ──
        _rearGearField  = view.createField(WatchUi.loadResource(Rez.Strings.FieldRearGear),   F_REAR_GEAR,   Fit.DATA_TYPE_UINT8, {:mesgType => REC, :units => UNIT_GEAR});
        _frontGearField = view.createField(WatchUi.loadResource(Rez.Strings.FieldFrontGear),  F_FRONT_GEAR,  Fit.DATA_TYPE_UINT8, {:mesgType => REC, :units => UNIT_GEAR});
        _rearTeethField = view.createField(WatchUi.loadResource(Rez.Strings.FieldRearTeeth),  F_REAR_TEETH,  Fit.DATA_TYPE_UINT8, {:mesgType => REC, :units => UNIT_TEETH});
        _frontTeethField= view.createField(WatchUi.loadResource(Rez.Strings.FieldFrontTeeth), F_FRONT_TEETH, Fit.DATA_TYPE_UINT8, {:mesgType => REC, :units => UNIT_TEETH});
        _ratioField     = view.createField(WatchUi.loadResource(Rez.Strings.FieldRatio),      F_RATIO,       Fit.DATA_TYPE_FLOAT, {:mesgType => REC, :units => ratio});
        _batteryField   = view.createField(WatchUi.loadResource(Rez.Strings.FieldBattery),    F_BATTERY,     Fit.DATA_TYPE_UINT8, {:mesgType => REC, :units => pct});

        // ── session ──
        _maxRearField       = view.createField(WatchUi.loadResource(Rez.Strings.FieldMaxRearGear),    F_MAX_REAR,         Fit.DATA_TYPE_UINT8,  {:mesgType => SES, :units => UNIT_GEAR});
        _maxRatioField      = view.createField(WatchUi.loadResource(Rez.Strings.FieldMaxRatio),       F_MAX_RATIO,        Fit.DATA_TYPE_FLOAT,  {:mesgType => SES, :units => ratio});
        _minBatteryField    = view.createField(WatchUi.loadResource(Rez.Strings.FieldMinBattery),     F_MIN_BATTERY,      Fit.DATA_TYPE_UINT8,  {:mesgType => SES, :units => pct});
        _avgRatioField      = view.createField(WatchUi.loadResource(Rez.Strings.FieldAvgRatio),       F_AVG_RATIO,        Fit.DATA_TYPE_FLOAT,  {:mesgType => SES, :units => ratio});
        _frontShiftsField   = view.createField(WatchUi.loadResource(Rez.Strings.FieldFrontShifts),    F_FRONT_SHIFTS,     Fit.DATA_TYPE_UINT16, {:mesgType => SES, :units => shift});
        _rearShiftsField    = view.createField(WatchUi.loadResource(Rez.Strings.FieldRearShifts),     F_REAR_SHIFTS,      Fit.DATA_TYPE_UINT16, {:mesgType => SES, :units => shift});
        _mostComboField     = view.createField(WatchUi.loadResource(Rez.Strings.FieldMostCombo),      F_MOST_COMBO,       Fit.DATA_TYPE_STRING, {:mesgType => SES, :count => 8});
        _mostComboTimeField = view.createField(WatchUi.loadResource(Rez.Strings.FieldMostComboTime),  F_MOST_COMBO_TIME,  Fit.DATA_TYPE_FLOAT,  {:mesgType => SES, :units => pct});
        _leastComboField    = view.createField(WatchUi.loadResource(Rez.Strings.FieldLeastCombo),     F_LEAST_COMBO,      Fit.DATA_TYPE_STRING, {:mesgType => SES, :count => 8});
        _leastComboTimeField= view.createField(WatchUi.loadResource(Rez.Strings.FieldLeastComboTime), F_LEAST_COMBO_TIME, Fit.DATA_TYPE_FLOAT,  {:mesgType => SES, :units => pct});
        _rearTop1Field      = view.createField(WatchUi.loadResource(Rez.Strings.FieldRearTop1),       F_REAR_TOP1,        Fit.DATA_TYPE_UINT8,  {:mesgType => SES, :units => sprk});
        _rearTop2Field      = view.createField(WatchUi.loadResource(Rez.Strings.FieldRearTop2),       F_REAR_TOP2,        Fit.DATA_TYPE_UINT8,  {:mesgType => SES, :units => sprk});
        _rearTop3Field      = view.createField(WatchUi.loadResource(Rez.Strings.FieldRearTop3),       F_REAR_TOP3,        Fit.DATA_TYPE_UINT8,  {:mesgType => SES, :units => sprk});

        // начальные значения
        _rearGearField.setData(0); _frontGearField.setData(0); _rearTeethField.setData(0);
        _frontTeethField.setData(0); _ratioField.setData(0.0); _batteryField.setData(0);
        _maxRearField.setData(0); _maxRatioField.setData(0.0); _minBatteryField.setData(100);
        _avgRatioField.setData(0.0); _frontShiftsField.setData(0); _rearShiftsField.setData(0);
        _mostComboField.setData("-"); _mostComboTimeField.setData(0.0);
        _leastComboField.setData("-"); _leastComboTimeField.setData(0.0);
        _rearTop1Field.setData(0); _rearTop2Field.setData(0); _rearTop3Field.setData(0);
    }

    function update(rearGear as Lang.Number, frontGear as Lang.Number,
                    rearTeeth as Lang.Number, frontTeeth as Lang.Number,
                    ratio as Lang.Float, battery as Lang.Number) as Void {
        // record
        _rearGearField.setData(rearGear < 0 ? 0 : rearGear);
        _frontGearField.setData(frontGear < 0 ? 0 : frontGear);
        _rearTeethField.setData(rearTeeth);
        _frontTeethField.setData(frontTeeth);
        _ratioField.setData(ratio);
        _batteryField.setData(battery < 0 ? 0 : battery);

        // накопление статистики
        _stats.sample(frontGear, rearGear, frontTeeth, rearTeeth, ratio);

        // session: значение, которое будет записано при завершении заезда
        if (rearGear > _maxRear) { _maxRear = rearGear; _maxRearField.setData(_maxRear); }
        if (battery > 0 && battery < _minBattery) { _minBattery = battery; _minBatteryField.setData(_minBattery); }
        _maxRatioField.setData(_stats.maxRatio());
        _avgRatioField.setData(_stats.avgRatio());
        _frontShiftsField.setData(_stats.frontShifts());
        _rearShiftsField.setData(_stats.rearShifts());
        _mostComboTimeField.setData(_stats.mostComboPct());
        _leastComboTimeField.setData(_stats.leastComboPct());
        _rearTop1Field.setData(_stats.rearTop(1));
        _rearTop2Field.setData(_stats.rearTop(2));
        _rearTop3Field.setData(_stats.rearTop(3));

        var mc = _stats.mostCombo();
        _mostComboField.setData(mc.length() > 0 ? mc : "-");
        var lc = _stats.leastCombo();
        _leastComboField.setData(lc.length() > 0 ? lc : "-");
    }
}
