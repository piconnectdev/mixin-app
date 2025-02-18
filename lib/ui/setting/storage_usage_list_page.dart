import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:watcher/watcher.dart';

import '../../db/extension/conversation.dart';
import '../../db/mixin_database.dart';
import '../../utils/extension/extension.dart';
import '../../utils/hook.dart';
import '../../widgets/app_bar.dart';
import '../../widgets/avatar_view/avatar_view.dart';
import '../../widgets/cell.dart';
import '../home/route/responsive_navigator_cubit.dart';

class StorageUsageListPage extends HookWidget {
  const StorageUsageListPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.theme.background,
        appBar: MixinAppBar(
          title: Text(context.l10n.storageUsage),
        ),
        body: const _Content(),
      );
}

class _Content extends HookWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    final watchEvent = useMemoizedStream(
      () => DirectoryWatcher(context.accountServer.getMediaFilePath())
          .events
          .throttleTime(const Duration(milliseconds: 400)),
    ).data;

    final list =
        useMemoizedFuture<List<(ConversationStorageUsage, int)>?>(() async {
      try {
        final accountServer = context.accountServer;
        final list = await accountServer.database.conversationDao
            .conversationStorageUsage()
            .get();
        final result = await Future.wait(
          list.map(
            (e) async => (
              e,
              await accountServer.getConversationMediaSize(e.conversationId),
            ),
          ),
        );
        result.sort((a, b) => b.$2 - a.$2);
        return result;
      } catch (e) {
        return [];
      }
    }, null, keys: [watchEvent]).data;

    if (list == null) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(context.theme.accent),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 40),
      itemBuilder: (_, index) {
        final (item, size) = list[index];
        return _Item(item: item, size: size);
      },
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: list.length,
    );
  }
}

class _Item extends HookWidget {
  const _Item({
    required this.item,
    required this.size,
  });

  final ConversationStorageUsage item;
  final int size;

  @override
  Widget build(BuildContext context) {
    final sizeString = useMemoized(() => filesize(size), [item, size]);
    return Align(
      child: CellGroup(
        padding: EdgeInsets.zero,
        cellBackgroundColor: context.dynamicColor(
          Colors.white,
          darkColor: const Color.fromRGBO(255, 255, 255, 0.06),
        ),
        child: CellItem(
          leading: ConversationAvatarWidget(
            conversationId: item.conversationId,
            fullName: item.fullName,
            groupIconUrl: item.iconUrl,
            avatarUrl: item.avatarUrl,
            category: item.category,
            size: 50,
            userId: item.ownerId,
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(conversationValidName(item.name, item.fullName)),
              Text(
                sizeString,
                style: TextStyle(
                  color: context.theme.secondaryText,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          onTap: () => context.read<ResponsiveNavigatorCubit>().pushPage(
            ResponsiveNavigatorCubit.storageUsageDetail,
            arguments: (
              conversationValidName(item.name, item.fullName),
              item.conversationId,
            ),
          ),
        ),
      ),
    );
  }
}
