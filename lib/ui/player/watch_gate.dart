import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/auth/auth_service.dart';
import '../auth/access_dialogs.dart';
import 'player_args.dart';
import 'player_view.dart';

/// Opens the player only for an admin or a premium account that has not
/// expired. Everyone else stays on this route and never starts extract.
class WatchGate extends StatefulWidget {
  const WatchGate({super.key, required this.args});
  final PlayerArgs args;

  @override
  State<WatchGate> createState() => _WatchGateState();
}

class _WatchGateState extends State<WatchGate> {
  late bool _checked = AuthService.canStream;

  @override
  void initState() {
    super.initState();
    if (_checked) return;
    AuthService.refreshProfile().whenComplete(() {
      if (mounted) setState(() => _checked = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (AuthService.canStream) return PlayerScreen(args: widget.args);
    if (!_checked) {
      return const Scaffold(
        backgroundColor: AppColors.charcoal,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final type = widget.args.type ?? 'movie';
    final id = widget.args.tmdbId;
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    premiumRequiredMessage(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (id != null)
                    TextButton(
                      autofocus: true,
                      onPressed: () => context.go('/details/$type/$id'),
                      child: const Text('Back to title'),
                    ),
                  if (!AuthService.isSignedIn)
                    TextButton(
                      autofocus: id == null,
                      onPressed: () => context.go('/settings'),
                      child: const Text('Sign in'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
