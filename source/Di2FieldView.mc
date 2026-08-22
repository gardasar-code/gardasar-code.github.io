using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Application;
using Toybox.System;

// Рендеринг Data Field (светлая тема). Структура экрана:
//   ROOT (внутр. отступ)
//   ├── HEADER ── Di2 + индикатор фазы | батарея
//   └── BODY
//       ├── LEFT  (перёд, только при frontTotal > 1)
//       │   ├── GRAF (столбики передних звёзд)
//       │   └── NUM  (цифра текущей передней)
//       └── RIGHT (зад, всегда)
//           ├── GRAF (кассета)
//           └── NUM  (текущая · всего)
// GRAF/NUM присутствуют по displayMode (цифры/график/оба). Нет связи — статус-экран.
// Точка-индикатор в HEADER: цвет = фаза (зелёная connected / синяя поиск / …).
class Di2FieldView extends WatchUi.DataField {

    // Принудительный диаг-оверлей для симулятора/калибровки (где настройки не подать).
    // В обычной работе оверлей включается настройкой diagOverlay (Di2State.diagOverlay),
    // которая работает в любой store-сборке. Здесь true — чтобы форсировать оверлей в
    // debug-сборке. В коммите всегда false.
    private const DEBUG_OVERLAY = false;

    private var _state as Di2State?;
    private var _delegate as Di2BleDelegate?;   // null, если BLE отключён
    private var _fit as Di2FitContributor?;     // запись в FIT-файл активности

    // DEBUG (симулятор): монотонный счётчик тиков для демо-цикла состояний.
    (:debug) private var _demoTick as Lang.Number = 0;

    // Кэш строк из ресурсов (грузим один раз, с учётом языка устройства).
    private var _lblDi2 as Lang.String = "Di2";
    private var _noData as Lang.String = "---";
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
    // Полный цикл сцен (0..8) — прогоняет фазы связи И варианты показа батареи/передачи:
    //   0 Searching   — синяя пульсирующая точка, статус-экран поиска
    //   1 Connecting  — жёлтая точка, статус-экран подключения
    //   2 Live        — цифры + батарея %, 1x, передача 5/12, 80 %
    //   3 Live        — цифры + батарея ИКОНКОЙ, 1x, 8/12, 45 %
    //   4 Live+lock   — цифры + иконка+% (низкий заряд), 2x (цифра передней), 11/12, 12 %
    //   5 Live        — ГРАФИК кассеты + %, 2x (бар передней, текущая неизв.), 3/12, 60 %
    //   6 Live+lock   — ГРАФИК кассеты + иконка, 3x (бар передней активный), 9/12, 30 %
    //   7 Live+lock   — ОБА (график+цифры) + иконка+%, 2x (бар+цифра), 12/12, 90 %
    //   8 Retry       — оранжевая точка, статус-экран (привязка ещё активна)
    //   9 Diag        — диагностический экран (BLE-разбор по фото): discovery, GATT-имя,
    //                   профиль, передачи, сырой notify-пакет
    //
    // Зафиксировать ОДИН вид (для скриншота) двумя способами:
    //   • в коде — константа DEMO_SCENE ниже: -1 = цикл по всем сценам (как сейчас),
    //     0..8 = всегда показывать эту сцену (быстро менять прямо в исходнике);
    //   • в рантайме — «File → Edit Persistent Storage» в симуляторе → ключ debugScene.
    // Приоритет: DEMO_SCENE (если >=0) → debugScene → цикл по тикам.
    (:debug) const DEMO_SCENE = -1;        // -1 = цикл; 0..9 = зафиксировать сцену в коде
    (:debug) const DEMO_SCENE_TICKS = 5;
    (:debug) const DEMO_SCENE_COUNT = 10;  // число сцен в демо-цикле (0..9)

    (:debug)
    function applyDebugData() as Void {
        if (_state == null) {
            return;
        }
        _demoTick += 1;
        _state.anim = _demoTick;   // анимация точки и многоточия

        var scene;
        if (DEMO_SCENE >= 0) {
            scene = DEMO_SCENE % DEMO_SCENE_COUNT;            // зафиксировано в коде
        } else {
            var forced = Application.Storage.getValue("debugScene");
            scene = (forced != null)
                ? ((forced as Lang.Number) % DEMO_SCENE_COUNT)   // зафиксировано в storage
                : ((_demoTick / DEMO_SCENE_TICKS) % DEMO_SCENE_COUNT);  // цикл
        }

        // Параметры setDemo: connected, phase, locked, rear, rearTotal, battery,
        //                    batMode(0 проц/1 иконка/2 оба), dispMode(0 цифры/1 график/2 оба),
        //                    front(текущая передняя, <0 = неизвестна), frontTotal(1/2/3).
        switch (scene) {
            case 0:   // поиск
                setDemo(false, CONN_SCANNING,  false, -1, -1, -1, 0, 0, 1, 1);
                break;
            case 1:   // подключение
                setDemo(false, CONN_CONNECTING, false, -1, -1, -1, 0, 0, 1, 1);
                break;
            case 2:   // цифры + батарея %, 1x (передней нет)
                setDemo(true,  CONN_LIVE, false, 5, 12, 80, 0, 0, 1, 1);
                break;
            case 3:   // цифры + батарея иконкой, 1x
                setDemo(true,  CONN_LIVE, false, 8, 12, 45, 1, 0, 1, 1);
                break;
            case 4:   // цифры + батарея иконка+%, 2x (цифра передней слева)
                setDemo(true,  CONN_LIVE, true, 11, 12, 12, 2, 0, 2, 2);
                break;
            case 5:   // ГРАФИК кассеты + %, 2x (бар передней, текущая неизвестна)
                setDemo(true,  CONN_LIVE, false, 3, 12, 60, 0, 1, -1, 2);
                break;
            case 6:   // ГРАФИК кассеты + иконка, 3x (бар передней, активная подсвечена)
                setDemo(true,  CONN_LIVE, true, 9, 12, 30, 1, 1, 2, 3);
                break;
            case 7:   // ОБА (график+цифры) + иконка+%, 2x (бар у кассеты + цифра у цифр)
                setDemo(true,  CONN_LIVE, true, -1, 12, 90, 2, 2, 2, 2);
                break;
            case 8:   // потеря связи / реконнект
                setDemo(false, CONN_RETRY, true, -1, -1, -1, 0, 0, 1, 1);
                break;
            default:  // диагностический экран (BLE-разбор по фото)
                setDemo(true, CONN_LIVE, true, 5, 12, 80, 0, 0, 2, 2);
                setDemoDiag();
                break;
        }
    }

    // Применить одну демо-сцену к состоянию (только debug). battery<0 не трогаем.
    // batMode/dispMode прокидываем в state, чтобы в превью прогонять новые варианты
    // показа батареи (процент/иконка/оба) и передачи (цифры/график/оба).
    // front/frontTotal — для превью переднего индикатора (1x скрыт; 2x/3x — бар/цифра;
    // front<0 имитирует «текущая неизвестна», как на реальном 2x/3x).
    (:debug)
    function setDemo(connected as Lang.Boolean, phase as Lang.Number, locked as Lang.Boolean,
                     rear as Lang.Number, rearTotal as Lang.Number, battery as Lang.Number,
                     batMode as Lang.Number, dispMode as Lang.Number,
                     front as Lang.Number, frontTotal as Lang.Number) as Void {
        _state.connected = connected;
        _state.phase = phase;
        _state.locked = locked;
        _state.rear = rear;
        _state.rearTotal = rearTotal;
        _state.front = front;
        _state.frontTotal = frontTotal;
        // Зубья передних звёзд под выбранное число (для высот бар-столбиков).
        _state.frontTeeth = (frontTotal == 3) ? ([40, 30, 22] as Lang.Array<Lang.Number>)
                          : (frontTotal == 2) ? ([50, 34] as Lang.Array<Lang.Number>)
                          : ([32] as Lang.Array<Lang.Number>);
        _state.battery = battery;
        _state.batteryMode = batMode;
        _state.displayMode = dispMode;
        _state.diagOverlay = false;   // обычные сцены — основной макет (не diag-экран)
    }

    // Демо-данные для диагностического экрана: включаем diagOverlay и заполняем dbg-поля
    // правдоподобными значениями (discovery, GATT-имя, профиль, сырой пакет передач).
    (:debug)
    function setDemoDiag() as Void {
        _state.diagOverlay = true;
        _state.dbgScanTotal = 7;
        _state.dbgScanShimano = 1;
        _state.dbgBestRssi = -68;
        _state.dbgDeviceName = "RDM8250S2A8";
        _state.dbgModel = "XT M8250 12s";
        _state.dbgGearLen = 3;
        _state.dbgPktTotal = 124;
        _state.dbgPktGood = 41;
        _state.dbgLastPktMs = 1;
        _state.dbgSub = "ok";
        _state.dbgSvcCount = 4;
        _state.dbgReconnects = 2;
        // Три разновидности пакетов — ровно как их шлёт реальный XT M8250 (doc/NOTES.md).
        _state.recordPacket(17, "00 00 03 FF FF 05 0C 80 80 80 FF EE 12 FF FF 15 00");
        _state.recordPacket(6, "06 42 00 00 00 03");
        _state.recordPacket(3, "04 FF FF");
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

        // ── Диагностический режим (настройка diagOverlay или DEBUG_OVERLAY) ──────
        // Занимает ВЕСЬ экран: основной макет (крупные передачи/батарея) не нужен при
        // разборе подключения — вместо него максимум диагностики + компактный световой
        // индикатор этапа сверху. Работает в обычной store-сборке (это рисование, не
        // println) → пользователь присылает ФОТО для разбора. См. doc/LOGGING.md.
        if ((DEBUG_OVERLAY || (_state != null && _state.diagOverlay)) && _state != null) {
            drawDiagScreen(dc, w, h, fg, bg, fade);
            return;
        }

        var connected = (_state != null) && _state.connected;

        // ── Раскладка: ROOT с внутренним отступом → HEADER (сверху) + BODY (снизу) ──
        var padX = (w * PAD_X_FRAC).toNumber();
        if (padX < 2) { padX = 2; }
        var padTop = (h * PAD_TOP_FRAC).toNumber();
        var padBot = (h * PAD_BOT_FRAC).toNumber();
        var headerH = dc.getFontHeight(Graphics.FONT_XTINY);

        // HEADER: слева Di2 + индикатор фазы, справа батарея.
        drawHeader(dc, padX, padTop, w - 2 * padX, headerH, connected, fg);

        // BODY: графики и цифры передач под шапкой.
        var bodyY = padTop + headerH + (h * HEADER_GAP_FRAC).toNumber();
        var bodyX = padX;
        var bodyW = w - 2 * padX;
        var bodyH = h - bodyY - padBot;
        drawBody(dc, bodyX, bodyY, bodyW, bodyH, connected, fg, fade);
    }

    // HEADER: слева метка Di2 + кружок-индикатор фазы (по центру высоты текста),
    // справа — батарея (процент/иконка/оба). Центр-линия строки = y + h/2.
    private function drawHeader(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number,
                               w as Lang.Number, h as Lang.Number,
                               connected as Lang.Boolean, fg as Graphics.ColorType) as Void {
        var vc = Graphics.TEXT_JUSTIFY_VCENTER;
        var centerY = y + h / 2;

        // Слева: метка Di2 + кружок фазы. Цвет кодирует фазу; пока не подключены —
        // пульсирует (видно, что поле живо и ищет, а не зависло).
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, centerY, Graphics.FONT_XTINY, _lblDi2, Graphics.TEXT_JUSTIFY_LEFT | vc);
        var di2Width = dc.getTextWidthInPixels(_lblDi2, Graphics.FONT_XTINY);
        var dotX = x + di2Width + 8;
        // VCENTER центрирует по font-box; в «Di2» нет свисающих глифов, поэтому
        // поднимаем точку на descent/2 к оптическому центру букв (заметно в поиске).
        var dotY = centerY - Graphics.getFontDescent(Graphics.FONT_XTINY) / 2;
        dc.setColor(phaseColor(connected), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dotX, dotY, dotRadius(connected));

        // Справа: батарея у правого края HEADER.
        drawBattery(dc, x + w, centerY, h, fg);
    }

    // ── Диагностический экран (полноэкранный) ───────────────────────────────────

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
    private function drawDiagScreen(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number,
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

    // Сколько hex-байт в одной строке дампа на diag-экране.
    private const DIAG_HEX_PER_ROW = 8;

    // Возраст последнего notify-пакета в секундах ("--", если пакетов ещё не было).
    // Считается во View, а не в делегате: значение нужно свежим на каждый кадр.
    private function pktAge(s as Di2State) as Lang.String {
        if (s.dbgLastPktMs == 0) {
            return "--";
        }
        var age = (System.getTimer() - s.dbgLastPktMs) / 1000;
        return age.toString();
    }

    // Число для diag: значение или "-" при отсутствии данных (<0).
    private function numOrDash(v as Lang.Number) as Lang.String {
        return (v < 0) ? "-" : v.toString();
    }

    // Слово-подпись этапа для светового индикатора diag-экрана.
    private function phaseWord() as Lang.String {
        if (_state != null && _state.connected) {
            return "Live";
        }
        var p = (_state != null) ? _state.phase : CONN_SCANNING;
        if (p == CONN_CONNECTING) { return "Connecting"; }
        if (p == CONN_RETRY)      { return "Retry"; }
        return "Scanning";
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
        var mode = (_state != null) ? _state.batteryMode : BAT_PCT;
        var vc = Graphics.TEXT_JUSTIFY_VCENTER;

        // Режим «процент» или отсутствие данных → текст.
        if (mode == BAT_PCT || b < 0) {
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
        if (mode == BAT_BOTH) {
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

    // ── Раскладка: ROOT(внутр. отступ) → HEADER + BODY → LEFT/RIGHT → GRAF/NUM ──
    // LEFT (перёд) есть только при 2x/3x; RIGHT (зад) — всегда. Каждая колонка делится
    // на GRAF (сверху) и NUM (снизу) по displayMode.
    private const PAD_X_FRAC = 0.04;        // боковой внутренний отступ корня
    private const PAD_TOP_FRAC = 0.06;      // верхний отступ (над HEADER)
    private const PAD_BOT_FRAC = 0.05;      // нижний отступ (под BODY)
    private const HEADER_GAP_FRAC = 0.02;   // зазор между HEADER и BODY
    private const COL_GAP_FRAC = 0.05;      // зазор LEFT|RIGHT в режиме «только график»
    private const BOTH_VPAD_FRAC = 0.08;    // верх/низ-отступ BODY в режиме «оба»
    private const BOTH_GRAF_FRAC = 0.52;    // доля рабочей высоты под GRAF («оба») на больших полях
    private const BOTH_GRAF_MIN_FRAC = 0.30; // пол высоты GRAF: ниже не ужимаем даже на малых
    private const BOTH_VGAP_FRAC = 0.12;    // зазор между GRAF и NUM («оба»)
    private const GRAPH_H_FRAC = 0.88;      // доля высоты BODY под GRAF («только график»)
    private const BAR_GAP_RATIO = 0.4;      // зазор = BAR_GAP_RATIO * толщина столбика
                                            // (столбики+зазоры заполняют ширину GRAF целиком)
    // Доля видимого глифа в ячейке числового шрифта (getFontHeight включает «воздух»
    // сверху/снизу). Подбор шрифта разрешает ячейке быть выше блока в 1/NUM_VFILL раз —
    // видимые цифры заполняют блок, пустой «воздух» уходит в отступы ROOT. Меньше →
    // крупнее цифры (но больше риск задеть край при асимметричном глифе).
    private const NUM_VFILL = 0.68;
    // Режим «только цифры»: LEFT NUM прижата к левому краю, RIGHT NUM — к правому.
    // Резерв на средний зазор при подборе шрифта = 0 (нет внутренних отступов у цифр),
    // плюс убраны зазоры вокруг точки-разделителя — цифры пакуются максимально плотно.
    private const NUM_EDGE_GAP_RATIO = 0.0;

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

    // BODY: блок графиков и цифр. Делится на колонки LEFT (перёд, только 2x/3x) и
    // RIGHT (зад, всегда); каждая колонка — на GRAF (сверху) и NUM (снизу) по режиму
    // displayMode. Нет связи — статус-экран на всю зону. Ширина колонок «по контенту»:
    // LEFT ровно под цифру передней (тем же шрифтом, что задняя), RIGHT — остальное.
    private function drawBody(dc as Graphics.Dc, bx as Lang.Number, by as Lang.Number,
                             bw as Lang.Number, bh as Lang.Number, connected as Lang.Boolean,
                             fg as Graphics.ColorType, fade as Graphics.ColorType) as Void {
        if (!connected) {
            drawStatus(dc, bx + bw / 2, by + bh / 2, bw, fg, fade);
            return;
        }

        var mode = (_state != null) ? _state.displayMode : DISP_NUM;
        var n = rearTotalVal();
        if (mode == DISP_GRAPH && n <= 0) {
            mode = DISP_NUM;   // нет конфигурации кассеты — показать хотя бы цифры
        }
        var fn = frontTotalVal();
        var showFront = fn >= 2;
        // Зазор вокруг точки-разделителя в блоке задней: «только цифры» — 0 (плотно),
        // иначе обычный REAR_GAP_FRAC. Используется и в подборе шрифта, и в отрисовке NUM.
        var numGapFrac = (mode == DISP_NUM) ? 0.0 : REAR_GAP_FRAC;

        // ── Вертикальные полосы GRAF/NUM (общие для обеих колонок) ──
        var grafTop = by;
        var grafH = 0;
        var numCY = by + bh / 2;
        var numH = bh;
        if (mode == DISP_BOTH) {
            var vpad = (bh * BOTH_VPAD_FRAC).toNumber();
            var top = by + vpad;
            var bot = by + bh - vpad;
            var work = bot - top;
            var vgap = (work * BOTH_VGAP_FRAC).toNumber();
            grafH = (work * BOTH_GRAF_FRAC).toNumber();
            // На малых полях график уступает высоту цифрам: если под NUM остаётся меньше,
            // чем нужно для самого мелкого числового шрифта, ужимаем GRAF (но не ниже пола).
            var numWant = (dc.getFontHeight(Graphics.FONT_NUMBER_MILD) * NUM_VFILL).toNumber();
            if (work - grafH - vgap < numWant) {
                grafH = work - vgap - numWant;
                var grafFloor = (work * BOTH_GRAF_MIN_FRAC).toNumber();
                if (grafH < grafFloor) { grafH = grafFloor; }
            }
            grafTop = top;
            var numTop = top + grafH + vgap;
            numH = bot - numTop;
            numCY = (numTop + bot) / 2;
        } else if (mode == DISP_GRAPH) {
            grafH = (bh * GRAPH_H_FRAC).toNumber();
            grafTop = by + (bh - grafH) / 2;
            numH = 0;
        }

        // ── Горизонтальное деление BODY на колонки LEFT | RIGHT ──
        var numFont = Graphics.FONT_NUMBER_MILD;
        var leftW = 0;
        var colGap = 0;
        var rightW = bw;
        var leftX = bx;
        var rightX = bx;
        if (mode == DISP_GRAPH) {
            // Только график — ширины пропорционально числу звёзд (единый слот → одинаковая
            // толщина столбиков у переда и зада).
            colGap = showFront ? (bw * COL_GAP_FRAC).toNumber() : 0;
            var usable = bw - colGap;
            var slots = n + (showFront ? fn : 0);
            leftW = showFront ? (usable * fn / slots) : 0;
            rightW = usable - leftW;
            rightX = bx + leftW + colGap;
        } else {
            // Ширина LEFT «по контенту»: ровно под цифру передней тем же шрифтом, что задняя.
            var rcur = (rearVal() < 0) ? "--" : rearVal().toString();      // неизв. задняя → "--"
            var rtot = (rearTotalVal() < 0) ? "--" : rearTotalVal().toString();
            var fstr = (frontVal() < 0) ? "--" : frontVal().toString();   // неизв. передняя → "--"
            // Резерв на средний зазор при подборе шрифта: «только цифры» — 0 (цифры к краям,
            // без внутренних отступов); «оба» — 0.5 ширины цифры передней.
            var gapRatio = (mode == DISP_NUM) ? NUM_EDGE_GAP_RATIO : 0.5;
            numFont = fitNumFont(dc, rcur, rtot, fstr, showFront, gapRatio, numGapFrac, bw, numH);
            leftW = showFront ? paddedWidth(dc, fstr, numFont) : 0;
            if (mode == DISP_NUM) {
                // Только цифры: LEFT NUM прижата к ЛЕВОМУ краю, RIGHT NUM (блок задней) —
                // к ПРАВОМУ; разрыв уходит в середину. Шрифт максимизирован под границы ROOT.
                var fhN = dc.getFontHeight(numFont);
                var innerN = (fhN * REAR_DOT_FRAC + fhN * numGapFrac).toNumber();
                var sideN = paddedWidth(dc, rcur, numFont);
                var rtotW = paddedWidth(dc, rtot, numFont);
                if (rtotW > sideN) { sideN = rtotW; }
                rightW = 2 * (innerN + sideN);                  // ширина блока задних цифр
                if (showFront) {
                    leftX = bx;                                 // LEFT NUM — к левому краю
                    rightX = bx + bw - rightW;                  // RIGHT NUM — к правому краю
                } else {
                    rightX = bx + (bw - rightW) / 2;            // 1x: задняя по центру BODY
                }
            } else {
                // Оба: задний блок заполняет широкую колонку под кассетой (выровнен с ней),
                // цифры центрируются в колонке. Зазор = половина ширины цифры передней.
                colGap = showFront ? (leftW / 2) : 0;
                rightW = bw - leftW - colGap;
                rightX = bx + leftW + colGap;
            }
        }

        // ── Толщина столбиков: высчитываем так, чтобы n задних столбиков с зазорами
        // (gap = BAR_GAP_RATIO * bar) заполнили ширину RIGHT.GRAF целиком. Передние
        // берут ту же толщину (единая толщина у переда и зада) и заполняют свою колонку
        // собственным зазором — расчёт заполнения в drawRearGraf/drawFrontGraf.
        var barW = 0;
        if (mode != DISP_NUM && n > 0) {
            barW = (rightW.toFloat() / (n + (n - 1) * BAR_GAP_RATIO)).toNumber();
            if (barW < 1) { barW = 1; }
        }

        // ── Рисуем блоки колонок ──
        if (mode != DISP_NUM) {                         // GRAF
            drawRearGraf(dc, rightX, rightW, grafTop, grafH, barW, fg, fade);
            if (showFront) {
                drawFrontGraf(dc, leftX, leftW, grafTop, grafH, barW, fg, fade);
            }
        }
        if (mode != DISP_GRAPH) {                        // NUM
            drawRearNum(dc, rightX, rightW, numCY, numFont, numGapFrac, fg, fade);
            if (showFront) {
                drawFrontNum(dc, leftX, leftW, numCY, numFont, fg, fade);
            }
        }
    }

    // RIGHT.GRAF — задняя кассета: n столбиков заполняют колонку [colX, colX+colW].
    // Бóльшая звезда — СЛЕВА (высокий столбик), меньшая — справа; высота ∝ зубьям
    // (или линейно). Толщина barW едина с передними столбиками (приходит из drawBody).
    // Текущая передача — ярко (fg), прочие — приглушённо (fade).
    private function drawRearGraf(dc as Graphics.Dc, colX as Lang.Number, colW as Lang.Number,
                                 grafTop as Lang.Number, grafH as Lang.Number, barW as Lang.Number,
                                 fg as Graphics.ColorType, fade as Graphics.ColorType) as Void {
        var n = rearTotalVal();
        if (n <= 0) {
            return;
        }
        var cur = rearVal();
        var baseline = grafTop + grafH;

        // Заполнение ширины: n столбиков толщиной bw + (n-1) зазоров заполняют colW
        // целиком (крайние столбики флешем к краям). bw приходит из drawBody (единая
        // толщина); если не влезает — локально ужимаем.
        var bw = barW;
        var gap = (n > 1) ? (colW - n * bw).toFloat() / (n - 1) : 0.0;
        if (gap < 0) {
            bw = (colW.toFloat() / (n + (n - 1) * BAR_GAP_RATIO)).toNumber();
            if (bw < 1) { bw = 1; }
            gap = (n > 1) ? (colW - n * bw).toFloat() / (n - 1) : 0.0;
        }

        // Профиль высот по зубьям, если список задан и звёзды различны.
        var teeth = (_state != null) ? _state.rearTeeth : null;
        var useTeeth = (teeth != null) && (teeth.size() == n) && (n > 1);
        var minT = 0;
        var maxT = 0;
        if (useTeeth) {
            minT = teeth[0];
            maxT = teeth[0];
            for (var i = 0; i < n; i++) {
                if (teeth[i] < minT) { minT = teeth[i]; }
                if (teeth[i] > maxT) { maxT = teeth[i]; }
            }
            if (maxT == minT) { useTeeth = false; }
        }

        for (var i = 1; i <= n; i++) {
            var frac;
            if (n == 1) {
                frac = 1.0;
            } else if (useTeeth) {
                frac = (teeth[i - 1] - minT).toFloat() / (maxT - minT);
            } else {
                frac = (i - 1).toFloat() / (n - 1);
            }
            var bh = (grafH * (0.3 + 0.7 * frac)).toNumber();
            if (bh < 2) { bh = 2; }
            // Бóльшая звезда (i=n) — СЛЕВА: позиция p = n - i (p=0 — левый край).
            var p = n - i;
            var barX = (colX + p * (bw + gap)).toNumber();
            dc.setColor((i == cur) ? fg : fade, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barX, baseline - bh, bw, bh);
        }
    }

    // LEFT.GRAF — передние звёзды: fn столбиков заполняют колонку [colX, colX+colW].
    // Слева→направо по ВОЗРАСТАНИЮ зубьев (меньшая звезда слева, бóльшая справа —
    // примыкает к высокому краю задней кассеты). Высота ∝ зубьям (или линейно).
    // Толщина barW едина с задней кассетой (из drawBody). Текущая — ярко (fg), прочие —
    // приглушённо. Для 2x/3x текущая пока не читается из BLE (front<0) → подсветки нет:
    // каркас готов к данным (см. doc/NOTES.md).
    private function drawFrontGraf(dc as Graphics.Dc, colX as Lang.Number, colW as Lang.Number,
                                  grafTop as Lang.Number, grafH as Lang.Number, barW as Lang.Number,
                                  fg as Graphics.ColorType, fade as Graphics.ColorType) as Void {
        var n = frontTotalVal();
        if (n < 2) {
            return;
        }
        var cur = frontVal();
        var baseline = grafTop + grafH;

        // Толщина bw — единая с задней; зазор — обычный (как у кассеты, BAR_GAP_RATIO),
        // а ГРУППА столбиков ЦЕНТРИРУЕТСЯ в колонке (а не растягивается на всю ширину),
        // чтобы при 2 звёздах не было огромного пустого промежутка между столбиками.
        var bw = barW;
        var gap = bw * BAR_GAP_RATIO;
        var groupW = n * bw + (n - 1) * gap;
        if (groupW > colW) {                 // не влезает — ужимаем под колонку
            bw = (colW.toFloat() / (n + (n - 1) * BAR_GAP_RATIO)).toNumber();
            if (bw < 1) { bw = 1; }
            gap = bw * BAR_GAP_RATIO;
            groupW = n * bw + (n - 1) * gap;
        }
        var startX = colX + (colW - groupW) / 2.0;   // центр группы в колонке

        // Профиль высот по зубьям передних звёзд, если список задан и звёзды различны.
        var teeth = (_state != null) ? _state.frontTeeth : null;
        var useTeeth = (teeth != null) && (teeth.size() == n);
        var minT = 0;
        var maxT = 0;
        if (useTeeth) {
            minT = teeth[0];
            maxT = teeth[0];
            for (var i = 0; i < n; i++) {
                if (teeth[i] < minT) { minT = teeth[i]; }
                if (teeth[i] > maxT) { maxT = teeth[i]; }
            }
            if (maxT == minT) { useTeeth = false; }
        }

        // Порядок слотов слева→направо: по возрастанию зубьев (меньшая звезда — слева).
        // order[pos] = 0-based индекс звезды для позиции pos. Без зубьев — натуральный.
        var order = new [n];
        for (var i = 0; i < n; i++) { order[i] = i; }
        if (useTeeth) {
            for (var a = 1; a < n; a++) {        // insertion sort по teeth asc
                var key = order[a];
                var b = a - 1;
                while (b >= 0 && teeth[order[b]] > teeth[key]) {
                    order[b + 1] = order[b];
                    b -= 1;
                }
                order[b + 1] = key;
            }
        }

        for (var pos = 0; pos < n; pos++) {
            var idx = order[pos];
            var frac = useTeeth
                ? (teeth[idx] - minT).toFloat() / (maxT - minT)
                : pos.toFloat() / (n - 1);
            var bh = (grafH * (0.3 + 0.7 * frac)).toNumber();
            if (bh < 2) { bh = 2; }
            var barX = (startX + pos * (bw + gap)).toNumber();
            dc.setColor((idx + 1 == cur) ? fg : fade, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barX, baseline - bh, bw, bh);
        }
    }

    // RIGHT.NUM — задние цифры «текущая · всего» с кружком-разделителем, центрированы
    // в колонке [colX, colX+colW] (кружок = центр колонки):
    //   • текущая — правым краем к кружку (с зазором), растёт влево;
    //   • всего   — левым краем к кружку (с зазором), растёт вправо.
    // Одиночные цифры дополняются лидирующим "0" приглушённым цветом (стабильная ширина).
    private function drawRearNum(dc as Graphics.Dc, colX as Lang.Number, colW as Lang.Number,
                               cy as Lang.Number, font as Graphics.FontDefinition, gapFrac as Lang.Float,
                               fg as Graphics.ColorType, fade as Graphics.ColorType) as Void {
        var left = (rearVal() < 0) ? "--" : rearVal().toString();        // неизв. задняя → "--"
        var right = (rearTotalVal() < 0) ? "--" : rearTotalVal().toString();
        var fh = dc.getFontHeight(font);
        var rDot = (fh * REAR_DOT_FRAC).toNumber();
        var gap = (fh * gapFrac).toNumber();   // 0 в режиме «только цифры» (цифры вплотную к точке)
        var inner = rDot + gap;   // отступ от центра до края цифры

        var dotX = colX + colW / 2;
        var dotY = cy + (fh * REAR_DOT_Y_FRAC).toNumber();   // опускаем к центру цифр
        dc.setColor(fade, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dotX, dotY, rDot);
        drawPadded(dc, dotX - inner, cy, font, left, true, fg, fade);    // текущая: правым краем
        drawPadded(dc, dotX + inner, cy, font, right, false, fg, fade);  // всего: левым краем
    }

    // LEFT.NUM — цифра текущей передней звезды, тем же шрифтом, что задние, со светлым
    // лидирующим нулём; центрирована в колонке [colX, colX+colW]. Текущая неизвестна
    // (2x/3x ещё не парсится, front<0) → приглушённый двойной прочерк "--".
    private function drawFrontNum(dc as Graphics.Dc, colX as Lang.Number, colW as Lang.Number,
                                cy as Lang.Number, font as Graphics.FontDefinition,
                                fg as Graphics.ColorType, fade as Graphics.ColorType) as Void {
        var cx = colX + colW / 2;
        var f = frontVal();
        if (f < 0) {
            dc.setColor(fade, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, font, "--",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var s = f.toString();
        // Центрируем падед-пару "0X": её ширина = paddedWidth, левый край = cx - w/2.
        var pw = paddedWidth(dc, s, font);
        drawPadded(dc, cx - pw / 2, cy, font, s, false, fg, fade);
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

    // Подбор шрифта для цифр. ПРИОРИТЕТ — числовые шрифты (крупный глиф в ячейке):
    // берём самый крупный числовой, влезающий И по высоте, И по ширине. Только если ни
    // один числовой не влез (очень низкий блок) — откатываемся на обычные шрифты как
    // меньший запас. Это важно: обычные шрифты имеют высокую ячейку при мелкой видимой
    // цифре, и при выборе «по максимальной высоте ячейки» могли бы выиграть у числового,
    // дав визуально МЕЛЬЧЕ. По высоте сверяем видимый глиф (≈ fh*NUM_VFILL). Ширина =
    // блок задних цифр (две стороны + кружок + зазоры) плюс, при 2x/3x, цифра передней +
    // зазор (gapRatio·её ширины).
    private function fitNumFont(dc as Graphics.Dc, left as Lang.String, right as Lang.String,
                              frontStr as Lang.String, showFront as Lang.Boolean, gapRatio as Lang.Float,
                              gapFrac as Lang.Float, maxWidth as Lang.Number, maxHeight as Lang.Number) as Graphics.FontDefinition {
        // Числовые — по убыванию размера: первый влезающий и есть самый крупный.
        var numFonts = [
            Graphics.FONT_NUMBER_THAI_HOT,
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD
        ];
        for (var i = 0; i < numFonts.size(); i++) {
            if (numFits(dc, numFonts[i], left, right, frontStr, showFront, gapRatio, gapFrac, maxWidth, maxHeight)) {
                return numFonts[i];
            }
        }
        // Запас: обычные шрифты (по убыванию) — первый влезающий.
        var regFonts = [
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ];
        for (var i = 0; i < regFonts.size(); i++) {
            if (numFits(dc, regFonts[i], left, right, frontStr, showFront, gapRatio, gapFrac, maxWidth, maxHeight)) {
                return regFonts[i];
            }
        }
        return Graphics.FONT_XTINY;
    }

    // Влезает ли шрифт f под цифры по высоте (видимый глиф ≈ fh*NUM_VFILL ≤ maxHeight)
    // и по ширине (блок задних цифр + при 2x/3x цифра передней с зазором ≤ maxWidth).
    // gapFrac — зазор вокруг точки-разделителя (0 в режиме «только цифры»).
    private function numFits(dc as Graphics.Dc, f as Graphics.FontDefinition,
                            left as Lang.String, right as Lang.String, frontStr as Lang.String,
                            showFront as Lang.Boolean, gapRatio as Lang.Float, gapFrac as Lang.Float,
                            maxWidth as Lang.Number, maxHeight as Lang.Number) as Lang.Boolean {
        var fh = dc.getFontHeight(f);
        if (fh * NUM_VFILL > maxHeight) {
            return false;
        }
        var inner = fh * REAR_DOT_FRAC + fh * gapFrac;
        var lw = paddedWidth(dc, left, f);
        var rw = paddedWidth(dc, right, f);
        var maxSide = (lw > rw) ? lw : rw;
        var total = 2 * (inner + maxSide);            // блок задних цифр
        if (showFront) {
            total += paddedWidth(dc, frontStr, f) * (1.0 + gapRatio);  // цифра передней + зазор
        }
        return total <= maxWidth;
    }
}
