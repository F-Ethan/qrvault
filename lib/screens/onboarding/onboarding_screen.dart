import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/settings_providers.dart';

// ---------------------------------------------------------------------------
// Data for each carousel page
// ---------------------------------------------------------------------------
class _PageData {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  const _PageData({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });
}

const _pages = [
    _PageData(
    icon: Icons.add_circle_outline_rounded,
    iconColor: Color(0xFF0D9488), // teal
    title: 'Create Your Own',
    description:
        'Build QR codes from scratch — URLs, Wi-Fi passwords, contacts, '
        'emails, and plain text. Customise colours to match your style.',
  ),
  _PageData(
    icon: Icons.qr_code_scanner_rounded,
    iconColor: Color(0xFF4F46E5), // indigo
    title: 'Scan & Save',
    description:
        'Point your camera at any QR code to instantly save it to your vault. '
        'Every scan is logged with location and timestamp.',
  ),
  _PageData(
    icon: Icons.lock_outline_rounded,
    iconColor: Color(0xFF7C3AED), // purple
    title: 'Your Personal Vault',
    description:
        'All your QR codes in one secure place. Browse your collection, '
        'filter by type, and see which codes are nearby.',
  ),
];

// ---------------------------------------------------------------------------
// Onboarding screen
// ---------------------------------------------------------------------------
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      final next = (_currentPage + 1) % _pages.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _goToSignIn() {
    markOnboardingSeen(ref);
    context.go('/sign-in');
  }

  void _goToSignUp() {
    markOnboardingSeen(ref);
    context.go('/sign-up');
  }

  void _explore() {
    markOnboardingSeen(ref);
    ref.read(guestModeProvider.notifier).setGuest(true);
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Carousel ──────────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) =>
                    _OnboardingPage(data: _pages[index]),
              ),
            ),

            // ── Dot indicators ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (i) => _Dot(active: i == _currentPage),
                ),
              ),
            ),

            // ── CTA buttons ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _goToSignUp,
                      child: const Text('Create Account'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _goToSignIn,
                      child: const Text('Sign In'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _explore,
                      child: const Text(
                        'Explore without an account',
                        style: TextStyle(fontWeight: FontWeight.w400),
                      ),
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
}

// ---------------------------------------------------------------------------
// Single carousel page
// ---------------------------------------------------------------------------
class _OnboardingPage extends StatelessWidget {
  final _PageData data;
  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon badge
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: data.iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(data.icon, color: data.iconColor, size: 52),
          ),
          const SizedBox(height: 36),
          Text(
            data.title,
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            data.description,
            style: tt.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated dot indicator
// ---------------------------------------------------------------------------
class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? cs.primary : cs.outlineVariant,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
