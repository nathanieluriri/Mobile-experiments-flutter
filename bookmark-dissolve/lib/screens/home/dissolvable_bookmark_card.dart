import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../../constants/board.dart';
import '../../constants/interpolation.dart';
import '../../data/bookmark_cards.dart';
import '../../widgets/bookmark_card.dart';
import '../../widgets/dissolve/dissolve_scope.dart';

/// A bookmark card that can come apart when its close button is tapped, and
/// that puts itself back together when it is handed a snapshot of itself.
class DissolvableBookmarkCard extends StatefulWidget {
  const DissolvableBookmarkCard({
    super.key,
    required this.card,
    required this.snapshot,
    required this.onRemove,
    required this.onSnapshot,
    required this.onRestored,
  });

  final BookmarkCardDefinition card;

  /// The picture this card was last dissolved from, when it is coming back.
  final ui.Image? snapshot;

  final void Function(String cardId) onRemove;
  final void Function(String cardId, ui.Image image) onSnapshot;
  final void Function(String cardId) onRestored;

  @override
  State<DissolvableBookmarkCard> createState() => _DissolvableBookmarkCardState();
}

class _DissolvableBookmarkCardState extends State<DissolvableBookmarkCard>
    with SingleTickerProviderStateMixin {
  final _cardKey = GlobalKey();
  late final AnimationController _enter;
  late bool _hidden = widget.snapshot != null;
  bool _materializeStarted = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final restoring = widget.snapshot != null;
    _enter = AnimationController.unbounded(vsync: this, value: restoring ? 1 : 0);
    final delay = restoreDelay(widget.card.id);
    if (restoring) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleMaterialize(delay));
    } else if (delay == Duration.zero) {
      _startEnter();
    } else {
      _timer = Timer(delay, _startEnter);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _enter.dispose();
    super.dispose();
  }

  void _startEnter() {
    if (mounted) {
      _enter.animateWith(SpringSimulation(kCardSpring, 0, 1, 0));
    }
  }

  void _scheduleMaterialize(Duration delay) {
    if (!mounted || _materializeStarted) {
      return;
    }
    _materializeStarted = true;
    _timer = Timer(delay, () {
      if (!mounted) {
        return;
      }
      DissolveScope.of(context).materialize(
        _cardKey,
        widget.snapshot!,
        onDone: () {
          if (mounted) {
            setState(() => _hidden = false);
          }
          widget.onRestored(widget.card.id);
        },
      );
    });
  }

  void _close() {
    if (_hidden) {
      return;
    }
    final image = DissolveScope.of(context).dissolve(
      _cardKey,
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
      onCaptured: () => setState(() => _hidden = true),
      onDone: () => widget.onRemove(widget.card.id),
    );
    if (image != null) {
      widget.onSnapshot(widget.card.id, image);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = BookmarkCard(
      cardKey: _cardKey,
      title: widget.card.title,
      icon: widget.card.icon,
      onClose: _close,
      child: widget.card.body,
    );
    return AnimatedBuilder(
      animation: _enter,
      builder: (context, child) {
        final value = _enter.value;
        return Opacity(
          opacity: clamp01(value),
          child: Transform.translate(
            offset: Offset(0, kCardEnterOffset * (1 - value)),
            child: child,
          ),
        );
      },
      child: Opacity(opacity: _hidden ? 0 : 1, child: card),
    );
  }
}
