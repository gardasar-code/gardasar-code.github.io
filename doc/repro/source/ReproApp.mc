using Toybox.Application;
using Toybox.BluetoothLowEnergy as Ble;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.WatchUi;

// Minimal reproduction: registering a custom 128-bit BLE service UUID crashes the
// data field on Edge Explore 2 / FW 31.33 with "System Error: Failed invoking <symbol>".
//
// Expected: registerProfile returns, and onProfileRegister reports the result.
// Actual (FW 31.33): the app dies inside the registerProfile call, in onStart.
//                    try/catch does not help - a System Error is not catchable.
// On FW 30.23 the very same code registers the profile and receives notifications.
//
// The standard Battery Service (0x180F) registers fine on FW 31.33, so the problem
// is specific to the custom 128-bit service UUID, not to registerProfile itself.

// Shimano D-Fly service/characteristic. Any other custom 128-bit UUID shows the
// same behaviour - the peripheral does not even have to be present or powered on.
const SERVICE_UUID = "000018ef-5348-494d-414e-4f5f424c4500";
const CHAR_UUID    = "00002ac1-5348-494d-414e-4f5f424c4500";

// Set to false to register the characteristic without an explicit CCCD descriptor.
// Both variants crash the same way.
const WITH_CCCD = true;

class ReproDelegate extends Ble.BleDelegate {

    public var status as Lang.String = "registering...";

    function initialize() {
        BleDelegate.initialize();
    }

    function onProfileRegister(uuid, s) {
        // Never reached on FW 31.33 for the custom service.
        status = (s == Ble.STATUS_SUCCESS) ? "registered" : ("status=" + s.toString());
    }
}

class ReproApp extends Application.AppBase {

    private var _delegate as ReproDelegate?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        var d = new ReproDelegate();
        _delegate = d;
        Ble.setDelegate(d);

        var chr = WITH_CCCD
            ? { :uuid => Ble.stringToUuid(CHAR_UUID), :descriptors => [Ble.cccdUuid()] }
            : { :uuid => Ble.stringToUuid(CHAR_UUID) };
        try {
            // FW 31.33: the application dies here. No exception is delivered.
            Ble.registerProfile({
                :uuid => Ble.stringToUuid(SERVICE_UUID),
                :characteristics => [chr]
            });
        } catch (e) {
            d.status = "exception";
        }
    }

    function getInitialView() {
        return [new ReproView(_delegate)];
    }
}

class ReproView extends WatchUi.DataField {

    private var _delegate as ReproDelegate?;

    function initialize(delegate as ReproDelegate?) {
        DataField.initialize();
        _delegate = delegate;
    }

    function compute(info) {
    }

    // Shows the registration result - on FW 31.33 it is never drawn, the field
    // is replaced by the Connect IQ error icon instead.
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.clear();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        var text = (_delegate != null) ? _delegate.status : "no delegate";
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_SMALL, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
