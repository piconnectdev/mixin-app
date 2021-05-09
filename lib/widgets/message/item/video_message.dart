import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mixin_bot_sdk_dart/mixin_bot_sdk_dart.dart';
import 'package:provider/provider.dart';

import '../../../account/account_server.dart';
import '../../../constants/resources.dart';
import '../../../db/mixin_database.dart' hide Offset, Message;
import '../../../enum/media_status.dart';
import '../../../utils/uri_utils.dart';
import '../../brightness_observer.dart';
import '../../image.dart';
import '../../interacter_decorated_box.dart';
import '../../status.dart';
import '../message_bubble.dart';
import '../message_datetime.dart';
import '../message_status.dart';

class VideoMessageWidget extends StatelessWidget {
  const VideoMessageWidget({
    Key? key,
    required this.message,
    required this.isCurrentUser,
    required this.showNip,
  }) : super(key: key);

  final MessageItem message;
  final bool isCurrentUser;
  final bool showNip;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, boxConstraints) {
          final maxWidth = min(boxConstraints.maxWidth * 0.6, 200);
          final width = min(message.mediaWidth!, maxWidth).toDouble();
          final scale = message.mediaWidth! / message.mediaHeight!;
          final height = width / scale;

          return MessageBubble(
            quoteMessageId: message.quoteId,
            quoteMessageContent: message.quoteContent,
            isCurrentUser: isCurrentUser,
            padding: EdgeInsets.zero,
            showNip: showNip,
            includeNip: true,
            child: InteractableDecoratedBox(
              onTap: () {
                if (message.mediaStatus == MediaStatus.canceled) {
                  if (message.relationship == UserRelationship.me &&
                      message.mediaUrl?.isNotEmpty == true) {
                    context.read<AccountServer>().reUploadAttachment(message);
                  } else {
                    context.read<AccountServer>().downloadAttachment(message);
                  }
                } else if (message.mediaStatus == MediaStatus.done &&
                    message.mediaUrl != null) {
                  openUri(Uri.file(message.mediaUrl!).toString());
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: height,
                  width: width,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (message.thumbImage != null)
                        ImageByBase64(message.thumbImage!),
                      Center(
                        child: Builder(
                          builder: (BuildContext context) {
                            switch (message.mediaStatus) {
                              case MediaStatus.canceled:
                                if (message.relationship ==
                                        UserRelationship.me &&
                                    message.mediaUrl?.isNotEmpty == true)
                                  return const StatusUpload();
                                else
                                  return const StatusDownload();
                              case MediaStatus.pending:
                                return const StatusPending();
                              case MediaStatus.expired:
                                return const StatusWarning();
                              default:
                                return SvgPicture.asset(
                                  Resources.assetsImagesPlaySvg,
                                  width: 38,
                                  height: 38,
                                );
                            }
                          },
                        ),
                      ),
                      Builder(builder: (context) {
                        try {
                          final duration = Duration(
                              milliseconds: int.parse(message.mediaDuration!));
                          return Positioned(
                            top: 6,
                            left: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color.fromRGBO(0, 0, 0, 0.3),
                                borderRadius: BorderRadius.circular(5.0),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Text(
                                  '${duration.inMinutes.remainder(60)}:${duration.inSeconds.remainder(60)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: BrightnessData.themeOf(context).text,
                                  ),
                                ),
                              ),
                            ),
                          );
                        } catch (e) {
                          return const SizedBox();
                        }
                      }),
                      Positioned(
                        bottom: 4,
                        right: 12,
                        child: DecoratedBox(
                          decoration: const ShapeDecoration(
                            color: Color.fromRGBO(0, 0, 0, 0.3),
                            shape: StadiumBorder(),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 3,
                              horizontal: 5,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MessageDatetime(dateTime: message.createdAt),
                                MessageStatusWidget(status: message.status),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}
