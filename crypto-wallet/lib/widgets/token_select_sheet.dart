import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../theme/theme.dart';
import '../utils/format.dart';
import 'app_bottom_sheet.dart';
import 'enter.dart';
import 'haptics.dart';
import 'pressable_scale.dart';
import 'token_icon.dart';

const List<TokenId> _popular = [TokenId.eth, TokenId.usdc];

/// Lets the user pick a token, with the popular ones pinned on top.
class TokenSelectSheet extends StatefulWidget {
  const TokenSelectSheet({
    super.key,
    required this.open,
    required this.onClose,
    required this.tokens,
    required this.selectedId,
    required this.onSelect,
    this.searchable = false,
  });

  final bool open;
  final VoidCallback onClose;
  final List<Token> tokens;
  final TokenId selectedId;
  final ValueChanged<Token> onSelect;
  final bool searchable;

  @override
  State<TokenSelectSheet> createState() => _TokenSelectSheetState();
}

class _TokenSelectSheetState extends State<TokenSelectSheet> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() {
    _query.clear();
    widget.onClose();
  }

  void _select(Token token) {
    if (token.id != widget.selectedId) {
      widget.onSelect(token);
      Haptics.press();
    }
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = _query.text.trim().toLowerCase();
    final List<Token> pinned;
    final List<Token> rest;
    if (trimmed.isNotEmpty) {
      pinned = const [];
      rest = widget.tokens
          .where(
            (t) =>
                t.name.toLowerCase().contains(trimmed) ||
                t.symbol.toLowerCase().contains(trimmed),
          )
          .toList();
    } else {
      pinned = widget.tokens.where((t) => _popular.contains(t.id)).toList();
      rest = widget.tokens.where((t) => !_popular.contains(t.id)).toList();
    }

    Widget label(String value, {double top = 0}) {
      return Padding(
        padding: EdgeInsets.only(top: top, bottom: 4),
        child: Text(
          value.toUpperCase(),
          style: text(
            11,
            weight: FontWeight.w600,
            color: AppColors.subtle,
            tracking: kTrackingWide,
          ),
        ),
      );
    }

    List<Widget> rows(List<Token> list, int offset) {
      return [
        for (var i = 0; i < list.length; i++)
          _TokenRow(
            token: list[i],
            active: list[i].id == widget.selectedId,
            index: offset + i,
            onPress: () => _select(list[i]),
          ),
      ];
    }

    return AppBottomSheet(
      open: widget.open,
      onClose: _close,
      title: 'Choose asset',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.searchable)
            Container(
              height: 44,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _focus.hasFocus ? AppColors.white : AppColors.chip,
                borderRadius: BorderRadius.circular(22),
                border: _focus.hasFocus
                    ? Border.all(color: AppColors.accent.withValues(alpha: 0.4))
                    : null,
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.search,
                    size: 16,
                    color: AppColors.subtle,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _query,
                      focusNode: _focus,
                      autocorrect: false,
                      style: text(15),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search assets',
                        hintStyle: text(15, color: AppColors.subtle),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (pinned.isNotEmpty) ...[
            label('Popular'),
            ...rows(pinned, 0),
            label('All assets', top: 8),
          ],
          ...rows(rest, pinned.length),
          if (rest.isEmpty && pinned.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No assets found',
                textAlign: TextAlign.center,
                style: text(14, color: AppColors.subtle),
              ),
            ),
        ],
      ),
    );
  }
}

class _TokenRow extends StatelessWidget {
  const _TokenRow({
    required this.token,
    required this.active,
    required this.index,
    required this.onPress,
  });

  final Token token;
  final bool active;
  final int index;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return Enter(
      kind: EnterKind.fadeInDown,
      delay: Duration(milliseconds: 60 + index * 45),
      duration: const Duration(milliseconds: 320),
      child: PressableScale(
        scaleTo: 0.98,
        haptic: HapticKind.selection,
        onPress: onPress,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? AppColors.accentSoft.withValues(alpha: 0.6) : null,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              TokenIcon(id: token.id, size: 42),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(token.name, style: text(16, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      token.symbol,
                      style: text(13, color: AppColors.subtle),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${formatNumber(token.balance)} ${token.symbol}',
                    style: text(15, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\$${formatFiat(token.balance * token.priceUsd)}',
                    style: text(13, color: AppColors.subtle),
                  ),
                ],
              ),
              if (active)
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Icon(
                    LucideIcons.circleCheck,
                    size: 18,
                    color: AppColors.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
