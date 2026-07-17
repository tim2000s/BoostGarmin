# Connect IQ Store listing — Boost BG Ring

Draft copy for the store submission. Edit to taste before uploading.

## Package
- **File to upload:** `boost.iq` (built with `monkeyc -f monkey.jungle -o boost.iq -y developer_key -e -r -w`)
- **App id:** `c87388c1f2c74b3baec0ed1d11af74de` (stable — never regenerate)
- **Signing key:** `developer_key` — back it up; every update must use the same one.
- **Devices:** 95 round watches (46 AMOLED, 49 MIP), CIQ ≥ 3.2.0. All build-verified.

## Name
Boost BG Ring

## Category
Watch Faces

## Short description (one line)
Glucose, trend and loop status at a glance for AndroidAPS / Boost users.

## Full description
Boost BG Ring is a companion watch face for **AndroidAPS** (and the Boost fork). It
shows your current glucose inside a colour-banded ring, with trend arrow and delta,
plus the loop's insulin-on-board, temp basal and dynamic ISF, and your heart rate and
steps — laid out to mirror the Boost Wear face.

- Colour-banded BG ring (low / in-range / high) with trend arrow and 5-minute delta
- IOB · temp basal · DynISF from the loop
- On-device heart rate and step count
- mmol/L or mg/dL automatically, matching your AndroidAPS setting
- Honest staleness: the reading greys out rather than showing an old value as current
- Battery-friendly always-on (AOD) mode

**Requires AndroidAPS with the Garmin data source enabled** — the face pulls glucose
and loop data from the AndroidAPS phone app over the Garmin Connect bridge. Without an
AndroidAPS phone running that data source it will show no data. This is a tool for
people already running AndroidAPS/Boost; it is not a standalone CGM display.

Not affiliated with Garmin or Dexcom. Boost/AndroidAPS is DIY open-source software; use
at your own risk.

## Screenshots
In `store_assets/` — one per resolution family, populated with sample data:
`venu3_454.png`, `venu2_416.png`, `vivoactive5_390.png`, `fenix7_260.png` (MIP).

## Pricing
Free.

## Languages
English.
