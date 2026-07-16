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

        // Faithful port of the Boost BG-Ring WFF face
        // (BoostWFFVariants/watchface/src/bgring/res/raw/watchface.xml, 450x450). Every y/x below is a
        // WFF box-centre ÷ 450, so proportions match the Wear face exactly.

        // ── BG ring: WFF Arc -150°..+150° (60° gap at the bottom), r = 205/450, thickness 14. ──
        drawRing(dc, cx, cy, (w * 0.456).toNumber(), BoostData.bgFrac(bg), stale ? 0x5A5A5A : band);

        // NB: the WFF grid (450px) packs time+BG almost touching because its fonts fit their boxes
        // exactly; Garmin's NUMBER_* fonts are taller, so the stack is spread wider than the raw WFF
        // y's to avoid overlap while keeping the same order/proportions.

        // ── Top slot: date (grey-blue) ──
        dc.setColor(0xB0BEC5, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.115).toNumber(), Graphics.FONT_TINY, dateString(), VC);

        // ── Time ──
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.250).toNumber(), Graphics.FONT_NUMBER_MILD, timeStr, VC);

        // ── BG hero: TIR-band coloured ──
        drawBgValue(dc, cx, (h * 0.455).toNumber(), BoostData.bgText(), bgCol, Graphics.FONT_NUMBER_MEDIUM);

        // ── delta + age + trend arrow (grey-blue) ──
        var dy = (h * 0.610).toNumber();
        drawTrendArrows(dc, (cx - w * 0.17).toNumber(), dy, (h * 0.028).toNumber(), BoostData.dir(), 0xB0BEC5);
        var sub = BoostData.deltaText();
        if (age >= 0)  { sub += (sub.length() > 0 ? "     " : "") + age.toString() + "m"; }
        dc.setColor(0xB0BEC5, Graphics.COLOR_TRANSPARENT);
        dc.drawText((cx + w * 0.05).toNumber(), dy, Graphics.FONT_TINY, sub, VC);

        // ── IOB (left) + ISF (right): grey label over white value ──  WFF x40/x240, y286 label / y308 value
        var lx  = (w * 0.278).toNumber();
        var rx  = (w * 0.722).toNumber();
        var iob = BoostData.iob();
        var isf = BoostData.isf();
        dc.setColor(0x90A4AE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(lx, (h * 0.700).toNumber(), Graphics.FONT_XTINY, "IOB", VC);
        dc.drawText(rx, (h * 0.700).toNumber(), Graphics.FONT_XTINY, "ISF", VC);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(lx, (h * 0.775).toNumber(), Graphics.FONT_SMALL, (iob == null ? "--" : fmt1(iob) + "U"), VC);
        dc.drawText(rx, (h * 0.775).toNumber(), Graphics.FONT_SMALL, (isf == null ? "--" : fmt1(isf)), VC);

        // ── Status line (bottom, teal): compound details like the Wear bgring bottom slot
        //    (COB · IOB · TBR), not the bare loop mode. ──
        var cobV = BoostData.cob();
        var tbrV = BoostData.tbr();
        var st = "";
        if (cobV != null) { st += cobV.format("%d") + "g"; }
        if (iob != null)  { st += (st.length() > 0 ? "  " : "") + fmt1(iob) + "U"; }
        if (tbrV != null) { st += (st.length() > 0 ? "  " : "") + tbrV.format("%d") + "%"; }
        if (st.equals("")) { st = "--"; }
        dc.setColor(0x80CBC4, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.900).toNumber(), Graphics.FONT_TINY, st, VC);
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
