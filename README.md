# Boost Garmin watch face

A Connect IQ (Monkey C) BG watch face for Garmin, first target **Venu 3** (454×454 AMOLED round).
Companion to the Wear OS Boost WFF faces. Plan: `resume-point` / `garmin-watchface-port-2026-07-08`.

## Architecture (why it's built this way)
A Garmin **watch face cannot receive a phone push**. So a background `ServiceDelegate` runs on the
SDK-enforced **5-minute** temporal floor and pulls BG from the **AAPS phone HTTP server**
(`http://127.0.0.1:<port>/sgv.json`, bridged over BLE via Garmin Connect Mobile), then hands it to
the foreground via `onBackgroundData()`, which stores it for the face's `onUpdate` to draw. No
Nightscout — the source is AAPS on the phone (matches Tim's plumbing).

```
BgService.onTemporalEvent → makeWebRequest(127.0.0.1:28891/sgv.json) → Background.exit(data)
  → App.onBackgroundData → BoostData.store → Storage → BoostFaceView.onUpdate draws
```

## Files
- `manifest.xml` — app id, `type=watchface`, product `venu3`, permissions `Communications` + `Background`.
- `source/BoostGarminApp.mc` — registers the 5-min pull; wires background↔face.
- `source/BgService.mc` — the pull (GET `/sgv.json?count=12&brief_mode=true`).
- `source/BoostFaceView.mc` — renders time, BG value (band-coloured), BG ring, trend, staleness; AOD-dim layer.
- `source/BoostData.mc` — storage keys, host/port settings, WFF colour bands + ring formula.
- `resources/` — settings (host/port), strings, launcher icon (**placeholder — replace with a real one**).

## Status — Phase 0 (BG display only)
- BG value + ring + trend + staleness from the STOCK AAPS payload. **No Boost fields yet**
  (DynISF / state / TIR need the AAPS-side payload extension = Workstream B, below).
- NOT yet compiled — the Connect IQ SDK is not installed here (see Build).

## Build (needs the Connect IQ SDK — not installed yet)
1. Install the **Connect IQ SDK Manager** (Garmin developer account) and the **Venu 3** device.
2. Generate a **developer key** (4096-bit RSA) — `openssl genrsa -out developer_key.pem 4096` then
   convert to DER: `openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key -nocrypt`.
   **BACK IT UP** — lose it and you can never update a published face.
3. Build:  `monkeyc -d venu3 -f monkey.jungle -o boost.prg -y developer_key`
4. Sideload: copy `boost.prg` to `GARMIN/APPS/` on the mounted watch. Or run in the simulator:
   `connectiq` then `monkeydo boost.prg venu3`.

## Phase-0 verification checklist (the plan's load-bearing unknowns)
- [ ] The background `ServiceDelegate` can reach `127.0.0.1:28891` through the Garmin Connect bridge
      (enable the AAPS HTTP server first: Config → Garmin → communication_http_port).
- [ ] The CIQ background memory ceiling is enough for the pull + JSON parse (Venu 3 has headroom).
- [ ] The BG **ring angles** render correctly (WFF 0°=top/CW vs CIQ 0°=3-o'clock/CCW — the ring
      start/sweep in `drawRing` is a best guess and needs eyeballing).

## Next
- **Workstream B (priority): HR + steps INTO AAPS.** AAPS-side: add `/hr` + `/steps` batch endpoints
  and extend the payload with Boost fields (DynISF/state/TIR). Face-side: read `getHeartRateHistory`
  (1-min samples + 5-min max/min) and `ActivityMonitor.getInfo().steps` (delta) and POST them.
- Real launcher icon + trend-arrow drawable; TIR/HR ring variants; more devices.
