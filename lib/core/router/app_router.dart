import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';

// Screen imports — uncomment each one as you build it
import '../../screens/auth/sign_in_screen.dart';
import '../../screens/auth/sign_up_screen.dart';
import '../../screens/auth/forgot_password_screen.dart';
import '../../screens/auth/reset_password_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/home/map_screen.dart';
import '../../screens/library/library_screen.dart';
import '../../screens/create/create_screen.dart';
import '../../screens/scan/scan_screen.dart';
import '../../screens/scan/scan_result_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/detail/detail_screen.dart';
import '../../screens/mycards/my_cards_screen.dart';
import '../../screens/onboarding/onboarding_screen.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/settings_providers.dart';
import '../../providers/auth_providers.dart';

// Notifies GoRouter whenever Supabase auth state changes so the redirect
// guard re-evaluates immediately (sign-in → home, sign-out → sign-in).
//
// notifyListeners() is deferred to the next frame via addPostFrameCallback
// so it never fires while the Navigator is mid-navigation (e.g. dismissing
// a dialog). Calling it synchronously inside a navigation callback causes
// the '!_debugLocked' assertion in Navigator.push.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(Ref ref) {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        ref.read(passwordRecoveryProvider.notifier).set(true);
      }
      refresh();
    });
  }

  late final StreamSubscription<AuthState> _sub;

  void refresh() {
    Future.microtask(() {
      if (hasListeners) notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthNotifier(ref);
  ref.onDispose(authNotifier.dispose);
  ref.listen<bool>(guestModeProvider, (_, __) => authNotifier.refresh());

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isSignedIn = session != null;
      final isGuest = ref.read(guestModeProvider);
      final isOnAuthRoute = state.matchedLocation == '/sign-in' ||
          state.matchedLocation == '/sign-up' ||
          state.matchedLocation == '/forgot-password';
      final isOnOnboarding = state.matchedLocation == '/onboarding';
      final hasSeenOnboarding = ref.read(hasSeenOnboardingProvider);

      // A password-recovery link creates a valid session, but the user must
      // set a new password before doing anything else in the app.
      if (ref.read(passwordRecoveryProvider)) {
        if (state.matchedLocation != '/reset-password') {
          return '/reset-password';
        }
        return null;
      }
      if (state.matchedLocation == '/reset-password') {
        // Reached directly without a recovery session — bounce to sign-in.
        return '/sign-in';
      }

      // Signed-in users always go to home; clear guest flag if just signed in
      if (isSignedIn) {
        if (isGuest) ref.read(guestModeProvider.notifier).setGuest(false);
        if (isOnAuthRoute || isOnOnboarding) return '/';
        return null;
      }

      // Guest users can browse the main app freely
      if (isGuest) return null;

      // First-time visitors see onboarding before auth screens
      if (!hasSeenOnboarding && !isOnOnboarding) return '/onboarding';

      // Unauthenticated users who have seen onboarding go to sign-in
      if (!isOnAuthRoute && !isOnOnboarding) return '/sign-in';
      return null;
    },
    routes: [
      // Onboarding — shown once to new users before auth
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),

      // Auth
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordScreen(),
      ),

      // Create QR flow — full-screen, no shell chrome
      GoRoute(
        path: '/map',
        builder: (context, state) {
          final extra = state.extra;
          double? lat;
          double? lng;
          if (extra is Map) {
            lat = (extra['lat'] as num?)?.toDouble();
            lng = (extra['lng'] as num?)?.toDouble();
          }
          return MapScreen(initialLat: lat, initialLng: lng);
        },
      ),
      GoRoute(
        path: '/create',
        builder: (context, state) => const CreateScreen(),
      ),

      // Scan QR flow — full-screen camera, no shell chrome
      GoRoute(
        path: '/scan',
        builder: (context, state) => const ScanScreen(),
      ),
      GoRoute(
        path: '/scan/result',
        builder: (context, state) {
          final content = state.extra is String ? state.extra as String : '';
          return ScanResultScreen(content: content);
        },
      ),

      // Detail screen — full-screen, no shell chrome
      GoRoute(
        path: '/detail/:id',
        builder: (context, state) => DetailScreen(
          id: state.pathParameters['id']!,
        ),
      ),

      // Main app — shell provides the bottom nav + FAB
      ShellRoute(
        builder: (context, state, child) => _MainShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/library',
            builder: (context, state) => const LibraryScreen(),
          ),
          GoRoute(
            path: '/mycards',
            builder: (context, state) => const MyCardsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

// ---------------------------------------------------------------------------
// Main shell — bottom navigation bar + centred FAB
// ---------------------------------------------------------------------------
class _MainShell extends StatelessWidget {
  final Widget child;
  const _MainShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    final currentIndex = switch (location) {
      '/' => 0,
      '/library' => 1,
      '/mycards' => 2,
      '/settings' => 3,
      _ => 0,
    };

    return Scaffold(
      body: child,

      // Centred FAB sits in the notch
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(context),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // Bottom app bar with notch
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          children: [
            // Left side: Home + Library
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home_rounded,
                      label: 'Home',
                      isActive: currentIndex == 0,
                      onTap: () => context.go('/'),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.grid_view_outlined,
                      activeIcon: Icons.grid_view_rounded,
                      label: 'Library',
                      isActive: currentIndex == 1,
                      onTap: () => context.go('/library'),
                    ),
                  ),
                ],
              ),
            ),

            // Space for the FAB notch
            const SizedBox(width: 80),

            // Right side: My Cards + Settings
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      icon: Icons.bookmark_outline_rounded,
                      activeIcon: Icons.bookmark_rounded,
                      label: 'My Cards',
                      isActive: currentIndex == 2,
                      onTap: () => context.go('/mycards'),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.settings_outlined,
                      activeIcon: Icons.settings_rounded,
                      label: 'Settings',
                      isActive: currentIndex == 3,
                      onTap: () => context.go('/settings'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Add a QR Code',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            _SheetOption(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Scan & Save',
              subtitle: 'Point your camera at any QR code',
              onTap: () {
                Navigator.pop(context);
                context.push('/scan');
              },
            ),
            const SizedBox(height: 12),
            _SheetOption(
              icon: Icons.add_circle_outline_rounded,
              title: 'Create New',
              subtitle: 'Build a QR code from scratch',
              onTap: () {
                Navigator.pop(context);
                context.push('/create');
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable nav item
// ---------------------------------------------------------------------------
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppTheme.primary : AppTheme.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isActive ? activeIcon : icon, color: color, size: 22),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheet option row
// ---------------------------------------------------------------------------
class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

