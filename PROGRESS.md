# QRVault progress

Shipped app: Flutter + Supabase, version `1.5.0+7` on `main`. This file tracks leftovers so agents do not drop them.

## Known gaps

Document out-of-scope bugs, doc drift, and follow-ups here. Add a row when you notice something you are not fixing in the current PR. Remove or rewrite a row when it is actually fixed.

- **README vs live schema.** Nearby copy still says 500 m; the app uses a user-set radius in miles (`nearbyRadiusProvider`, default 1 mile) and `AppConstants.nearbyRadiusKm` (8 km) is unused for that setting. Apply `supabase/payload_editor.sql` in the Supabase SQL editor before saving codes with `has_date` / `has_parts` / `payload_template` / `payload_parts` or inserts will fail.
- **Payload editor limits.** Date/part rewriting only works for plain HTTP(S) query and path values. Signed, JWT, HMAC, or opaque blobs are left alone. Same-code matching uses the stored `payload_template` column (client lookup), not a Postgres function.
- **Secrets docs vs code.** `AppConstants` reads Supabase from gitignored `app_secrets.dart`. Mapbox uses `--dart-define=MAPBOX_ACCESS_TOKEN` (with `AppSecrets.mapboxAccessToken` as fallback). `dart_defines/dev.json` is still tracked with live Supabase keys; do not add the Mapbox token to that file. Xcode Cloud should set `MAPBOX_ACCESS_TOKEN` so `ios/ci_scripts/ci_post_clone.sh` can bake it into the archive.
- **No in-repo migrations.** Repository comments refer to “migration SQL” for public-row RLS. Schema/policies live only in the Supabase project. Adding columns or loosening RLS without a recorded SQL change will drift further.
- **Nearby / public geo is client-side.** `getNearby` / `getPublicNearby` select rows then Haversine-filter in Dart. Fine at small scale; not PostGIS. Do not “fix” this by substituting a mock nearby list. The explore map clusters in the client and fuzzes pin display (~150 m); exact `first_scanned_*` / `last_scanned_*` coords are still stored.
- **Tests are a stub.** `test/widget_test.dart` is a placeholder. No repository, router, or widget coverage for auth, scan, or public/nearby.
- **Guest mode is memory-only.** `guestModeProvider` resets on launch. Guests cannot persist a library; save flows must keep prompting for an account rather than inventing a local store of fixture codes.
- **Android package still `com.example.qrvault`.** iOS is the maintained store target (Xcode Cloud `ios/ci_scripts/ci_post_clone.sh`). Android identity has not been productized.
- **Flutter iOS still on CocoaPods.** Do not `pod deintegrate` until we migrate `ios/` to SPM on purpose. Plugin deprecation warnings (`mobile_scanner`, `share_plus`, `geolocator_apple`) are upstream and do not fail the archive. Xcode Cloud must install Flutter via git (`ci_post_clone.sh`), not Homebrew, so `xcode_backend.sh` exists for the archive Run Script.
- **`origin/dev` is stale.** It is behind `main`. Do not branch from it or push to it; integrate through PRs to `main`.
