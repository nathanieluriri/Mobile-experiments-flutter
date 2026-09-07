import 'package:flutter/widgets.dart';

import '../../models/chat.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/avatar.dart';

const _horizontalPadding = 20.0;
const _avatarGap = 16.0;
const _verticalPadding = 14.0;
const _messageGap = 2.0;
const _messageRightInset = 40.0;

/// One conversation: avatar, name, timestamp, and the last message.
class ChatRow extends StatelessWidget {
  const ChatRow({super.key, required this.chat});

  final Chat chat;

  @override
  Widget build(BuildContext context) {
    final hairline = 1 / MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
      child: Row(
        children: [
          Avatar(colors: chat.avatarColors),
          const SizedBox(width: _avatarGap),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.rowDivider,
                    width: hairline,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: _verticalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(chat.name, style: AppTypography.chatName),
                      Text(chat.lastMessageTime, style: AppTypography.chatTime),
                    ],
                  ),
                  const SizedBox(height: _messageGap),
                  Padding(
                    padding: const EdgeInsets.only(right: _messageRightInset),
                    child: Text(
                      chat.lastMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.chatMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
