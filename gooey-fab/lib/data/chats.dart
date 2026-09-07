import 'package:flutter/painting.dart';

import '../models/chat.dart';

String _firstName(String fullName) => fullName.split(' ').first;

class _ChatSeed {
  const _ChatSeed(this.id, this.name, this.lastMessageTime, this.avatarColors);

  final String id;
  final String name;
  final String lastMessageTime;
  final List<Color> avatarColors;
}

const _seeds = <_ChatSeed>[
  _ChatSeed('1', 'Julian Smith', 'Now', [Color(0xFF0B1B2B), Color(0xFF14424E), Color(0xFFC2492E)]),
  _ChatSeed('2', 'Amara Okafor', '25m', [Color(0xFF141216), Color(0xFF5A2B18), Color(0xFFE8862F)]),
  _ChatSeed('3', 'Leo Tanaka', '1hr', [Color(0xFFEFE6D8), Color(0xFFDDBE8A), Color(0xFF9A6B33)]),
  _ChatSeed('4', 'Sofia Marchetti', 'Thu', [
    Color(0xFF6D8BE8),
    Color(0xFFB9A7EE),
    Color(0xFFF1A6C6),
  ]),
  _ChatSeed('5', 'Noah Bergström', 'Thu', [
    Color(0xFFD87A5E),
    Color(0xFFA44530),
    Color(0xFF5C2C20),
  ]),
];

/// The conversations the list renders, in order.
final List<Chat> chats = _seeds
    .map(
      (seed) => Chat(
        id: seed.id,
        name: seed.name,
        lastMessage: '${_firstName(seed.name)} set disappearing message time to 30 seconds.',
        lastMessageTime: seed.lastMessageTime,
        avatarColors: seed.avatarColors,
      ),
    )
    .toList(growable: false);
