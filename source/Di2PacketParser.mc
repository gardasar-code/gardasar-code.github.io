using Toybox.Lang;

// Разбор notify-пакета Di2 и выбор раскладки по модели переключателя.
//
// Вынесено из Di2BleDelegate намеренно: это единственная часть проекта, которую можно
// проверить без BLE-стека и без устройства — а меняется она чаще всего (каждая новая
// серия Di2 приходит сюда). Тесты на неё — source/Di2Tests.mc.
//
// Результат разбора кладётся в ПОЛЯ объекта, а не возвращается словарём: parse()
// зовётся на каждый notify (десятки раз в секунду), и аллокация результата в этом
// пути была бы заметна на устройстве с жёстким лимитом памяти.
class Di2PacketParser {

    // ── Профили серий Di2: раскладка пакета 0x2ac1 по GATT-имени ──────────────
    // Новая серия добавляется ОДНОЙ строкой — логика разбора не меняется.
    //   :prefix — префикс GATT-имени модели (как приходит по getName());
    //   :label  — человекочитаемая метка (diag-оверлей и краудсорс моделей);
    //   :len    — длина пакета передач (байт);
    //   :rear   — индекс байта текущей ЗАДНЕЙ передачи;
    //   :front  — индекс байта текущей ПЕРЕДНЕЙ передачи (-1 = не выявлен);
    //   :cogs   — индекс байта ЧИСЛА задних звёзд (-1 = не выявлен).
    //
    // ПОДТВЕРЖДЕНО на железе: XT M8250 (len 17, rear=5, cogs=6; front не выявлен —
    // тест 1x). Дорожные/гравийные серии — ГИПОТЕЗА: тот же шлюз D-Fly (EW-WU) вещает
    // тот же канал. Подтверждение — по фото diag-оверлея. См. doc/NOTES.md.
    static const PROFILES = [
        { :prefix => "RDM8250", :label => "XT Di2 M8250",   :len => 17, :rear => 5, :front => -1, :cogs => 6 },
        // ── ниже: гипотеза, требует подтверждения по фото оверлея ──
        { :prefix => "RDM9250", :label => "XTR Di2 M9250",  :len => 17, :rear => 5, :front => -1, :cogs => 6 },
        { :prefix => "RDR9250", :label => "DURA-ACE R9250", :len => 17, :rear => 5, :front => -1, :cogs => 6 },
        { :prefix => "RDR8150", :label => "Ultegra R8150",  :len => 17, :rear => 5, :front => -1, :cogs => 6 },
        { :prefix => "RDR7150", :label => "105 R7150",      :len => 17, :rear => 5, :front => -1, :cogs => 6 },
        { :prefix => "RDRX825", :label => "GRX RX825",      :len => 17, :rear => 5, :front => -1, :cogs => 6 }
    ] as Lang.Array<Lang.Dictionary>;

    // Дефолт (XT M8250) — пока имя неизвестно или не совпало ни с одним префиксом.
    static const DEFAULT_PKT_LEN   = 17;
    static const DEFAULT_REAR_IDX  = 5;
    static const DEFAULT_FRONT_IDX = -1;
    static const DEFAULT_COGS_IDX  = 6;

    // Границы санитарной проверки. Данные приходят по воздуху от чужого устройства:
    // мусорный или чужой по формату пакет не должен попадать ни на экран, ни в FIT.
    static const MAX_REAR_COGS    = 31;   // предел ANT+/Di2 для задних звёзд
    static const MAX_FRONT_RINGS  = 3;    // 1x/2x/3x

    // Активная раскладка (из выбранного профиля).
    public var pktLen as Lang.Number = DEFAULT_PKT_LEN;
    public var rearIdx as Lang.Number = DEFAULT_REAR_IDX;
    public var frontIdx as Lang.Number = DEFAULT_FRONT_IDX;
    public var cogsIdx as Lang.Number = DEFAULT_COGS_IDX;

    // Метка распознанной модели: "" — имени ещё нет, "?" — имя есть, но незнакомое.
    public var label as Lang.String = "";

    // Результат последнего успешного parse(); -1 = значение не извлекалось.
    public var rear as Lang.Number = -1;
    public var front as Lang.Number = -1;
    public var rearTotal as Lang.Number = -1;

    function initialize() {
    }

    // Выбрать раскладку по GATT-имени: первый профиль, чей :prefix совпал с началом
    // имени. Имя null/без совпадения → дефолт (самая вероятная раскладка), а сырой
    // пакет всё равно виден в diag-оверлее.
    function selectProfile(name as Lang.String?) as Void {
        pktLen   = DEFAULT_PKT_LEN;
        rearIdx  = DEFAULT_REAR_IDX;
        frontIdx = DEFAULT_FRONT_IDX;
        cogsIdx  = DEFAULT_COGS_IDX;

        var p = matchProfile(name);
        if (p != null) {
            pktLen   = p[:len] as Lang.Number;
            rearIdx  = p[:rear] as Lang.Number;
            frontIdx = p[:front] as Lang.Number;
            cogsIdx  = (p[:cogs] != null) ? (p[:cogs] as Lang.Number) : DEFAULT_COGS_IDX;
            label    = p[:label] as Lang.String;
        } else {
            label = (name != null && name.length() > 0) ? "?" : "";
        }
    }

    // Найти профиль по префиксу GATT-имени (name.find(prefix)==0 → имя начинается с него).
    function matchProfile(name as Lang.String?) as Lang.Dictionary? {
        if (name == null || name.length() == 0) {
            return null;
        }
        for (var i = 0; i < PROFILES.size(); i++) {
            var p = PROFILES[i] as Lang.Dictionary;
            if (name.find(p[:prefix] as Lang.String) == 0) {
                return p;
            }
        }
        return null;
    }

    // Разобрать пакет. knownRearTotal/knownFrontTotal — число звёзд из настроек
    // (<=0, если неизвестно): по ним проверяется правдоподобность индекса передачи.
    // Возвращает true, если из пакета извлечено хоть одно валидное значение; поля
    // rear/front/rearTotal при этом содержат результат (-1 = не извлекалось).
    function parse(value as Lang.ByteArray,
                   knownRearTotal as Lang.Number,
                   knownFrontTotal as Lang.Number) as Lang.Boolean {
        rear = -1;
        front = -1;
        rearTotal = -1;

        if (value.size() != pktLen) {
            return false;   // чужая длина — это служебный пакет или другая серия
        }

        // Число задних звёзд из пакета (байт 6 на подтверждённых сериях). Железо
        // авторитетнее настроек: пользователь может ошибиться в конфигурации, а
        // переключатель знает свою кассету.
        var totalForCheck = knownRearTotal;
        if (cogsIdx >= 0 && cogsIdx < value.size()) {
            var cogs = value[cogsIdx].toNumber();
            if (cogs >= 1 && cogs <= MAX_REAR_COGS) {
                rearTotal = cogs;
                totalForCheck = cogs;
            }
        }

        // Задняя передача. Вне диапазона — пакет не наш: не отдаём НИЧЕГО, включая
        // уже посчитанное число звёзд, иначе мусорный пакет переписал бы конфигурацию.
        if (rearIdx >= 0 && rearIdx < value.size()) {
            var r = value[rearIdx].toNumber();
            if (!validGear(r, totalForCheck, MAX_REAR_COGS)) {
                rearTotal = -1;
                return false;
            }
            rear = r;
        }

        // Передняя передача: только если профиль выявил её байт (frontIdx >= 0).
        // Иначе front остаётся из настроек (1x → 1; 2x/3x → "-/N", см. Di2Settings).
        if (frontIdx >= 0 && frontIdx < value.size()) {
            var f = value[frontIdx].toNumber();
            if (validGear(f, knownFrontTotal, MAX_FRONT_RINGS)) {
                front = f;
            }
        }

        return (rear > 0) || (front > 0) || (rearTotal > 0);
    }

    // Индекс передачи правдоподобен: 1..total (если число звёзд известно) либо
    // 1..hardMax (пока неизвестно — например до первого валидного байта числа звёзд).
    function validGear(v as Lang.Number, total as Lang.Number, hardMax as Lang.Number) as Lang.Boolean {
        if (v < 1) {
            return false;
        }
        return (total > 0) ? (v <= total) : (v <= hardMax);
    }
}
