import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:provider/provider.dart';

import '../../../blaze/vo/pin_message_minimal.dart';
import '../../../constants/resources.dart';
import '../../../db/database_event_bus.dart';
import '../../../db/mixin_database.dart';
import '../../../utils/extension/extension.dart';
import '../../../utils/hook.dart';
import '../../../widgets/action_button.dart';
import '../../../widgets/app_bar.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/interactive_decorated_box.dart';
import '../../../widgets/message/item/audio_message.dart';
import '../../../widgets/message/message.dart';
import '../../../widgets/message/message_day_time.dart';
import '../bloc/conversation_cubit.dart';
import '../chat/chat_page.dart';

class PinMessagesPage extends HookWidget {
  const PinMessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final conversationId = useMemoized(
        () => context.read<ConversationCubit>().state!.conversationId);

    final rawList = useMemoizedStream<List<MessageItem>>(
      () => context.database.pinMessageDao
          .messageItems(conversationId)
          .watchWithStream(
        eventStreams: [
          DataBaseEventBus.instance.watchPinMessageStream(
            conversationIds: [conversationId],
          )
        ],
        duration: kSlowThrottleDuration,
      ),
      keys: [conversationId],
    ).data;

    final chatSideCubit = useBloc(ChatSideCubit.new);
    final searchConversationKeywordCubit = useBloc(
      () => SearchConversationKeywordCubit(chatSideCubit: chatSideCubit),
    );

    useEffect(() {
      if (rawList?.isNotEmpty ?? true) return;
      scheduleMicrotask(() => Navigator.pop(context));
    }, [rawList?.isNotEmpty]);

    final list = (rawList ?? []).reversed.toList();

    final scrollController = useMemoized(ScrollController.new);
    final listKey = useMemoized(() => GlobalKey(debugLabel: 'PinMessagesPage'));

    return MultiProvider(
      providers: [
        BlocProvider.value(
          value: searchConversationKeywordCubit,
        ),
        Provider(
          create: (_) => AudioMessagesPlayAgent(list,
              (m) => context.accountServer.convertMessageAbsolutePath(m, true)),
        ),
      ],
      child: Scaffold(
        backgroundColor: context.theme.popUp,
        appBar: MixinAppBar(
          title:
              Text(context.l10n.pinnedMessageTitle(list.length, list.length)),
          backgroundColor: context.theme.popUp,
          actions: [
            if (!Navigator.of(context).canPop())
              ActionButton(
                name: Resources.assetsImagesIcCloseSvg,
                color: context.theme.icon,
                onTap: () => context.read<ChatSideCubit>().onPopPage(),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: MessageDayTimeViewportWidget.singleList(
                scrollController: scrollController,
                listKey: listKey,
                reTraversalKey: list,
                reverse: true,
                child: ListView.builder(
                  key: listKey,
                  reverse: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  controller: scrollController,
                  itemBuilder: (BuildContext context, int index) {
                    final messageItem = list[index];
                    return MessageItemWidget(
                      prev: list.getOrNull(index + 1),
                      message: messageItem,
                      next: list.getOrNull(index - 1),
                      blink: false,
                      isPinnedPage: true,
                    );
                  },
                  itemCount: list.length,
                ),
              ),
            ),
            InteractiveDecoratedBox(
              cursor: MaterialStateMouseCursor.clickable,
              onTap: () async {
                await showMixinDialog<bool>(
                  context: context,
                  child: Builder(
                      builder: (context) => AlertDialogLayout(
                            title:
                                Text(context.l10n.unpinAllMessagesConfirmation),
                            content: const SizedBox(),
                            actions: [
                              MixinButton(
                                  backgroundTransparent: true,
                                  onTap: () => Navigator.pop(context),
                                  child: Text(context.l10n.cancel)),
                              MixinButton(
                                onTap: () {
                                  Navigator.pop(context);
                                  context.accountServer.unpinMessage(
                                    conversationId: conversationId,
                                    pinMessageMinimals: list
                                        .map((e) => PinMessageMinimal(
                                              type: e.type,
                                              messageId: e.messageId,
                                              content: e.content,
                                            ))
                                        .toList(),
                                  );
                                },
                                child: Text(context.l10n.confirm),
                              ),
                            ],
                          )),
                );
              },
              child: Container(
                height: 56,
                alignment: Alignment.center,
                child: Text(
                  context.l10n.unpinAllMessages,
                  style: TextStyle(
                    fontSize: 16,
                    color: context.theme.accent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
