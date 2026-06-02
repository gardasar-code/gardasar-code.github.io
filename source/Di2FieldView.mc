using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;

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

    // Кэш строк из ресурсов (грузим один раз).
    private var _lblDi2 as Lang.String = "Di2";
    private var _noData as Lang.String = "---";

    function initialize(state as Di2State?, delegate as Di2BleDelegate?) {
        DataField.initialize();
        _state = state;
        _delegate = delegate;
        _lblDi2 = WatchUi.loadResource(Rez.Strings.LabelDi2) as Lang.String;
        _noData = WatchUi.loadResource(Rez.Strings.LabelNoData) as Lang.String;
    }

    // Data Field вызывает compute каждую секунду — это heartbeat дата-филда.
    // Toybox.Timer здесь недоступен, поэтому периодику BLE (реконнект, опрос
    // батареи) гоним отсюда через onTick(). Сами данные приходят асинхронно в
    // Di2State из BLE-колбэков; рисуем их в onUpdate.
    function compute(info as Toybox.Activity.Info) as Void {
        if (_delegate != null) {
            _delegate.onTick();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // Фон — белый, очистка.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.clear();

        var connected = (_state != null) && _state.connected;

        // ── Верхняя строка ────────────────────────────────────────────────────
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        var topY = (h * 0.08).toNumber();

        // Слева: метка [Di2] + индикатор подключения.
        dc.drawText(2, topY, Graphics.FONT_XTINY, _lblDi2, Graphics.TEXT_JUSTIFY_LEFT);
        var dotColor = connected ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY;
        var di2Width = dc.getTextWidthInPixels(_lblDi2, Graphics.FONT_XTINY);
        dc.setColor(dotColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(di2Width + 10, topY + 6, 4);

        // По центру: передняя передача F:{front}/{frontTotal}.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        var frontStr = "F:" + pair(frontVal(), frontTotalVal());
        dc.drawText(w / 2, topY, Graphics.FONT_XTINY, frontStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Справа: батарея {bat}%.
        var battStr = batteryStr();
        dc.drawText(w - 2, topY, Graphics.FONT_XTINY, battStr, Graphics.TEXT_JUSTIFY_RIGHT);

        // ── Центр: задняя передача (крупно) ───────────────────────────────────
        var rearStr = pair(rearVal(), rearTotalVal());
        dc.drawText(w / 2, h / 2, biggestFont(), rearStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Отладочный дамп gear-пакета (калибровка байта передней) ────────────
        if (DEBUG_OVERLAY && _state != null && _state.dbgGear.length() > 0) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
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
    //   оба известны -> "a/b"; известна только текущая -> "a" (полезно при калибровке);
    //   ничего нет -> "---".
    private function pair(a as Lang.Number, b as Lang.Number) as Lang.String {
        if (a < 0) {
            return _noData;
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

    private function frontVal() as Lang.Number      { return (_state != null) ? _state.front : -1; }
    private function frontTotalVal() as Lang.Number { return (_state != null) ? _state.frontTotal : -1; }
    private function rearVal() as Lang.Number       { return (_state != null) ? _state.rear : -1; }
    private function rearTotalVal() as Lang.Number  { return (_state != null) ? _state.rearTotal : -1; }

    // Крупнейший разумно доступный шрифт для центральной цифры.
    private function biggestFont() as Graphics.FontDefinition {
        return Graphics.FONT_NUMBER_THAI_HOT;
    }
}
