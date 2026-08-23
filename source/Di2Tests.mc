using Toybox.Lang;
using Toybox.Test;

// Юнит-тесты чистой логики: разбор notify-пакета, выбор профиля серии Di2 и
// пользовательские настройки трансмиссии.
//
// Запуск (нужен симулятор):
//   monkeyc --unit-test -d edgeexplore2 -f monkey.jungle -o bin/Di2App-test.prg -y <key>
//   monkeydo bin/Di2App-test.prg edgeexplore2 -t
//
// Функции с аннотацией (:test) в обычную сборку не попадают, поэтому файл не
// утяжеляет релиз. Здесь НЕ тестируются BLE, FIT и рисование: первое требует стека
// устройства, второе — DataField, третье — Dc. Тестируем то, что ломалось на практике:
// границы значений, приходящих по воздуху, и разбор пользовательского ввода.

// ── Di2PacketParser: выбор профиля ────────────────────────────────────────────

(:test)
function testProfileMatchByPrefix(logger as Test.Logger) as Lang.Boolean {
    var p = new Di2PacketParser();
    p.selectProfile("RDM8250S2A8");
    Test.assertEqual(p.label, "XT Di2 M8250");
    Test.assertEqual(p.rearIdx, 5);
    Test.assertEqual(p.cogsIdx, 6);
    Test.assertEqual(p.pktLen, 17);
    return true;
}

(:test)
function testProfileUnknownNameFallsBackToDefault(logger as Test.Logger) as Lang.Boolean {
    var p = new Di2PacketParser();
    p.selectProfile("SOMETHING-ELSE");
    // Имя есть, но незнакомое: метка "?" и дефолтная (самая вероятная) раскладка.
    Test.assertEqual(p.label, "?");
    Test.assertEqual(p.rearIdx, Di2PacketParser.DEFAULT_REAR_IDX);
    return true;
}

(:test)
function testProfileNullNameHasNoLabel(logger as Test.Logger) as Lang.Boolean {
    var p = new Di2PacketParser();
    p.selectProfile(null);
    // Имя ещё не пришло (GATT-дискавери не завершилась) — метки нет, но парсить можем.
    Test.assertEqual(p.label, "");
    Test.assertEqual(p.pktLen, Di2PacketParser.DEFAULT_PKT_LEN);
    return true;
}

// ── Di2PacketParser: разбор пакета ────────────────────────────────────────────

// Реальный пакет XT M8250 (doc/NOTES.md): байт 5 = передача, байт 6 = число звёзд.
function samplePacket(gear as Lang.Number, cogs as Lang.Number) as Lang.ByteArray {
    return [0x00, 0x00, 0x03, 0xFF, 0xFF, gear, cogs,
            0x80, 0x80, 0x80, 0xFF, 0xEE, 0x12, 0xFF, 0xFF, 0x15, 0x00]b;
}

(:test)
function testParseRealPacket(logger as Test.Logger) as Lang.Boolean {
    var p = new Di2PacketParser();
    p.selectProfile("RDM8250S2A8");
    Test.assert(p.parse(samplePacket(7, 12), 12, 1));
    Test.assertEqual(p.rear, 7);
    Test.assertEqual(p.rearTotal, 12);
    return true;
}

(:test)
function testParseRejectsWrongLength(logger as Test.Logger) as Lang.Boolean {
    var p = new Di2PacketParser();
    p.selectProfile("RDM8250S2A8");
    // Служебные пакеты D-Fly (3 и 6 байт) идут вперемешку с пакетом передач.
    Test.assert(!p.parse([0x04, 0xFF, 0xFF]b, 12, 1));
    Test.assert(!p.parse([0x06, 0x42, 0x00, 0x00, 0x00, 0x03]b, 12, 1));
    Test.assertEqual(p.rear, -1);
    return true;
}

(:test)
function testParseRejectsGearOutOfRange(logger as Test.Logger) as Lang.Boolean {
    var p = new Di2PacketParser();
    p.selectProfile("RDM8250S2A8");
    // 0xFF в байте передачи — мусор либо чужая раскладка: не показываем "255/12".
    Test.assert(!p.parse(samplePacket(0xFF, 12), 12, 1));
    Test.assertEqual(p.rear, -1);
    // Передача 0 тоже невалидна (нумерация с 1).
    Test.assert(!p.parse(samplePacket(0, 12), 12, 1));
    Test.assertEqual(p.rear, -1);
    return true;
}

(:test)
function testParseRejectsGearAboveCogCount(logger as Test.Logger) as Lang.Boolean {
    var p = new Di2PacketParser();
    p.selectProfile("RDM8250S2A8");
    // 13-я передача на 12-скоростной кассете невозможна.
    Test.assert(!p.parse(samplePacket(13, 12), 12, 1));
    Test.assertEqual(p.rear, -1);
    // ...и число звёзд из того же пакета применяться не должно.
    Test.assertEqual(p.rearTotal, -1);
    return true;
}

(:test)
function testParseTakesCogCountFromHardware(logger as Test.Logger) as Lang.Boolean {
    var p = new Di2PacketParser();
    p.selectProfile("RDM8250S2A8");
    // В настройках 12 звёзд, а железо сообщает 11 — верим железу.
    Test.assert(p.parse(samplePacket(9, 11), 12, 1));
    Test.assertEqual(p.rearTotal, 11);
    Test.assertEqual(p.rear, 9);
    return true;
}

(:test)
function testParseIgnoresInvalidCogCount(logger as Test.Logger) as Lang.Boolean {
    var p = new Di2PacketParser();
    p.selectProfile("RDM8250S2A8");
    // Число звёзд вне 1..31 — не наш формат: остаётся значение из настроек.
    Test.assert(p.parse(samplePacket(5, 0xFF), 12, 1));
    Test.assertEqual(p.rearTotal, -1);
    Test.assertEqual(p.rear, 5);
    return true;
}

(:test)
function testParseSkipsFrontWhenProfileHasNoByte(logger as Test.Logger) as Lang.Boolean {
    var p = new Di2PacketParser();
    p.selectProfile("RDM8250S2A8");
    Test.assert(p.parse(samplePacket(4, 12), 12, 2));
    // Байт передней звезды на этой серии не выявлен (:front => -1) — не выдумываем.
    Test.assertEqual(p.front, -1);
    return true;
}

(:test)
function testValidGearBounds(logger as Test.Logger) as Lang.Boolean {
    var p = new Di2PacketParser();
    // Число звёзд известно → верхняя граница по нему.
    Test.assert(p.validGear(12, 12, 31));
    Test.assert(!p.validGear(13, 12, 31));
    // Неизвестно (<=0) → работает только жёсткий предел.
    Test.assert(p.validGear(20, -1, 31));
    Test.assert(!p.validGear(32, -1, 31));
    Test.assert(!p.validGear(0, -1, 31));
    return true;
}

// ── Di2Settings: разбор ввода ─────────────────────────────────────────────────

function teethEqual(actual as Lang.Array<Lang.Number>, expected as Lang.Array<Lang.Number>) as Lang.Boolean {
    if (actual.size() != expected.size()) {
        return false;
    }
    for (var i = 0; i < actual.size(); i++) {
        if (actual[i] != expected[i]) {
            return false;
        }
    }
    return true;
}

(:test)
function testParseTeethSeparators(logger as Test.Logger) as Lang.Boolean {
    var dflt = [11, 12]  as Lang.Array<Lang.Number>;
    var want = [50, 34] as Lang.Array<Lang.Number>;
    // Любой нецифровой символ — разделитель: пользователь пишет как привык.
    Test.assert(teethEqual(Di2Settings.parseTeeth("50,34", dflt), want));
    Test.assert(teethEqual(Di2Settings.parseTeeth("50/34", dflt), want));
    Test.assert(teethEqual(Di2Settings.parseTeeth("50 34", dflt), want));
    Test.assert(teethEqual(Di2Settings.parseTeeth(" 50 , 34 ", dflt), want));
    return true;
}

(:test)
function testParseTeethGarbageFallsBackToDefault(logger as Test.Logger) as Lang.Boolean {
    var dflt = [11, 12] as Lang.Array<Lang.Number>;
    // Пустой и полностью нецифровой ввод не должен оставлять поле без конфигурации.
    Test.assert(teethEqual(Di2Settings.parseTeeth("", dflt), dflt));
    Test.assert(teethEqual(Di2Settings.parseTeeth("abc", dflt), dflt));
    Test.assert(teethEqual(Di2Settings.parseTeeth(",,,", dflt), dflt));
    return true;
}

(:test)
function testPresetOverridesManualInput(logger as Test.Logger) as Lang.Boolean {
    var dflt = [32] as Lang.Array<Lang.Number>;
    // Пресет 1 = Compact 50/34; ручной ввод и счётчик звёзд игнорируются.
    var r = Di2Settings.resolveTeeth(Di2Settings.FRONT_PRESETS, 1, "38,28", 3, dflt);
    Test.assert(teethEqual(r[0] as Lang.Array<Lang.Number>, [50, 34] as Lang.Array<Lang.Number>));
    Test.assertEqual(r[1] as Lang.Number, 2);   // число звёзд — из пресета, не из селектора
    return true;
}

(:test)
function testCustomPresetUsesManualInput(logger as Test.Logger) as Lang.Boolean {
    var dflt = [32] as Lang.Array<Lang.Number>;
    // Пресет 0 = Custom → работает ручной ввод и селектор числа звёзд.
    var r = Di2Settings.resolveTeeth(Di2Settings.FRONT_PRESETS, 0, "38,28", 2, dflt);
    Test.assert(teethEqual(r[0] as Lang.Array<Lang.Number>, [38, 28] as Lang.Array<Lang.Number>));
    Test.assertEqual(r[1] as Lang.Number, 2);
    return true;
}

(:test)
function testMissingManualInputFallsBackToDefault(logger as Test.Logger) as Lang.Boolean {
    var dflt = [11, 13, 15] as Lang.Array<Lang.Number>;
    // Свойство не строка (не заполнено) → дефолтные зубья, счётчик из селектора.
    var r = Di2Settings.resolveTeeth(Di2Settings.REAR_PRESETS, 0, null, 11, dflt);
    Test.assert(teethEqual(r[0] as Lang.Array<Lang.Number>, dflt));
    Test.assertEqual(r[1] as Lang.Number, 11);
    return true;
}

(:test)
function testPresetIndexOutOfRangeIsCustom(logger as Test.Logger) as Lang.Boolean {
    var dflt = [32] as Lang.Array<Lang.Number>;
    // Индекс вне таблицы (рассинхрон settings.xml и кода) не должен ронять загрузку.
    // assertEqual не работает с null — сравниваем явно.
    Test.assert(Di2Settings.presetTeeth(Di2Settings.FRONT_PRESETS, 99) == null);
    var r = Di2Settings.resolveTeeth(Di2Settings.FRONT_PRESETS, 99, "46,30", 2, dflt);
    Test.assert(teethEqual(r[0] as Lang.Array<Lang.Number>, [46, 30] as Lang.Array<Lang.Number>));
    return true;
}

(:test)
function testRearPresetsAreConsistent(logger as Test.Logger) as Lang.Boolean {
    var dflt = [11] as Lang.Array<Lang.Number>;
    // Каждая раскладка кассеты должна разбираться и идти по возрастанию зубьев:
    // на этом строится профиль высот столбиков в графике кассеты.
    for (var i = 1; i < Di2Settings.REAR_PRESETS.size(); i++) {
        var teeth = Di2Settings.parseTeeth(Di2Settings.REAR_PRESETS[i], dflt);
        Test.assert(teeth.size() >= 10);
        for (var j = 1; j < teeth.size(); j++) {
            Test.assert(teeth[j] > teeth[j - 1]);
        }
    }
    return true;
}

(:test)
function testFrontPresetsAreConsistent(logger as Test.Logger) as Lang.Boolean {
    var dflt = [32] as Lang.Array<Lang.Number>;
    // Передние звёзды в таблице записаны от большей к меньшей (50,34).
    for (var i = 1; i < Di2Settings.FRONT_PRESETS.size(); i++) {
        var teeth = Di2Settings.parseTeeth(Di2Settings.FRONT_PRESETS[i], dflt);
        Test.assert(teeth.size() >= 2);
        for (var j = 1; j < teeth.size(); j++) {
            Test.assert(teeth[j] < teeth[j - 1]);
        }
    }
    return true;
}

// ── Di2State: производные значения ────────────────────────────────────────────

(:test)
function testGearRatioAndTeethBounds(logger as Test.Logger) as Lang.Boolean {
    var s = new Di2State();
    s.frontTeeth = [50, 34] as Lang.Array<Lang.Number>;
    s.rearTeeth = [11, 12, 14] as Lang.Array<Lang.Number>;

    s.front = 1;
    s.rear = 1;
    Test.assertEqual(s.currentFrontTeeth(), 50);
    Test.assertEqual(s.currentRearTeeth(), 11);
    Test.assert(s.gearRatio() > 4.5);

    // Индекс вне списка зубьев (настройки не совпали с железом) → 0 и ratio 0.0.
    s.rear = 99;
    Test.assertEqual(s.currentRearTeeth(), 0);
    Test.assertEqual(s.gearRatio(), 0.0);

    // «Нет данных» (-1) тоже не должно считаться передачей.
    s.rear = -1;
    Test.assertEqual(s.currentRearTeeth(), 0);
    return true;
}

(:test)
function testRecordPacketKeepsOnePerLength(logger as Test.Logger) as Lang.Boolean {
    var s = new Di2State();
    s.recordPacket(3, "04 FF FF");
    s.recordPacket(17, "AA");
    s.recordPacket(17, "BB");        // тот же вид — обновляем, а не добавляем
    Test.assertEqual(s.dbgPktLen.size(), 2);
    // Порядок — по убыванию длины: самый информативный пакет рисуется первым.
    Test.assertEqual(s.dbgPktLen[0], 17);
    Test.assertEqual(s.dbgPktHex[0], "BB");
    Test.assertEqual(s.dbgPktLen[1], 3);
    return true;
}

(:test)
function testRecordPacketDropsShortestOverLimit(logger as Test.Logger) as Lang.Boolean {
    var s = new Di2State();
    s.recordPacket(2, "a");
    s.recordPacket(3, "b");
    s.recordPacket(6, "c");
    s.recordPacket(17, "d");
    s.recordPacket(20, "e");   // сверх лимита — отбрасывается самый короткий
    Test.assertEqual(s.dbgPktLen.size(), s.DBG_MAX_KINDS);
    Test.assertEqual(s.dbgPktLen[0], 20);
    Test.assert(s.dbgPktLen[s.dbgPktLen.size() - 1] > 2);
    return true;
}

// ── Di2RideStats: счётчики переключений ───────────────────────────────────────

(:test)
function testShiftCountersIgnoreSignalLoss(logger as Test.Logger) as Lang.Boolean {
    var st = new Di2RideStats();
    st.sample(1, 5, 3.0);
    st.sample(1, 6, 3.0);      // одно переключение назад
    st.sample(1, -1, 0.0);     // потеря связи — не переключение
    st.sample(1, 9, 3.0);      // после восстановления тоже не считаем
    Test.assertEqual(st.rearShifts(), 1);
    Test.assertEqual(st.frontShifts(), 0);
    return true;
}

(:test)
function testMaxRatioTracksPeak(logger as Test.Logger) as Lang.Boolean {
    var st = new Di2RideStats();
    st.sample(2, 1, 4.5);
    st.sample(2, 5, 2.1);
    Test.assert(st.maxRatio() > 4.4 && st.maxRatio() < 4.6);
    return true;
}

// ── Di2DiagScreen: утилиты hex-дампа ──────────────────────────────────────────

(:test)
function testDiagTokensAndJoin(logger as Test.Logger) as Lang.Boolean {
    var d = new Di2DiagScreen(null);
    var t = d.toTokens("00 11 22 33 ");
    Test.assertEqual(t.size(), 4);
    Test.assertEqual(t[0], "00");
    Test.assertEqual(t[3], "33");
    // Срез строки дампа: [from, to) с защитой от выхода за границу.
    Test.assertEqual(d.joinRange(t, 0, 2), "00 11 ");
    Test.assertEqual(d.joinRange(t, 2, 99), "22 33 ");
    Test.assertEqual(d.joinRange(t, 4, 8), "");
    return true;
}

(:test)
function testDiagTokensHandleEmptyAndDoubleSpaces(logger as Test.Logger) as Lang.Boolean {
    var d = new Di2DiagScreen(null);
    Test.assertEqual(d.toTokens("").size(), 0);
    Test.assertEqual(d.toTokens("  ").size(), 0);
    Test.assertEqual(d.toTokens("AA  BB").size(), 2);
    return true;
}

(:test)
function testDiagNumOrDash(logger as Test.Logger) as Lang.Boolean {
    var d = new Di2DiagScreen(null);
    // -1 в состоянии означает «нет данных» — на экране это прочерк, а не число.
    Test.assertEqual(d.numOrDash(-1), "-");
    Test.assertEqual(d.numOrDash(0), "0");
    Test.assertEqual(d.numOrDash(12), "12");
    return true;
}

(:test)
function testDiagPktAgeWithoutPackets(logger as Test.Logger) as Lang.Boolean {
    var st = new Di2State();
    var d = new Di2DiagScreen(st);
    // Пакетов ещё не было (dbgLastPktMs == 0) — возраст неизвестен, а не «0 секунд».
    Test.assertEqual(d.pktAge(st), "--");
    return true;
}
