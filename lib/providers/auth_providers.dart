import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set true when Supabase delivers a `passwordRecovery` auth event (the user
/// tapped the reset-password link in their email). The router redirects to
/// `/reset-password` whenever this is true, regardless of session state,
/// since Supabase treats a recovery link as a valid signed-in session.
final passwordRecoveryProvider =
    NotifierProvider<PasswordRecoveryNotifier, bool>(
  PasswordRecoveryNotifier.new,
);

class PasswordRecoveryNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}
