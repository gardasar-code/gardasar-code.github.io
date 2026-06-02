using Toybox.Lang;

// Разделяемое состояние между BLE-делегатом (писатель) и View (читатель).
// Один экземпляр создаётся в Di2FieldApp и передаётся обоим.
// Значение -1 означает «нет данных» (рисуем "---").
class Di2State {

    public var connected as Lang.Boolean = false;  // есть ли активное BLE-соединение
    public var rear as Lang.Number = -1;            // текущая задняя передача (1-based)
    public var rearTotal as Lang.Number = -1;       // число задних передач
    public var front as Lang.Number = -1;           // текущая передняя передача (1-based)
    public var frontTotal as Lang.Number = -1;      // число передних передач
    public var battery as Lang.Number = -1;         // заряд D-Fly, % (0..100)

    // Отладка калибровки: hex последнего gear-пакета + его длина.
    // Показывается на экране при DEBUG_OVERLAY, чтобы вручную найти байт передней.
    public var dbgGear as Lang.String = "";

    function initialize() {
    }

    // Сбросить «живые» данные (при потере соединения): задняя передача и батарея.
    // Не трогаем front/frontTotal/rearTotal — это конфигурация (из настроек), а не
    // данные BLE; они переживают реконнект.
    function resetLiveData() as Void {
        rear = -1;
        battery = -1;
    }
}
