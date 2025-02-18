import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

import '../../../account/scam_warning_key_value.dart';
import '../../../account/show_pin_message_key_value.dart';
import '../../../bloc/simple_cubit.dart';
import '../../../bloc/subscribe_mixin.dart';
import '../../../constants/resources.dart';
import '../../../db/database_event_bus.dart';
import '../../../utils/extension/extension.dart';
import '../../../utils/hook.dart';
import '../../../widgets/action_button.dart';
import '../../../widgets/actions/actions.dart';
import '../../../widgets/animated_visibility.dart';
import '../../../widgets/clamping_custom_scroll_view/clamping_custom_scroll_view.dart';
import '../../../widgets/conversation/mute_dialog.dart';
import '../../../widgets/dash_path_border.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/interactive_decorated_box.dart';
import '../../../widgets/message/item/text/mention_builder.dart';
import '../../../widgets/message/message.dart';
import '../../../widgets/message/message_bubble.dart';
import '../../../widgets/message/message_day_time.dart';
import '../../../widgets/pin_bubble.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/window/menus.dart';
import '../bloc/blink_cubit.dart';
import '../bloc/conversation_cubit.dart';
import '../bloc/message_bloc.dart';
import '../bloc/message_selection_cubit.dart';
import '../bloc/pending_jump_message_cubit.dart';
import '../bloc/quote_message_cubit.dart';
import '../chat_slide_page/chat_info_page.dart';
import '../chat_slide_page/circle_manager_page.dart';
import '../chat_slide_page/disappear_message_page.dart';
import '../chat_slide_page/group_participants_page.dart';
import '../chat_slide_page/groups_in_common_page.dart';
import '../chat_slide_page/pin_messages_page.dart';
import '../chat_slide_page/search_message_page.dart';
import '../chat_slide_page/shared_apps_page.dart';
import '../chat_slide_page/shared_media_page.dart';
import '../home.dart';
import '../hook/pin_message.dart';
import '../route/responsive_navigator.dart';
import '../route/responsive_navigator_cubit.dart';
import 'chat_bar.dart';
import 'files_preview.dart';
import 'input_container.dart';
import 'selection_bottom_bar.dart';

class ChatSideCubit extends AbstractResponsiveNavigatorCubit {
  ChatSideCubit() : super(const ResponsiveNavigatorState());

  static const infoPage = 'infoPage';
  static const circles = 'circles';
  static const searchMessageHistory = 'searchMessageHistory';
  static const sharedMedia = 'sharedMedia';
  static const participants = 'participants';
  static const pinMessages = 'pinMessages';
  static const sharedApps = 'sharedApps';
  static const groupsInCommon = 'groupsInCommon';
  static const disappearMessages = 'disappearMessages';

  @override
  MaterialPage route(String name, Object? arguments) {
    switch (name) {
      case infoPage:
        return const MaterialPage(
          key: ValueKey(infoPage),
          name: infoPage,
          child: ChatInfoPage(),
        );
      case circles:
        return const MaterialPage(
          key: ValueKey(circles),
          name: circles,
          child: CircleManagerPage(),
        );
      case searchMessageHistory:
        return const MaterialPage(
          key: ValueKey(searchMessageHistory),
          name: searchMessageHistory,
          child: SearchMessagePage(),
        );
      case sharedMedia:
        return const MaterialPage(
          key: ValueKey(sharedMedia),
          name: sharedMedia,
          child: SharedMediaPage(),
        );
      case participants:
        return const MaterialPage(
          key: ValueKey(participants),
          name: participants,
          child: GroupParticipantsPage(),
        );
      case pinMessages:
        return const MaterialPage(
          key: ValueKey(pinMessages),
          name: pinMessages,
          child: PinMessagesPage(),
        );
      case sharedApps:
        return const MaterialPage(
          key: ValueKey(sharedApps),
          name: sharedApps,
          child: SharedAppsPage(),
        );
      case groupsInCommon:
        return const MaterialPage(
          key: ValueKey(groupsInCommon),
          name: groupsInCommon,
          child: GroupsInCommonPage(),
        );
      case disappearMessages:
        return const MaterialPage(
          key: ValueKey(disappearMessages),
          name: disappearMessages,
          child: DisappearMessagePage(),
        );
      default:
        throw ArgumentError('Invalid route');
    }
  }

  void toggleInfoPage() {
    if (state.pages.isEmpty) {
      return emit(state.copyWith(pages: [route(ChatSideCubit.infoPage, null)]));
    }
    return clear();
  }
}

class SearchConversationKeywordCubit extends SimpleCubit<(String?, String)>
    with SubscribeMixin {
  SearchConversationKeywordCubit({required ChatSideCubit chatSideCubit})
      : super(const (null, '')) {
    addSubscription(chatSideCubit.stream
        .map((event) => event.pages.any(
            (element) => element.name == ChatSideCubit.searchMessageHistory))
        .distinct()
        .listen((event) => emit(const (null, ''))));
  }

  static void updateKeyword(BuildContext context, String keyword) {
    final cubit = context.read<SearchConversationKeywordCubit>();
    cubit.emit((cubit.state.$1, keyword));
  }

  static void updateSelectedUser(BuildContext context, String? userId) {
    final cubit = context.read<SearchConversationKeywordCubit>();
    cubit.emit((userId, cubit.state.$2));
  }
}

class ChatPage extends HookWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final chatContainerPageKey = useMemoized(GlobalKey.new);
    final conversationId =
        useBlocStateConverter<ConversationCubit, ConversationState?, String?>(
            converter: (state) => state?.conversationId);
    final initialSidePage =
        useBlocStateConverter<ConversationCubit, ConversationState?, String?>(
            converter: (state) => state?.initialSidePage);

    final chatSideCubit = useBloc(ChatSideCubit.new, keys: [conversationId]);

    final searchConversationKeywordCubit = useBloc(
        () => SearchConversationKeywordCubit(chatSideCubit: chatSideCubit),
        keys: [conversationId]);

    final messageSelectionCubit = useBloc(
      MessageSelectionCubit.new,
      keys: [conversationId],
    );

    useEffect(() {
      if (initialSidePage != null) {
        chatSideCubit.pushPage(initialSidePage);
      }
    }, [initialSidePage, chatSideCubit]);

    final navigatorState =
        useBlocState<ChatSideCubit, ResponsiveNavigatorState>(
            bloc: chatSideCubit);

    useEffect(
        () => messageSelectionCubit.stream
                .map((event) => event.hasSelectedMessage)
                .distinct()
                .listen((hasSelectedMessage) {
              if (hasSelectedMessage) {
                chatSideCubit.clear();
              }
            }).cancel,
        [messageSelectionCubit, chatSideCubit]);

    final chatContainerPage = MaterialPage(
      key: const ValueKey('chatContainer'),
      name: 'chatContainer',
      child: ChatContainer(
        key: chatContainerPageKey,
      ),
    );

    final windowHeight = MediaQuery.of(context).size.height;

    final tickerProvider = useSingleTickerProvider();
    final blinkCubit = useBloc(
      () => BlinkCubit(
        tickerProvider,
        context.theme.accent.withOpacity(0.5),
      ),
    );
    final pinMessageState = usePinMessageState();

    return MultiProvider(
      providers: [
        BlocProvider.value(value: blinkCubit),
        BlocProvider.value(value: chatSideCubit),
        BlocProvider.value(value: searchConversationKeywordCubit),
        BlocProvider(
          create: (context) => MessageBloc(
            accountServer: context.accountServer,
            database: context.database,
            conversationCubit: context.read<ConversationCubit>(),
            mentionCache: context.read<MentionCache>(),
            limit: windowHeight ~/ 20,
          ),
        ),
        Provider.value(value: pinMessageState),
        BlocProvider.value(value: messageSelectionCubit),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.theme.primary,
        ),
        child: LayoutBuilder(
          builder: (context, boxConstraints) {
            final routeMode = boxConstraints.maxWidth <
                (kResponsiveNavigationMinWidth + kChatSidePageWidth);
            chatSideCubit.updateRouteMode(routeMode);

            return _ChatMenuHandler(
              child: Row(
                children: [
                  if (!routeMode)
                    Expanded(
                      child: chatContainerPage.child,
                    ),
                  if (!routeMode)
                    Container(
                      width: 1,
                      color: context.theme.divider,
                    ),
                  FocusableActionDetector(
                    shortcuts: const {
                      SingleActivator(LogicalKeyboardKey.escape):
                          EscapeIntent(),
                    },
                    actions: {
                      EscapeIntent: CallbackAction<EscapeIntent>(
                        onInvoke: (intent) => chatSideCubit.pop(),
                      )
                    },
                    child: _SideRouter(
                      chatSideCubit: chatSideCubit,
                      constraints: boxConstraints,
                      onPopPage: (Route<dynamic> route, dynamic result) {
                        chatSideCubit.onPopPage();
                        return route.didPop(result);
                      },
                      pages: [
                        if (routeMode) chatContainerPage,
                        ...navigatorState.pages,
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SideRouter extends StatelessWidget {
  const _SideRouter({
    required this.chatSideCubit,
    required this.pages,
    this.onPopPage,
    required this.constraints,
  });

  final ChatSideCubit chatSideCubit;

  final List<Page<dynamic>> pages;

  final PopPageCallback? onPopPage;

  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final routeMode = chatSideCubit.state.routeMode;
    return routeMode
        ? SizedBox(
            width: constraints.maxWidth,
            child: Navigator(pages: pages, onPopPage: onPopPage))
        : _AnimatedChatSlide(
            constraints: constraints, pages: pages, onPopPage: onPopPage);
  }
}

class _AnimatedChatSlide extends HookWidget {
  const _AnimatedChatSlide({
    required this.pages,
    required this.constraints,
    required this.onPopPage,
  });

  final List<Page<dynamic>> pages;

  final PopPageCallback? onPopPage;

  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 300),
    );

    final _pages = useState(<Page<dynamic>>[]);

    useEffect(() {
      if (pages.isNotEmpty) {
        _pages.value = pages;
        controller.forward();
      } else {
        controller.reverse().whenComplete(() {
          _pages.value = pages;
        });
      }
    }, [pages, controller]);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => SizedBox(
        width: kChatSidePageWidth *
            Curves.easeInOut.transform(
              controller.value,
            ),
        height: constraints.maxHeight,
        child: controller.value != 0 ? child : null,
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: AlignmentDirectional.centerStart,
          maxHeight: constraints.maxHeight,
          minHeight: constraints.maxHeight,
          maxWidth: kChatSidePageWidth,
          minWidth: kChatSidePageWidth,
          child: Navigator(
            pages: _pages.value,
            onPopPage: onPopPage,
          ),
        ),
      ),
    );
  }
}

class ChatContainer extends HookWidget {
  const ChatContainer({super.key});

  @override
  Widget build(BuildContext context) {
    final quoteMessageCubit = useBloc(QuoteMessageCubit.new);
    BlocProvider.of<MessageBloc>(context).limit =
        MediaQuery.of(context).size.height ~/ 20;

    final pendingJumpMessageCubit = useBloc(PendingJumpMessageCubit.new);

    final inMultiSelectMode = useBlocStateConverter<MessageSelectionCubit,
        MessageSelectionState, bool>(
      converter: (state) => state.hasSelectedMessage,
    );

    return RepaintBoundary(
      child: MultiProvider(
        providers: [
          BlocProvider.value(value: quoteMessageCubit),
          BlocProvider.value(value: pendingJumpMessageCubit),
        ],
        child: FocusableActionDetector(
          autofocus: true,
          shortcuts: {
            if (inMultiSelectMode)
              const SingleActivator(LogicalKeyboardKey.escape):
                  const EscapeIntent(),
          },
          actions: {
            EscapeIntent: CallbackAction<EscapeIntent>(
              onInvoke: (intent) {
                context.read<MessageSelectionCubit>().clearSelection();
              },
            )
          },
          child: Column(
            children: [
              Container(
                height: 64,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: context.theme.divider,
                    ),
                  ),
                ),
                child: const ChatBar(),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.theme.chatBackground,
                    image: DecorationImage(
                      image: const ExactAssetImage(
                        Resources.assetsImagesChatBackgroundPng,
                      ),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        context.brightnessValue == 1.0
                            ? Colors.white.withOpacity(0.02)
                            : Colors.black.withOpacity(0.03),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  child: Navigator(
                    onPopPage: (Route<dynamic> route, dynamic result) =>
                        route.didPop(result),
                    pages: [
                      MaterialPage(
                        child: _ChatDropOverlay(
                          enable: !inMultiSelectMode,
                          child: Column(
                            children: [
                              Expanded(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: context.theme.divider,
                                      ),
                                    ),
                                  ),
                                  child: const Stack(
                                    children: [
                                      RepaintBoundary(
                                        child: _NotificationListener(
                                          child: _List(),
                                        ),
                                      ),
                                      Positioned(
                                        left: 6,
                                        right: 6,
                                        bottom: 6,
                                        child: _BottomBanner(),
                                      ),
                                      Positioned(
                                        bottom: 16,
                                        right: 16,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _JumpMentionButton(),
                                            _JumpCurrentButton(),
                                          ],
                                        ),
                                      ),
                                      _PinMessagesBanner(),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedCrossFade(
                                firstChild: const InputContainer(),
                                secondChild: const SelectionBottomBar(),
                                crossFadeState: inMultiSelectMode
                                    ? CrossFadeState.showSecond
                                    : CrossFadeState.showFirst,
                                duration: const Duration(milliseconds: 300),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationListener extends StatelessWidget {
  const _NotificationListener({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          final dimension = notification.metrics.viewportDimension / 2;

          if (notification is ScrollUpdateNotification) {
            if (notification.scrollDelta == null) return false;

            if (notification.scrollDelta! > 0) {
              // down
              if (notification.metrics.maxScrollExtent -
                      notification.metrics.pixels <
                  dimension) {
                BlocProvider.of<MessageBloc>(context).after();
              }
            } else if (notification.scrollDelta! < 0) {
              // up
              if ((notification.metrics.minScrollExtent -
                          notification.metrics.pixels)
                      .abs() <
                  dimension) {
                BlocProvider.of<MessageBloc>(context).before();
              }
            }
          }

          return false;
        },
        child: child,
      );
}

class _List extends HookWidget {
  const _List();

  @override
  Widget build(BuildContext context) {
    final state = useBlocState<MessageBloc, MessageState>(
      when: (state) => state.conversationId != null,
    );

    final key = ValueKey(
      (
        state.conversationId,
        state.refreshKey,
      ),
    );
    final top = state.top;
    final center = state.center;
    final bottom = state.bottom;

    final ref = useRef<Map<String, Key>>({});

    final ids = state.list.map((e) => e.messageId);

    useMemoized(() {
      ref.value.removeWhere((key, value) => !ids.contains(key));
      ids.forEach((id) {
        ref.value[id] = ref.value[id] ?? GlobalKey(debugLabel: id);
      });
    }, [ids]);

    final topKey = useMemoized(() => GlobalKey(debugLabel: 'chat list top'));
    final bottomKey =
        useMemoized(() => GlobalKey(debugLabel: 'chat list bottom'));

    final scrollController =
        BlocProvider.of<MessageBloc>(context).scrollController;

    return MessageDayTimeViewportWidget.chatPage(
      key: key,
      bottomKey: bottomKey,
      center: center,
      topKey: topKey,
      scrollController: scrollController,
      centerKey:
          center == null ? null : ref.value[center.messageId] as GlobalKey?,
      child: ClampingCustomScrollView(
        key: key,
        center: key,
        controller: scrollController,
        anchor: 0.3,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverList(
            key: topKey,
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                final actualIndex = top.length - index - 1;
                final messageItem = top[actualIndex];
                return MessageItemWidget(
                  key: ref.value[messageItem.messageId],
                  prev: top.getOrNull(actualIndex - 1),
                  message: messageItem,
                  next: top.getOrNull(actualIndex + 1) ??
                      center ??
                      bottom.lastOrNull,
                  lastReadMessageId: state.lastReadMessageId,
                );
              },
              childCount: top.length,
            ),
          ),
          SliverToBoxAdapter(
            key: key,
            child: Builder(builder: (context) {
              if (center == null) return const SizedBox();
              return MessageItemWidget(
                key: ref.value[center.messageId],
                prev: top.lastOrNull,
                message: center,
                next: bottom.firstOrNull,
                lastReadMessageId: state.lastReadMessageId,
              );
            }),
          ),
          SliverList(
            key: bottomKey,
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                final messageItem = bottom[index];
                return MessageItemWidget(
                  key: ref.value[messageItem.messageId],
                  prev: bottom.getOrNull(index - 1) ?? center ?? top.lastOrNull,
                  message: messageItem,
                  next: bottom.getOrNull(index + 1),
                  lastReadMessageId: state.lastReadMessageId,
                );
              },
              childCount: bottom.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
        ],
      ),
    );
  }
}

class _JumpCurrentButton extends HookWidget {
  const _JumpCurrentButton();

  @override
  Widget build(BuildContext context) {
    final messageBloc = context.read<MessageBloc>();
    final conversationId =
        useBlocStateConverter<ConversationCubit, ConversationState?, String?>(
      converter: (state) => state?.conversationId,
      when: (conversationId) => conversationId != null,
    )!;

    final state = useBlocState<MessageBloc, MessageState>();
    final scrollController = useListenable(messageBloc.scrollController);

    final listPositionIsLatest = useState(false);

    double? pixels;
    try {
      pixels = scrollController.position.pixels;
    } catch (_) {}

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) =>
          listPositionIsLatest.value = scrollController.hasClients &&
              (scrollController.position.maxScrollExtent -
                      scrollController.position.pixels) >
                  40);
    }, [
      scrollController.hasClients,
      pixels,
      conversationId,
      state.refreshKey,
    ]);

    final enable =
        (!state.isEmpty && !state.isLatest) || listPositionIsLatest.value;

    final pendingJumpMessageCubit = context.read<PendingJumpMessageCubit>();

    if (!enable) {
      pendingJumpMessageCubit.emit(null);
      return const SizedBox();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InteractiveDecoratedBox(
        onTap: () {
          final messageId = pendingJumpMessageCubit.state;
          if (messageId != null) {
            messageBloc.scrollTo(messageId);
            context.read<BlinkCubit>().blinkByMessageId(messageId);
            pendingJumpMessageCubit.emit(null);
            return;
          }
          messageBloc.jumpToCurrent();
        },
        child: Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            color: context.messageBubbleColor(false),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.15),
                offset: Offset(0, 2),
                blurRadius: 10,
              ),
            ],
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(
            Resources.assetsImagesJumpCurrentArrowSvg,
            colorFilter: ColorFilter.mode(context.theme.text, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}

class _BottomBanner extends HookWidget {
  const _BottomBanner();

  @override
  Widget build(BuildContext context) {
    final userId =
        useBlocStateConverter<ConversationCubit, ConversationState?, String?>(
            converter: (state) => state?.userId);
    final isScam =
        useBlocStateConverter<ConversationCubit, ConversationState?, bool>(
            converter: (state) => (state?.user?.isScam ?? 0) > 0);

    final showScamWarning = useMemoizedStream(
          () {
            if (userId == null || !isScam) return Stream.value(false);
            return ScamWarningKeyValue.instance.watch(userId);
          },
          initialData: false,
          keys: [userId],
        ).data ??
        false;

    return AnimatedVisibility(
      visible: showScamWarning,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          color: context.messageBubbleColor(false),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.15),
              offset: Offset(0, 2),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: 8,
                right: 16,
                top: 8,
                bottom: 8,
              ),
              child: SvgPicture.asset(
                Resources.assetsImagesTriangleWarningSvg,
                colorFilter:
                    ColorFilter.mode(context.theme.red, BlendMode.srcIn),
                width: 26,
                height: 26,
              ),
            ),
            Expanded(
              child: Text(
                context.l10n.scamWarning,
                style: TextStyle(
                  color: context.theme.text,
                  fontSize: 14,
                ),
              ),
            ),
            ActionButton(
              name: Resources.assetsImagesIcCloseSvg,
              color: context.theme.icon,
              size: 20,
              onTap: () {
                final userId = context.read<ConversationCubit>().state?.userId;
                if (userId == null) return;
                ScamWarningKeyValue.instance.dismiss(userId);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PinMessagesBanner extends HookWidget {
  const _PinMessagesBanner();

  @override
  Widget build(BuildContext context) {
    final currentPinMessageIds = context.watchCurrentPinMessageIds;
    final lastMessage = context.lastMessage;

    final showLastPinMessage = lastMessage?.isNotEmpty ?? false;

    return Positioned(
      top: 12,
      right: 16,
      left: 10,
      height: 64,
      child: AnimatedVisibility(
        visible: showLastPinMessage || currentPinMessageIds.isNotEmpty,
        child: Row(
          children: [
            Expanded(
              child: AnimatedVisibility(
                visible: showLastPinMessage,
                child: PinMessageBubble(
                  child: Row(
                    children: [
                      ActionButton(
                        name: Resources.assetsImagesIcCloseSvg,
                        color: context.theme.icon,
                        size: 20,
                        onTap: () {
                          final conversationId = context
                              .read<ConversationCubit>()
                              .state
                              ?.conversationId;
                          if (conversationId == null) return;
                          ShowPinMessageKeyValue.instance
                              .dismiss(conversationId);
                        },
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          (lastMessage ?? '').overflow,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedVisibility(
              visible: currentPinMessageIds.isNotEmpty,
              child: InteractiveDecoratedBox(
                onTap: () {
                  final cubit = context.read<ChatSideCubit>();
                  if (cubit.state.pages.lastOrNull?.name ==
                      ChatSideCubit.pinMessages) {
                    return cubit.pop();
                  }

                  cubit.replace(ChatSideCubit.pinMessages);
                },
                child: Container(
                  height: 34,
                  width: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.messageBubbleColor(false),
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.15),
                        offset: Offset(0, 2),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: SvgPicture.asset(
                    Resources.assetsImagesChatPinSvg,
                    width: 34,
                    height: 34,
                    colorFilter:
                        ColorFilter.mode(context.theme.text, BlendMode.srcIn),
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

class _JumpMentionButton extends HookWidget {
  const _JumpMentionButton();

  @override
  Widget build(BuildContext context) {
    final conversationId =
        useBlocStateConverter<ConversationCubit, ConversationState?, String?>(
      converter: (state) => state?.conversationId,
      when: (conversationId) => conversationId != null,
    )!;
    final messageMentions = useMemoizedStream(
            () => context.database.messageMentionDao
                    .unreadMentionMessageByConversationId(conversationId)
                    .watchWithStream(
                  eventStreams: [
                    DataBaseEventBus.instance.watchUpdateMessageMention(
                      conversationIds: [conversationId],
                    )
                  ],
                  duration: kSlowThrottleDuration,
                ),
            keys: [conversationId]).data ??
        [];

    if (messageMentions.isEmpty) return const SizedBox();

    return InteractiveDecoratedBox(
      onTap: () {
        final mention = messageMentions.first;
        context.read<MessageBloc>().scrollTo(mention.messageId);
        context.accountServer
            .markMentionRead(mention.messageId, mention.conversationId);
      },
      child: SizedBox(
        height: 52,
        width: 40,
        child: Stack(
          children: [
            Positioned(
              top: 12,
              child: Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: context.messageBubbleColor(false),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.15),
                      offset: Offset(0, 2),
                      blurRadius: 10,
                    ),
                  ],
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '@',
                  style: TextStyle(
                    fontSize: 17,
                    height: 1,
                    color: context.theme.text,
                  ),
                ),
              ),
            ),
            Container(
              width: 40,
              alignment: Alignment.topCenter,
              child: Container(
                decoration: BoxDecoration(
                  color: context.theme.accent,
                  shape: BoxShape.circle,
                ),
                width: 20,
                height: 20,
                alignment: Alignment.center,
                child: Text(
                  '${messageMentions.length}',
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1,
                    color: Colors.white,
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

class _ChatDropOverlay extends HookWidget {
  const _ChatDropOverlay({
    required this.child,
    required this.enable,
  });

  final Widget child;

  final bool enable;

  @override
  Widget build(BuildContext context) {
    final dragging = useState(false);
    final enable = useState(true);
    return DropTarget(
      onDragEntered: (_) => dragging.value = true,
      onDragExited: (_) => dragging.value = false,
      onDragDone: (details) async {
        final files = details.files.where((xFile) {
          final file = File(xFile.path);
          return file.existsSync();
        }).toList();
        if (files.isEmpty) {
          return;
        }
        enable.value = false;
        await showFilesPreviewDialog(
          context,
          files.map((e) => e.withMineType()).toList(),
        );
        enable.value = true;
      },
      enable: this.enable && enable.value,
      child: Stack(
        children: [
          child,
          if (dragging.value) const _ChatDragIndicator(),
        ],
      ),
    );
  }
}

class _ChatDragIndicator extends StatelessWidget {
  const _ChatDragIndicator();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: context.theme.popUp),
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: context.theme.listSelected,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              border: DashPathBorder.all(
                borderSide: BorderSide(
                  color: context.theme.divider,
                ),
                dashArray: CircularIntervalList([4, 4]),
              )),
          child: Center(
            child: Text(
              context.l10n.dragAndDropFileHere,
              style: TextStyle(
                fontSize: 14,
                color: context.theme.text,
              ),
            ),
          ),
        ),
      );
}

class _ChatMenuHandler extends HookWidget {
  const _ChatMenuHandler({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final conversationId =
        useBlocStateConverter<ConversationCubit, ConversationState?, String?>(
      converter: (state) => state?.conversationId,
      when: (conversationId) => conversationId != null,
    )!;

    useEffect(() {
      final cubit = context.read<MacMenuBarCubit?>();
      if (cubit == null) {
        return null;
      }
      final handle = _ConversationHandle(context, conversationId);
      cubit.attach(handle);
      return () => cubit.unAttach(handle);
    }, [conversationId]);

    return child;
  }
}

class _ConversationHandle extends ConversationMenuHandle {
  _ConversationHandle(this.context, this.conversationId);

  final BuildContext context;
  final String conversationId;

  @override
  Future<void> delete() async {
    final name = context.read<ConversationCubit>().state?.name ?? '';
    assert(name.isNotEmpty, 'name is empty');
    final ret = await showConfirmMixinDialog(
      context,
      context.l10n.conversationDeleteTitle(name),
      description: context.l10n.deleteChatDescription,
    );
    if (ret == null) return;
    await context.database.conversationDao.deleteConversation(conversationId);
    await context.database.pinMessageDao.deleteByConversationId(conversationId);
    if (context.read<ConversationCubit>().state?.conversationId ==
        conversationId) {
      context.read<ConversationCubit>().unselected();
    }
  }

  @override
  Stream<bool> get isMuted => context
      .read<ConversationCubit>()
      .stream
      .map((event) => event?.conversation?.isMute == true);

  @override
  Stream<bool> get isPinned => context
      .read<ConversationCubit>()
      .stream
      .map((event) => event?.conversation?.pinTime != null);

  @override
  Future<void> mute() async {
    final result = await showMixinDialog<int?>(
        context: context, child: const MuteDialog());
    if (result == null) return;
    final conversationState = context.read<ConversationCubit>().state;
    if (conversationState == null) {
      return;
    }
    final isGroupConversation = conversationState.isGroup == true;
    await runFutureWithToast(
      context.accountServer.muteConversation(
        result,
        conversationId: isGroupConversation ? conversationId : null,
        userId: isGroupConversation
            ? null
            : conversationState.conversation?.ownerId,
      ),
    );
  }

  @override
  void pin() {
    runFutureWithToast(
      context.accountServer.pin(conversationId),
    );
  }

  @override
  void showSearch() {
    final cubit = context.read<ChatSideCubit>();
    if (cubit.state.pages.lastOrNull?.name ==
        ChatSideCubit.searchMessageHistory) {
      return cubit.pop();
    }

    cubit.replace(ChatSideCubit.searchMessageHistory);
  }

  @override
  void toggleSideBar() {
    context.read<ChatSideCubit>().toggleInfoPage();
  }

  @override
  void unPin() {
    runFutureWithToast(
      context.accountServer.unpin(conversationId),
    );
  }

  @override
  void unmute() {
    final conversationState = context.read<ConversationCubit>().state;
    if (conversationState == null) {
      return;
    }
    final isGroup = conversationState.isGroup == true;
    runFutureWithToast(
      context.accountServer.unMuteConversation(
        conversationId: isGroup ? conversationId : null,
        userId: isGroup ? null : conversationState.conversation?.ownerId,
      ),
    );
  }
}
