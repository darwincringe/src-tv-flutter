import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A branded loading screen: the SRCTV logo above a white spinner, with an
/// optional caption. Used for the app-open splash (large, charcoal, with a
/// caption) and the in-video buffering screen ([compact], black, logo only).
class BrandedLoader extends StatelessWidget {
  const BrandedLoader({
    super.key,
    this.caption,
    this.compact = false,
    this.background,
  });

  /// Elegant status line under the spinner (e.g. "Loading…"). Null hides it.
  final String? caption;

  /// Smaller logo + tighter spacing, for the in-player buffering overlay.
  final bool compact;

  /// Defaults to charcoal (splash) — the player passes black.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final logoWidth = compact ? 170.0 : 260.0;
    return ColoredBox(
      color: background ?? AppColors.charcoal,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/srctv_logo.png',
              width: logoWidth,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
            SizedBox(height: compact ? 26 : 40),
            const SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 22),
              Text(
                caption!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
