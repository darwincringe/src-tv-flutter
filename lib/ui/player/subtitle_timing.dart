import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/store/subtitle_offset.dart';

/// Minus and plus controls for caption timing. Each step is half a second.
/// The label is the running total, negative or positive.
class SubtitleTimingControls extends StatefulWidget {
  const SubtitleTimingControls({
    super.key,
    required this.offsetMs,
    required this.onChanged,
  });

  final int offsetMs;
  final ValueChanged<int> onChanged;

  @override
  State<SubtitleTimingControls> createState() => _SubtitleTimingControlsState();
}

class _SubtitleTimingControlsState extends State<SubtitleTimingControls> {
  static const _stepMs = 500;
  static const _limitMs = 120000;
  late int _offset = widget.offsetMs;

  void _nudge(int delta) {
    final next = (_offset + delta).clamp(-_limitMs, _limitMs);
    if (next == _offset) return;
    setState(() => _offset = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          _TimingButton(
            label: '−',
            onTap: () => _nudge(-_stepMs),
          ),
          Expanded(
            child: Text(
              formatSubtitleOffset(_offset),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _TimingButton(
            label: '+',
            onTap: () => _nudge(_stepMs),
          ),
        ],
      ),
    );
  }
}

class _TimingButton extends StatefulWidget {
  const _TimingButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_TimingButton> createState() => _TimingButtonState();
}

class _TimingButtonState extends State<_TimingButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final fg = _focused ? Colors.black : AppColors.textPrimary;
    return FocusableActionDetector(
      onFocusChange: (f) => setState(() => _focused = f),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 64,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _focused ? AppColors.focusRing : AppColors.charcoal,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: fg,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
