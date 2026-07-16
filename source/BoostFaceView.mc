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
            drawBgValue(dc, cx, cy + h * 0.08, bg, stale ? 0x555555 : 0x888888, Graphics.FONT_NUMBER_MEDIUM);
            return;
        }

        // ── Perimeter BG ring (300° sweep, band-coloured fill over a dim track) ──
        var r = (w / 2) - 12;
        drawRing(dc, cx, cy, r, BoostData.bgFrac(bg), stale ? 0x5A5A5A : band);

        // ── Time + date (top) ──
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.155, Graphics.FONT_NUMBER_MEDIUM, timeStr, CTR);
        dc.setColor(0x8A8A8A, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.285, Graphics.FONT_XTINY, dateString(), CTR);

        // ── BG hero (centre) + trend arrow + delta ──
        // Value sits slightly left of centre so the arrow has room to its right.
        drawBgValue(dc, cx - w * 0.10, cy - h * 0.015, bg, bgCol, Graphics.FONT_NUMBER_HOT);
        drawTrendArrows(dc, (cx + w * 0.235).toNumber(), cy.toNumber(), (h * 0.055).toNumber(),
                        BoostData.dir(), bgCol);

        var d = BoostData.delta();
        if (d != null) {
            var ds = (d >= 0 ? "+" : "") + d.format("%d");
            dc.setColor(0xB0B0B0, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + h * 0.135, Graphics.FONT_SMALL, ds, CTR);
        }

        // ── HR (left) ──
        var hx = (cx - w * 0.255).toNumber();
        var hy = (cy + h * 0.015).toNumber();
        var hr = currentHr();
        drawHeart(dc, hx, hy, (h * 0.028).toNumber(), 0xFF5252);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(hx, hy + h * 0.075, Graphics.FONT_TINY, (hr == null ? "--" : hr.toString()), CTR);

        // ── Steps (right) ──
        var sx = (cx + w * 0.255).toNumber();
        var sy = hy;
        dc.setColor(0x7EC8FF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(sx, sy - h * 0.045, Graphics.FONT_XTINY, "STEPS", CTR);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(sx, sy + h * 0.075, Graphics.FONT_TINY, stepStr(), CTR);

        // ── Staleness stamp (bottom, above battery) — never hide old data ──
        if (age >= 0) {
            dc.setColor(stale ? 0xFF9F45 : 0x707070, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + h * 0.245, Graphics.FONT_XTINY, age.toString() + "m", CTR);
        }

        // ── Battery (bottom) ──
        drawBattery(dc, cx, (h * 0.85).toNumber(), (w * 0.10).toNumber(), System.getSystemStats().battery);
    }

    // ── BG value ──
    function drawBgValue(dc, cx, cy, bg, color, font) as Void {
        var s = (bg == null) ? "--" : bg.format("%d");
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, font, s, VC);
    }

    // Ring: dim full track + a band-coloured fill of `frac` of a 300° sweep from the top, clockwise
    // (60° gap at the bottom, mirroring the WFF -150°..+150° span). CIQ angles: 0°=3 o'clock, CCW-positive.
    function drawRing(dc, cx, cy, r, frac, color) as Void {
        var startDeg = 90;              // 12 o'clock
        var maxSweep = 300.0;
        dc.setPenWidth(10);
        dc.setColor(0x262626, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, startDeg, startDeg - maxSweep + 360);
        if (frac > 0.0) {
            var end = startDeg - (frac * maxSweep);
            if (end < 0) { end += 360; }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, startDeg, end);
        }
    }

    // CGM trend as rotated filled arrow(s): Double* draws two stacked arrows, single one.
    // Visual angle: up = +90°, Flat = 0° (points right), down = -90°.
    function drawTrendArrows(dc, x, y, size, dir, color) as Void {
        if (dir == null) {
            dc.setColor(0x808080, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_SMALL, "?", VC);
            return;
        }
        var ang;
        var count = 1;
        if      (dir.equals("DoubleUp"))      { ang =  90; count = 2; }
        else if (dir.equals("SingleUp"))      { ang =  90; }
        else if (dir.equals("FortyFiveUp"))   { ang =  45; }
        else if (dir.equals("Flat"))          { ang =   0; }
        else if (dir.equals("FortyFiveDown")) { ang = -45; }
        else if (dir.equals("SingleDown"))    { ang = -90; }
        else if (dir.equals("DoubleDown"))    { ang = -90; count = 2; }
        else {
            dc.setColor(0x808080, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_SMALL, "-", VC);
            return;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (count == 2) {
            // stack the pair along the arrow's perpendicular so both point the same way
            var ox = (Math.cos((ang) * Math.PI / 180.0) * size * 0.55);
            var oy = (Math.sin((ang) * Math.PI / 180.0) * size * 0.55);
            drawArrow(dc, x - ox, y + oy, size, ang, color);
            drawArrow(dc, x + ox, y - oy, size, ang, color);
        } else {
            drawArrow(dc, x, y, size, ang, color);
        }
    }

    // One filled arrow centred at (x,y), pointing at visual angle `ang` (deg; up=+90). Screen y is
    // down, so we negate the rotated y to make +angle point up.
    function drawArrow(dc, x, y, size, ang, color) as Void {
        var a = ang * Math.PI / 180.0;
        var ca = Math.cos(a);
        var sa = Math.sin(a);
        // arrow in local frame (pointing +x): tip, two barbs, shaft rectangle back.
        var pts = [
            [ size,        0.0        ],   // tip
            [ size * 0.15, -size * 0.7 ],   // upper barb
            [ size * 0.15, -size * 0.28],
            [-size,        -size * 0.28],   // shaft back-upper
            [-size,         size * 0.28],   // shaft back-lower
            [ size * 0.15,  size * 0.28],
            [ size * 0.15,  size * 0.7 ]    // lower barb
        ];
        var scr = new [pts.size()];
        for (var i = 0; i < pts.size(); i++) {
            var px = pts[i][0];
            var py = pts[i][1];
            var rx = px * ca - py * sa;
            var ry = px * sa + py * ca;
            scr[i] = [ x + rx, y - ry ];   // negate ry: math-up -> screen-up
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(scr);
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
