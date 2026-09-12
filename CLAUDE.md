# QRVault — Agent working rules

QRVault is a Flutter app for scanning, creating, and managing QR codes. Codes live in Supabase and sync per signed-in user. Visual design is in `STYLE_GUIDE.md`. Local setup is in `README.md`. Out-of-scope work and leftover issues go in `PROGRESS.md` → **Known gaps**.

This file is the committed agent contract. `.claude/` is gitignored local memory — do not commit it.

## Process

These rules are non-negotiable.

- **Never work or push to `main`.** Do not commit on `main`, force-push `main`, or merge locally into `main`. `origin/dev` exists but is behind `main` — do not treat `dev` as the integration branch and do not push to it.
- **Every new feature or fix is a branch + PR.** Branch from the latest `origin/main`. Open a pull request targeting `main`. Do not land work by committing straight to a shared branch.
- **Document out-of-scope issues explicitly.** If you find a bug, doc drift, missing migration, or follow-up that is not part of the current change, add it to `PROGRESS.md` → **Known gaps**. Do not silently skip it, and do not expand the PR to “while we’re here” unless the user asked.
- **Shipped features use the real backend.** Screens, Riverpod providers, and repositories that serve live data must call Supabase (Auth + the `qr_codes` table). Never use mock lists, fixture JSON, or hardcoded sample codes as the app’s data source. Test-only mocks, fakes, and `ProviderScope` overrides in `test/` are fine.

## Stack

| Concern | What this repo uses |
|---|---|
| App | Flutter / Dart (`sdk: '>=3.4.0 <4.0.0'`), Material 3 |
| Backend / Auth | `supabase_flutter` — email/password Auth, `qr_codes` table, RLS |
| State | `flutter_riverpod` (`Notifier` / `AsyncNotifier` / `FutureProvider`) |
| Navigation | `go_router` with a `ShellRoute` for the tab bar |
| QR generate / scan | `qr_flutter` / `mobile_scanner` |
| Location | `geolocator` + `geocoding` |
| Local prefs | `shared_preferences` (theme, onboarding, nearby radius) |
| Share / files | `share_plus`, `path_provider` |
| Lint | `flutter_lints` via `analysis_options.yaml` |

Platform folders (`ios/`, `android/`, `macos/`, `web/`, `windows/`, `linux/`) are the Flutter embeddings. iOS is the shipped App Store target (Xcode Cloud uses `ios/ci_scripts/ci_post_clone.sh`). Do not add a second app framework or a parallel HTTP client next to Supabase.

## Layout

```
lib/
├── main.dart                 # Supabase.initialize, onboarding pref, ProviderScope
├── core/
│   ├── constants/            # AppConstants + gitignored AppSecrets
│   ├── router/app_router.dart
│   └── theme/app_theme.dart
├── data/
│   ├── models/qr_code_model.dart
│   └── repositories/qr_code_repository.dart
├── providers/                # Auth, QR list, settings, onboarding
└── screens/
    ├── auth/                 # sign-in, sign-up, forgot/reset password
    ├── onboarding/
    ├── home/                 # feed + Near You
    ├── library/              # My Codes / All Public + filters
    ├── mycards/              # pinned codes
    ├── create/               # builder + social templates
    ├── scan/                 # camera + FIDO intercept
    ├── detail/               # per-code actions, share, edit
    └── settings/
test/                         # flutter_test — currently a placeholder
dart_defines/                 # unused by current AppConstants; see PROGRESS.md
```

Routes that matter:

- Auth / first run: `/onboarding`, `/sign-in`, `/sign-up`, `/forgot-password`, `/reset-password`
- Shell tabs: `/` (Home), `/library`, `/mycards`, `/settings`
- Full-screen (no tab chrome): `/create`, `/scan`, `/detail/:id`

Deep link for Auth redirects: `qrvault://auth-callback` (`AppConstants.authRedirectUrl`). Keep it registered in Supabase Auth URL config and in iOS URL schemes.

Guest mode (`guestModeProvider`) is in-memory only. Guests can browse; saving a code must prompt sign-in. Do not persist guest libraries locally as a substitute for Supabase.

## Data layer

- **Contract:** `QrCodeRepository` in `lib/data/repositories/qr_code_repository.dart`. The live implementation is `SupabaseQrCodeRepository`. Wire it through `qrCodeRepositoryProvider` — screens should not construct a client or query `.from('qr_codes')` themselves.
- **Model:** `QrCodeModel` maps the `qr_codes` row. Types: `url`, `text`, `wifi`, `contact`, `email`. Sources: `scanned`, `created`. Also persist `is_pinned`, `is_public`, scan timestamps/coords/place names, and colours.
- **Auth:** `Supabase.instance.client.auth`. Router redirect listens to `onAuthStateChange`. Password-recovery links set `passwordRecoveryProvider` and must land on `/reset-password` before the rest of the app.
- **User’s library:** `qrCodesProvider` → `getAll()` (RLS limits rows to `auth.uid() = user_id`). Empty list when signed out — do not invent demo codes.
- **Public / nearby:** `getPublicNearby` / `getAllPublic` and the matching providers. Nearby filtering is currently Haversine in Dart after a Supabase select (see **Known gaps**). Do not replace this with a canned nearby list.
- **Defaults:** `defaultIsPublic` makes `url` / `email` public and other types private. Changing a sensitive type (`wifi`, `contact`, `text`) to public must keep the existing warning copy.
- **Local-only prefs** (theme, `has_seen_onboarding`, nearby radius miles) stay in `shared_preferences`. QR payloads, scan history, pin/public flags, and profile metadata (`full_name`, `phone`) belong in Supabase.

There is no in-repo SQL migration folder. Schema and RLS live in the Supabase project. If you add a column or policy, update `QrCodeModel`, the repository, `README.md` schema notes, and record any applied-vs-documented mismatch under **Known gaps**.

## Secrets and local run

- Compile-time credentials: copy `lib/core/constants/app_secrets.dart.template` → `app_secrets.dart` (gitignored). `AppConstants` reads that file — not `dart_defines/` (README still describes dart-define; that path is unused).
- Never commit `app_secrets.dart`, real Supabase service-role keys, or new credential files.
- Run: `flutter pub get` then `flutter run` after `app_secrets.dart` exists. Analyze with `flutter analyze`.

## Tests

- Add `flutter_test` coverage next to the change when you touch logic that can run without a device camera.
- Mocks belong in `test/` only. A green test suite is not a reason to ship fixture data in `lib/`.
- `test/widget_test.dart` is a placeholder — do not assume the suite covers auth, routing, or the repository.

## UI

Follow `STYLE_GUIDE.md`: colorScheme tokens (not hardcoded hex in widgets), 16 px cards, 12 px buttons/fields, shadowless surfaces, `BottomAppBar` + centre FAB. Keep new screens on the existing theme.

## Done when

- The change is on a feature branch with a PR to `main`.
- Live paths still go through Supabase / `QrCodeRepository`.
- Anything you did not fix is listed in `PROGRESS.md` → **Known gaps**.
