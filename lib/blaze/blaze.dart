import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';

import 'blaze_message.dart';

class Blaze {
  IOWebSocketChannel channel;
  void connect(String token) {
    channel = IOWebSocketChannel.connect(
        'wss://blaze.mixin.one?access_token=$token',
        protocols: ['Mixin-Blaze-1']);
    debugPrint('wss://blaze.mixin.one?access_token=$token');
    channel.stream.listen((message) {
      debugPrint(String.fromCharCodes(GZipDecoder().decodeBytes(message)));
    }, onError: (error) {
      debugPrint('onError');
    }, onDone: () {
      debugPrint('onDone');
    }, cancelOnError: true);

    _sendListPending();
  }

  void _sendListPending() {
    _sendGZip(BlazeMessage(Uuid().v4(), 'LIST_PENDING_MESSAGES'));
  }

  void _sendGZip(BlazeMessage msg) {
    channel.sink.add(
        GZipEncoder().encode(Uint8List.fromList(jsonEncode(msg).codeUnits)));
  }
}
