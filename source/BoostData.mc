import Toybox.Lang;
using Toybox.Application;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Time;

// Shared data + visual constants. Storage write happens in the foreground (onBackgroundData);
// host()/port() are also read in the background, so this module is (:background)-safe.
(:background)
module BoostData {

    // ── Storage keys ──
    const K_BG    = "bg";
    const K_DIR   = "dir";
    const K_DELTA = "delta";
    const K_SGVMS = "sgvMs";     // sensor timestamp of the reading (ms)
    const K_UPDMS = "updMs";     // when WE last got a good pull (for staleness)
    const K_OK    = "ok";
    const K_IOB   = "iob";       // bolus+basal IOB (U)
    const K_COB   = "cob";       // carbs on board (g)
    const K_TBR   = "tbr";       // temp basal rate (%)
    const K_LOOP  = "loop";      // loop status string (CLOSED/OPEN/LGS/SUSPEND/…)
    const K_LOOPMS= "loopMs";    // epoch-ms of the last APS run (loop freshness)

    // ── Settings (from resources/settings/settings.xml) ──
    function host() as String {
        var h = Application.Properties.getValue("aapsHost");
        return (h == null) ? "127.0.0.1" : h;
    }
    function port() as Number {
        var p = Application.Properties.getValue("aapsPort");
        return (p == null) ? 28891 : p;
    }

    // Persist a background pull result (foreground context).
    function store(data) as Void {
        var ok = (data.hasKey("ok") && data["ok"] == true);
        Application.Storage.setValue(K_OK, ok);
        if (ok) {
            Application.Storage.setValue(K_BG,    data["bg"]);
            Application.Storage.setValue(K_DIR,   data["dir"]);
            Application.Storage.setValue(K_DELTA, data["delta"]);
            Application.Storage.setValue(K_SGVMS, data["sgvMs"]);
            Application.Storage.setValue(K_IOB,   data["iob"]);
            Application.Storage.setValue(K_COB,   data["cob"]);
            Application.Storage.setValue(K_TBR,   data["tbr"]);
            Application.Storage.setValue(K_LOOP,  data["loop"]);
            Application.Storage.setValue(K_LOOPMS,data["loopMs"]);
            Application.Storage.setValue(K_UPDMS, System.getTimer());
        }
        // On failure we keep the last-good values and just let the age grow (honest staleness).
    }

    function bg()    { return Application.Storage.getValue(K_BG); }
    function dir()   { return Application.Storage.getValue(K_DIR); }
    function delta() { return Application.Storage.getValue(K_DELTA); }
    function iob()   { return Application.Storage.getValue(K_IOB); }
    function cob()   { return Application.Storage.getValue(K_COB); }
    function tbr()   { return Application.Storage.getValue(K_TBR); }
    function loop()  { return Application.Storage.getValue(K_LOOP); }

    // Minutes since the last APS run (loop freshness), or -1 if unknown.
    function loopAgeMin() as Number {
        var s = Application.Storage.getValue(K_LOOPMS);
        if (s == null) { return -1; }
        var nowMs = Time.now().value().toLong() * 1000;
        return ((nowMs - s) / 60000).toNumber();
    }

    // Loop pill colour: green if it ran in the last ~7 min, amber if older, grey if unknown.
    function loopColor() as Number {
        var a = loopAgeMin();
        if (a < 0)   { return 0x808080; }
        if (a <= 7)  { return 0x41C97B; }
        if (a <= 20) { return 0xFFC233; }
        return 0xFF5252;
    }

    // Minutes since the reading's sensor timestamp (staleness the face shows).
    function ageMin() as Number {
        var s = Application.Storage.getValue(K_SGVMS);
        if (s == null) { return -1; }
        var nowMs = Time.now().value().toLong() * 1000;
        return ((nowMs - s) / 60000).toNumber();
    }

    // ── BG colour bands (WFF DigitalStyle spec, mg/dL) ──
    //   <54 dark-red · 54-69 orange · 70-180 green · 180-250 amber · >250 red
    function bgColor(v) as Number {
        if (v == null)       { return 0x808080; }   // grey = no data
        if (v < 54)          { return 0xC62828; }
        if (v < 70)          { return 0xFF9F45; }
        if (v <= 180)        { return 0x41C97B; }
        if (v <= 250)        { return 0xFFC233; }
        return 0xFF5252;
    }

    // Ring fill fraction 0..1. WFF: norm*1.476 with norm=(bg-40)/310 → full sweep at BG 250.
    // Simplified to (bg-40)/210, clamped. (250-40 = 210.)
    function bgFrac(v) as Float {
        if (v == null) { return 0.0; }
        var f = (v - 40).toFloat() / 210.0;
        if (f < 0.0) { f = 0.0; }
        if (f > 1.0) { f = 1.0; }
        return f;
    }
}
