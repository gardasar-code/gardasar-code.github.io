using Toybox.FitContributor as Fit;
using Toybox.WatchUi;
using Toybox.Lang;

// Запись данных Di2 в FIT (секция Connect IQ в Garmin Connect).
//   record (посекундно): передача по индексу (зад/перёд), зубья (зад/перёд),
//                        передаточное отношение, заряд D-Fly;
//   session (сводка):    макс/средн. ratio, мин. заряд, число переключений
//                        (перёд/зад), самая используемая комбинация + доля времени,
//                        топ-3 задних звёзд, макс. задняя.
//
// ВАЖНО: на data field лимит не только в байтах (32 на сообщение), но и в ЧИСЛЕ
// полей. На Edge Explore 2 (прошивка 31.33) createField падает системной ошибкой
// ровно на 12-м поле — раньше то же место давало "New Field out of memory"
// (doc/CIQ_LOG.BAK). Поэтому полей СТРОГО не больше 11: 6 record + 5 session,
// а самая объёмная статистика (комбинация передач, топ-3 звёзд, средний ratio)
// в FIT не пишется — она есть на экране. Не добавлять поля, не убрав другие!
// Само создание обёрнуто в try: на устройстве с ещё более жёстким лимитом поле
// продолжит работать без FIT-записи, а не свалится с жёлтым значком.
class Di2FitContributor {

    private const F_REAR_GEAR       = 0;
    private const F_FRONT_GEAR      = 1;
    private const F_REAR_TEETH      = 2;
    private const F_FRONT_TEETH     = 3;
    private const F_RATIO           = 4;
    private const F_BATTERY         = 5;
    private const F_MAX_REAR        = 6;
    private const F_MAX_RATIO       = 7;
    private const F_MIN_BATTERY     = 8;
    private const F_FRONT_SHIFTS    = 10;
    private const F_REAR_SHIFTS     = 11;

    private const UNIT_GEAR  = "gear";
    private const UNIT_TEETH = "T";

    private var _stats as Di2RideStats;

    // record (9 байт: 1+1+1+1+4+1)
    private var _rearGearField;
    private var _frontGearField;
    private var _rearTeethField;
    private var _frontTeethField;
    private var _ratioField;
    private var _batteryField;
    // session (10 байт: 1+4+1+2+2). Флаги ниже говорят, созданы ли группы полей.
    private var _maxRearField;
    private var _maxRatioField;
    private var _minBatteryField;
    private var _frontShiftsField;
    private var _rearShiftsField;

    private var _maxRear as Lang.Number = 0;
    private var _minBattery as Lang.Number = 101;

    // Созданы ли группы полей. false → соответствующая часть update() пропускается:
    // без этого setData на несозданном поле уронил бы дата-филд.
    private var _recOk as Lang.Boolean = false;
    private var _sesOk as Lang.Boolean = false;

    function initialize(view as WatchUi.DataField) {
        _stats = new Di2RideStats();

        var pct   = WatchUi.loadResource(Rez.Strings.FieldBatteryUnit);
        var ratio = WatchUi.loadResource(Rez.Strings.FieldRatioUnit);
        var shift = WatchUi.loadResource(Rez.Strings.FieldShiftUnit);

        var REC = Fit.MESG_TYPE_RECORD;
        var SES = Fit.MESG_TYPE_SESSION;

        // ── record ── (создаём в try: лимит полей у прошивок разный)
        try {
        _rearGearField  = view.createField(WatchUi.loadResource(Rez.Strings.FieldRearGear),   F_REAR_GEAR,   Fit.DATA_TYPE_UINT8, {:mesgType => REC, :units => UNIT_GEAR});
        _frontGearField = view.createField(WatchUi.loadResource(Rez.Strings.FieldFrontGear),  F_FRONT_GEAR,  Fit.DATA_TYPE_UINT8, {:mesgType => REC, :units => UNIT_GEAR});
        _rearTeethField = view.createField(WatchUi.loadResource(Rez.Strings.FieldRearTeeth),  F_REAR_TEETH,  Fit.DATA_TYPE_UINT8, {:mesgType => REC, :units => UNIT_TEETH});
        _frontTeethField= view.createField(WatchUi.loadResource(Rez.Strings.FieldFrontTeeth), F_FRONT_TEETH, Fit.DATA_TYPE_UINT8, {:mesgType => REC, :units => UNIT_TEETH});
        _ratioField     = view.createField(WatchUi.loadResource(Rez.Strings.FieldRatio),      F_RATIO,       Fit.DATA_TYPE_FLOAT, {:mesgType => REC, :units => ratio});
        _batteryField   = view.createField(WatchUi.loadResource(Rez.Strings.FieldBattery),    F_BATTERY,     Fit.DATA_TYPE_UINT8, {:mesgType => REC, :units => pct});

            _recOk = true;
        } catch (e) {
            _recOk = false;   // FIT-запись недоступна — поле работает без неё
        }

        // ── session ──
        try {
        _maxRearField       = view.createField(WatchUi.loadResource(Rez.Strings.FieldMaxRearGear),   F_MAX_REAR,        Fit.DATA_TYPE_UINT8,  {:mesgType => SES, :units => UNIT_GEAR});
        _maxRatioField      = view.createField(WatchUi.loadResource(Rez.Strings.FieldMaxRatio),      F_MAX_RATIO,       Fit.DATA_TYPE_FLOAT,  {:mesgType => SES, :units => ratio});
        _minBatteryField    = view.createField(WatchUi.loadResource(Rez.Strings.FieldMinBattery),    F_MIN_BATTERY,     Fit.DATA_TYPE_UINT8,  {:mesgType => SES, :units => pct});
        _frontShiftsField   = view.createField(WatchUi.loadResource(Rez.Strings.FieldFrontShifts),   F_FRONT_SHIFTS,    Fit.DATA_TYPE_UINT16, {:mesgType => SES, :units => shift});
        _rearShiftsField    = view.createField(WatchUi.loadResource(Rez.Strings.FieldRearShifts),    F_REAR_SHIFTS,     Fit.DATA_TYPE_UINT16, {:mesgType => SES, :units => shift});
            _sesOk = true;
        } catch (e) {
            _sesOk = false;   // сводки не будет, посекундная запись при этом жива
        }

        // Начальные значения — только для созданных групп.
        if (_recOk) {
            _rearGearField.setData(0); _frontGearField.setData(0); _rearTeethField.setData(0);
            _frontTeethField.setData(0); _ratioField.setData(0.0); _batteryField.setData(0);
        }
        if (_sesOk) {
            _maxRearField.setData(0); _maxRatioField.setData(0.0); _minBatteryField.setData(100);
            _frontShiftsField.setData(0); _rearShiftsField.setData(0);
        }
    }

    function update(rearGear as Lang.Number, frontGear as Lang.Number,
                    rearTeeth as Lang.Number, frontTeeth as Lang.Number,
                    ratio as Lang.Float, battery as Lang.Number) as Void {
        // record
        if (_recOk) {
            _rearGearField.setData(rearGear < 0 ? 0 : rearGear);
            _frontGearField.setData(frontGear < 0 ? 0 : frontGear);
            _rearTeethField.setData(rearTeeth);
            _frontTeethField.setData(frontTeeth);
            _ratioField.setData(ratio);
            _batteryField.setData(battery < 0 ? 0 : battery);
        }

        // накопление статистики (нужно и для экрана, поэтому вне флагов FIT)
        _stats.sample(frontGear, rearGear, frontTeeth, rearTeeth, ratio);

        // session
        if (_sesOk) {
            if (rearGear > _maxRear) { _maxRear = rearGear; _maxRearField.setData(_maxRear); }
            if (battery > 0 && battery < _minBattery) { _minBattery = battery; _minBatteryField.setData(_minBattery); }
            _maxRatioField.setData(_stats.maxRatio());
            _frontShiftsField.setData(_stats.frontShifts());
            _rearShiftsField.setData(_stats.rearShifts());
        }
    }
}
