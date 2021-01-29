import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/blaze/vo/live_message.dart';
import 'package:flutter_app/blaze/vo/attachment_message.dart';
import 'package:flutter_app/blaze/vo/blaze_message_data.dart';
import 'package:flutter_app/blaze/vo/contact_message.dart';
import 'package:flutter_app/blaze/vo/location_message.dart';
import 'package:flutter_app/blaze/vo/plain_json_message.dart';
import 'package:flutter_app/blaze/vo/recall_message.dart';
import 'package:flutter_app/blaze/vo/snapshot_message.dart';
import 'package:flutter_app/blaze/vo/sticker_message.dart';
import 'package:flutter_app/blaze/vo/system_circle_message.dart';
import 'package:flutter_app/blaze/vo/system_conversation_message.dart';
import 'package:flutter_app/blaze/vo/system_session_message.dart';
import 'package:flutter_app/blaze/vo/system_user_message.dart';
import 'package:flutter_app/constants.dart';
import 'package:flutter_app/db/database.dart';
import 'package:flutter_app/db/mixin_database.dart';
import 'package:flutter_app/enum/media_status.dart';
import 'package:flutter_app/enum/message_status.dart';
import 'package:flutter_app/utils/attachment_util.dart';
import 'package:flutter_app/utils/enum_to_string.dart';
import 'package:flutter_app/utils/load_Balancer_utils.dart';
import 'package:mixin_bot_sdk_dart/mixin_bot_sdk_dart.dart';
import 'package:uuid/uuid.dart';
import 'injector.dart';

class DecryptMessage extends Injector {
  DecryptMessage(String selfId, Database database, Client client, this._attachmentUtil) : super(selfId, database, client);

  String _conversationId;
  AttachmentUtil _attachmentUtil;

  void setConversationId(String conversationId) {
    _conversationId = conversationId;
  }

  void process(FloodMessage floodMessage) async {
    final data = BlazeMessageData.fromJson(
        await LoadBalancerUtils.jsonDecode(floodMessage.data));
    if (data.conversationId != null) {
      syncConversion(data.conversationId);
    }
    final category = data.category;
    if (category.startsWith('SIGNAL_')) {
      _processSignalMessage(data);
    } else if (category.startsWith('PLAIN_')) {
      processPlainMessage(data);
    } else if (category.startsWith('SYSTEM_')) {
      _processSystemMessage(data);
    } else if (category == 'APP_BUTTON_GROUP' || category == 'APP_CARD') {
      _processApp(data);
    } else if (category == 'MESSAGE_RECALL') {
      _processRecallMessage(data);
    }
    _updateRemoteMessageStatus(floodMessage.messageId, MessageStatus.delivered);
    await database.floodMessagesDao.deleteFloodMessage(floodMessage);
  }

  void _processSignalMessage(BlazeMessageData data) {
    // todo decrypt
    _updateRemoteMessageStatus(data.messageId, MessageStatus.delivered);
  }

  void processPlainMessage(BlazeMessageData data) {
    if (data.category == MessageCategory.plainJson) {
      final plain = utf8.decode(base64.decode(data.data));
      final plainJsonMessage = PlainJsonMessage.fromJson(jsonDecode(plain));
      if (plainJsonMessage.action == acknowledgeMessageReceipts &&
          plainJsonMessage.ackMessages?.isNotEmpty == true) {
        _markMessageStatus(plainJsonMessage.ackMessages);
      } else if (plainJsonMessage.action == resendMessages) {
        // todo
      } else if (plainJsonMessage.action == resendKey) {
        // todo
      }
      _updateRemoteMessageStatus(data.messageId, MessageStatus.delivered);
    } else if (data.category == MessageCategory.plainText ||
        data.category == MessageCategory.plainImage ||
        data.category == MessageCategory.plainVideo ||
        data.category == MessageCategory.plainData ||
        data.category == MessageCategory.plainAudio ||
        data.category == MessageCategory.plainContact ||
        data.category == MessageCategory.plainSticker ||
        data.category == MessageCategory.plainLive ||
        data.category == MessageCategory.plainPost ||
        data.category == MessageCategory.plainLocation) {
      if (data.representativeId?.isNotEmpty == true) {
        data.userId = data.representativeId;
      }
      _processDecryptSuccess(data, data.data);
    }
  }

  void _processSystemMessage(BlazeMessageData data) {
    if (data.category == MessageCategory.systemConversation) {
      final systemMessage = SystemConversationMessage.fromJson(
          jsonDecode(utf8.decode(base64.decode(data.data))));
      _processSystemConversationMessage(data, systemMessage);
    } else if (data.category == MessageCategory.systemUser) {
      final systemMessage = SystemUserMessage.fromJson(
          jsonDecode(utf8.decode(base64.decode(data.data))));
      _processSystemUserMessage(systemMessage);
    } else if (data.category == MessageCategory.systemCircle) {
      final systemMessage = SystemCircleMessage.fromJson(
          jsonDecode(utf8.decode(base64.decode(data.data))));
      _processSystemCircleMessage(data, systemMessage);
    } else if (data.category == MessageCategory.systemAccountSnapshot) {
      final systemSnapshot = SnapshotMessage.fromJson(
          jsonDecode(utf8.decode(base64.decode(data.data))));
      _processSystemSnapshotMessage(data, systemSnapshot);
    } else if (data.category == MessageCategory.systemSession) {
      final systemSession = SystemSessionMessage.fromJson(
          jsonDecode(utf8.decode(base64.decode(data.data))));
      _processSystemSessionMessage(systemSession);
    }
    _updateRemoteMessageStatus(data.messageId, MessageStatus.read);
  }

  void _processApp(BlazeMessageData data) {
    _updateRemoteMessageStatus(data.messageId, MessageStatus.read);
  }

  void _processRecallMessage(BlazeMessageData data) {
    // todo
    // ignore: unused_local_variable
    final recallMessage = RecallMessage.fromJson(
        jsonDecode(utf8.decode(base64.decode(data.data))));
    _updateRemoteMessageStatus(data.messageId, MessageStatus.read);
  }

  void _processDecryptSuccess(BlazeMessageData data, String plainText) async {
    // todo
    // ignore: unused_local_variable
    final user = await syncUser(data.userId);

    // todo process quote message

    var messageStatus = MessageStatus.delivered;
    if (_conversationId != null && data.conversationId == _conversationId) {
      messageStatus = MessageStatus.read;
    }

    if (data.category.endsWith('_TEXT')) {
      String plain;
      if (data.category == MessageCategory.signalText) {
        plain = 'SignalText';
      } else {
        plain = utf8.decode(base64.decode(plainText));
      }
      final message = Message(
        messageId: data.messageId,
        conversationId: data.conversationId,
        userId: data.userId,
        category: data.category,
        content: plain,
        status: messageStatus,
        createdAt: data.createdAt,
      );
      await database.messagesDao.insert(message, selfId);
    } else if (data.category.endsWith('_IMAGE')) {
      String plain;
      if (data.category == MessageCategory.signalImage) {
        _updateRemoteMessageStatus(data.messageId, messageStatus);
        return;
      } else {
        plain = utf8.decode(base64.decode(plainText));
      }
      final attachment =
          AttachmentMessage.fromJson(await LoadBalancerUtils.jsonDecode(plain));
      final message = Message(
          messageId: data.messageId,
          conversationId: data.conversationId,
          userId: data.userId,
          category: data.category,
          content: attachment.attachmentId,
          mediaUrl: null,
          mediaMimeType: attachment.mimeType,
          mediaSize: attachment.size,
          mediaWidth: attachment.width,
          mediaHeight: attachment.height,
          thumbImage: attachment.thumbnail,
          mediaKey: attachment.key,
          mediaDigest: attachment.digest,
          status: messageStatus,
          createdAt: data.createdAt,
          mediaStatus: MediaStatus.canceled);
      await database.messagesDao.insert(message, selfId);
    } else if (data.category.endsWith('_VIDEO')) {
      String plain;
      if (data.category == MessageCategory.signalVideo) {
        _updateRemoteMessageStatus(data.messageId, messageStatus);
        return;
      } else {
        plain = utf8.decode(base64.decode(plainText));
      }
      final attachment =
          AttachmentMessage.fromJson(await LoadBalancerUtils.jsonDecode(plain));
      final message = Message(
          messageId: data.messageId,
          conversationId: data.conversationId,
          userId: data.userId,
          category: data.category,
          content: attachment.attachmentId,
          name: attachment.name,
          mediaMimeType: attachment.mimeType,
          mediaDuration: attachment.duration.toString(),
          mediaSize: attachment.size,
          mediaWidth: attachment.width,
          mediaHeight: attachment.height,
          thumbImage: attachment.thumbnail,
          mediaKey: attachment.key,
          mediaDigest: attachment.digest,
          status: messageStatus,
          createdAt: data.createdAt,
          mediaStatus: MediaStatus.canceled);
      await database.messagesDao.insert(message, selfId);
    } else if (data.category.endsWith('_DATA')) {
      String plain;
      if (data.category == MessageCategory.signalData) {
        _updateRemoteMessageStatus(data.messageId, messageStatus);
        return;
      } else {
        plain = utf8.decode(base64.decode(plainText));
      }
      final attachment =
          AttachmentMessage.fromJson(await LoadBalancerUtils.jsonDecode(plain));
      final message = Message(
          messageId: data.messageId,
          conversationId: data.conversationId,
          userId: data.userId,
          category: data.category,
          content: attachment.attachmentId,
          name: attachment.name,
          mediaMimeType: attachment.mimeType,
          mediaSize: attachment.size,
          mediaKey: attachment.key,
          mediaDigest: attachment.digest,
          status: messageStatus,
          createdAt: data.createdAt,
          mediaStatus: MediaStatus.canceled);
      await database.messagesDao.insert(message, selfId);
    } else if (data.category.endsWith('_AUDIO')) {
      String plain;
      if (data.category == MessageCategory.signalAudio) {
        _updateRemoteMessageStatus(data.messageId, messageStatus);
        return;
      } else {
        plain = utf8.decode(base64.decode(plainText));
      }
      final attachment =
          AttachmentMessage.fromJson(await LoadBalancerUtils.jsonDecode(plain));
      final message = Message(
          messageId: data.messageId,
          conversationId: data.conversationId,
          userId: data.userId,
          category: data.category,
          content: attachment.attachmentId,
          name: attachment.name,
          mediaMimeType: attachment.mimeType,
          mediaSize: attachment.size,
          mediaKey: attachment.key,
          mediaDigest: attachment.digest,
          mediaWaveform: attachment.waveform,
          status: messageStatus,
          createdAt: data.createdAt,
          mediaStatus: MediaStatus.pending);
      await database.messagesDao.insert(message, selfId);
    } else if (data.category.endsWith('_STICKER')) {
      String plain;
      if (data.category == MessageCategory.signalSticker) {
        _updateRemoteMessageStatus(data.messageId, messageStatus);
        return;
      } else {
        plain = utf8.decode(base64.decode(plainText));
      }
      final stickerMessage =
          StickerMessage.fromJson(await LoadBalancerUtils.jsonDecode(plain));
      final sticker = await database.stickerDao
          .getStickerByUnique(stickerMessage.stickerId);
      if (sticker == null) {
        refreshSticker(stickerMessage.stickerId);
      }
      final message = Message(
          messageId: data.messageId,
          conversationId: data.conversationId,
          userId: data.userId,
          category: data.category,
          content: plainText,
          name: stickerMessage.name,
          stickerId: stickerMessage.stickerId,
          albumId: stickerMessage.albumId,
          status: messageStatus,
          createdAt: data.createdAt);
      await database.messagesDao.insert(message, selfId);
    } else if (data.category.endsWith('_CONTACT')) {
      String plain;
      if (data.category == MessageCategory.signalContact) {
        _updateRemoteMessageStatus(data.messageId, messageStatus);
        return;
      } else {
        plain = utf8.decode(base64.decode(plainText));
      }
      final contactMessage =
          ContactMessage.fromJson(await LoadBalancerUtils.jsonDecode(plain));
      final user = await syncUser(contactMessage.userId);
      final message = Message(
          messageId: data.messageId,
          conversationId: data.conversationId,
          userId: data.userId,
          category: data.category,
          content: plainText,
          name: user.fullName ?? '',
          status: messageStatus,
          createdAt: data.createdAt);
      await database.messagesDao.insert(message, selfId);
    } else if (data.category.endsWith('_LIVE')) {
      String plain;
      if (data.category == MessageCategory.signalLive) {
        _updateRemoteMessageStatus(data.messageId, messageStatus);
        return;
      } else {
        plain = utf8.decode(base64.decode(plainText));
      }
      final liveMessage =
          LiveMessage.fromJson(await LoadBalancerUtils.jsonDecode(plain));
      final message = Message(
          messageId: data.messageId,
          conversationId: data.conversationId,
          userId: data.userId,
          category: data.category,
          mediaWidth: liveMessage.width,
          mediaHeight: liveMessage.height,
          mediaUrl: liveMessage.url,
          thumbUrl: liveMessage.thumbUrl,
          status: messageStatus,
          createdAt: data.createdAt);
      await database.messagesDao.insert(message, selfId);
    } else if (data.category.endsWith('_LOCATION')) {
      String plain;
      if (data.category == MessageCategory.signalLocation) {
        _updateRemoteMessageStatus(data.messageId, messageStatus);
        return;
      } else {
        plain = utf8.decode(base64.decode(plainText));
      }
      // ignore: unused_local_variable todo check location
      LocationMessage locationMessage;
      try {
        locationMessage =
            LocationMessage.fromJson(await LoadBalancerUtils.jsonDecode(plain));
      } catch (e) {
        debugPrint(e);
      }
      if (locationMessage == null ||
          locationMessage.latitude == 0.0 ||
          locationMessage.longitude == 0.0) {
        _updateRemoteMessageStatus(data.messageId, MessageStatus.read);
        return;
      }
      final message = Message(
          messageId: data.messageId,
          conversationId: data.conversationId,
          userId: data.userId,
          category: data.category,
          content: plain,
          status: messageStatus,
          createdAt: data.createdAt);
      await database.messagesDao.insert(message, selfId);
    } else if (data.category.endsWith('_POST')) {
      String plain;
      if (data.category == MessageCategory.signalPost) {
        plain = 'SignalPost';
      } else {
        plain = utf8.decode(base64.decode(plainText));
      }
      final message = Message(
        messageId: data.messageId,
        conversationId: data.conversationId,
        userId: data.userId,
        category: data.category,
        content: plain,
        status: messageStatus,
        createdAt: data.createdAt,
      );
      await database.messagesDao.insert(message, selfId);
    }

    _updateRemoteMessageStatus(data.messageId, messageStatus);
  }

  void _processSystemConversationMessage(BlazeMessageData data, SystemConversationMessage systemMessage) {}

  void _processSystemUserMessage(SystemUserMessage systemMessage) {}

  void _processSystemCircleMessage(BlazeMessageData data, SystemCircleMessage systemMessage) {}

  void _processSystemSnapshotMessage(BlazeMessageData data, SnapshotMessage systemSnapshot) {}

  void _processSystemSessionMessage(SystemSessionMessage systemSession) {}

  void _updateRemoteMessageStatus(messageId, MessageStatus status) {
    if (status != MessageStatus.delivered && status != MessageStatus.read) {
      return;
    }
    final blazeMessage = BlazeAckMessage(
        messageId: messageId, status: EnumToString.convertToString(status));
    database.jobsDao.insert(Job(
        jobId: Uuid().v4(),
        action: acknowledgeMessageReceipts,
        priority: 5,
        blazeMessage: jsonEncode(blazeMessage),
        createdAt: DateTime.now(),
        runCount: 0));
  }

  void _markMessageStatus(List<BlazeAckMessage> messages) async {
    final messageIds = <String>[];
    messages
        .takeWhile((m) => m.status != 'READ' || m.status != 'MENTION_READ')
        .forEach((m) {
      if (m.status == 'MENTION_READ') {
      } else {
        messageIds.add(m.messageId);
      }
    });

    if (messageIds.isNotEmpty) {
      database.messagesDao.markMessageRead(messageIds);
      // todo refresh conversion
    }
  }
}
