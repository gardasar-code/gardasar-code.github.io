using Toybox.Lang;

// Пресеты трансмиссии и разбор пользовательского ввода зубьев.
//
// Вынесено из Di2FieldApp: это чистая логика над строками и таблицами, без Storage,
// BLE и графики — её можно и нужно проверять тестами (source/Di2Tests.mc). Чтение
// самих настроек (Application.Properties) осталось в Di2FieldApp: там оно и уместно,
// а сюда приходят уже готовые значения.
module Di2Settings {

    // Таблицы пресетов зубьев (популярные конфигурации Shimano). Индекс = значение
    // селектора в settings.xml; индекс 0 = Custom (ручной ввод). Раскладки кассет
    // сверены по ki2 (doc/ki2 RearTeethPattern). Зубья — от меньшей звезды к большей.
    const FRONT_PRESETS as Lang.Array<Lang.String> = [
        "",            // 0 — Custom
        "50,34",       // 1 — Compact
        "52,36",       // 2 — Semi-compact
        "53,39",       // 3 — Standard
        "54,40",       // 4
        "48,31",       // 5 — GRX
        "46,30",       // 6 — GRX
        "38,28",       // 7 — MTB 2x
        "40,30,22"     // 8 — 3x
    ];
    const REAR_PRESETS as Lang.Array<Lang.String> = [
        "",                                       // 0 — Custom
        "10,12,14,16,18,21,24,28,33,39,45,51",    // 1 — 12sp 10-51
        "11,12,13,14,15,17,19,21,24,27,30,34",    // 2 — 12sp 11-34
        "11,12,13,14,15,16,17,19,21,24,27,30",    // 3 — 12sp 11-30
        "11,12,13,14,15,17,19,21,24,28,32,36",    // 4 — 12sp 11-36
        "11,12,13,14,15,16,17,18,19,21,24,28",    // 5 — 12sp 11-28
        "11,13,15,17,19,21,23,25,27,30,34",       // 6 — 11sp 11-34
        "11,12,13,14,16,18,20,22,25,28,32",       // 7 — 11sp 11-32
        "11,13,15,17,19,21,24,28,32,37,46",       // 8 — 11sp 11-46
        "11,12,13,14,15,17,19,21,23,25,28",       // 9 — 11sp 11-28
        "11,13,15,17,19,21,24,27,31,35,40",       // 10 — 11sp 11-40
        "11,13,15,17,20,23,26,30,36,43",          // 11 — 10sp 11-43
        "11,13,15,17,20,23,28,34,41,48"           // 12 — 10sp 11-48
    ];

    // Строка зубьев для выбранного пресета или null (Custom/вне диапазона → ручной ввод).
    function presetTeeth(table as Lang.Array<Lang.String>, idx as Lang.Number) as Lang.String? {
        if (idx <= 0 || idx >= table.size()) {
            return null;
        }
        var s = table[idx];
        return (s.length() > 0) ? s : null;
    }

    // Распарсить строку зубьев в список чисел (общая логика для ручного ввода и пресетов).
    // Любой нецифровой символ — разделитель, поэтому "50,34", "50/34" и "50 34" равнозначны.
    // Пустой/битый ввод → дефолт: поле должно работать даже при мусоре в настройках.
    function parseTeeth(s as Lang.String, dflt as Lang.Array<Lang.Number>) as Lang.Array<Lang.Number> {
        var out = [] as Lang.Array<Lang.Number>;
        var cur = "";
        var digits = "0123456789";
        var chars = s.toCharArray();
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

    // Разрешить зубья + число звёзд. Выбранный пресет ПЕРЕОПРЕДЕЛЯЕТ ручной ввод:
    // записать значения обратно в поля настроек телефона из кода нельзя (ограничение
    // Connect IQ), поэтому пресет действует в рантайме. Возвращает [teeth, total].
    //   presetIdx    — индекс пресета (0 = Custom);
    //   manualTeeth  — строка ручного ввода (null, если свойство не строка);
    //   manualCount  — число звёзд из селектора;
    //   defaultTeeth — зубья по умолчанию, если и пресет, и ручной ввод непригодны.
    function resolveTeeth(table as Lang.Array<Lang.String>, presetIdx as Lang.Number,
                          manualTeeth as Lang.String?, manualCount as Lang.Number,
                          defaultTeeth as Lang.Array<Lang.Number>) as Lang.Array {
        var preset = presetTeeth(table, presetIdx);
        if (preset != null) {
            var teeth = parseTeeth(preset, defaultTeeth);
            return [teeth, teeth.size()];
        }
        var manual = (manualTeeth != null)
            ? parseTeeth(manualTeeth as Lang.String, defaultTeeth)
            : defaultTeeth;
        return [manual, manualCount];
    }
}
