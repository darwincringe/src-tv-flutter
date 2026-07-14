import 'package:flutter/material.dart';

import '../../core/focus.dart';
import '../../core/theme.dart';

enum _AuthMode { login, register }

/// Account page — UI only for now; submit explains accounts aren't wired up
/// yet. Mirrors the Kotlin `SettingsScreen`.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _AuthMode _mode = _AuthMode.login;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
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
              const Text(
                'Sign in to sync your watchlist across devices',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ModeTab(
                    label: 'Login',
                    selected: _mode == _AuthMode.login,
                    onTap: () => setState(() => _mode = _AuthMode.login),
                  ),
                  const SizedBox(width: 12),
                  _ModeTab(
                    label: 'Register',
                    selected: _mode == _AuthMode.register,
                    onTap: () => setState(() => _mode = _AuthMode.register),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _AuthField(placeholder: 'Email'),
              const SizedBox(height: 14),
              const _AuthField(placeholder: 'Password', obscure: true),
              if (_mode == _AuthMode.register) ...[
                const SizedBox(height: 14),
                const _AuthField(placeholder: 'Confirm password', obscure: true),
              ],
              const SizedBox(height: 24),
              _PrimaryButton(
                label: _mode == _AuthMode.login ? 'Sign In' : 'Create Account',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Accounts are coming soon')),
                  );
                },
              ),
              const SizedBox(height: 14),
              const Text(
                "Accounts aren't functional yet — coming soon.",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: onTap,
      focusedScale: 1.05,
      showBorder: false,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.charcoalLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.charcoal : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({required this.placeholder, this.obscure = false});
  final String placeholder;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      obscureText: obscure,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.charcoalLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.textPrimary, width: 2),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: onTap,
      focusedScale: 1.05,
      showBorder: false,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.charcoal,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
