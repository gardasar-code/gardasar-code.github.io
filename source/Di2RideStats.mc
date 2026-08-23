using Toybox.Lang;

// Накопитель статистики заезда для session-сводки FIT: макс. передаточное отношение
// и число переключений (перёд/зад).
// Считаем только валидные секунды (есть задняя передача), чтобы простои/обрывы
// связи не искажали статистику.
//
// ИСТОРИЯ: раньше здесь копились ещё средний ratio, самая используемая комбинация,
// её доля времени и топ-3 задних звёзд. Соответствующие FIT-поля убраны в 0.0.43
// (устройство роняет дата-филд на 12-м createField, см. doc/NOTES.md), и накопление
// осталось «в никуда»: две конкатенации строк и два обращения к словарю КАЖДУЮ
// секунду на устройстве с жёстким лимитом памяти. Убрано вместе с полями.
class Di2RideStats {

    private var _maxRatio as Lang.Float = 0.0;
    private var _frontShifts as Lang.Number = 0;
    private var _rearShifts as Lang.Number = 0;
    private var _prevFront as Lang.Number = -1;
    private var _prevRear as Lang.Number = -1;

    function initialize() {
    }

    // Учесть одну секунду. front/rear — индексы передач, ratio — передаточное отношение.
    function sample(front as Lang.Number, rear as Lang.Number, ratio as Lang.Float) as Void {
        if (rear <= 0) {
            _prevRear = -1;   // нет валидной передачи — не считаем ложные переключения
            return;
        }
        if (ratio > _maxRatio) { _maxRatio = ratio; }

        if (_prevRear > 0 && rear != _prevRear) { _rearShifts += 1; }
        if (_prevFront > 0 && front > 0 && front != _prevFront) { _frontShifts += 1; }
        _prevRear = rear;
        _prevFront = front;
    }

    function maxRatio() as Lang.Float { return _maxRatio; }
    function frontShifts() as Lang.Number { return _frontShifts; }
    function rearShifts() as Lang.Number { return _rearShifts; }
}
