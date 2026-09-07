import 'package:flutter/material.dart';

import '../../data/chats.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/gooey_fab/gooey_fab.dart';
import 'chat_row.dart';

/// The one screen the app has: a list of conversations with the FAB over it.
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key, this.onVideoCall, this.onVoiceCall});

  final VoidCallback? onVideoCall;
  final VoidCallback? onVoiceCall;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: DefaultTextStyle(
        style: AppTypography.base,
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Text('Chats', style: AppTypography.screenTitle),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                      final chat = chats[index];
                      return ChatRow(key: ValueKey(chat.id), chat: chat);
                    },
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: GooeyFab(onVideoCall: onVideoCall, onVoiceCall: onVoiceCall),
            ),
          ],
        ),
      ),
    );
  }
}
