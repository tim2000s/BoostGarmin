using Toybox.Application;
using Toybox.Graphics;
using Toybox.System;

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
            Application.Storage.setValue(K_UPDMS, System.getTimer());
        }
        // On failure we keep the last-good values and just let the age grow (honest staleness).
    }

    function bg()    { return Application.Storage.getValue(K_BG); }
    function dir()   { return Application.Storage.getValue(K_DIR); }
    function delta() { return Application.Storage.getValue(K_DELTA); }

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
