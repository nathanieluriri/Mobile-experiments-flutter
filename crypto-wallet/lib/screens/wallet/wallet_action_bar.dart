import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/theme.dart';

/// Receive, Send, Swap and IPO on the dark band between the cards.
class WalletActionBar extends StatelessWidget {
  const WalletActionBar({
    super.key,
    required this.onReceive,
    required this.onSend,
    required this.onSwap,
    required this.onIpo,
  });

  final VoidCallback onReceive;
  final VoidCallback onSend;
  final VoidCallback onSwap;
  final VoidCallback onIpo;

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('Receive', LucideIcons.arrowDownLeft, onReceive),
      ('Send', LucideIcons.arrowUpRight, onSend),
      ('Swap', LucideIcons.repeat, onSwap),
      ('IPO', LucideIcons.trendingUp, onIpo),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final (label, icon, onPress) in actions)
            _ActionButton(label: label, icon: icon, onPress: onPress),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPress,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPress;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPress,
      child: Opacity(
        opacity: _pressed ? 0.6 : 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 19, color: AppColors.white),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: text(15, weight: FontWeight.w600, color: AppColors.white),
            ),
          ],
        ),
      ),
    );
  }
}
