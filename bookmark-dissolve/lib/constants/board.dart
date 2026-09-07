import 'package:flutter/physics.dart';

/// How many of the cards are on the board when the app opens.
const kInitialVisibleCards = 3;

/// Columns the board is split into.
const kBoardColumnCount = 2;

/// How long the empty board waits before it puts every card back.
const kRestorePause = Duration(milliseconds: 250);

/// How much later each card in the list restores than the one before it.
const kRestoreStagger = Duration(milliseconds: 140);

/// The spring a card reflows and enters with.
const kCardSpring = SpringDescription(mass: 1, stiffness: 100, damping: 18);

/// How far below its resting place a card starts when it fades in.
const kCardEnterOffset = 25.0;
