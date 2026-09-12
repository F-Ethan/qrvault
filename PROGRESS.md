# QRVault progress

Shipped app: Flutter + Supabase, version `1.3.0+4` on `main`. This file tracks leftovers so agents do not drop them.

## Known gaps

Document out-of-scope bugs, doc drift, and follow-ups here. Add a row when you notice something you are not fixing in the current PR. Remove or rewrite a row when it is actually fixed.

- **README vs live schema.** `README.md` omits `is_pinned` and `is_public` on `qr_codes`. Nearby copy still says 500 m; the app uses a user-set radius in miles (`nearbyRadiusProvider`, default 1 mile) and `AppConstants.nearbyRadiusKm` (8 km) is unused for that setting.
- **Secrets docs vs code.** `AppConstants` imports gitignored `lib/core/constants/app_secrets.dart`. README and `dart_defines/` still describe `--dart-define-from-file`, but nothing in `lib/` reads those defines. `dart_defines/dev.json` is tracked (README claims it is gitignored).
- **No in-repo migrations.** Repository comments refer to “migration SQL” for public-row RLS. Schema/policies live only in the Supabase project. Adding columns or loosening RLS without a recorded SQL change will drift further.
- **Nearby / public geo is client-side.** `getNearby` / `getPublicNearby` select rows then Haversine-filter in Dart. Fine at small scale; not PostGIS. Do not “fix” this by substituting a mock nearby list.
- **Tests are a stub.** `test/widget_test.dart` is a placeholder. No repository, router, or widget coverage for auth, scan, or public/nearby.
- **Guest mode is memory-only.** `guestModeProvider` resets on launch. Guests cannot persist a library; save flows must keep prompting for an account rather than inventing a local store of fixture codes.
- **Android package still `com.example.qrvault`.** iOS is the maintained store target (Xcode Cloud `ios/ci_scripts/ci_post_clone.sh`). Android identity has not been productized.
- **`origin/dev` is stale.** It is behind `main`. Do not branch from it or push to it; integrate through PRs to `main`.
