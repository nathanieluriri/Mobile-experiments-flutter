import 'package:flutter/painting.dart';

/// One conversation in the chat list.
class Chat {
  const Chat({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.avatarColors,
  });

  final String id;
  final String name;
  final String lastMessage;
  final String lastMessageTime;
  final List<Color> avatarColors;
}
