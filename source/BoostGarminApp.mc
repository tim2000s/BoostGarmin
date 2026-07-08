import Toybox.Lang;
using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Background;
using Toybox.Time;
using Toybox.System;

// Boost Garmin watch face.
// Architecture (per the 2026-07-08 port plan): a watch FACE cannot receive phone pushes, so a
// background ServiceDelegate runs on the SDK-enforced 5-min temporal floor, pulls BG from the
// AAPS phone HTTP server (127.0.0.1:<port>, bridged over BLE via Garmin Connect Mobile), and
// hands the result to the foreground via onBackgroundData(), which stores it for the face to draw.
(:background)
class BoostGarminApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        registerPull();
    }

    function onStop(state as Dictionary?) as Void {
    }

    // (Re)register the 5-min background pull. The SDK clamps anything below 5 min to 5 min for
    // watch faces, so 300s is the practical floor.
    function registerPull() as Void {
        if (Toybox has :Background) {
            Background.registerForTemporalEvent(new Time.Duration(300));
        }
    }

    // Foreground view = the watch face.
    function getInitialView() {
        return [ new BoostFaceView() ];
    }

    // Background entry point — the SDK instantiates this in the background code space.
    function getServiceDelegate() {
        return [ new BgService() ];
    }

    // FOREGROUND callback when the background service exits with data. Persist + refresh.
    function onBackgroundData(data) as Void {
        if (data != null) {
            BoostData.store(data);
            WatchUi.requestUpdate();
        }
    }

    function onSettingsChanged() as Void {
        // Host/port may have changed; nothing to do beyond letting the next pull use the new value.
        WatchUi.requestUpdate();
    }
}
