# QRVault

A Flutter app for scanning, creating, and managing QR codes. All codes are stored securely in the cloud via Supabase and synced across devices.

## Features

- **Scan & Save** — Scan any QR code with your camera. Each scan is automatically tagged with its GPS location and timestamp.
- **Create** — Build QR codes from scratch: URLs, plain text, Wi-Fi credentials, contacts, and email addresses. Customise foreground and background colours.
- **Library** — Browse your full collection, filter by type (URL, Wi-Fi, contact, etc.) or source (scanned vs. created).
- **Near You** — Codes scanned within 500 m of your current location surface automatically on the home screen.
- **Detail view** — See scan history, location data, and type-specific actions (open URL, copy Wi-Fi password, launch Maps for a contact address, etc.).
- **FIDO passkey detection** — Passkey QR codes (`FIDO:` URIs) are recognised at scan time and in the detail view, with a prompt to use the native iPhone Camera app.
- **Dark mode** — Full light/dark theme support, respects the system setting with a manual override in Settings.
- **Authentication** — Email/password sign-up and sign-in via Supabase Auth, with a one-time onboarding carousel for new users.

## Tech Stack

| Concern | Package |
|---|---|
| Backend / Auth | [supabase_flutter](https://pub.dev/packages/supabase_flutter) |
| State management | [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) |
| Navigation | [go_router](https://pub.dev/packages/go_router) |
| QR generation | [qr_flutter](https://pub.dev/packages/qr_flutter) |
| QR scanning | [mobile_scanner](https://pub.dev/packages/mobile_scanner) |
| Location | [geolocator](https://pub.dev/packages/geolocator) + [geocoding](https://pub.dev/packages/geocoding) |
| Link handling | [url_launcher](https://pub.dev/packages/url_launcher) |
| Persistence | [shared_preferences](https://pub.dev/packages/shared_preferences) |

## Getting Started

### Prerequisites

- Flutter SDK `>=3.4.0`
- A [Supabase](https://supabase.com) project with the schema described below
- Xcode (for iOS builds)

### 1. Clone the repo

```bash
git clone https://github.com/F-Ethan/qrvault.git
cd qrvault
```

### 2. Set up secrets

Copy the secrets template and fill in your Supabase credentials:

```bash
cp dart_defines/dev.json.template dart_defines/dev.json
```

Edit `dart_defines/dev.json`:

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT_ID.supabase.co",
  "SUPABASE_ANON_KEY": "your_supabase_anon_key_here"
}
```

### 3. Set up VSCode (optional)

If you use VSCode, copy the launch config template so the dart-define file is passed automatically on every run:

```bash
cp .vscode/launch.json.template .vscode/launch.json
```

### 4. Install dependencies

```bash
flutter pub get
```

### 5. Run

**VSCode:** press **F5** or use the Run panel — the launch config handles everything.

**Terminal:**

```bash
flutter run --dart-define-from-file=dart_defines/dev.json
```

## Supabase Schema

Create a `qr_codes` table with the following columns:

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` | Primary key, default `gen_random_uuid()` |
| `user_id` | `uuid` | References `auth.users` |
| `label` | `text` | |
| `type` | `text` | `url`, `text`, `wifi`, `contact`, `email` |
| `content` | `text` | |
| `source` | `text` | `scanned` or `created` |
| `foreground_color` | `text` | Hex string, default `#000000` |
| `background_color` | `text` | Hex string, default `#FFFFFF` |
| `scan_count` | `int4` | Default `0` |
| `first_scanned_at` | `timestamptz` | Nullable |
| `last_scanned_at` | `timestamptz` | Nullable |
| `first_scanned_lat` | `float8` | Nullable |
| `first_scanned_lng` | `float8` | Nullable |
| `first_scanned_place` | `text` | Nullable |
| `last_scanned_lat` | `float8` | Nullable |
| `last_scanned_lng` | `float8` | Nullable |
| `last_scanned_place` | `text` | Nullable |
| `created_at` | `timestamptz` | Default `now()` |
| `updated_at` | `timestamptz` | Default `now()` |

Enable Row Level Security (RLS). Owner writes and Library/My Cards must be
**own rows only**. Public discovery is a **separate SELECT** policy — never
OR `is_public` into the owner policy, or an unfiltered `select()` will return
other people's codes (including their pinned cards).

See `supabase/fix_qr_codes_rls.sql` and `supabase/scan_match_notes.sql` for
scripts to paste into the Supabase SQL editor.

```sql
-- Owner access (Library, My Cards, create/update/delete)
create policy "Users select own codes"
on qr_codes for select using (auth.uid() = user_id);

create policy "Users insert own codes"
on qr_codes for insert with check (auth.uid() = user_id);

create policy "Users update own codes"
on qr_codes for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Users delete own codes"
on qr_codes for delete using (auth.uid() = user_id);

-- Public nearby / All Public — read only
create policy "Anyone can select public codes"
on qr_codes for select using (is_public = true);
```

## Project Structure

```
lib/
├── core/
│   ├── constants/      # App-wide constants (reads from dart-define)
│   ├── router/         # GoRouter config and bottom nav shell
│   └── theme/          # Light and dark MaterialTheme definitions
├── data/
│   ├── models/         # QrCodeModel + enums
│   └── repositories/   # Supabase data access layer
├── providers/          # Riverpod providers (QR codes, settings, onboarding)
└── screens/
    ├── auth/           # Sign-in and sign-up
    ├── create/         # QR code builder
    ├── detail/         # Per-code detail and actions
    ├── home/           # Home feed + Near You section
    ├── library/        # Filterable full collection
    ├── onboarding/     # First-launch carousel
    ├── scan/           # Camera scanner
    └── settings/       # Theme toggle, account, sign-out
```

## Security Notes

- `dart_defines/dev.json` is gitignored — **never commit real credentials**
- Supabase anon keys are safe to ship inside a built app binary (they are publishable keys), but should not be exposed in public source code
- All data access is protected by Supabase RLS policies; the anon key alone grants no access beyond what RLS permits
