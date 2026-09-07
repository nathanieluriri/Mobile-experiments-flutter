import 'package:flutter/physics.dart';

/// Settling spring for the deck, used for snaps, skips and taps.
const snapSpring = SpringDescription(mass: 1, stiffness: 190, damping: 24);

/// Button press spring, tight enough to feel instant.
const pressSpring = SpringDescription(mass: 1, stiffness: 400, damping: 20);

/// Spring the dock's pill uses when it grows or shrinks.
const dockLayoutSpring = SpringDescription(mass: 1, stiffness: 220, damping: 22);
