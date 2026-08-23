using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;

// Полноэкранный диагностический экран BLE.
//
// Вынесен из Di2FieldView намеренно: основной макет и диагностика живут по разным
// правилам (первый — про читаемость на ходу, вторая — про плотность технических
// данных под фото) и правятся независимо. Ни одного общего состояния, кроме Di2State.
//
// Экран целиком заменяет основной макет, когда включён diagOverlay: сверху компактный
// СВЕТОВОЙ индикатор этапа (цветной кружок фазы + слово), ниже — технические строки
// мелким шрифтом и сырые notify-пакеты. Технические подписи — английские литералы
// (диагностика, не локализуется). Расшифровка строк — doc/LOGGING.md.
class Di2DiagScreen {

    private var _state as Di2State?;

    function initialize(state as Di2State?) {
        _state = state;
    }

    // Цвет кружка фазы. Дублирует логику основного макета намеренно: диагностика
    // должна оставаться работоспособной независимо от изменений в оформлении поля.
    function phaseColor(connected as Lang.Boolean) as Graphics.ColorType {
        if (connected) {
            var locked = (_state != null) && _state.locked;
            return locked ? Graphics.COLOR_DK_BLUE : Graphics.COLOR_GREEN;
        }
        var phase = (_state != null) ? _state.phase : CONN_SCANNING;
        if (phase == CONN_CONNECTING) { return Graphics.COLOR_YELLOW; }
        if (phase == CONN_RETRY)      { return Graphics.COLOR_ORANGE; }
        return Graphics.COLOR_BLUE;   // CONN_SCANNING
    }


    // Полноэкранная BLE-диагностика для разбора подключения по ФОТО. Вместо основного
    // макета: сверху компактный СВЕТОВОЙ индикатор этапа (цветной кружок фазы + слово),
    // ниже — максимум технических данных мелким шрифтом, выровненных по левому краю:
    //   dev/shi/RSSI   — discovery эфира (виден ли Shimano-маркер)
    //   lk/bat         — sticky-lock и заряд
    //   id=<GATT-имя>  — модель переключателя (для краудсорса серий)
    //   mdl=<профиль>  — распознанный профиль (или "?" для неизвестной модели)
    //   R=/F=/ratio    — распарсенные передачи и передаточное
    //   len + hex      — длина и сырой notify-пакет (несколько строк)
    // Технические подписи — английские литералы (диагностика, не локализуется).
    function drawDiagScreen(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number,
                                    fg as Graphics.ColorType, bg as Graphics.ColorType,
                                    fade as Graphics.ColorType) as Void {
        var s = _state;
        if (s == null) {
            return;
        }
        var fh = dc.getFontHeight(Graphics.FONT_XTINY);
        var vc = Graphics.TEXT_JUSTIFY_VCENTER;
        var x = 3;

        // Световой индикатор этапа: цветной кружок (цвет = фаза) + слово-подпись.
        var r = (fh * 0.30).toNumber();
        if (r < 3) { r = 3; }
        var rowY = 1 + fh / 2;
        dc.setColor(phaseColor(s.connected), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + r, rowY, r);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 2 * r + 5, rowY, Graphics.FONT_XTINY, phaseWord(), Graphics.TEXT_JUSTIFY_LEFT | vc);

        // Технические строки (левое выравнивание, мелкий шрифт).
        var lines = [
            "dev=" + s.dbgScanTotal + " shi=" + s.dbgScanShimano
                + " r=" + (s.dbgBestRssi > -999 ? s.dbgBestRssi.toString() : "--"),
            "lk=" + (s.locked ? "1" : "0")
                + " bat=" + (s.battery >= 0 ? s.battery.toString() + "%" : "--")
        ] as Lang.Array<Lang.String>;
        if (s.dbgDeviceName.length() > 0) {
            lines.add("id=" + s.dbgDeviceName);
        }
        if (s.dbgModel.length() > 0) {
            lines.add("mdl=" + s.dbgModel);
        }
        // Распарсенные передачи + передаточное отношение.
        var ratio = s.gearRatio();
        lines.add("R=" + numOrDash(s.rear) + "/" + numOrDash(s.rearTotal)
            + " F=" + numOrDash(s.front) + "/" + numOrDash(s.frontTotal)
            + (ratio > 0.0 ? " " + ratio.format("%.2f") : ""));
        // Строка потока notify: длина последнего пакета, счётчики «всего/годных» и
        // возраст последнего пакета в секундах. Читается так:
        //   pkt=0/0        — канал молчит: смотреть sub= (подписка) ниже;
        //   pkt=N/0        — пакеты идут, но ни один не совпал с длиной профиля
        //                    → менять раскладку профиля, а не чинить связь;
        //   pkt=N/M age>10 — шли и прекратились (Di2 уснул или связь просела).
        lines.add("len=" + s.dbgGearLen + " pkt=" + s.dbgPktTotal + "/" + s.dbgPktGood
            + " age=" + pktAge(s));
        // Состояние подписки на CCCD + число реконнектов за сессию.
        // sub=ok при pkt=0/0 → подписка принята, молчит само устройство;
        // sub=no-svc/no-chr/no-cccd → GATT-раскладка не та, что мы ждём;
        // sub=e<N> → стек отклонил запись CCCD (частый случай — протухший бонд).
        // svc= число сервисов, видимых стеком в момент подписки: svc=0 при sub=no-svc
        // означает «дискавери не готова» (гонка), svc>0 — «сервиса нет в прошивке».
        lines.add("sub=" + s.dbgSub + " svc=" + numOrDash(s.dbgSvcCount)
            + " rc=" + s.dbgReconnects);
        // Результат регистрации профилей: без неё стек не ищет сервис на устройстве,
        // поэтому "18EF:e<N>" здесь — прямая причина "sub=no-svc" выше.
        if (s.dbgReg.length() > 0) {
            lines.add("reg=" + s.dbgReg + " n=" + s.dbgRegAttempts + s.dbgRegForm);
        }
        if (DIAG_VERSION.length() > 0) {
            lines.add("v=" + DIAG_VERSION);
        }
        // Список сервисов, реально видимых стеком (короткие UUID).
        if (s.dbgSvcList.length() > 0) {
            lines.add("svc: " + s.dbgSvcList);
        }

        // Рисуем технические строки под индикатором (с защитой от выхода за экран).
        var y = fh + 1;
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size() && y + fh <= h; i++) {
            dc.drawText(x, y, Graphics.FONT_XTINY, lines[i], Graphics.TEXT_JUSTIFY_LEFT);
            y += fh;
        }

        // Сырые notify-пакеты: ВСЕ разновидности, приглушённо, по DIAG_HEX_PER_ROW
        // байт в строке. Первая строка каждого пакета помечена его длиной ("17:"),
        // продолжения — с отступом под ней, иначе многострочные дампы разных форматов
        // сливаются в одно полотно. Порядок задан state (по убыванию длины), так что
        // при нехватке места обрежется хвост из коротких служебных пакетов.
        dc.setColor(fade, Graphics.COLOR_TRANSPARENT);
        var hexX = x + dc.getTextWidthInPixels("00: ", Graphics.FONT_XTINY);
        for (var k = 0; k < s.dbgPktHex.size() && y + fh <= h; k++) {
            var bytes = toTokens(s.dbgPktHex[k]);
            var head = true;
            for (var from = 0; from < bytes.size() && y + fh <= h; from += DIAG_HEX_PER_ROW) {
                if (head) {
                    dc.drawText(x, y, Graphics.FONT_XTINY, s.dbgPktLen[k].toString() + ":",
                        Graphics.TEXT_JUSTIFY_LEFT);
                    head = false;
                }
                dc.drawText(hexX, y, Graphics.FONT_XTINY, joinRange(bytes, from, from + DIAG_HEX_PER_ROW),
                    Graphics.TEXT_JUSTIFY_LEFT);
                y += fh;
            }
        }
    }

    // Версия сборки для diag-экрана. В обычной сборке пустая (строка не рисуется);
    // build-diag.sh подставляет сюда версию из manifest.xml — в имени diag-файла
    // версии нет, поэтому по фото экрана иначе не понять, какая сборка стоит.
    const DIAG_VERSION = "";

    // Сколько hex-байт в одной строке дампа на diag-экране.
    const DIAG_HEX_PER_ROW = 8;

    // Возраст последнего notify-пакета в секундах ("--", если пакетов ещё не было).
    // Считается во View, а не в делегате: значение нужно свежим на каждый кадр.
    function pktAge(s as Di2State) as Lang.String {
        if (s.dbgLastPktMs == 0) {
            return "--";
        }
        var age = (System.getTimer() - s.dbgLastPktMs) / 1000;
        return age.toString();
    }

    // Число для diag: значение или "-" при отсутствии данных (<0).
    function numOrDash(v as Lang.Number) as Lang.String {
        return (v < 0) ? "-" : v.toString();
    }

    // Слово-подпись этапа для светового индикатора diag-экрана.
    function phaseWord() as Lang.String {
        if (_state != null && _state.connected) {
            return "Live";
        }
        var p = (_state != null) ? _state.phase : CONN_SCANNING;
        if (p == CONN_CONNECTING) { return "Connecting"; }
        if (p == CONN_RETRY)      { return "Retry"; }
        return "Scanning";
    }

    // ── Утилиты hex-дампа ───────────────────────────────────────────────────────

    // Разбить "00 11 22 " на массив токенов ["00","11","22"].
    function toTokens(s as Lang.String) as Lang.Array<Lang.String> {
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
    function joinRange(tokens as Lang.Array<Lang.String>, from as Lang.Number, to as Lang.Number) as Lang.String {
        var s = "";
        for (var i = from; i < to && i < tokens.size(); i++) {
            s += tokens[i] + " ";
        }
        return s;
    }
}
