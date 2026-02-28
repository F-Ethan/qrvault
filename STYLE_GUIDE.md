# QRVault — Style Guide

A reference for replicating the visual design of QRVault in another Flutter app.

---

## Design Philosophy

- **Flat and minimal** — no shadows, no gradients, no skeuomorphism. Depth is conveyed by subtle borders and surface colour layering.
- **Rounded but not bubbly** — generous corner radii (12–24 px) without going circular on rectangular elements.
- **Indigo accent, neutral base** — a single strong accent colour on a near-white background. Colour is used sparingly to signal interactivity.
- **Dark mode first-class** — every colour token is theme-aware. No hardcoded hex in widgets; always use `Theme.of(context).colorScheme`.

---

## Colour Palette

### Brand tokens (defined in `AppTheme`)

| Token | Hex | Usage |
|---|---|---|
| `primary` | `#4F46E5` | Buttons, active icons, focused borders, links |
| `surface` | `#F9FAFB` | Scaffold background |
| `card` | `#FFFFFF` | Card / container fill (light mode) |
| `border` | `#E5E7EB` | Card outlines, dividers, inactive borders |
| `textPrimary` | `#111827` | Headlines, body copy, labels |
| `textSecondary` | `#6B7280` | Supporting copy, placeholders, inactive nav |
| `danger` | `#EF4444` | Destructive actions (delete, sign out) |

### In-widget colour (always use colorScheme tokens, not hex)

| Situation | Token |
|---|---|
| Card / container background | `colorScheme.surfaceContainerLow` |
| Card / container border | `colorScheme.outlineVariant` |
| Primary text inside cards | `colorScheme.onSurface` |
| Secondary / supporting text | `colorScheme.onSurfaceVariant` |
| Accent / interactive colour | `AppTheme.primary` (`Color(0xFF4F46E5)`) |
| Destructive colour | `AppTheme.danger` (`Color(0xFFEF4444)`) |

> **Rule:** `AppTheme.card` and `AppTheme.border` are static light-mode values — never use them directly in widget decorations. Use the colorScheme equivalents above so dark mode works automatically.

### Accent colours used for category badges / icons

These are used only as icon tints and `withValues(alpha: 0.12)` container fills — never as full backgrounds.

| Category | Colour |
|---|---|
| Scan / URL | `#4F46E5` indigo |
| Create / Wi-Fi | `#0D9488` teal |
| Vault / contact | `#7C3AED` purple |
| Warning / FIDO | `#D97706` amber |
| Danger | `#EF4444` red |

---

## Typography

Flutter's default system font (San Francisco on iOS, Roboto on Android). No custom font is loaded.

### Type scale

| Style | Weight | Letter spacing | Usage |
|---|---|---|---|
| `headlineLarge` | 700 | −0.5 | Page hero titles |
| `headlineMedium` | 600 | −0.3 | Section headers |
| `titleLarge` | 600 | — | Screen titles, sheet titles |
| `titleMedium` | 500 | — | Card titles, list item titles |
| `bodyLarge` | 400 | — | Primary body copy |
| `bodyMedium` | 400 | — | Supporting body copy (renders in `textSecondary`) |
| `labelSmall` | 400 | — | Metadata, timestamps, badges (renders in `textSecondary`) |

### AppBar title

```dart
TextStyle(
  color: textPrimary,
  fontSize: 20,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.3,
)
```

### Usage pattern

Always reach for `Theme.of(context).textTheme.titleMedium` etc. rather than raw `TextStyle`. Override only `color` when needed.

---

## Spacing & Layout

| Context | Value |
|---|---|
| Screen horizontal padding | `24 px` |
| Screen top padding (below app bar) | `8–16 px` |
| Screen bottom padding (above nav bar) | `24–32 px` |
| Gap between major sections | `24–32 px` |
| Gap between list items / cards | `12 px` |
| Gap between tightly related elements | `8 px` |
| Inner card padding | `16 px` all sides |
| Bottom sheet inner padding | `fromLTRB(24, 16, 24, 40)` |

---

## Corner Radii

| Element | Radius |
|---|---|
| Cards, containers | `16 px` |
| Buttons (filled, outlined) | `12 px` |
| Input fields | `12 px` |
| Icon badge containers | `12 px` (small), `28 px` (large hero) |
| Bottom sheets | `24 px` top corners only |
| Dot indicators (pill) | `4 px` |
| FAB | `CircleBorder()` |
| Drag handle | `2 px` |

---

## Elevation & Shadow

The design is intentionally **shadowless**. Depth is indicated by:

1. A 1 px `outlineVariant` border on cards and containers
2. A slightly tinted surface colour (`surfaceContainerLow`) vs the scaffold background
3. The bottom app bar uses a very faint shadow: `Color(0x1A000000)` (10 % black) at elevation 4 — this is the only shadow in the app

```dart
// The only place a shadow appears
bottomAppBarTheme: BottomAppBarThemeData(
  color: card,
  elevation: 4,
  shadowColor: Color(0x1A000000),
)
```

---

## Component Patterns

### Card / container

```dart
Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    borderRadius: BorderRadius.circular(16),
  ),
  child: ...,
)
```

### Icon badge (accent tinted)

```dart
Container(
  width: 44,
  height: 44,
  decoration: BoxDecoration(
    color: AppTheme.primary.withValues(alpha: 0.10),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Icon(icon, color: AppTheme.primary),
)
```

For a large hero badge (e.g. onboarding):

```dart
Container(
  width: 100,
  height: 100,
  decoration: BoxDecoration(
    color: accentColor.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(28),
  ),
  child: Icon(icon, color: accentColor, size: 52),
)
```

### Filled button (primary CTA)

Theme handles this globally. Just use:

```dart
FilledButton(onPressed: ..., child: Text('Label'))
```

The theme sets: `background = primary`, `foreground = white`, `height = 52`, `radius = 12`, `weight = w600`, `full width`.

### Outlined / secondary button

```dart
OutlinedButton(onPressed: ..., child: Text('Label'))
```

Border inherits `outlineVariant`. Use for secondary actions alongside a `FilledButton`.

### Text button (tertiary)

```dart
TextButton(onPressed: ..., child: Text('Label'))
```

Colour inherits `primary`. Used for low-priority actions (e.g. "Sign In" below "Create Account").

### Input field

Theme handles most of it. Key points:
- `filled: true`, fill = `card` (white)
- Inactive border: `border` grey
- Focused border: `primary` at 2 px width
- Content padding: `horizontal 16, vertical 14`
- Floating label colour: `primary`

### Divider

```dart
Divider(color: Theme.of(context).colorScheme.outlineVariant)
```

Never use `Divider()` alone — always pass the colour token.

### Bottom sheet drag handle

```dart
Container(
  width: 40,
  height: 4,
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.outlineVariant,
    borderRadius: BorderRadius.circular(2),
  ),
)
```

---

## App Bar

- `elevation: 0`, `scrolledUnderElevation: 0` — the bar never changes on scroll
- `centerTitle: false` — left-aligned titles throughout
- Background matches scaffold (`surface`)
- Back button / close icon in `textPrimary`

---

## Bottom Navigation

Uses `BottomAppBar` with a centred FAB notch (`CircularNotchedRectangle`), not `BottomNavigationBar`.

- Inactive nav icon/label: `AppTheme.textSecondary`
- Active nav icon/label: `AppTheme.primary`
- Active label weight: `w600`, inactive: `w400`
- Icon size: `22 px`
- Label font size: `11 px`

---

## Dark Mode

The dark theme is generated automatically from the same seed colour via `ColorScheme.fromSeed(brightness: Brightness.dark)`. No manual dark palette is defined — everything works because widgets use colorScheme tokens, not hardcoded colours.

The two exceptions that need explicit overrides in the light theme to stay readable are:

```dart
colorScheme: ColorScheme.fromSeed(...).copyWith(
  onSurface: AppTheme.textPrimary,        // #111827
  onSurfaceVariant: AppTheme.textSecondary, // #6B7280
),
```

These are only on the **light** theme. The dark theme leaves them at their generated defaults.

---

## ThemeData Setup (minimal copy-paste)

```dart
ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4F46E5),
    brightness: Brightness.light,
    surface: const Color(0xFFF9FAFB),
  ).copyWith(
    onSurface: const Color(0xFF111827),
    onSurfaceVariant: const Color(0xFF6B7280),
  ),
  scaffoldBackgroundColor: const Color(0xFFF9FAFB),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFF9FAFB),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
      side: BorderSide(color: Color(0xFFE5E7EB)),
    ),
    margin: EdgeInsets.zero,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: const Color(0xFF4F46E5),
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    floatingLabelStyle: const TextStyle(color: Color(0xFF4F46E5)),
  ),
)
```
