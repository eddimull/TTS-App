# Booking Price Estimator — Spec & Contract

Shared spec for the Laravel backend + web UI (`/home/eddie/github/TTS`) and the Flutter app (this repo).
Decisions (from Eddie): available both as a standalone tool AND as a "Suggest price" action in the booking
create/edit forms; hybrid model (history-derived baseline + band-editable adjustments); **owners only**.

## Algorithm (backend `App\Services\PriceEstimatorService`)

All money in API payloads is **dollars as numbers** (e.g. `9750.0`). Storage of settings is JSON.

1. **Baseline per event type**
   - If the band set `base_rates[event_type_id]` → use it (source `"manual"`).
   - Else history: band's bookings of that event type, `status != cancelled`, `price > 0`, with a primary event
     that has a `date`. For each, compute a *normalized* price = `price / (season_mult(month) × dow_mult(weekday) × duration_factor(hours))`,
     then inflate to today: `× (1 + annual_increase_pct/100) ^ years_ago`. Duration from event `start_time`/`end_time`;
     **end before start means it crosses midnight (+24h)**; missing times → factor 1.0.
   - Baseline = **recency-weighted median** of normalized prices, weight `0.5 ^ (years_ago / 2)` (2-yr half-life).
     Range low/high = weighted 25th/75th percentile.
   - Need ≥ 3 samples (source `"history"`). Otherwise fall back to the band's all-types weighted median (source
     `"band_average"`, confidence low). Nothing at all → return 200 with `estimate: null` and warning `no_baseline`.
   - Confidence: `high` ≥ 10 samples, `medium` 3–9, `low` fallback.
2. **Multipliers** (applied to baseline, each shown as a breakdown line unless = 1.0):
   - Season: `season_multipliers["1".."12"]`.
   - Day of week: `day_of_week_multipliers["0".."6"]` (0 = Sunday).
   - Special date: first match in `special_dates` (`date` as `MM-DD` recurring or `YYYY-MM-DD` one-off) — replaces neither, multiplies on top.
   - Duration: `1 + overtime_pct_per_hour/100 × (hours − standard_hours)`, clamped to ≥ `min_duration_factor`.
     `standard_hours` is per event type (`standard_hours_by_type[id]`) falling back to `standard_hours`.
   - Short notice: if days until event < `short_notice_days` → `short_notice_multiplier`.
3. **Fees** (added after multipliers):
   - Travel: one-way miles from band home address to venue (Google Distance Matrix via existing `\GoogleMaps`
     facade; cache per origin/destination 30 days; or client-supplied `distance_miles`). Fee =
     `max(0, miles − free_radius_miles) × 2 × per_mile_rate`. If miles > `lodging_threshold_miles` add `lodging_fee`.
     If distance can't be resolved → no fee, warning `distance_unavailable`.
   - Add-ons: each selected key from `add_ons` adds its `amount`.
4. **Round** estimate/low/high to nearest `round_to`. Low/high get the same multipliers + fees.
5. **Warnings** (codes + human message): `no_baseline`, `low_sample`, `distance_unavailable`,
   `date_conflict` (band already has a non-cancelled booking event on that date), `band_address_missing`.
6. **Comparables**: up to 5 past bookings of that type, ranked by same-month first then most recent.

### Default settings (merged under stored JSON)
```json
{
  "season_multipliers": {"1":1.0,"2":1.0,"3":1.1,"4":1.1,"5":1.1,"6":0.9,"7":0.9,"8":0.9,"9":1.0,"10":1.1,"11":1.1,"12":1.05},
  "day_of_week_multipliers": {"0":0.9,"1":0.8,"2":0.8,"3":0.8,"4":0.85,"5":0.95,"6":1.0},
  "special_dates": [{"date":"12-31","label":"New Year's Eve","multiplier":1.5}],
  "standard_hours": 4, "standard_hours_by_type": {},
  "overtime_pct_per_hour": 15, "min_duration_factor": 0.75,
  "short_notice_days": 30, "short_notice_multiplier": 1.0,
  "annual_increase_pct": 3,
  "free_radius_miles": 50, "per_mile_rate": 2.0,
  "lodging_threshold_miles": 150, "lodging_fee": 0,
  "add_ons": [
    {"key":"production","label":"Production (sound & lights)","amount":1500},
    {"key":"ceremony","label":"Ceremony music","amount":750},
    {"key":"outdoor","label":"Outdoor event","amount":250}
  ],
  "base_rates": {},
  "round_to": 50
}
```

## Storage
New table `band_pricing_settings` (`id`, `band_id` unique FK cascade, `settings` json, timestamps), model
`BandPricingSettings`. Do **not** add columns to `bands` or alter shared models/scopes.

## API — mobile (`routes/api.php`, inside `mobile` + `auth:sanctum`, `owner` middleware, `mobile.band`)

### `POST /api/mobile/bands/{band}/price-estimate`  (name `mobile.price-estimate`)
Request:
```json
{ "event_type_id": 1, "date": "2027-05-15", "start_time": "19:00", "end_time": "23:00",
  "duration_hours": null, "venue_address": "6500 Magazine St, New Orleans, LA", "distance_miles": null,
  "add_ons": ["production"] }
```
`event_type_id` + `date` required; either times or `duration_hours` (optional; default standard hours);
`venue_address`/`distance_miles` optional. 422 on validation failure.

Response 200:
```json
{
  "estimate": 11250.0, "low": 9800.0, "high": 12600.0,
  "confidence": "high", "baseline_source": "history", "sample_size": 42,
  "baseline": 9400.0, "duration_hours": 4.0, "distance_miles": 12.3,
  "breakdown": [
    {"key":"baseline","label":"Wedding baseline (42 past bookings)","type":"base","factor":null,"amount":9400.0},
    {"key":"season","label":"May (peak season)","type":"multiplier","factor":1.1,"amount":940.0},
    {"key":"day_of_week","label":"Saturday","type":"multiplier","factor":1.0,"amount":0.0},
    {"key":"addon:production","label":"Production (sound & lights)","type":"fee","factor":null,"amount":1500.0}
  ],
  "warnings": [{"code":"date_conflict","message":"You already have a booking on May 15, 2027."}],
  "comparables": [{"booking_id":12,"name":"Smith Wedding","date":"2026-05-09","price":9800.0,"venue_name":"…"}]
}
```
`amount` on multiplier lines = the dollar delta that step contributed (sequential). Lines with factor 1.0 are omitted
except season/day_of_week, which are always shown.

### `GET /api/mobile/bands/{band}/pricing-settings`  → `{ "settings": {…merged defaults…}, "event_types": [{"id","name"}], "history": [{"event_type_id","sample_size","baseline"}] }`
### `PUT /api/mobile/bands/{band}/pricing-settings`  body `{ "settings": {…} }` (validated, partial merge ok) → same shape as GET.

## Web (Inertia + Vue 3)
- `POST /bands/{band}/price-estimate` (JSON, `owner`) — same request/response as mobile; reused by the page and forms.
- `GET /bands/{band}/price-estimator` → Inertia page `PriceEstimator/Index` (standalone tool: inputs left, result card
  with big number, range, confidence, breakdown table, warnings, comparables). Link from band nav / bookings area (owners only).
- Booking create (`BookingCreation.vue`) + edit (`BookingForm.vue`): "Suggest price" button next to price → calls estimate
  with current form fields, shows a small popover with estimate/range/breakdown and "Use this price".
- Band settings: new `Band/Components/EditPricing.vue` section via `bands/{band}/edit/pricing`, saved with
  `PATCH /bands/{band}/pricing-settings` (`owner`). Shows learned baselines per event type next to manual override inputs.

## Flutter
- `lib/features/pricing/` — `data/models/{price_estimate,pricing_settings}.dart`, `data/pricing_repository.dart`,
  `providers/`, `screens/{price_estimator_screen,pricing_settings_screen}.dart`, `widgets/estimate_result_card.dart`.
- Endpoints in `api_endpoints.dart`: `mobileBandPriceEstimate(bandId)`, `mobileBandPricingSettings(bandId)`.
- Entry points (owners only): Operations screen "Price Estimator"; Band Settings → "Pricing Rules";
  booking form FINANCIALS section "Suggest price" row → bottom sheet with result card + "Use this price" (fills `_price`).
- Routes `/price-estimator`, `/band-settings/pricing` in `router.dart`.

## Tests
- Backend: unit tests for the service (normalization, midnight crossing, weighted median, fallback, multipliers,
  travel/lodging, rounding, special dates); feature tests for mobile + web endpoints incl. 403 for non-owner members.
- Flutter: model `fromJson` tests, repository/provider tests with fakes, a widget test for the result card.
