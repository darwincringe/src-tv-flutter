import 'package:flutter/material.dart';

import '../../data/stream/extract_response.dart';
import '../../data/stream/mirror_choice.dart';

/// Source choices shown under the title while the player controls are up.
/// Each button is focusable so a D-pad can move onto it and activate it with
/// Select, the same way the transport buttons work.
class MirrorBar extends StatelessWidget {
  const MirrorBar({
    super.key,
    required this.mirrors,
    required this.selected,
    required this.focusNodes,
    required this.onSelect,
  });

  final List<StreamMirror> mirrors;
  final int selected;
  final List<FocusNode> focusNodes;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (mirrors.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < mirrors.length; i++)
          _MirrorChip(
            label: mirrorButtonLabel(i, mirrors[i]),
            selected: i == selected,
            focusNode: i < focusNodes.length ? focusNodes[i] : null,
            onTap: () => onSelect(i),
          ),
      ],
    );
  }
}

class _MirrorChip extends StatefulWidget {
  const _MirrorChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.focusNode,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  State<_MirrorChip> createState() => _MirrorChipState();
}

class _MirrorChipState extends State<_MirrorChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _focused ? 1.08 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? Colors.white : const Color(0xCC000000),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white,
                width: _focused ? 2.5 : 1.5,
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
