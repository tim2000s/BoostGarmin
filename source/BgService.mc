using Toybox.System;
using Toybox.Background;
using Toybox.Communications;
using Toybox.Application;
using Toybox.Time;

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

    function onTemporalEvent() as Void {
        var host = BoostData.host();
        var port = BoostData.port();
        var url = "http://" + host + ":" + port.toString() + "/sgv.json";
        var params = { "count" => 12, "brief_mode" => "true" };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(url, params, options, method(:onReceive));
    }

    // NS SGV objects: { "sgv": <mgdl>, "direction": "<Flat|FortyFiveUp|...>", "date": <ms>, "delta": <n> }
    function onReceive(code as Number, data) as Void {
        if (code == 200 && data != null && data instanceof Toybox.Lang.Array && data.size() > 0) {
            var latest = data[0];            // newest first
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

    function numOrNull(d, key) {
        if (d != null && d.hasKey(key) && d[key] != null) { return d[key]; }
        return null;
    }
}
