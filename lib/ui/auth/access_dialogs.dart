import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/auth/auth_service.dart';

const registrationClosedMessage =
    "Due to popular demands, SRCTV can no longer be free, the server can't keep up anymore";

/// Why this signed-in (or signed-out) account cannot open the player.
String premiumRequiredMessage() {
  if (!AuthService.isSignedIn) {
    return 'Sign in with a premium account to watch.';
  }
  if (AuthService.premium == 1) {
    return 'Your premium access has expired.';
  }
  return 'Premium is required to watch.';
}

Future<void> showRegistrationClosedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.charcoalLight,
      content: const Text(
        registrationClosedMessage,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<void> showPremiumRequiredDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.charcoalLight,
      content: Text(
        premiumRequiredMessage(),
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
