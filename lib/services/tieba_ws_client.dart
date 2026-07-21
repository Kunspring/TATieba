import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/tieba_private_message.dart';
import 'device_id_service.dart';
import 'tieba_protobuf.dart';
import 'tieba_ws_crypto.dart';

/// 贴吧 IM WebSocket 短连接客户端（init + 拉取私信）。
class TiebaWsClient {
  static const _clientVersion = '12.64.1.1';
  static const _wsUrl = 'ws://im.tieba.baidu.com:8000';

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _waiters = <int, Completer<Uint8List>>{};
  late final Uint8List _secKey;
  late final Uint8List _aesKey;
  int _reqId = 0;
  String? _cuid;

  Future<List<TiebaWsGroupInfo>> connect({
    required String bduss,
    required String stoken,
  }) async {
    _secKey = TiebaWsCrypto.randomAesSecKey();
    _aesKey = TiebaWsCrypto.deriveAesKey(_secKey);
    _reqId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final cuidGalaxy2 = await DeviceIdService.getCuidGalaxy2();
    _cuid = 'baidutiebaapp${const Uuid().v4()}';

    _channel = IOWebSocketChannel.connect(
      _wsUrl,
      headers: const {'Sec-WebSocket-Extensions': 'im_version=2.3'},
    );
    _sub = _channel!.stream.listen(
      _onFrame,
      onError: (Object e, StackTrace st) {
        for (final c in _waiters.values) {
          if (!c.isCompleted) c.completeError(e, st);
        }
        _waiters.clear();
      },
      onDone: () {
        for (final c in _waiters.values) {
          if (!c.isCompleted) {
            c.completeError(StateError('WebSocket closed'));
          }
        }
        _waiters.clear();
      },
    );

    return initSession(bduss: bduss, stoken: stoken, cuidGalaxy2: cuidGalaxy2);
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _channel?.sink.close();
    _sub = null;
    _channel = null;
  }

  void _onFrame(dynamic event) {
    if (event is! List<int>) return;
    try {
      final (body, _, reqId) = TiebaWsCrypto.parseWsFrame(
        _aesKey,
        Uint8List.fromList(event),
      );
      final waiter = _waiters.remove(reqId);
      waiter?.complete(body);
    } catch (_) {
      // 忽略无法解析的推送帧
    }
  }

  Future<Uint8List> _request(
    Uint8List payload, {
    required int cmd,
    bool encrypt = true,
    bool compress = false,
  }) async {
    final channel = _channel;
    if (channel == null) throw StateError('WebSocket not connected');

    _reqId += 1;
    final reqId = _reqId;
    final frame = TiebaWsCrypto.packWsFrame(
      aesKey: _aesKey,
      payload: payload,
      cmd: cmd,
      reqId: reqId,
      encrypt: encrypt,
      compress: compress,
    );

    final completer = Completer<Uint8List>();
    _waiters[reqId] = completer;
    channel.sink.add(frame);

    return completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        _waiters.remove(reqId);
        throw TimeoutException('WS request timeout cmd=$cmd');
      },
    );
  }

  Future<List<TiebaWsGroupInfo>> initSession({
    required String bduss,
    required String stoken,
    required String cuidGalaxy2,
  }) async {
    final deviceJson = jsonEncode({
      'cuid': _cuid,
      '_client_version': _clientVersion,
      '_msg_status': '1',
      'cuid_galaxy2': cuidGalaxy2,
      '_client_type': '2',
      'timestamp': '${DateTime.now().millisecondsSinceEpoch}',
    });

    final dataW = ProtobufWriter();
    dataW.writeString(1, bduss);
    dataW.writeString(2, deviceJson);
    dataW.writeMessage(3, TiebaWsCrypto.rsaEncryptSecretKey(_secKey));
    if (stoken.isNotEmpty) {
      dataW.writeString(12, stoken);
    }

    final outerW = ProtobufWriter();
    outerW.writeString(1, '$_cuid|com.baidu.tieba$_clientVersion');
    outerW.writeMessage(2, dataW.toBytes());

    final resp = await _request(
      outerW.toBytes(),
      cmd: 1001,
      encrypt: false,
      compress: false,
    );
    _throwIfError(resp);
    return _parseInitGroups(resp);
  }

  Future<List<PrivateChatConversation>> fetchPrivateChats({
    required List<TiebaWsGroupInfo> groups,
    required int selfUserId,
  }) async {
    return _fetchGroups(groups: groups, selfUserId: selfUserId);
  }

  /// 单会话完整聊天记录（详情页按需拉取）。
  Future<List<TiebaPrivateMessage>> fetchGroupMessageHistory({
    required TiebaWsGroupInfo group,
    required int selfUserId,
  }) async {
    final chats = await _fetchGroups(
      groups: [group],
      selfUserId: selfUserId,
      retainMessages: true,
    );
    if (chats.isEmpty) return const [];
    return chats.first.messages;
  }

  Future<List<PrivateChatConversation>> _fetchGroups({
    required List<TiebaWsGroupInfo> groups,
    required int selfUserId,
    bool retainMessages = false,
  }) async {
    final privateGroups = groups
        .where((g) => g.isPrivateChat && g.groupId > 0)
        .toList();
    if (privateGroups.isEmpty) return const [];

    final reqW = ProtobufWriter();
    final dataW = ProtobufWriter();
    for (final g in privateGroups) {
      final pairW = ProtobufWriter();
      pairW.writeInt64(1, g.groupId);
      pairW.writeInt64(2, g.lastMsgId);
      dataW.writeMessage(6, pairW.toBytes());
    }
    dataW.writeString(7, '1');
    reqW.writeString(1, '$_cuid|com.baidu.tieba$_clientVersion');
    reqW.writeMessage(2, dataW.toBytes());

    final resp = await _request(reqW.toBytes(), cmd: 202003);
    _throwIfError(resp);
    return _parsePrivateConversations(
      resp,
      selfUserId: selfUserId,
      retainMessages: retainMessages,
    );
  }

  static void _throwIfError(Uint8List data) {
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fn, wt) = tag;
      if (fn == 1 && wt == 2) {
        final errBytes = reader.readBytes();
        final errReader = ProtobufReader(errBytes);
        var code = 0;
        var msg = '';
        while (errReader.hasMore) {
          final eTag = errReader.readTag();
          if (eTag == null) break;
          final (eFn, eWt) = eTag;
          if (eFn == 1 && eWt == 0) {
            code = errReader.readVarint();
          } else if (eFn == 2 && eWt == 2) {
            msg = errReader.readString();
          } else {
            errReader.skipField(eWt);
          }
        }
        if (code != 0) {
          throw TiebaWsException(code, msg.isEmpty ? 'error $code' : msg);
        }
      } else {
        reader.skipField(wt);
      }
    }
  }

  static List<TiebaWsGroupInfo> _parseInitGroups(Uint8List data) {
    final groups = <TiebaWsGroupInfo>[];
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fn, wt) = tag;
      if (fn != 2 || wt != 2) {
        reader.skipField(wt);
        continue;
      }
      final dataBytes = reader.readBytes();
      final dReader = ProtobufReader(dataBytes);
      while (dReader.hasMore) {
        final dTag = dReader.readTag();
        if (dTag == null) break;
        final (dFn, dWt) = dTag;
        if (dFn == 1 && dWt == 2) {
          groups.add(_parseGroupInfo(dReader.readBytes()));
        } else {
          dReader.skipField(dWt);
        }
      }
    }
    return groups;
  }

  static TiebaWsGroupInfo _parseGroupInfo(Uint8List data) {
    var groupId = 0;
    var groupType = 0;
    var lastMsgId = 0;
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fn, wt) = tag;
      if (fn == 1 && wt == 0) {
        groupId = reader.readVarint();
      } else if (fn == 20 && wt == 0) {
        groupType = reader.readVarint();
      } else if (fn == 21 && wt == 0) {
        lastMsgId = reader.readVarint();
      } else {
        reader.skipField(wt);
      }
    }
    return TiebaWsGroupInfo(
      groupId: groupId,
      groupType: groupType,
      lastMsgId: lastMsgId,
    );
  }

  static List<PrivateChatConversation> _parsePrivateConversations(
    Uint8List data, {
    required int selfUserId,
    bool retainMessages = false,
  }) {
    final conversations = <PrivateChatConversation>[];
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fn, wt) = tag;
      if (fn != 2 || wt != 2) {
        reader.skipField(wt);
        continue;
      }
      final dataBytes = reader.readBytes();
      final dReader = ProtobufReader(dataBytes);
      while (dReader.hasMore) {
        final dTag = dReader.readTag();
        if (dTag == null) break;
        final (dFn, dWt) = dTag;
        if (dFn == 1 && dWt == 2) {
          final conv = _parseGroupMsg(
            dReader.readBytes(),
            selfUserId: selfUserId,
            retainMessages: retainMessages,
          );
          if (conv != null) conversations.add(conv);
        } else {
          dReader.skipField(dWt);
        }
      }
    }
    conversations.sort((a, b) {
      final ta = a.lastMessage?.createTime ?? 0;
      final tb = b.lastMessage?.createTime ?? 0;
      return tb.compareTo(ta);
    });
    return conversations;
  }

  static PrivateChatConversation? _parseGroupMsg(
    Uint8List data, {
    required int selfUserId,
    bool retainMessages = false,
  }) {
    var groupId = 0;
    final messages = retainMessages ? <TiebaPrivateMessage>[] : null;
    TiebaPrivateMessage? latest;
    TiebaPrivateMessage? peerMsg;
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fn, wt) = tag;
      if (fn == 1 && wt == 2) {
        groupId = _readGroupId(reader.readBytes());
      } else if (fn == 2 && wt == 2) {
        final msg = _parseMsgInfo(reader.readBytes());
        if (retainMessages) {
          messages!.add(msg);
        } else {
          if (latest == null || msg.createTime >= latest.createTime) {
            latest = msg;
          }
          if (msg.userId != selfUserId && msg.userId > 0) {
            if (peerMsg == null || msg.createTime >= peerMsg.createTime) {
              peerMsg = msg;
            }
          }
        }
      } else {
        reader.skipField(wt);
      }
    }
    if (groupId == 0) return null;

    if (retainMessages) {
      messages!.sort((a, b) => b.createTime.compareTo(a.createTime));
      latest = messages.isNotEmpty ? messages.first : null;
      peerMsg = null;
      for (final m in messages) {
        if (m.userId != selfUserId && m.userId > 0) {
          peerMsg = m;
          break;
        }
      }
      peerMsg ??= latest;
    } else {
      peerMsg ??= latest;
    }

    return PrivateChatConversation(
      groupId: groupId,
      peerUserId: peerMsg?.userId ?? 0,
      peerName: peerMsg?.userName ?? '私信',
      peerPortrait: peerMsg?.portrait,
      lastMessage: latest,
      messages: retainMessages ? messages! : const [],
    );
  }

  static int _readGroupId(Uint8List data) {
    var groupId = 0;
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fn, wt) = tag;
      if (fn == 1 && wt == 0) {
        groupId = reader.readVarint();
      } else {
        reader.skipField(wt);
      }
    }
    return groupId;
  }

  static TiebaPrivateMessage _parseMsgInfo(Uint8List data) {
    var msgId = 0;
    var msgType = 0;
    var text = '';
    var createTime = 0;
    var userId = 0;
    var userName = '';
    String? portrait;

    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fn, wt) = tag;
      if (fn == 1 && wt == 0) {
        msgId = reader.readVarint();
      } else if (fn == 3 && wt == 0) {
        msgType = reader.readVarint();
      } else if (fn == 5 && wt == 2) {
        text = reader.readString();
      } else if (fn == 8 && wt == 0) {
        createTime = reader.readVarint();
      } else if (fn == 10 && wt == 2) {
        final u = _parseUserInfo(reader.readBytes());
        userId = u.$1;
        userName = u.$2;
        portrait = u.$3;
      } else {
        reader.skipField(wt);
      }
    }

    return TiebaPrivateMessage(
      msgId: msgId,
      msgType: msgType,
      text: text,
      userId: userId,
      userName: userName,
      portrait: portrait,
      createTime: createTime,
    );
  }

  static (int, String, String?) _parseUserInfo(Uint8List data) {
    var userId = 0;
    var userName = '';
    String? portrait;
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fn, wt) = tag;
      if (fn == 1 && wt == 0) {
        userId = reader.readVarint();
      } else if (fn == 2 && wt == 2) {
        userName = reader.readString();
      } else if (fn == 3 && wt == 2) {
        portrait = reader.readString();
        if (portrait.contains('?')) {
          portrait = portrait.split('?').first;
        }
      } else {
        reader.skipField(wt);
      }
    }
    return (userId, userName, portrait);
  }
}

class TiebaWsException implements Exception {
  final int code;
  final String message;
  const TiebaWsException(this.code, this.message);

  @override
  String toString() => 'TiebaWsException($code): $message';
}

/// 简易 UUID v4（仅用于 cuid 生成）。
class Uuid {
  const Uuid();
  String v4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int i) => i.toRadixString(16).padLeft(2, '0');
    return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}-'
        '${hex(bytes[4])}${hex(bytes[5])}-'
        '${hex(bytes[6])}${hex(bytes[7])}-'
        '${hex(bytes[8])}${hex(bytes[9])}-'
        '${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}${hex(bytes[13])}'
        '${hex(bytes[14])}${hex(bytes[15])}';
  }
}
