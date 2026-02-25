import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingKey = 'has_seen_onboarding';

// Set in main() before runApp so the notifier's build() returns the correct
// initial value without needing ProviderScope overrides.
bool _initialHasSeenOnboarding = true; // safe default for existing users

void setInitialOnboardingState(bool value) {
  _initialHasSeenOnboarding = value;
}

final hasSeenOnboardingProvider =
    NotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);

class OnboardingNotifier extends Notifier<bool> {
  @override
  bool build() => _initialHasSeenOnboarding;

  void markSeen() => state = true;
}

Future<void> markOnboardingSeen(WidgetRef ref) async {
  ref.read(hasSeenOnboardingProvider.notifier).markSeen();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kOnboardingKey, true);
}
