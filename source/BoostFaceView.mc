import Toybox.Lang;
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Math;

// Boost BG watch face — Venu 3 (454x454 AMOLED round).
// Layout (Trio-inspired): perimeter BG ring · time+date up top · large band-coloured BG value with a
// rotated CGM trend arrow + delta in the centre · HR (left) · steps (right) · battery + staleness (bottom).
// Data: BG/trend/delta from Application.Storage (BgService pull); HR/steps/battery/date read on-device.
// The IOB/COB/loop tier the Trio face shows needs the AAPS Garmin payload extension (workstream B) —
// space is reserved for it below the value.
class BoostFaceView extends WatchUi.WatchFace {

    var _lowPower as Boolean = false;   // true in always-on (AOD) mode

    // Justify shorthands
    const CTR = Graphics.TEXT_JUSTIFY_CENTER;
    const VC  = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {}
    function onShow() as Void {}

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var bg    = BoostData.bg();
        var band  = BoostData.bgColor(bg);
        var age   = BoostData.ageMin();
        var stale = (age < 0 || age > 15);            // >15 min = 3 missed 5-min pulls
        var bgCol = stale ? 0x808080 : band;          // grey out stale BG

        var clock   = System.getClockTime();
        var timeStr = clock.hour.format("%02d") + ":" + clock.min.format("%02d");

        // ── Always-on (AOD): sparse + dim, no ring/fills (burn-in friendly) ──
        if (_lowPower) {
            dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - h * 0.20, Graphics.FONT_NUMBER_MEDIUM, timeStr, CTR);
            drawBgValue(dc, cx, cy + h * 0.08, BoostData.bgText(), stale ? 0x555555 : 0x888888, Graphics.FONT_NUMBER_MEDIUM);
            return;
        }

        // Faithful port of the Boost BG-Ring WFF face (bgring/watchface.xml, 450x450). Positions are
        // the WFF box-CENTRES and text uses VECTOR fonts at the WFF point-sizes — both scaled by
        // R = screen/450 — so the Garmin proportionally matches the Wear face.
        var R = h / 450.0;

        // ── BG ring (WFF Arc -150°..+150°, r=205, thickness 14) ──
        drawRing(dc, cx, cy, (205 * R).toNumber(), BoostData.bgFrac(bg), stale ? 0x5A5A5A : band);

        // ── date (top slot @ y63, size 24, grey-blue) ──
        dc.setColor(0xB0BEC5, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (63 * R).toNumber(), vf(24, false, R, Graphics.FONT_SMALL), dateString(), VC);

        // ── time (@ y122, size 48, white) ──
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (122 * R).toNumber(), vf(48, false, R, Graphics.FONT_NUMBER_MEDIUM), timeStr, VC);

        // ── BG (@ y191, size 80 bold, TIR-band) ──
        dc.setColor(bgCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (191 * R).toNumber(), vf(80, true, R, Graphics.FONT_NUMBER_HOT), BoostData.bgText(), VC);

        // ── delta + age + trend arrow (@ y250, size 26, grey-blue) ──
        var dy = (250 * R).toNumber();
        drawTrendArrows(dc, (cx - w * 0.17).toNumber(), dy, (h * 0.026).toNumber(), BoostData.dir(), 0xB0BEC5);
        var sub = BoostData.deltaText();
        if (age >= 0)  { sub += (sub.length() > 0 ? "     " : "") + age.toString() + "m"; }
        dc.setColor(0xB0BEC5, Graphics.COLOR_TRANSPARENT);
        dc.drawText((cx + w * 0.05).toNumber(), dy, vf(26, false, R, Graphics.FONT_SMALL), sub, VC);

        // ── IOB (@ x125) + ISF (@ x325): label y286 size 18, value y333 size 32 ──
        var lx  = (125 * R).toNumber();
        var rx  = (325 * R).toNumber();
        var iob = BoostData.iob();
        var isf = BoostData.isf();
        dc.setColor(0x90A4AE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(lx, (297 * R).toNumber(), vf(18, false, R, Graphics.FONT_XTINY), "IOB", VC);
        dc.drawText(rx, (297 * R).toNumber(), vf(18, false, R, Graphics.FONT_XTINY), "ISF", VC);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(lx, (333 * R).toNumber(), vf(32, false, R, Graphics.FONT_MEDIUM), (iob == null ? "--" : fmt1(iob) + "U"), VC);
        dc.drawText(rx, (333 * R).toNumber(), vf(32, false, R, Graphics.FONT_MEDIUM), (isf == null ? "--" : fmt1(isf)), VC);

        // ── status (bottom @ y394, size 24, teal): IOB · TBR (Boost doesn't use COB) ──
        var tbrV = BoostData.tbr();
        var st = "";
        if (iob != null)  { st += fmt1(iob) + "U"; }
        if (tbrV != null) { st += (st.length() > 0 ? "   " : "") + tbrV.format("%d") + "%"; }
        if (st.equals("")) { st = "--"; }
        dc.setColor(0x80CBC4, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (394 * R).toNumber(), vf(24, false, R, Graphics.FONT_SMALL), st, VC);
    }

    // ── BG value (s is pre-formatted for the user's units) ──
    function drawBgValue(dc, cx, cy, s, color, font) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, font, s, VC);
    }

    // Small labelled tile: grey caption above a white value.
    function drawTile(dc, x, y, label, value) as Void {
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, label, CTR);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + dc.getHeight() * 0.05, Graphics.FONT_TINY, value, CTR);
    }

    // Format a numeric (Number or Float) to one decimal place.
    function fmt1(v) as String {
        return v.toFloat().format("%.1f");
    }

    // Vector font at a WFF point-size `pt` scaled by R (= screen/450), so sizes match the Wear face
    // proportionally. `bold` picks a bold face. Falls back to `fallback` (a named font) if the device
    // has no matching vector font.
    function vf(pt, bold, R, fallback) {
        if (Graphics has :getVectorFont) {
            var faces = bold
                ? ["RobotoCondensedBold", "RobotoBold", "NanumGothicBold"]
                : ["RobotoCondensedRegular", "RobotoRegular", "NanumGothic"];
            var f = Graphics.getVectorFont({ :face => faces, :size => (pt * R).toNumber() });
            if (f != null) { return f; }
        }
        return fallback;
    }

    // Ring: dim full track + a band-coloured fill of `frac` of a 300° sweep from the top, clockwise
    // (60° gap at the bottom, mirroring the WFF -150°..+150° span). CIQ angles: 0°=3 o'clock, CCW-positive.
    function drawRing(dc, cx, cy, r, frac, color) as Void {
        // Match the Wear "bgring" WFF face: track spans WFF -150°..+150° (60° gap at the bottom).
        // WFF angle (top=0, clockwise+) -150° → CIQ angle (3-o'clock=0, CCW+) 240° = bottom-left.
        // Fill grows clockwise from there (up the left side, over the top, down to bottom-right).
        var startDeg = 240;
        var maxSweep = 300.0;
        dc.setPenWidth(14);                       // WFF Stroke thickness=14
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);   // dim track (WFF #33ffffff)
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, startDeg, startDeg - maxSweep + 360);
        if (frac > 0.0) {
            var end = startDeg - (frac * maxSweep);
            if (end < 0) { end += 360; }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, startDeg, end);
        }
    }

    // CGM trend as a clean line arrow. `ang` is SCREEN degrees (y down): the arrow points along
    // (cos,sin) — Flat=0 (right), up=-90, down=+90, 45° variants between. Double = two stacked.
    function drawTrendArrows(dc, x, y, size, dir, color) as Void {
        var ang;
        var dbl = false;
        if      (dir != null && dir.equals("DoubleUp"))      { ang = -90; dbl = true; }
        else if (dir != null && dir.equals("SingleUp"))      { ang = -90; }
        else if (dir != null && dir.equals("FortyFiveUp"))   { ang = -45; }
        else if (dir != null && dir.equals("Flat"))          { ang =   0; }
        else if (dir != null && dir.equals("FortyFiveDown")) { ang =  45; }
        else if (dir != null && dir.equals("SingleDown"))    { ang =  90; }
        else if (dir != null && dir.equals("DoubleDown"))    { ang =  90; dbl = true; }
        else {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_TINY, "-", VC);
            return;
        }
        if (dbl) {
            drawArrow(dc, x, y - size * 0.45, size, ang, color);
            drawArrow(dc, x, y + size * 0.45, size, ang, color);
        } else {
            drawArrow(dc, x, y, size, ang, color);
        }
    }

    // One arrow centred at (x,y): a shaft (tail→tip) plus two barb lines at the tip.
    function drawArrow(dc, x, y, size, ang, color) as Void {
        var a  = ang * Math.PI / 180.0;
        var ca = Math.cos(a);
        var sa = Math.sin(a);
        var tx = x + size * ca;   var ty = y + size * sa;   // tip
        var bx = x - size * ca;   var by = y - size * sa;   // tail
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(bx, by, tx, ty);
        var barb = size * 0.7;
        var a1 = a + Math.PI - 0.6;   // ~34° off the shaft
        var a2 = a + Math.PI + 0.6;
        dc.drawLine(tx, ty, tx + barb * Math.cos(a1), ty + barb * Math.sin(a1));
        dc.drawLine(tx, ty, tx + barb * Math.cos(a2), ty + barb * Math.sin(a2));
        dc.setPenWidth(1);
    }

    // Simple filled heart (two lobes + a triangle) centred at (x,y).
    function drawHeart(dc, x, y, s, color) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var lobeR = (s * 0.55).toNumber();
        var offX  = (s * 0.5).toNumber();
        var offY  = (s * 0.25).toNumber();
        dc.fillCircle(x - offX, y - offY, lobeR);
        dc.fillCircle(x + offX, y - offY, lobeR);
        dc.fillPolygon([
            [x - s, y - offY * 0.2],
            [x + s, y - offY * 0.2],
            [x,     y + s]
        ]);
    }

    // Battery: rounded outline + fill (green >30, amber >15, red else) + terminal nub.
    function drawBattery(dc, cx, cy, wpx, pct) as Void {
        if (pct == null) { pct = 0.0; }
        var bw = wpx;
        var bh = (wpx * 0.5).toNumber();
        var x0 = cx - bw / 2;
        var y0 = cy - bh / 2;
        var col = (pct > 30) ? 0x41C97B : ((pct > 15) ? 0xFFC233 : 0xFF5252);
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x0, y0, bw, bh, 2);
        dc.fillRoundedRectangle(x0 + bw + 1, y0 + bh / 4, 2, bh / 2, 1);   // nub
        var fillW = ((bw - 4) * (pct / 100.0)).toNumber();
        if (fillW < 1 && pct > 0) { fillW = 1; }
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x0 + 2, y0 + 2, fillW, bh - 4);
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + bh, Graphics.FONT_XTINY, pct.format("%d") + "%", CTR);
    }

    // Loop status as a ring (green O when fresh, amber/red as it ages, grey if unknown).
    function drawLoopRing(dc, x, y, radius, loopStr, color) as Void {
        dc.setColor((loopStr == null) ? 0x606060 : color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(5);
        dc.drawCircle(x, y, radius);
        dc.setPenWidth(1);
    }

    // Horizontal battery: icon then "NN%" to its right (matches the target row).
    function drawBatteryH(dc, x, y, wpx, pct) as Void {
        if (pct == null) { pct = 0.0; }
        var bw = wpx;
        var bh = (wpx * 0.5).toNumber();
        var x0 = x - bw / 2;
        var y0 = y - bh / 2;
        var col = (pct > 30) ? 0x41C97B : ((pct > 15) ? 0xFFC233 : 0xFF5252);
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x0, y0, bw, bh, 2);
        dc.fillRoundedRectangle(x0 + bw + 1, y0 + bh / 4, 2, bh / 2, 1);   // nub
        var fillW = ((bw - 4) * (pct / 100.0)).toNumber();
        if (fillW < 1 && pct > 0) { fillW = 1; }
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x0 + 2, y0 + 2, fillW, bh - 4);
        // % text sits just to the RIGHT of the icon (left-justified), smaller font — no overlap.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText((x + bw / 2 + 8).toNumber(), y, Graphics.FONT_XTINY, pct.format("%d") + "%",
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ── On-device data ──
    function currentHr() {
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) { return info.currentHeartRate; }
        return null;
    }

    function currentSteps() {
        var info = ActivityMonitor.getInfo();
        if (info != null && info.steps != null) { return info.steps; }
        return null;
    }

    function stepStr() as String {
        var s = currentSteps();
        if (s == null) { return "--"; }
        if (s >= 1000) {
            var k = s.toFloat() / 1000.0;
            return k.format("%.1f") + "k";
        }
        return s.toString();
    }

    function dateString() as String {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        return info.day_of_week + " " + info.day.format("%d") + " " + info.month;
    }

    function onEnterSleep() as Void { _lowPower = true;  WatchUi.requestUpdate(); }
    function onExitSleep()  as Void { _lowPower = false; WatchUi.requestUpdate(); }
}
