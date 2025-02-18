import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:mixin_bot_sdk_dart/mixin_bot_sdk_dart.dart';

import '../../../constants/resources.dart';
import '../../../db/database_event_bus.dart';
import '../../../db/mixin_database.dart';
import '../../../utils/extension/extension.dart';
import '../../../utils/hook.dart';
import '../../../widgets/action_button.dart';
import '../../../widgets/app_bar.dart';
import '../../../widgets/avatar_view/avatar_view.dart';
import '../../../widgets/conversation/verified_or_bot_widget.dart';
import '../../../widgets/high_light_text.dart';
import '../../../widgets/menu.dart';
import '../../../widgets/search_text_field.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/user/user_dialog.dart';
import '../../../widgets/user_selector/conversation_selector.dart';
import '../bloc/conversation_cubit.dart';
import 'group_invite/group_invite_dialog.dart';

/// The participants of group.
class GroupParticipantsPage extends HookWidget {
  const GroupParticipantsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final conversationId = useMemoized(() {
      final conversationId =
          context.read<ConversationCubit>().state?.conversationId;
      assert(conversationId != null);
      return conversationId!;
    });

    final participants = useMemoizedStream(() {
          final dao = context.database.participantDao;
          return dao
              .groupParticipantsByConversationId(conversationId)
              .watchWithStream(
            eventStreams: [
              DataBaseEventBus.instance.watchUpdateParticipantStream(
                  conversationIds: [conversationId])
            ],
            duration: kDefaultThrottleDuration,
          );
        }, keys: [conversationId]).data ??
        const <ParticipantUser>[];

    // Find current user info to check if we have group manage permission.
    // Could be null if has been removed from group.
    final currentUser = useMemoized(
      () => participants
          .firstWhereOrNull((e) => e.userId == context.accountServer.userId),
      [participants],
    );

    final controller = useTextEditingController();

    return Scaffold(
      backgroundColor: context.theme.primary,
      appBar: MixinAppBar(
        title: Text(context.l10n.groupParticipants),
        actions: [
          if (currentUser?.role != null)
            _ActionAddParticipants(participants: participants)
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchTextField(
              hintText: context.l10n.settingAuthSearchHint,
              autofocus: context.textFieldAutoGainFocus,
              controller: controller,
            ),
          ),
          Expanded(
            child: _ParticipantList(
              filterKeyword: controller,
              currentUser: currentUser,
              participants: participants,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantList extends HookWidget {
  const _ParticipantList({
    required this.filterKeyword,
    required this.participants,
    required this.currentUser,
  });

  /// The keyword to filter participants of group.
  /// Empty indicates non filter.
  final ValueListenable<TextEditingValue> filterKeyword;

  final List<ParticipantUser> participants;

  final ParticipantUser? currentUser;

  @override
  Widget build(BuildContext context) {
    final keyword = useValueListenable(filterKeyword).text.trim();
    final filteredParticipants = useMemoized(() {
      if (keyword.isEmpty) {
        return participants;
      }
      return participants
          .where((e) =>
              (e.fullName?.toLowerCase().contains(keyword.toLowerCase()) ??
                  false) ||
              e.identityNumber.contains(keyword))
          .toList();
    }, [participants, keyword]);

    return ListView.builder(
      itemCount: filteredParticipants.length,
      padding: const EdgeInsets.only(top: 8),
      itemBuilder: (context, index) => _ParticipantTile(
        participant: filteredParticipants[index],
        currentUser: currentUser,
        keyword: keyword,
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.currentUser,
    required this.keyword,
  });

  final ParticipantUser participant;

  final ParticipantUser? currentUser;

  final String keyword;

  @override
  Widget build(BuildContext context) => _ParticipantMenuEntry(
        participant: participant,
        currentUser: currentUser,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          leading: AvatarWidget(
            size: 50,
            avatarUrl: participant.avatarUrl,
            userId: participant.userId,
            name: participant.fullName,
          ),
          title: Row(
            children: [
              Flexible(
                child: HighlightText(
                  participant.fullName ?? '?',
                  style: TextStyle(
                    color: context.theme.text,
                    fontSize: 16,
                  ),
                  highlightTextSpans: [
                    HighlightTextSpan(
                      keyword,
                      style: TextStyle(
                        color: context.theme.accent,
                      ),
                    )
                  ],
                ),
              ),
              VerifiedOrBotWidget(
                isBot: participant.appId != null,
                verified: participant.isVerified,
              ),
            ],
          ),
          onTap: () {
            showUserDialog(context, participant.userId);
          },
          trailing: _RoleWidget(role: participant.role),
        ),
      );
}

class _ParticipantMenuEntry extends StatelessWidget {
  const _ParticipantMenuEntry({
    required this.child,
    required this.participant,
    required this.currentUser,
  });

  final ParticipantUser participant;
  final ParticipantUser? currentUser;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final self = participant.userId == context.accountServer.userId;
    if (self) {
      return child;
    }

    return ContextMenuPortalEntry(
      buildMenus: () {
        final menus = [
          ContextMenu(
            icon: Resources.assetsImagesContextMenuChatSvg,
            title:
                context.l10n.groupPopMenuMessage(participant.fullName ?? '?'),
            onTap: () {
              ConversationCubit.selectUser(
                context,
                participant.userId,
              );
            },
          ),
        ];
        if (currentUser?.role == ParticipantRole.owner) {
          if (participant.role != ParticipantRole.admin) {
            menus.add(ContextMenu(
              icon: Resources.assetsImagesContextMenuUserEditSvg,
              title: context.l10n.makeGroupAdmin,
              onTap: () => runFutureWithToast(
                context.accountServer.updateParticipantRole(
                    context.read<ConversationCubit>().state!.conversationId,
                    participant.userId,
                    ParticipantRole.admin),
              ),
            ));
          } else {
            menus.add(ContextMenu(
              icon: Resources.assetsImagesContextMenuStopSvg,
              title: context.l10n.dismissAsAdmin,
              onTap: () => runFutureWithToast(context.accountServer
                  .updateParticipantRole(
                      context.read<ConversationCubit>().state!.conversationId,
                      participant.userId,
                      null)),
            ));
          }
        }

        if (currentUser?.role != null && participant.role == null ||
            currentUser?.role == ParticipantRole.owner) {
          menus.add(ContextMenu(
            icon: Resources.assetsImagesContextMenuDeleteSvg,
            isDestructiveAction: true,
            title: context.l10n.groupPopMenuRemove(participant.fullName ?? '?'),
            onTap: () => runFutureWithToast(context.accountServer
                .removeParticipant(
                    context.read<ConversationCubit>().state!.conversationId,
                    participant.userId)),
          ));
        }
        return menus;
      },
      child: child,
    );
  }
}

class _RoleWidget extends StatelessWidget {
  const _RoleWidget({required this.role});

  final ParticipantRole? role;

  @override
  Widget build(BuildContext context) {
    switch (role) {
      case ParticipantRole.owner:
        return _RoleLabel(context.l10n.owner);
      case ParticipantRole.admin:
        return _RoleLabel(context.l10n.admin);
      case null:
        return Container(width: 0);
    }
  }
}

class _RoleLabel extends StatelessWidget {
  const _RoleLabel(
    this.label,
  );

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          color: context.theme.secondaryText,
          fontSize: 14,
        ),
      );
}

class _ActionAddParticipants extends StatelessWidget {
  const _ActionAddParticipants({
    required this.participants,
  });

  final List<ParticipantUser> participants;

  @override
  Widget build(BuildContext context) => ContextMenuPortalEntry(
        buildMenus: () => [
          ContextMenu(
            icon: Resources.assetsImagesContextMenuSearchUserSvg,
            title: context.l10n.addParticipants,
            onTap: () async {
              final result = await showConversationSelector(
                context: context,
                singleSelect: false,
                title: context.l10n.addParticipants,
                onlyContact: true,
              );
              if (result == null || result.isEmpty) return;

              final userIds =
                  result.map((e) => e.userId).whereNotNull().toList();
              final conversationId =
                  context.read<ConversationCubit>().state?.conversationId;
              assert(conversationId != null);
              await runFutureWithToast(
                context.accountServer.addParticipant(conversationId!, userIds),
              );
            },
          ),
          ContextMenu(
            icon: Resources.assetsImagesContextMenuLinkSvg,
            title: context.l10n.inviteToGroupViaLink,
            onTap: () {
              final conversationCubit = context.read<ConversationCubit>().state;
              assert(conversationCubit != null);
              showGroupInviteByLinkDialog(context,
                  conversationId: conversationCubit!.conversationId);
            },
          ),
        ],
        child: Builder(
            builder: (context) => ActionButton(
                  name: Resources.assetsImagesIcAddSvg,
                  color: context.theme.icon,
                  onTapUp: (event) =>
                      context.sendMenuPosition(event.globalPosition),
                )),
      );
}
