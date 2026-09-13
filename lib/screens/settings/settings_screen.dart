import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/qr_code_providers.dart';
import '../../providers/settings_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _editingProfile = false;
  bool _profileSaving = false;
  bool _deletingAccount = false;
  bool _loading = true;

  // Holds data freshly fetched from Supabase; falls back to local cache on error.
  User? _liveUser;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;

  // Always prefer the server-fresh user over the SDK's local cache.
  User? get _user =>
      _liveUser ?? Supabase.instance.client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    // Seed controllers from the local cache so they're never blank while loading.
    final cached = Supabase.instance.client.auth.currentUser;
    _nameCtrl = TextEditingController(
      text: cached?.userMetadata?['full_name'] as String? ?? '',
    );
    _phoneCtrl = TextEditingController(
      text: cached?.userMetadata?['phone'] as String? ?? '',
    );
    // Then immediately refresh from the server.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchUser());
  }

  // ── Fetch fresh user data from Supabase ──────────────────────────────────────
  Future<void> _fetchUser() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final response = await Supabase.instance.client.auth.getUser();
      if (mounted && response.user != null) {
        setState(() {
          _liveUser = response.user;
          _nameCtrl.text =
              _liveUser?.userMetadata?['full_name'] as String? ?? '';
          _phoneCtrl.text =
              _liveUser?.userMetadata?['phone'] as String? ?? '';
        });
      }
    } catch (_) {
      // Keep cached data — already seeded in initState.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Profile save ────────────────────────────────────────────────────────────
  Future<void> _saveProfile() async {
    setState(() => _profileSaving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': _nameCtrl.text.trim(),
            'phone': _phoneCtrl.text.trim(),
          },
        ),
      );
      // Refresh from server so displayed values reflect what was actually saved.
      await _fetchUser();
      if (mounted) setState(() => _editingProfile = false);
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } catch (_) {
      if (mounted) _showError('Could not save profile. Please try again.');
    } finally {
      if (mounted) setState(() => _profileSaving = false);
    }
  }

  // ── Sign out ─────────────────────────────────────────────────────────────────
  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      // Use `dialogContext` (not the outer settings context) so Navigator.pop
      // targets the root navigator where the dialog lives, not the ShellRoute's
      // inner navigator — mixing them causes the _debugLocked assertion.
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await Supabase.instance.client.auth.signOut();
    ref.invalidate(qrCodesProvider);
    // GoRouter's refreshListenable detects the auth change and redirects
    // to /sign-in automatically — no explicit navigation needed here.
  }

  // ── Delete account ────────────────────────────────────────────────────────────
  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirm != true || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await Supabase.instance.client.rpc('delete_own_account');
      await Supabase.instance.client.auth.signOut();
      ref.invalidate(qrCodesProvider);
    } catch (_) {
      if (mounted) {
        _showError(
          'Could not delete account. Please try again or contact support.',
        );
      }
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isGuest = ref.watch(guestModeProvider);
    final user = _user;
    final initials = _initials(
      _nameCtrl.text.isNotEmpty
          ? _nameCtrl.text
          : (user?.email ?? '?'),
    );

    // Guests see a stripped-down settings screen with a sign-up prompt
    if (isGuest) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            const SizedBox(height: 16),
            // Sign-up card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.person_add_outlined,
                            color: AppTheme.primary),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Create a free account',
                                style:
                                    Theme.of(context).textTheme.titleMedium),
                            Text('Save and manage your QR codes',
                                style:
                                    Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.push('/sign-up'),
                    child: const Text('Sign Up — It\'s Free'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => context.push('/sign-in'),
                    child: const Text('Sign In'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Location section still works for guests
            _SectionHeader('Location'),
            _SettingsCard(
              children: [_NearbyRadiusRow()],
            ),

            const SizedBox(height: 24),

            // Appearance still works for guests
            _SectionHeader('Appearance'),
            _SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.brightness_6_outlined,
                              color: AppTheme.textSecondary, size: 20),
                          const SizedBox(width: 12),
                          Text('Theme',
                              style:
                                  Theme.of(context).textTheme.bodyLarge),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<ThemeMode>(
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor:
                              AppTheme.primary.withValues(alpha: 0.12),
                          selectedForegroundColor: AppTheme.primary,
                        ),
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('System'),
                            icon: Icon(Icons.brightness_auto_rounded,
                                size: 16),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Light'),
                            icon: Icon(Icons.light_mode_rounded, size: 16),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Dark'),
                            icon: Icon(Icons.dark_mode_rounded, size: 16),
                          ),
                        ],
                        selected: {themeMode},
                        onSelectionChanged: (modes) {
                          ref
                              .read(themeModeProvider.notifier)
                              .setMode(modes.first);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          if (_editingProfile) ...[
            TextButton(
              onPressed: () => setState(() {
                _editingProfile = false;
                // Reset controllers if cancelled
                _nameCtrl.text =
                    user?.userMetadata?['full_name'] as String? ?? '';
                _phoneCtrl.text =
                    user?.userMetadata?['phone'] as String? ?? '';
              }),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: _profileSaving ? null : _saveProfile,
              child: _profileSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit profile',
              onPressed: () => setState(() => _editingProfile = true),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          // ── Avatar ─────────────────────────────────────────────────────────
          const SizedBox(height: 12),
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                if (_editingProfile)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          color: Colors.white, size: 14),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Profile section ────────────────────────────────────────────────
          _SectionHeader('Profile'),
          _SettingsCard(
            children: [
              // Name
              _EditableRow(
                icon: Icons.person_outline_rounded,
                label: 'Name',
                controller: _nameCtrl,
                placeholder: 'Add your name',
                editing: _editingProfile,
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
              ),
              const _Divider(),
              // Email — non-editable inline; change via dialog
              _InfoRow(
                icon: Icons.email_outlined,
                label: 'Email',
                value: user?.email ?? 'Not set',
                trailing: _editingProfile
                    ? TextButton(
                        onPressed: () => _showChangeEmailDialog(context),
                        child: const Text('Change'),
                      )
                    : null,
              ),
              const _Divider(),
              // Phone — stored in user metadata
              _EditableRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                controller: _phoneCtrl,
                placeholder: 'Add a phone number',
                editing: _editingProfile,
                keyboardType: TextInputType.phone,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Location section ──────────────────────────────────────────────
          _SectionHeader('Location'),
          _SettingsCard(
            children: [
              _NearbyRadiusRow(),
            ],
          ),

          const SizedBox(height: 24),

          // ── Appearance section ────────────────────────────────────────────
          _SectionHeader('Appearance'),
          _SettingsCard(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.brightness_6_outlined,
                            color: AppTheme.textSecondary, size: 20),
                        const SizedBox(width: 12),
                        Text('Theme',
                            style: Theme.of(context).textTheme.bodyLarge),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<ThemeMode>(
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor:
                            AppTheme.primary.withValues(alpha: 0.12),
                        selectedForegroundColor: AppTheme.primary,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_rounded, size: 16),
                        ),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (modes) {
                        ref
                            .read(themeModeProvider.notifier)
                            .setMode(modes.first);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Account section ───────────────────────────────────────────────
          _SectionHeader('Account'),
          _SettingsCard(
            children: [
              _ActionRow(
                icon: Icons.lock_outline_rounded,
                label: 'Change Password',
                onTap: () => _showChangePasswordDialog(context),
              ),
              const _Divider(),
              _ActionRow(
                icon: Icons.logout_rounded,
                label: 'Sign Out',
                onTap: _signOut,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── More from developer ───────────────────────────────────────────
          _SectionHeader('Our Other Apps'),
          _SettingsCard(
            children: [
              _ActionRow(
                icon: Icons.menu_book_rounded,
                label: 'Bookmark: Horner Bible Reading',
                onTap: () => launchUrl(
                  Uri.parse(
                      'https://apps.apple.com/us/app/bookmark-horner-bible-reading/id6761035698'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Danger zone ───────────────────────────────────────────────────
          _SettingsCard(
            children: [
              _ActionRow(
                icon: Icons.delete_outline_rounded,
                label: 'Delete Account',
                textColor: AppTheme.danger,
                iconColor: AppTheme.danger,
                onTap: _deletingAccount ? () {} : _deleteAccount,
              ),
            ],
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────────

  Future<void> _showChangeEmailDialog(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangeEmailDialog(currentEmail: _user?.email ?? ''),
    );
    if (changed == true && mounted) {
      _showSuccess('Verification email sent. Check your inbox to confirm.');
    }
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (changed == true && mounted) {
      _showSuccess('Password updated successfully.');
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return name.isNotEmpty ? name[0].toUpperCase() : '?';
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card wrapper
// ---------------------------------------------------------------------------
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thin divider inside cards
// ---------------------------------------------------------------------------
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 48, endIndent: 0);
  }
}

// ---------------------------------------------------------------------------
// Read-only info row (email, etc.)
// ---------------------------------------------------------------------------
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 2),
                Text(value, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Editable row — switches between read and text field mode
// ---------------------------------------------------------------------------
class _EditableRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final String placeholder;
  final bool editing;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;

  const _EditableRow({
    required this.icon,
    required this.label,
    required this.controller,
    required this.placeholder,
    required this.editing,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    if (editing) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                textCapitalization: textCapitalization,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  labelText: label,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final displayValue =
        controller.text.isNotEmpty ? controller.text : placeholder;
    final isPlaceholder = controller.text.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 2),
                Text(
                  displayValue,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: isPlaceholder
                            ? AppTheme.textSecondary
                            : null,
                        fontStyle: isPlaceholder
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tappable action row (sign out, change password, etc.)
// ---------------------------------------------------------------------------
class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? textColor;
  final Color? iconColor;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.textColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: iconColor ?? AppTheme.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: textColor,
                    ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nearby radius slider
// ---------------------------------------------------------------------------
class _NearbyRadiusRow extends ConsumerWidget {
  const _NearbyRadiusRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final miles = ref.watch(nearbyRadiusProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 20, color: AppTheme.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text('"Near You" radius',
                    style: Theme.of(context).textTheme.bodyLarge),
              ),
              Text(
                '${miles.toStringAsFixed(0)} mi',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: miles,
            min: 1,
            max: 25,
            divisions: 24,
            label: '${miles.toStringAsFixed(0)} miles',
            onChanged: (v) =>
                ref.read(nearbyRadiusProvider.notifier).setRadius(v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1 mi',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppTheme.textSecondary)),
              Text('25 mi',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppTheme.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Change Email dialog
// ---------------------------------------------------------------------------
class _ChangeEmailDialog extends StatefulWidget {
  final String currentEmail;
  const _ChangeEmailDialog({required this.currentEmail});

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: email),
      );
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Email'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current: ${widget.currentEmail}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'New email address'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style:
                    const TextStyle(color: AppTheme.danger, fontSize: 13)),
          ],
          const SizedBox(height: 10),
          const Text(
            'A confirmation link will be sent to the new address.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Send Link'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Change Password dialog
// ---------------------------------------------------------------------------
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_newCtrl.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newCtrl.text),
      );
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _newCtrl,
            obscureText: _obscureNew,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'New password',
              suffixIcon: IconButton(
                icon: Icon(_obscureNew
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () =>
                    setState(() => _obscureNew = !_obscureNew),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm new password',
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style:
                    const TextStyle(color: AppTheme.danger, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Update'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Delete account confirmation dialog
// ---------------------------------------------------------------------------
class _DeleteAccountDialog extends StatelessWidget {
  const _DeleteAccountDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete Account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_rounded, color: AppTheme.danger, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This action cannot be undone.',
                    style: TextStyle(color: AppTheme.danger, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Deleting your account will permanently remove all your QR codes and data. You will be signed out immediately.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete Account'),
        ),
      ],
    );
  }
}
