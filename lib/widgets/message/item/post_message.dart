import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/svg.dart';

import '../../../constants/resources.dart';
import '../../../db/mixin_database.dart' hide Offset, Message;
import '../../../utils/extension/extension.dart';
import '../../app_bar.dart';
import '../../buttons.dart';
import '../../interactive_decorated_box.dart';
import '../../markdown.dart';
import '../message.dart';
import '../message_bubble.dart';
import '../message_datetime_and_status.dart';
import '../message_style.dart';

const _decoration = BoxDecoration(
  borderRadius: BorderRadius.all(Radius.circular(8)),
  color: Color.fromRGBO(0, 0, 0, 0.2),
);

class PostMessage extends HookWidget {
  const PostMessage({super.key});

  @override
  Widget build(BuildContext context) {
    final content =
        useMessageConverter(converter: (state) => state.content ?? '');

    return MessageBubble(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: DefaultTextStyle.merge(
          style: TextStyle(fontSize: context.messageStyle.primaryFontSize),
          child: MessagePost(showStatus: true, content: content),
        ),
      ),
    );
  }
}

class MessagePost extends StatelessWidget {
  const MessagePost({
    super.key,
    this.padding,
    this.decoration,
    required this.showStatus,
    required this.content,
    this.clickable = true,
  });

  final EdgeInsetsGeometry? padding;
  final Decoration? decoration;
  final bool showStatus;
  final String content;
  final bool clickable;

  @override
  Widget build(BuildContext context) => SelectionArea(
        selectionControls: _PostTextSelectionControls(),
        child: InteractiveDecoratedBox(
          onTap: clickable
              ? () => PostPreview.push(context, message: context.message)
              : null,
          behavior: HitTestBehavior.deferToChild,
          child: Container(
            padding: padding,
            decoration: decoration,
            child: Stack(
              children: [
                HookBuilder(builder: (context) {
                  final postContent =
                      useMemoized(content.postOptimize, [content]);

                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: showStatus ? 48 : 0,
                      minWidth: 128,
                      maxHeight: 400,
                    ),
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: MarkdownColumn(data: postContent),
                      ),
                    ),
                  );
                }),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    decoration: _decoration,
                    alignment: Alignment.center,
                    child: SvgPicture.asset(
                      Resources.assetsImagesPostDetailSvg,
                      width: 20,
                      height: 20,
                    ),
                  ),
                ),
                if (showStatus)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: _decoration,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: const MessageDatetimeAndStatus(
                        color: Color.fromRGBO(255, 255, 255, 1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

class PostPreview extends StatelessWidget {
  const PostPreview({
    super.key,
    required this.message,
  });

  static Future<void> push(
    BuildContext context, {
    required MessageItem message,
  }) =>
      showGeneralDialog(
        context: context,
        barrierColor: Colors.transparent,
        barrierDismissible: true,
        barrierLabel:
            MaterialLocalizations.of(context).modalBarrierDismissLabel,
        pageBuilder: (BuildContext buildContext, Animation<double> animation,
                Animation<double> secondaryAnimation) =>
            InheritedTheme.capture(
                    from: context,
                    to: Navigator.of(context, rootNavigator: true).context)
                .wrap(
          PostPreview(
            message: message,
          ),
        ),
      );

  final MessageItem message;

  @override
  Widget build(BuildContext context) => Material(
        color: context.theme.background,
        child: Column(
          children: [
            MixinAppBar(
              leading: const SizedBox(),
              actions: [
                MixinCloseButton(
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
            Expanded(
              child: Markdown(
                data: message.content ?? '',
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 32),
              ),
            ),
          ],
        ),
      );
}

class _PostTextSelectionControls extends TextSelectionControls {
  @override
  Widget buildHandle(BuildContext context, TextSelectionHandleType type,
          double textLineHeight,
          [VoidCallback? onTap]) =>
      const SizedBox.shrink();

  @override
  Widget buildToolbar(
          BuildContext context,
          Rect globalEditableRegion,
          double textLineHeight,
          Offset position,
          List<TextSelectionPoint> endpoints,
          TextSelectionDelegate delegate,
          ValueListenable<ClipboardStatus>? clipboardStatus,
          Offset? lastSecondaryTapDownPosition) =>
      const SizedBox.shrink();

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) =>
      Offset.zero;

  @override
  Size getHandleSize(double textLineHeight) => Size.zero;
}
