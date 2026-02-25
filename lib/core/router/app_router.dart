import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';

// Screen imports — uncomment each one as you build it
import '../../screens/auth/sign_in_screen.dart';
import '../../screens/auth/sign_up_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/library/library_screen.dart';
import '../../screens/create/create_screen.dart';
import '../../screens/scan/scan_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/detail/detail_screen.dart';
import '../../screens/onboarding/onboarding_screen.dart';
import '../../providers/onboarding_provider.dart';

// Notifies GoRouter whenever Supabase auth state changes so the redirect
// guard re-evaluates immediately (sign-in → home, sign-out → sign-in).
//
// notifyListeners() is deferred to the next frame via addPostFrameCallback
// so it never fires while the Navigator is mid-navigation (e.g. dismissing
// a dialog). Calling it synchronously inside a navigation callback causes
// the '!_debugLocked' assertion in Navigator.push.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) notifyListeners();
      });
    });
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthNotifier();
  ref.onDispose(authNotifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isSignedIn = session != null;
      final isOnAuthRoute = state.matchedLocation == '/sign-in' ||
          state.matchedLocation == '/sign-up';
      final isOnOnboarding = state.matchedLocation == '/onboarding';
      final hasSeenOnboarding = ref.read(hasSeenOnboardingProvider);

      // Signed-in users always go to home
      if (isSignedIn && (isOnAuthRoute || isOnOnboarding)) return '/';
      if (isSignedIn) return null;

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

      // Create QR flow — full-screen, no shell chrome
      GoRoute(
        path: '/create',
        builder: (context, state) => const CreateScreen(),
      ),

      // Scan QR flow — full-screen camera, no shell chrome
      GoRoute(
        path: '/scan',
        builder: (context, state) => const ScanScreen(),
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
      '/settings' => 2,
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
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _NavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: 'Home',
                    isActive: currentIndex == 0,
                    onTap: () => context.go('/'),
                  ),
                  _NavItem(
                    icon: Icons.grid_view_outlined,
                    activeIcon: Icons.grid_view_rounded,
                    label: 'Library',
                    isActive: currentIndex == 1,
                    onTap: () => context.go('/library'),
                  ),
                ],
              ),
            ),

            // Space for the FAB notch
            const SizedBox(width: 80),

            // Right side: Settings
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _NavItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings_rounded,
                    label: 'Settings',
                    isActive: currentIndex == 2,
                    onTap: () => context.go('/settings'),
                  ),
                  // Placeholder to keep Settings centred in its half
                  const SizedBox(width: 48),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isActive ? activeIcon : icon, color: color, size: 22),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.w400,
                color: color,
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

