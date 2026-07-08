using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Lang;

// Boost BG-ring watch face. Draws from Application.Storage (populated by BgService via
// onBackgroundData). Foreground only — NOT (:background).
class BoostFaceView extends WatchUi.WatchFace {

    var _lowPower as Boolean = false;   // true in always-on (AOD) mode

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {}
    function onShow() as Void {}

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var bg    = BoostData.bg();
        var color = BoostData.bgColor(bg);
        var age   = BoostData.ageMin();
        var stale = (age < 0 || age > 15);   // >15 min = stale (3 missed 5-min pulls)

        // ── Time (top) ──
        var clock = System.getClockTime();
        var timeStr = clock.hour.format("%02d") + ":" + clock.min.format("%02d");
        dc.setColor(_lowPower ? 0x555555 : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (h * 0.34), Graphics.FONT_SMALL, timeStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (_lowPower) {
            // AOD: sparse + dim (respect Garmin's ~10% pixel / burn-in rules — no ring fill, no big fill).
            drawBgValue(dc, cx, cy, bg, stale ? 0x777777 : 0x999999, Graphics.FONT_NUMBER_MEDIUM);
            return;
        }

        // ── BG ring (full-colour, interactive only) ──
        var r = (w / 2) - 14;
        drawRing(dc, cx, cy, r, BoostData.bgFrac(bg), stale ? 0x606060 : color);

        // ── BG value (large, band-coloured) ──
        drawBgValue(dc, cx, cy, bg, stale ? 0x808080 : color, Graphics.FONT_NUMBER_HOT);

        // ── Trend + delta + age (below the value) ──
        var trend = arrowFor(BoostData.dir());
        var d = BoostData.delta();
        var sub = trend;
        if (d != null) { sub += "  " + (d >= 0 ? "+" : "") + d.format("%d"); }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (h * 0.16), Graphics.FONT_TINY, sub,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Staleness stamp — never hide that the data is old.
        if (age >= 0) {
            dc.setColor(stale ? 0xFF9F45 : 0x666666, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + (h * 0.30), Graphics.FONT_XTINY, age.toString() + "m",
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawBgValue(dc, cx, cy, bg, color, font) as Void {
        var s = (bg == null) ? "--" : bg.format("%d");
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (dc.getHeight() * 0.02), font, s,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Ring: a dim full track + a band-coloured fill of `frac` of a 300° sweep starting at the top,
    // going clockwise (60° gap at the bottom, mirroring the WFF -150°..+150° span).
    // NB the CIQ angle convention (0°=3 o'clock, CCW-positive) is the inverse of WFF's — these
    // start/sweep values are the Phase-0 best guess and MUST be eyeballed on the device/simulator.
    function drawRing(dc, cx, cy, r, frac, color) as Void {
        var startDeg = 90;                 // top (12 o'clock) in CIQ degrees
        var maxSweep = 300.0;
        dc.setPenWidth(10);
        // track
        dc.setColor(0x2A2A2A, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, startDeg, startDeg - maxSweep + 360);
        // fill
        if (frac > 0.0) {
            var end = startDeg - (frac * maxSweep);
            if (end < 0) { end += 360; }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, startDeg, end);
        }
    }

    // NS trend direction → a simple ASCII arrow (Phase 0; a custom arrow drawable comes later).
    function arrowFor(dir) as String {
        if (dir == null) { return "?"; }
        if (dir.equals("DoubleUp"))     { return "^^"; }
        if (dir.equals("SingleUp"))     { return "^"; }
        if (dir.equals("FortyFiveUp"))  { return "/"; }
        if (dir.equals("Flat"))         { return "->"; }
        if (dir.equals("FortyFiveDown")){ return "\\"; }
        if (dir.equals("SingleDown"))   { return "v"; }
        if (dir.equals("DoubleDown"))   { return "vv"; }
        return "-";
    }

    function onEnterSleep() as Void { _lowPower = true;  WatchUi.requestUpdate(); }
    function onExitSleep()  as Void { _lowPower = false; WatchUi.requestUpdate(); }
}
