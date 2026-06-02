using Toybox.Lang;

// Накопитель статистики заезда для session-сводки FIT (как у продвинутых полей):
//   средний/макс. ratio, число переключений (перёд/зад), самая/редкая комбинация
//   и доля времени в ней, топ-3 самых используемых задних звёзд.
// Считаем только валидные секунды (есть задняя передача), чтобы простои/обрывы
// связи не искажали статистику.
class Di2RideStats {

    private var _samples as Lang.Number = 0;
    private var _ratioSum as Lang.Float = 0.0;
    private var _maxRatio as Lang.Float = 0.0;
    private var _frontShifts as Lang.Number = 0;
    private var _rearShifts as Lang.Number = 0;
    private var _prevFront as Lang.Number = -1;
    private var _prevRear as Lang.Number = -1;
    private var _comboSec as Lang.Dictionary = {};   // "Ft/Rt" -> секунды
    private var _rearSec as Lang.Dictionary = {};     // индекс задней -> секунды

    function initialize() {
    }

    // Учесть одну секунду. front/rear — индексы; *Teeth — зубья; ratio — отношение.
    function sample(front as Lang.Number, rear as Lang.Number,
                    frontTeeth as Lang.Number, rearTeeth as Lang.Number,
                    ratio as Lang.Float) as Void {
        if (rear <= 0) {
            _prevRear = -1;   // нет валидной передачи — не считаем ложные переключения
            return;
        }
        _samples += 1;
        _ratioSum += ratio;
        if (ratio > _maxRatio) { _maxRatio = ratio; }

        if (frontTeeth > 0 && rearTeeth > 0) {
            var key = frontTeeth.toString() + "/" + rearTeeth.toString();
            _comboSec[key] = (_comboSec.hasKey(key) ? _comboSec[key] : 0) + 1;
        }
        // топ задних звёзд считаем по ЗУБЬЯМ (rearTop вернёт зубья, не индекс)
        if (rearTeeth > 0) {
            _rearSec[rearTeeth] = (_rearSec.hasKey(rearTeeth) ? _rearSec[rearTeeth] : 0) + 1;
        }

        if (_prevRear > 0 && rear != _prevRear) { _rearShifts += 1; }
        if (_prevFront > 0 && front > 0 && front != _prevFront) { _frontShifts += 1; }
        _prevRear = rear;
        _prevFront = front;
    }

    function avgRatio() as Lang.Float { return (_samples > 0) ? _ratioSum / _samples : 0.0; }
    function maxRatio() as Lang.Float { return _maxRatio; }
    function frontShifts() as Lang.Number { return _frontShifts; }
    function rearShifts() as Lang.Number { return _rearShifts; }

    function mostCombo() as Lang.String { return comboKey(true); }
    function leastCombo() as Lang.String { return comboKey(false); }
    function mostComboPct() as Lang.Float { return pct(comboSec(true)); }
    function leastComboPct() as Lang.Float { return pct(comboSec(false)); }

    // Зубья n-й по используемости задней звезды (1 = самая частая); 0 если нет данных.
    function rearTop(n as Lang.Number) as Lang.Number {
        var keys = _rearSec.keys();
        var used = [] as Lang.Array<Lang.Number>;
        var result = 0;
        for (var rank = 0; rank < n; rank++) {
            var bestIdx = 0;
            var bestVal = -1;
            for (var i = 0; i < keys.size(); i++) {
                var idx = keys[i] as Lang.Number;
                if (contains(used, idx)) { continue; }
                var v = _rearSec[idx] as Lang.Number;
                if (v > bestVal) { bestVal = v; bestIdx = idx; }
            }
            if (bestVal < 0) { return 0; }
            used.add(bestIdx);
            result = bestIdx;
        }
        return result;
    }

    // ── приватные ──
    private function comboKey(wantMax as Lang.Boolean) as Lang.String {
        var keys = _comboSec.keys();
        var bestKey = null;
        var bestVal = 0;
        for (var i = 0; i < keys.size(); i++) {
            var v = _comboSec[keys[i]] as Lang.Number;
            if (bestKey == null || (wantMax ? v > bestVal : v < bestVal)) {
                bestKey = keys[i];
                bestVal = v;
            }
        }
        return (bestKey == null) ? "" : (bestKey as Lang.String);
    }

    private function comboSec(wantMax as Lang.Boolean) as Lang.Number {
        var keys = _comboSec.keys();
        var bestVal = -1;
        for (var i = 0; i < keys.size(); i++) {
            var v = _comboSec[keys[i]] as Lang.Number;
            if (bestVal < 0 || (wantMax ? v > bestVal : v < bestVal)) {
                bestVal = v;
            }
        }
        return (bestVal < 0) ? 0 : bestVal;
    }

    private function pct(sec as Lang.Number) as Lang.Float {
        return (_samples > 0) ? sec * 100.0 / _samples : 0.0;
    }

    private function contains(arr as Lang.Array<Lang.Number>, x as Lang.Number) as Lang.Boolean {
        for (var i = 0; i < arr.size(); i++) {
            if (arr[i] == x) { return true; }
        }
        return false;
    }
}
