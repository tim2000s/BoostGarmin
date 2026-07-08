import Toybox.Lang;
using Toybox.System;
using Toybox.Background;
using Toybox.Communications;
using Toybox.Application;
using Toybox.Time;
using Toybox.PersistedContent;
using Toybox.ActivityMonitor;

// Background pull from the AAPS phone HTTP server.
// Endpoint (AAPS Garmin plugin HttpServer): GET http://127.0.0.1:<port>/sgv.json?count=12&brief_mode=true
// Returns a Nightscout-format SGV array (newest first). NB the AAPS server is OFF by default — the
// user must enable it (Config > Garmin > "communication_http_port") for this to return data.
//
// Phase 0 = BG + trend only, from the STOCK AAPS payload (no Boost fields yet). Workstream-B
// (AAPS-side /hr, /steps and Boost-enriched payload) + the DynISF/state/TIR fields come later.
(:background)
class BgService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    // One background pass does BOTH directions on the same wake (workstream B):
    //   1. POST fine-grained HR samples to AAPS /hr, then
    //   2. GET BG from /sgv.json (its callback ends the session).
    function onTemporalEvent() as Void {
        sendHeartRatesThenFetchBg();
    }

    function base() as String {
        return "http://" + BoostData.host() + ":" + BoostData.port().toString();
    }

    // Read the last 5 min of firmware-logged HR at ~1-min resolution and POST it. Peak preservation
    // is on the AAPS side (hrBpmMax5m over the 1-min rows), so we just ship the samples.
    function sendHeartRatesThenFetchBg() as Void {
        var samples = readHrSamples();
        if (samples.length() > 0) {
            var options = { :method => Communications.HTTP_REQUEST_METHOD_GET };
            Communications.makeWebRequest(base() + "/hr",
                { "device" => "venu3", "samples" => samples }, options, method(:onHrSent));
        } else {
            fetchBg();
        }
    }

    // HR POST done (success or not) → send steps.
    function onHrSent(code as Number, data as Null or Dictionary or String or PersistedContent.Iterator) as Void {
        sendStepsThenFetchBg();
    }

    // Steps: getInfo().steps is a CUMULATIVE daily counter (resets ~0 at device-midnight). We keep a
    // ring buffer of recent (tSec, cumulative) in Storage and compute the six trailing-window deltas
    // (reset-resilient: a negative delta = a midnight reset → use the current cumulative).
    function sendStepsThenFetchBg() as Void {
        var info = ActivityMonitor.getInfo();
        var cum = (info != null && info.steps != null) ? info.steps : null;
        if (cum == null) { fetchBg(); return; }
        var nowSec = Time.now().value();

        var buf = Application.Storage.getValue("stepBuf");
        if (!(buf instanceof Array)) { buf = []; }
        var cutoff = nowSec - 180 * 60;
        var pruned = [];
        for (var i = 0; i < buf.size(); i++) {
            if (buf[i] instanceof Array && buf[i][0] >= cutoff) { pruned.add(buf[i]); }
        }
        buf = pruned;

        var params = {
            "device" => "venu3", "t" => nowSec,
            "s5"  => deltaOver(buf, cum, nowSec, 5),
            "s10" => deltaOver(buf, cum, nowSec, 10),
            "s15" => deltaOver(buf, cum, nowSec, 15),
            "s30" => deltaOver(buf, cum, nowSec, 30),
            "s60" => deltaOver(buf, cum, nowSec, 60),
            "s180"=> deltaOver(buf, cum, nowSec, 180)
        };
        buf.add([nowSec, cum]);
        Application.Storage.setValue("stepBuf", buf);

        Communications.makeWebRequest(base() + "/steps", params,
            { :method => Communications.HTTP_REQUEST_METHOD_GET }, method(:onStepsSent));
    }

    function onStepsSent(code as Number, data as Null or Dictionary or String or PersistedContent.Iterator) as Void {
        fetchBg();
    }

    // Steps over the last `minutes`: cumulative_now − cumulative_at(≈minutes ago). Uses the EARLIEST
    // buffered sample within the window as the base. Reset-resilient. 0 if no history in window.
    function deltaOver(buf as Array, cum as Number, nowSec as Number, minutes as Number) as Number {
        var target = nowSec - minutes * 60;
        var base = null;
        for (var i = 0; i < buf.size(); i++) {
            if (buf[i][0] >= target && buf[i][0] <= nowSec) { base = buf[i][1]; break; }  // earliest in window
        }
        if (base == null) { return 0; }
        var d = cum - base;
        return (d < 0) ? cum : d;   // negative = midnight reset
    }

    // "<tSec>:<bpm>,<tSec>:<bpm>,..." for valid 1-min samples in the last 5 min.
    function readHrSamples() as String {
        var it = ActivityMonitor.getHeartRateHistory(new Time.Duration(300), true);
        if (it == null) { return ""; }
        var s = "";
        var sample = it.next();
        while (sample != null) {
            var hr = sample.heartRate;
            if (hr != null && hr != ActivityMonitor.INVALID_HR_SAMPLE && sample.when != null) {
                var tSec = sample.when.value();
                if (s.length() > 0) { s += ","; }
                s += tSec.toString() + ":" + hr.toString();
            }
            sample = it.next();
        }
        return s;
    }

    function fetchBg() as Void {
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(base() + "/sgv.json",
            { "count" => 12, "brief_mode" => "true" }, options, method(:onReceive));
    }

    // NS SGV objects: { "sgv": <mgdl>, "direction": "<Flat|FortyFiveUp|...>", "date": <ms>, "delta": <n> }
    // /sgv.json returns a JSON ARRAY (newest first). The callback param must be a supertype of the
    // makeWebRequest data union, so it lists Array + the required Dictionary/String/Iterator members.
    function onReceive(
        code as Number,
        data as Null or Dictionary or String or PersistedContent.Iterator
    ) as Void {
        // /sgv.json actually returns a JSON Array (not in the SDK's declared union), so widen to
        // Object, then runtime-check + narrow to Array.
        var obj = data as Object?;
        if (code == 200 && obj != null && obj instanceof Array && (obj as Array).size() > 0) {
            var latest = (obj as Array)[0] as Dictionary;   // newest first
            var out = {
                "bg"    => numOrNull(latest, "sgv"),
                "dir"   => (latest.hasKey("direction") ? latest["direction"] : null),
                "delta" => numOrNull(latest, "delta"),
                "sgvMs" => numOrNull(latest, "date"),
                "ok"    => true,
                "code"  => code
            };
            Background.exit(out);
        } else {
            // Fail visibly: the face shows staleness rather than a lie. -104 = no BLE/phone.
            Background.exit({ "ok" => false, "code" => code });
        }
    }

    function numOrNull(d as Dictionary, key as String) {
        if (d != null && d.hasKey(key) && d[key] != null) { return d[key]; }
        return null;
    }
}
