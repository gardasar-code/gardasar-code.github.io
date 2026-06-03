using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Application;

// Рендеринг Data Field (светлая тема). Макет:
//   [Di2] •      F:{front}/{frontTotal}      {bat}%      ← FONT_XTINY
//                    {rear}/{rearTotal}                  ← крупнейший шрифт
// Нет данных -> "---". Точка подключения: зелёная (connected) / серая (нет).
class Di2FieldView extends WatchUi.DataField {

    // Калибровка: показывать сырые байты gear-пакета двумя строками снизу.
    // true только для настройки смещений (напр. поиск байта передней для 2x).
    private const DEBUG_OVERLAY = false;

    private var _state as Di2State?;
    private var _delegate as Di2BleDelegate?;   // null, если BLE отключён
    private var _fit as Di2FitContributor?;     // запись в FIT-файл активности

    // DEBUG (симулятор): монотонный счётчик тиков для демо-цикла состояний.
    (:debug) private var _demoTick as Lang.Number = 0;

    // Кэш строк из ресурсов (грузим один раз, с учётом языка устройства).
    private var _lblDi2 as Lang.String = "Di2";
    private var _noData as Lang.String = "---";
    private var _lblFront as Lang.String = "F:";
    private var _statSearching as Lang.String = "Searching";
    private var _statConnecting as Lang.String = "Connecting";
    private var _statHint as Lang.String = "Wake the Di2";
    private var _statHintPair as Lang.String = "Hold Di2 button";

    // Через столько секунд непрерывного скана меняем подсказку на «нажми паринг»
    // (D-Fly после глубокого сна не вещает — щелчки его не будят, см. doc/NOTES.md).
    private const SCAN_HINT_PAIR_SECS = 60;

    function initialize(state as Di2State?, delegate as Di2BleDelegate?) {
        DataField.initialize();
        _state = state;
        _delegate = delegate;
        _lblDi2 = WatchUi.loadResource(Rez.Strings.LabelDi2) as Lang.String;
        _noData = WatchUi.loadResource(Rez.Strings.LabelNoData) as Lang.String;
        _lblFront = WatchUi.loadResource(Rez.Strings.LabelFront) as Lang.String;
        _statSearching = WatchUi.loadResource(Rez.Strings.StatusSearching) as Lang.String;
        _statConnecting = WatchUi.loadResource(Rez.Strings.StatusConnecting) as Lang.String;
        _statHint = WatchUi.loadResource(Rez.Strings.StatusHint) as Lang.String;
        _statHintPair = WatchUi.loadResource(Rez.Strings.StatusHintPair) as Lang.String;
        _fit = new Di2FitContributor(self);
    }

    // Data Field вызывает compute каждую секунду — это heartbeat дата-филда.
    // Toybox.Timer здесь недоступен, поэтому периодику BLE (реконнект, опрос
    // батареи) гоним отсюда через onTick(). Сами данные приходят асинхронно в
    // Di2State из BLE-колбэков; рисуем их в onUpdate.
    function compute(info as Toybox.Activity.Info) as Void {
        if (_delegate != null) {
            _delegate.onTick();
        }
        applyDebugData();
        // Запись в FIT: индекс передачи (зад/перёд) + зубья + передаточное + заряд.
        if (_fit != null && _state != null) {
            _fit.update(_state.rear, _state.front,
                        _state.currentRearTeeth(), _state.currentFrontTeeth(),
                        _state.gearRatio(), _state.battery);
        }
    }

    // DEBUG (симулятор): BLE в симуляторе нет и настройки/кнопки не подать, поэтому
    // прогоняем UI по всем состояниям автоматически — демо-цикл. Каждая сцена держится
    // DEMO_SCENE_TICKS секунд (compute ≈ 1 Гц), затем переключается на следующую.
    // anim крутим каждый тик, чтобы были видны пульсация точки и «бегущее» многоточие.
    //
    // Полный цикл сцен (0..5):
    //   0 Searching   — синяя пульсирующая точка, статус-экран поиска
    //   1 Connecting  — жёлтая точка, статус-экран подключения
    //   2 Live        — зелёная точка, передача 5/12, заряд 80 % (1-значная задняя)
    //   3 Live+lock   — тёмно-синяя точка, передача 11/12, заряд 15 % (2-значная, низкий заряд)
    //   4 Retry       — оранжевая точка, статус-экран поиска (привязка ещё активна)
    //   5 Live+lock   — тёмно-синяя точка, передача 12/12, заряд 50 % (макс. задняя)
    //
    // Зафиксировать ОДИН вид (для скриншота): «File → Edit Persistent Storage» в
    // симуляторе → ключ debugScene (число 0..5). Удали ключ — снова пойдёт цикл.
    (:debug) const DEMO_SCENE_TICKS = 5;

    (:debug)
    function applyDebugData() as Void {
        if (_state == null) {
            return;
        }
        _demoTick += 1;
        _state.anim = _demoTick;   // анимация точки и многоточия

        var forced = Application.Storage.getValue("debugScene");
        var scene = (forced != null)
            ? ((forced as Lang.Number) % 6)
            : ((_demoTick / DEMO_SCENE_TICKS) % 6);

        switch (scene) {
            case 0:   // поиск
                setDemo(false, CONN_SCANNING,  false, -1, -1, -1);
                break;
            case 1:   // подключение
                setDemo(false, CONN_CONNECTING, false, -1, -1, -1);
                break;
            case 2:   // на связи, не привязан, 1-значная задняя
                setDemo(true,  CONN_LIVE, false, 5, 12, 80);
                break;
            case 3:   // на связи, привязан, 2-значная задняя, низкий заряд
                setDemo(true,  CONN_LIVE, true, 11, 12, 15);
                break;
            case 4:   // потеря связи / реконнект (привязка сохраняется)
                setDemo(false, CONN_RETRY, true, -1, -1, -1);
                break;
            default:  // на связи, привязан, максимальная задняя
                setDemo(true,  CONN_LIVE, true, 12, 12, 50);
                break;
        }
    }

    // Применить одну демо-сцену к состоянию (только debug). battery<0 не трогаем.
    (:debug)
    function setDemo(connected as Lang.Boolean, phase as Lang.Number, locked as Lang.Boolean,
                     rear as Lang.Number, rearTotal as Lang.Number, battery as Lang.Number) as Void {
        _state.connected = connected;
        _state.phase = phase;
        _state.locked = locked;
        _state.rear = rear;
        _state.rearTotal = rearTotal;
        _state.front = 1;        // дефолтный привод: одна передняя звезда
        _state.frontTotal = 1;
        _state.battery = battery;
    }

    (:release)
    function applyDebugData() as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // Цвета по теме устройства: дневной фон белый / ночной чёрный.
        // getBackgroundColor() возвращает фон, заданный системой; текст инвертируем.
        var bg = getBackgroundColor();
        var dark = (bg == Graphics.COLOR_BLACK);
        var fg = dark ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        // Приглушённый цвет для лидирующего нуля (тусклее основного на текущем фоне).
        var fade = dark ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY;
        dc.setColor(bg, bg);
        dc.clear();

        var connected = (_state != null) && _state.connected;

        // ── Верхняя строка ────────────────────────────────────────────────────
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        var topY = (h * 0.08).toNumber();
        var topFontH = dc.getFontHeight(Graphics.FONT_XTINY);
        // Единая центр-линия верхней строки: и текст, и кружок выравниваются по
        // ней через VCENTER, поэтому совпадают по вертикали на любой раскладке
        // (раньше текст был top-aligned, а кружок — по центру шрифта → расхождение).
        var topVC = Graphics.TEXT_JUSTIFY_VCENTER;
        var centerY = topY + topFontH / 2;

        // Слева: метка Di2 + индикатор подключения (кружок по центру высоты текста).
        // Цвет кодирует фазу связи; пока не подключены — кружок пульсирует (1 Гц),
        // чтобы было видно: поле живо и активно ищет, а не зависло.
        dc.drawText(2, centerY, Graphics.FONT_XTINY, _lblDi2, Graphics.TEXT_JUSTIFY_LEFT | topVC);
        var di2Width = dc.getTextWidthInPixels(_lblDi2, Graphics.FONT_XTINY);
        var dotX = 2 + di2Width + 8;
        // VCENTER центрирует текст по font-box, но в «Di2» нет свисающих глифов,
        // поэтому видимые буквы сидят выше centerY на ~descent/2. Поднимаем точку
        // на ту же величину, чтобы она встала по оптическому центру букв (заметно
        // в фазе поиска, где точка крупнее). Шрифт фиксирован → поправка одна на все раскладки.
        var dotY = centerY - Graphics.getFontDescent(Graphics.FONT_XTINY) / 2;
        dc.setColor(phaseColor(connected), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dotX, dotY, dotRadius(connected));

        // По центру: передняя передача F:{front}/{frontTotal}. Пока нет связи — "---".
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        var frontStr = _lblFront + (connected ? pair(frontVal(), frontTotalVal()) : _noData);
        dc.drawText(w / 2, centerY, Graphics.FONT_XTINY, frontStr, Graphics.TEXT_JUSTIFY_CENTER | topVC);

        // Справа: батарея — процент / иконка / иконка+процент (по настройке).
        drawBattery(dc, w - 2, centerY, topFontH, fg);

        // ── Задняя передача (крупно): центр свободной зоны ПОД шапкой ──────────
        var maxWidth = (w * 0.84).toNumber();        // ~8% поля с каждой стороны
        var headerBottom = topY + topFontH;          // низ верхней строки
        var rearY = (headerBottom + h) / 2;          // центр оставшейся высоты
        var maxHeight = ((h - headerBottom) * 0.9).toNumber();  // запас по высоте
        drawRear(dc, w / 2, rearY, maxWidth, maxHeight, connected, fg, fade);

        // ── Отладочный дамп gear-пакета (калибровка байта передней) ────────────
        if (DEBUG_OVERLAY && _state != null && _state.dbgGear.length() > 0) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            var bytes = toTokens(_state.dbgGear);
            var half = (bytes.size() + 1) / 2;
            var line1 = joinRange(bytes, 0, half);          // байты 0..half-1
            var line2 = joinRange(bytes, half, bytes.size()); // остальные
            dc.drawText(w / 2, (h * 0.78).toNumber(), Graphics.FONT_XTINY, line1, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, (h * 0.88).toNumber(), Graphics.FONT_XTINY, line2, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // ── Отладочные утилиты ──────────────────────────────────────────────────────

    // Разбить "00 11 22 " на массив токенов ["00","11","22"].
    private function toTokens(s as Lang.String) as Lang.Array<Lang.String> {
        var out = [];
        var cur = "";
        var chars = s.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] == ' ') {
                if (cur.length() > 0) { out.add(cur); cur = ""; }
            } else {
                cur += chars[i].toString();
            }
        }
        if (cur.length() > 0) { out.add(cur); }
        return out;
    }

    // Склеить токены [from, to) через пробел.
    private function joinRange(tokens as Lang.Array<Lang.String>, from as Lang.Number, to as Lang.Number) as Lang.String {
        var s = "";
        for (var i = from; i < to && i < tokens.size(); i++) {
            s += tokens[i] + " ";
        }
        return s;
    }

    // ── Форматирование ────────────────────────────────────────────────────────

    // Форматирование пары «передача/всего» с деградацией:
    //   оба известны        -> "a/b"
    //   известна только текущая -> "a"
    //   известно только всего   -> "-/b"  (напр. 2x: число звёзд из настроек есть,
    //                                       текущую переднюю прочитать нельзя)
    //   ничего нет           -> "---"
    private function pair(a as Lang.Number, b as Lang.Number) as Lang.String {
        if (a < 0 && b < 0) {
            return _noData;
        }
        if (a < 0) {
            return "-/" + b.toString();
        }
        if (b < 0) {
            return a.toString();
        }
        return a.toString() + "/" + b.toString();
    }

    private function batteryStr() as Lang.String {
        var b = (_state != null) ? _state.battery : -1;
        if (b < 0) {
            return _noData;
        }
        return b.toString() + "%";
    }

    // Отрисовка батареи справа в верхней строке по режиму _state.batteryMode:
    //   0 — процент (как раньше); 1 — иконка; 2 — иконка + процент.
    // Нет данных (b<0) — всегда "---" (иконку рисовать нечем). rightX — правый край,
    // centerY — центр строки, fontH — высота FONT_XTINY (для масштаба иконки).
    private function drawBattery(dc as Graphics.Dc, rightX as Lang.Number, centerY as Lang.Number,
                                 fontH as Lang.Number, fg as Graphics.ColorType) as Void {
        var b = (_state != null) ? _state.battery : -1;
        var mode = (_state != null) ? _state.batteryMode : 0;
        var vc = Graphics.TEXT_JUSTIFY_VCENTER;

        // Режим «процент» или отсутствие данных → текст.
        if (mode == 0 || b < 0) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(rightX, centerY, Graphics.FONT_XTINY, batteryStr(),
                        Graphics.TEXT_JUSTIFY_RIGHT | vc);
            return;
        }

        // Геометрия иконки от высоты шрифта.
        var bh = (fontH * 0.5).toNumber();
        if (bh < 6) { bh = 6; }
        var bw = (bh * 1.9).toNumber();
        var nub = (bw * 0.10).toNumber();
        if (nub < 1) { nub = 1; }

        var iconRight = rightX;
        // Режим «иконка + процент»: процент справа, иконка слева от него.
        if (mode == 2) {
            var pct = b.toString() + "%";
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(rightX, centerY, Graphics.FONT_XTINY, pct, Graphics.TEXT_JUSTIFY_RIGHT | vc);
            iconRight = rightX - dc.getTextWidthInPixels(pct, Graphics.FONT_XTINY) - 4;
        }
        drawBatteryIcon(dc, iconRight - bw - nub, centerY - bh / 2, bw, bh, nub, b, fg);
    }

    // Горизонтальная иконка батареи: корпус-рамка + клемма справа + заливка ∝ заряду.
    // Цвет заливки кодирует уровень: <15 % красный, <40 % оранжевый, иначе зелёный.
    private function drawBatteryIcon(dc as Graphics.Dc, bx as Lang.Number, by as Lang.Number,
                                     bw as Lang.Number, bh as Lang.Number, nub as Lang.Number,
                                     pct as Lang.Number, fg as Graphics.ColorType) as Void {
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRectangle(bx, by, bw, bh);                              // корпус
        dc.fillRectangle(bx + bw, by + (bh * 0.28).toNumber(),         // клемма
                         nub, (bh * 0.44).toNumber());
        var lvl = (pct < 15) ? Graphics.COLOR_RED
                : (pct < 40) ? Graphics.COLOR_ORANGE : Graphics.COLOR_GREEN;
        var innerW = ((bw - 3) * pct / 100).toNumber();               // ширина заливки
        if (innerW > 0) {
            dc.setColor(lvl, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx + 2, by + 2, innerW, bh - 4);
        }
    }

    private function frontVal() as Lang.Number      { return (_state != null) ? _state.front : -1; }
    private function frontTotalVal() as Lang.Number { return (_state != null) ? _state.frontTotal : -1; }
    private function rearVal() as Lang.Number       { return (_state != null) ? _state.rear : -1; }
    private function rearTotalVal() as Lang.Number  { return (_state != null) ? _state.rearTotal : -1; }

    // Доля от высоты шрифта: радиус кружка-разделителя и зазор до цифр.
    private const REAR_DOT_FRAC = 0.085;   // радиус точки
    private const REAR_GAP_FRAC = 0.07;    // зазор между точкой и цифрой
    // Смещение кружка вниз (доля высоты шрифта): у числовых шрифтов визуальный центр
    // цифр ниже центра строки, поэтому опускаем точку, чтобы она смотрелась посередине.
    private const REAR_DOT_Y_FRAC = 0.06;

    // ── Индикация фазы связи ────────────────────────────────────────────────────

    // Цвет кружка-индикатора по фазе: зелёный = данные идут, жёлтый = подключаемся,
    // оранжевый = переподключение, синий = идёт поиск.
    // Подключены к «своему» (sticky-lock) — тёмно-синий вместо зелёного: связь есть
    // и это привязанный Di2. Цвет заменяет прежнее кольцо вокруг точки.
    private function phaseColor(connected as Lang.Boolean) as Graphics.ColorType {
        if (connected) {
            var locked = (_state != null) && _state.locked;
            return locked ? Graphics.COLOR_DK_BLUE : Graphics.COLOR_GREEN;
        }
        var phase = (_state != null) ? _state.phase : CONN_SCANNING;
        if (phase == CONN_CONNECTING) { return Graphics.COLOR_YELLOW; }
        if (phase == CONN_RETRY)      { return Graphics.COLOR_ORANGE; }
        return Graphics.COLOR_BLUE;   // CONN_SCANNING
    }

    // Радиус индикатора: подключены — стабильный; ищем — пульсирует 3→5 px по тикам.
    private function dotRadius(connected as Lang.Boolean) as Lang.Number {
        if (connected) {
            return 4;
        }
        var anim = (_state != null) ? _state.anim : 0;
        var step = [0, 1, 2, 1][anim % 4];   // плавный треугольник 0..2..0
        return 3 + step;
    }

    // Центральная зона, пока нет данных: статус-слово + анимированное многоточие
    // и подсказка снизу. Слово фиксировано по центру, точки «бегут» справа — слово
    // не дёргается. Это заменяет прежнее немое "---".
    private function drawStatus(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                               maxWidth as Lang.Number, fg as Graphics.ColorType,
                               fade as Graphics.ColorType) as Void {
        var vc = Graphics.TEXT_JUSTIFY_VCENTER;
        var phase = (_state != null) ? _state.phase : CONN_SCANNING;
        var anim = (_state != null) ? _state.anim : 0;
        var word = (phase == CONN_CONNECTING) ? _statConnecting : _statSearching;

        var dots = "";
        var n = anim % 4;   // 0..3 точек — «дыхание» поиска
        for (var i = 0; i < n; i++) { dots += "."; }

        var font = statusFont(dc, word + "...", maxWidth);
        var fh = dc.getFontHeight(font);

        // Слово по центру; точки добавляем от его правого края (центр не смещается).
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - fh / 2, font, word, Graphics.TEXT_JUSTIFY_CENTER | vc);
        var wWidth = dc.getTextWidthInPixels(word, font);
        dc.drawText(cx + wWidth / 2, cy - fh / 2, font, dots, Graphics.TEXT_JUSTIFY_LEFT | vc);

        // Подсказка под статусом. В фазе подключения показываем счётчик секунд
        // (коннект при слабом сигнале длится до ~17 c — видно, что идёт, а не зависло);
        // в фазе поиска — подсказку «разбудите Di2».
        dc.setColor(fade, Graphics.COLOR_TRANSPARENT);
        var hint;
        if (phase == CONN_CONNECTING && _state != null) {
            hint = _state.connSeconds.format("%d") + "s";   // прогресс подключения
        } else if (_state != null && _state.scanSeconds >= SCAN_HINT_PAIR_SECS) {
            hint = _statHintPair;                            // долгий поиск → подскажем паринг
        } else {
            hint = _statHint;                                // обычная подсказка «разбуди Di2»
        }
        dc.drawText(cx, cy + fh / 2, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER | vc);
    }

    // Крупнейший из обычных шрифтов, при котором статус-строка влезает по ширине.
    private function statusFont(dc as Graphics.Dc, s as Lang.String, maxWidth as Lang.Number) as Graphics.FontDefinition {
        var fonts = [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getTextWidthInPixels(s, fonts[i]) <= maxWidth) {
                return fonts[i];
            }
        }
        return Graphics.FONT_XTINY;
    }

    // Отрисовка задней передачи тремя зонами с кружком-разделителем по центру (cx):
    //   • кружок      — по центру cx;
    //   • текущая     — правым краем к кружку (с зазором), растёт влево;
    //   • всего       — левым краем к кружку (с зазором), растёт вправо.
    // Одиночные цифры дополняются лидирующим "0" приглушённым цветом (стабильная ширина).
    // Кружок не двигается при смене числа цифр/шрифта. Нет связи — статус через drawStatus.
    private function drawRear(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                             maxWidth as Lang.Number, maxHeight as Lang.Number,
                             connected as Lang.Boolean, fg as Graphics.ColorType,
                             fade as Graphics.ColorType) as Void {
        if (!connected) {
            drawStatus(dc, cx, cy, maxWidth, fg, fade);
            return;
        }
        var left = (rearVal() < 0) ? "-" : rearVal().toString();
        var right = (rearTotalVal() < 0) ? "-" : rearTotalVal().toString();
        var font = fitRearFont(dc, left, right, maxWidth, maxHeight);
        var fh = dc.getFontHeight(font);
        var rDot = (fh * REAR_DOT_FRAC).toNumber();
        var gap = (fh * REAR_GAP_FRAC).toNumber();
        var inner = rDot + gap;   // отступ от центра до края цифры

        var dotY = cy + (fh * REAR_DOT_Y_FRAC).toNumber();   // опускаем к центру цифр
        dc.setColor(fade, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, dotY, rDot);
        drawPadded(dc, cx - inner, cy, font, left, true, fg, fade);    // текущая: правым краем
        drawPadded(dc, cx + inner, cy, font, right, false, fg, fade);  // всего: левым краем
    }

    // Число с лидирующим "0" приглушённого цвета, если оно однозначное (не "-").
    // rightJustify=true → правый край в x; false → левый край в x.
    private function drawPadded(dc as Graphics.Dc, x as Lang.Number, cy as Lang.Number,
                               font as Graphics.FontDefinition, num as Lang.String,
                               rightJustify as Lang.Boolean, fg as Graphics.ColorType,
                               fade as Graphics.ColorType) as Void {
        var vc = Graphics.TEXT_JUSTIFY_VCENTER;
        var single = (num.length() == 1) && !num.equals("-");
        if (!single) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, cy, font, num, (rightJustify ? Graphics.TEXT_JUSTIFY_RIGHT : Graphics.TEXT_JUSTIFY_LEFT) | vc);
            return;
        }
        var dw = dc.getTextWidthInPixels("0", font);
        if (rightJustify) {
            // "0" + цифра, правый край цифры в x; "0" слева от неё
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, cy, font, num, Graphics.TEXT_JUSTIFY_RIGHT | vc);
            dc.setColor(fade, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x - dw, cy, font, "0", Graphics.TEXT_JUSTIFY_RIGHT | vc);
        } else {
            // "0" + цифра, левый край "0" в x; цифра справа
            dc.setColor(fade, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, cy, font, "0", Graphics.TEXT_JUSTIFY_LEFT | vc);
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + dw, cy, font, num, Graphics.TEXT_JUSTIFY_LEFT | vc);
        }
    }

    // Ширина числа с учётом лидирующего нуля (однозначное считаем как двузначное).
    private function paddedWidth(dc as Graphics.Dc, s as Lang.String, font as Graphics.FontDefinition) as Lang.Number {
        if (s.length() == 1 && !s.equals("-")) {
            return dc.getTextWidthInPixels("00", font);
        }
        return dc.getTextWidthInPixels(s, font);
    }

    // Самый крупный числовой шрифт, при котором запись с кружком-разделителем
    // влезает по ширине (учитывая бóльшую из сторон + кружок + зазор) и по высоте.
    private function fitRearFont(dc as Graphics.Dc, left as Lang.String, right as Lang.String,
                                maxWidth as Lang.Number, maxHeight as Lang.Number) as Graphics.FontDefinition {
        var fonts = [
            Graphics.FONT_NUMBER_THAI_HOT,
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD
        ];
        for (var i = 0; i < fonts.size(); i++) {
            var f = fonts[i];
            var fh = dc.getFontHeight(f);
            var inner = fh * REAR_DOT_FRAC + fh * REAR_GAP_FRAC;
            var lw = paddedWidth(dc, left, f);
            var rw = paddedWidth(dc, right, f);
            var maxSide = (lw > rw) ? lw : rw;
            // Каждая сторона = inner + maxSide должна влезать в maxWidth/2; плюс высота.
            if (2 * (inner + maxSide) <= maxWidth && fh <= maxHeight) {
                return f;
            }
        }
        return Graphics.FONT_NUMBER_MILD;
    }
}
