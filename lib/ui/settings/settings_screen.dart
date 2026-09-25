import 'package:flutter/material.dart';

import '../../core/focus.dart';
import '../../core/theme.dart';
import '../../data/auth/auth_service.dart';
import '../../data/sync/sync_service.dart';
import '../auth/auth_panel.dart';

/// Account page. Signed out → the register/login form (syncs on success).
/// Signed in → account summary + Sync now / Sign out. Rebuilds on auth changes.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    AuthService.revision.addListener(_onChange);
  }

  @override
  void dispose() {
    AuthService.revision.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: 32,
          bottom: 32 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          width: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Account',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AuthService.isSignedIn
                    ? 'Your watch history and library sync to this account.'
                    : 'Sign in to sync your watch history and library across devices.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              if (AuthService.isSignedIn) _signedIn() else _signedOut(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _signedOut() => const AuthPanel(initialMode: AuthMode.login);

  Widget _signedIn() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.charcoalLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AuthService.username ?? 'Signed in',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (AuthService.email != null) ...[
                const SizedBox(height: 4),
                Text(
                  AuthService.email!,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Button(
          label: _syncing ? 'Syncing…' : 'Sync now',
          autofocus: true,
          onTap: _syncing
              ? null
              : () async {
                  setState(() => _syncing = true);
                  await SyncService.pullAll();
                  if (mounted) setState(() => _syncing = false);
                },
        ),
        const SizedBox(height: 12),
        _Button(
          label: 'Sign out',
          filled: false,
          onTap: () => AuthService.signOut(),
        ),
      ],
    );
  }
}

class _Button extends StatefulWidget {
  const _Button({
    required this.label,
    required this.onTap,
    this.filled = true,
    this.autofocus = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool autofocus;

  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: widget.onTap,
      autofocus: widget.autofocus,
      focusedScale: 1.05,
      showBorder: false,
      onFocusChange: (f) => setState(() => _focused = f),
      borderRadius: BorderRadius.circular(11),
      child: FocusRing(
        focused: _focused,
        radius: 11,
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: widget.filled
                ? AppColors.textPrimary
                : AppColors.charcoalLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.filled ? AppColors.charcoal : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
