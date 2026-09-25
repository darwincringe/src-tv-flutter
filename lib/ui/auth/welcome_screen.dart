import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/auth/auth_service.dart';
import 'auth_panel.dart';

/// First-run gate: shown on a fresh install (no local data, not signed in) so
/// the user can register/login or skip. Skipping keeps everything local. The
/// router redirect (see router.dart) sends here only while the gate applies.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      // We manage the keyboard ourselves (padding + ensureVisible) so the
      // focused field always scrolls clear of the on-screen keyboard.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final keyboard = MediaQuery.of(context).viewInsets.bottom;
            return SingleChildScrollView(
              padding: EdgeInsets.only(top: 32, bottom: 32 + keyboard),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
                child: Center(
                  child: SizedBox(
                    width: 440,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Welcome to SRC TV',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'Create an account to keep your watch history and '
                            'library in sync across devices — or skip and just '
                            'use it here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        AuthPanel(
                          initialMode: AuthMode.register,
                          showSkip: true,
                          onSkip: () async {
                            await AuthService.markOnboarded();
                            if (context.mounted) context.go('/home');
                          },
                          onAuthenticated: () {
                            if (context.mounted) context.go('/home');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
