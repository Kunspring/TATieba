import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/tieba_post.dart';
import '../models/bar_forum_context.dart';
import '../models/tieba_video.dart';
import '../models/user_followed_forum.dart';
import '../utils/cover_image_cache.dart';
import '../utils/tieba_emoticon.dart';
import '../utils/tieba_video_util.dart';
import 'data_saver_service.dart';
import 'device_id_service.dart';
import 'tieba_protobuf.dart';

class TiebaClient {
  static const _appSalt = 'tiebaclient!!!';
  static const _pcSalt = <int>[
    0x36,
    0x77,
    0x0b,
    0x1f,
    0x34,
    0xc9,
    0xbb,
    0xf2,
    0xe7,
    0xd1,
    0xa9,
    0x9d,
    0x2b,
    0x82,
    0xfa,
    0x9e,
  ];
  static const _baseUrl = 'http://tiebac.baidu.com';
  static const _webBaseUrl = 'http://tieba.baidu.com';
  static const _clientVersion = '12.64.1.1';

  static const _appHeaders = {
    'User-Agent': 'bdtb for Android 12.57.4.0',
    'Accept-Encoding': 'gzip',
    'Connection': 'keep-alive',
    'Host': 'tiebac.baidu.com',
  };

  static const _webHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Accept-Encoding': 'gzip, deflate',
    'Connection': 'keep-alive',
  };

  static String computeSign(List<MapEntry<String, String>> params) {
    final sorted = List<MapEntry<String, String>>.from(params)
      ..sort((a, b) => a.key.compareTo(b.key));
    final buffer = StringBuffer();
    for (final entry in sorted) {
      buffer.write('${entry.key}=${entry.value}');
    }
    buffer.write(_appSalt);
    final bytes = utf8.encode(buffer.toString());
    return md5.convert(bytes).toString();
  }

  static List<MapEntry<String, String>> signParams(
    List<MapEntry<String, String>> params,
  ) {
    final signed = List<MapEntry<String, String>>.from(params);
    final sign = computeSign(signed);
    signed.add(MapEntry('sign', sign));
    return signed;
  }

  static String computePcSign(List<MapEntry<String, String>> params) {
    final sorted = List<MapEntry<String, String>>.from(params)
      ..sort((a, b) => a.key.compareTo(b.key));
    final buffer = StringBuffer();
    for (final entry in sorted) {
      buffer.write('${entry.key}=${entry.value}');
    }
    final bytes = <int>[...utf8.encode(buffer.toString()), ..._pcSalt];
    return md5.convert(bytes).toString();
  }

  static List<MapEntry<String, String>> signPcParams(
    List<MapEntry<String, String>> params,
  ) {
    final signed = List<MapEntry<String, String>>.from(params);
    signed.add(MapEntry('sign', computePcSign(signed)));
    return signed;
  }

  static Future<Map<String, dynamic>> postForm(
    String path, {
    required List<MapEntry<String, String>> params,
    String? bduss,
    String? stoken,
  }) async {
    final allParams = List<MapEntry<String, String>>.from(params);
    allParams.add(MapEntry('_client_version', _clientVersion));
    if (bduss != null) {
      allParams.add(MapEntry('BDUSS', bduss));
    }
    final signed = signParams(allParams);
    final body = Uri(
      queryParameters: {for (final e in signed) e.key: e.value},
    ).query;
    final headers = <String, String>{
      ..._appHeaders,
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    if (bduss != null && bduss.isNotEmpty) {
      headers['Cookie'] = _authCookie(bduss, stoken);
    }
    final resp = await http
        .post(Uri.parse('$_baseUrl$path'), headers: headers, body: body)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return {'error_code': resp.statusCode};
    return jsonDecode(resp.body);
  }

  /// 大 JSON 响应：解码放到 isolate，减轻主线程顿帧。
  static Future<Map<String, dynamic>> postFormHeavy(
    String path, {
    required List<MapEntry<String, String>> params,
    String? bduss,
    String? stoken,
  }) async {
    final allParams = List<MapEntry<String, String>>.from(params);
    allParams.add(MapEntry('_client_version', _clientVersion));
    if (bduss != null) {
      allParams.add(MapEntry('BDUSS', bduss));
    }
    final signed = signParams(allParams);
    final body = Uri(
      queryParameters: {for (final e in signed) e.key: e.value},
    ).query;
    final headers = <String, String>{
      ..._appHeaders,
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    if (bduss != null && bduss.isNotEmpty) {
      headers['Cookie'] = _authCookie(bduss, stoken);
    }
    final resp = await http
        .post(Uri.parse('$_baseUrl$path'), headers: headers, body: body)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return {'error_code': resp.statusCode};
    return compute(_decodeJsonMapIsolate, resp.body);
  }

  static Future<Map<String, dynamic>> postWebForm(
    String path, {
    required List<MapEntry<String, String>> params,
    String? bduss,
    String? stoken,
  }) async {
    final headers = Map<String, String>.from(_webHeaders);
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    headers['Origin'] = _webBaseUrl;
    headers['Referer'] = '$_webBaseUrl/';
    if (bduss != null && bduss.isNotEmpty) {
      headers['Cookie'] = _authCookie(bduss, stoken);
    }
    final body = Uri(
      queryParameters: {for (final e in params) e.key: e.value},
    ).query;
    final resp = await http
        .post(Uri.parse('$_webBaseUrl$path'), headers: headers, body: body)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return {'error_code': resp.statusCode};
    try {
      return jsonDecode(resp.body);
    } catch (_) {
      return {'error_code': resp.statusCode, 'raw': resp.body};
    }
  }

  static String _authCookie(String bduss, String? stoken) {
    if (stoken != null && stoken.isNotEmpty) {
      return 'BDUSS=$bduss; STOKEN=$stoken';
    }
    return 'BDUSS=$bduss';
  }

  /// 校验 BDUSS 是否仍有效（贴吧 Lite / 脚本通用 tbs 接口）。
  static Future<bool> isSessionValid(String bduss, {String? stoken}) async {
    if (bduss.isEmpty) return false;
    try {
      final headers = Map<String, String>.from(_webHeaders);
      headers['Cookie'] = _authCookie(bduss, stoken);
      final resp = await http
          .get(Uri.parse('$_webBaseUrl/dc/common/tbs'), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body);
      if (body is! Map) return false;
      final login = body['is_login'];
      return login == 1 || login == '1';
    } catch (_) {
      return false;
    }
  }

  static bool _isApiSuccess(Map<String, dynamic> resp) {
    final code = resp['error_code'];
    if (code == null) return !resp.containsKey('error_msg');
    final s = code.toString();
    return s == '0' || s == '1';
  }

  static bool _isWriteSuccess(Map<String, dynamic> resp) {
    final code = resp['error_code'];
    return code?.toString() == '0' || code == 0;
  }

  static String _writeErrorMessage(Map<String, dynamic> resp, String fallback) {
    final msg = resp['error_msg']?.toString().trim();
    if (msg != null && msg.isNotEmpty) return msg;
    final code = resp['error_code']?.toString();
    if (code != null && code.isNotEmpty) return '$fallback ($code)';
    return fallback;
  }

  static bool _isAlreadyFavorited(Map<String, dynamic> resp) {
    final msg = resp['error_msg']?.toString() ?? '';
    final code = resp['error_code']?.toString() ?? '';
    return msg.contains('已收藏') ||
        msg.contains('已经收藏') ||
        code == '340001' ||
        code == '110003';
  }

  static bool _isAlreadyUnfavorited(Map<String, dynamic> resp) {
    final msg = resp['error_msg']?.toString() ?? '';
    final code = resp['error_code']?.toString() ?? '';
    return msg.contains('未收藏') ||
        msg.contains('没有收藏') ||
        msg.contains('不存在') ||
        code == '340002';
  }

  static bool _isStored(dynamic value) {
    return value == true || value == 1 || value == '1';
  }

  static Future<Map<String, dynamic>> getWeb(
    String path, {
    required List<MapEntry<String, String>> params,
    String? bduss,
  }) async {
    final signed = signParams(params);
    final uri = Uri.parse(
      '$_webBaseUrl$path',
    ).replace(queryParameters: {for (final e in signed) e.key: e.value});
    final headers = Map<String, String>.from(_webHeaders);
    if (bduss != null) {
      headers['Cookie'] = 'BDUSS=$bduss';
    }
    final resp = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return {'error_code': resp.statusCode};
    return jsonDecode(resp.body);
  }

  static Future<Map<String, dynamic>> _getPcWebJson(
    String path, {
    required List<MapEntry<String, String>> params,
    String? bduss,
    String? stoken,
  }) async {
    final signed = signPcParams(params);
    final uri = Uri.parse(
      '$_webBaseUrl$path',
    ).replace(queryParameters: {for (final e in signed) e.key: e.value});
    final headers = Map<String, String>.from(_webHeaders);
    if (bduss != null && bduss.isNotEmpty) {
      headers['Cookie'] = _authCookie(bduss, stoken);
    }
    final resp = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return {'error_code': resp.statusCode};
    try {
      final body = jsonDecode(resp.body);
      if (body is Map<String, dynamic>) return body;
      if (body is Map) return Map<String, dynamic>.from(body);
      return {'error_code': -1};
    } catch (_) {
      return {'error_code': resp.statusCode, 'raw': resp.body};
    }
  }

  static Future<Map<String, dynamic>> getTbs(String bduss) async {
    return postForm(
      '/c/s/login',
      params: [MapEntry('bdusstoken', bduss)],
      bduss: bduss,
    );
  }

  static String parseTbs(Map<String, dynamic> result) {
    final anti = result['anti'];
    if (anti is Map) {
      return anti['tbs']?.toString() ?? '';
    }
    return result['tbs']?.toString() ?? '';
  }

  static Future<String> fetchTbsToken(String bduss) async {
    try {
      final result = await getTbs(bduss);
      final tbs = parseTbs(result);
      if (tbs.isNotEmpty) return tbs;
    } catch (e) {
      if (kDebugMode) debugPrint('fetchTbsToken app login failed: $e');
    }

    try {
      final headers = Map<String, String>.from(_webHeaders);
      headers['Cookie'] = 'BDUSS=$bduss';
      final resp = await http
          .get(Uri.parse('$_webBaseUrl/dc/common/tbs'), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map) {
          final tbs = body['tbs']?.toString() ?? '';
          if (tbs.isNotEmpty) return tbs;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('fetchTbsToken web failed: $e');
    }

    return '';
  }

  static Future<bool> signInBar(
    String barName,
    String bduss,
    String tbs,
  ) async {
    final result = await postForm(
      '/c/c/forum/sign',
      params: [MapEntry('kw', barName), MapEntry('tbs', tbs)],
      bduss: bduss,
    );
    final code = result['error_code'];
    final codeStr = code?.toString() ?? '';
    return codeStr == '0' || codeStr == '1' || codeStr == '160002';
  }

  static Future<Map<String, dynamic>> createPost({
    required String barName,
    required String title,
    required String content,
    required String bduss,
    required String tbs,
  }) async {
    return postForm(
      '/c/c/thread/addPost',
      params: [
        MapEntry('kw', barName),
        MapEntry('title', title),
        MapEntry('content', content),
        MapEntry('tbs', tbs),
        MapEntry('ie', 'utf-8'),
      ],
      bduss: bduss,
    );
  }

  static int get detailCommentPageSize =>
      DataSaverService.instance.enabled ? 30 : 100;
  static const subCommentPageSize = 30;

  static Future<Map<String, dynamic>> replyPost({
    required String tid,
    required String content,
    required String bduss,
    required String tbs,
    String? fname,
    int? fid,
    String? showName,
  }) async {
    return _replyPostProto(
      tid: tid,
      content: content,
      bduss: bduss,
      tbs: tbs,
      fname: fname ?? '',
      fid: fid ?? 0,
      showName: showName ?? '',
    );
  }

  static Future<Map<String, dynamic>> _replyPostProto({
    required String tid,
    required String content,
    required String bduss,
    required String tbs,
    required String fname,
    required int fid,
    required String showName,
    String? parentPid,
  }) async {
    try {
      final now = DateTime.now();
      final tsMs = now.millisecondsSinceEpoch;

      final commonW = ProtobufWriter();
      commonW.writeString(2, _clientVersion);
      commonW.writeString(3, 'dart_tieba');
      commonW.writeString(10, bduss);
      commonW.writeString(11, tbs);
      commonW.writeInt32(1, 2);
      commonW.writeString(36, '000000000000000');
      commonW.writeString(37, '1008621x');
      commonW.writeString(43, 'SM-G988N');
      commonW.writeString(48, '1');
      commonW.writeString(52, '10.3');
      commonW.writeString(53, 'samsung');
      commonW.writeInt32(61, tsMs);
      commonW.writeString(72, showName.isNotEmpty ? showName : '贴吧网友');
      if (showName.isNotEmpty) {
        commonW.writeString(73, showName);
      }
      final commonBytes = commonW.toBytes();

      final dataW = ProtobufWriter();
      dataW.writeString(1, '1');
      dataW.writeString(2, '0');
      dataW.writeString(3, '0');
      dataW.writeString(4, '0');
      dataW.writeString(5, '0');
      dataW.writeString(7, '12');
      dataW.writeString(8, '1');
      dataW.writeString(9, content);
      if (fid > 0) dataW.writeString(10, fid.toString());
      dataW.writeString(12, '');
      dataW.writeString(13, '');
      dataW.writeString(14, fname);
      dataW.writeString(15, '0');
      dataW.writeString(16, fid.toString());
      dataW.writeString(17, tid);
      dataW.writeString(18, parentPid ?? '0');
      dataW.writeString(19, '3');
      dataW.writeString(20, showName.isNotEmpty ? showName : '贴吧网友');
      dataW.writeString(21, '0');
      dataW.writeMessage(39, commonBytes);
      final dataBytes = dataW.toBytes();

      final outerW = ProtobufWriter();
      outerW.writeMessage(1, dataBytes);
      final reqBytes = outerW.toBytes();

      final respBytes = await postProto(
        '/c/c/post/add',
        reqBytes,
        cmdId: '309731',
      );
      return _parseAddPostResp(respBytes);
    } catch (e) {
      debugPrint('[TiebaAPI] _replyPostProto error: $e');
      return {'error_code': -1, 'error_msg': e.toString()};
    }
  }

  static Map<String, dynamic> _parseAddPostResp(Uint8List data) {
    try {
      final reader = ProtobufReader(data);
      int errorNo = 0;
      String errorMsg = '';
      int postId = 0;
      bool needVcode = false;

      while (reader.hasMore) {
        final tag = reader.readTag();
        if (tag == null) break;
        final (fieldNumber, wireType) = tag;
        if (wireType == 2 && fieldNumber == 2) {
          final errorBytes = reader.readBytes();
          final eReader = ProtobufReader(errorBytes);
          while (eReader.hasMore) {
            final eTag = eReader.readTag();
            if (eTag == null) break;
            final (efn, ewt) = eTag;
            if (efn == 1 && ewt == 0) {
              errorNo = eReader.readVarint();
            } else if (efn == 2 && ewt == 2) {
              errorMsg = eReader.readString();
            } else {
              eReader.skipField(ewt);
            }
          }
        } else if (wireType == 2 && fieldNumber == 3) {
          final dataBytes = reader.readBytes();
          final dReader = ProtobufReader(dataBytes);
          while (dReader.hasMore) {
            final dTag = dReader.readTag();
            if (dTag == null) break;
            final (dfn, dwt) = dTag;
            if (dfn == 1 && dwt == 2) {
              final infoBytes = dReader.readBytes();
              final iReader = ProtobufReader(infoBytes);
              while (iReader.hasMore) {
                final iTag = iReader.readTag();
                if (iTag == null) break;
                final (ifn, iwt) = iTag;
                if (ifn == 1 && iwt == 2) {
                  final vcodeBytes = iReader.readBytes();
                  final vReader = ProtobufReader(vcodeBytes);
                  while (vReader.hasMore) {
                    final vTag = vReader.readTag();
                    if (vTag == null) break;
                    final (vfn, vwt) = vTag;
                    if (vfn == 1 && vwt == 0) {
                      needVcode = vReader.readVarint() == 1;
                    } else {
                      vReader.skipField(vwt);
                    }
                  }
                } else if (ifn == 2 && iwt == 0) {
                  postId = iReader.readVarint();
                } else {
                  iReader.skipField(iwt);
                }
              }
            } else {
              dReader.skipField(dwt);
            }
          }
        } else {
          reader.skipField(wireType);
        }
      }

      if (errorNo != 0) {
        return {'error_code': errorNo, 'error_msg': errorMsg};
      }
      if (needVcode) {
        return {'error_code': -2, 'error_msg': '闇€瑕侀獙璇佺爜'};
      }
      return {'error_code': 0, 'pid': postId.toString()};
    } catch (e) {
      return {'error_code': -1, 'error_msg': e.toString()};
    }
  }

  static Future<bool> followBar(
    String barName,
    String bduss,
    String tbs,
  ) async {
    final fname = _normalizeForumName(barName);
    if (fname.isEmpty || tbs.isEmpty) return false;
    final fid = await getForumId(fname);
    if (fid == null || fid <= 0) return false;
    final result = await postForm(
      '/c/c/forum/like',
      params: [MapEntry('fid', fid.toString()), MapEntry('tbs', tbs)],
      bduss: bduss,
    );
    return _isApiSuccess(result);
  }

  static Future<bool> unfollowBar(
    String barName,
    String bduss,
    String tbs,
  ) async {
    final fname = _normalizeForumName(barName);
    if (fname.isEmpty || tbs.isEmpty) return false;
    final fid = await getForumId(fname);
    if (fid == null || fid <= 0) return false;
    final result = await postForm(
      '/c/c/forum/unfavolike',
      params: [MapEntry('fid', fid.toString()), MapEntry('tbs', tbs)],
      bduss: bduss,
    );
    return _isApiSuccess(result);
  }

  static bool _isAlreadyFollowingUser(Map<String, dynamic> resp) {
    final msg = resp['error_msg']?.toString() ?? '';
    return msg.contains('已经关注') || msg.contains('已关注') || msg.contains('重复关注');
  }

  static bool _isAlreadyUnfollowingUser(Map<String, dynamic> resp) {
    final msg = resp['error_msg']?.toString() ?? '';
    return msg.contains('未关注') || msg.contains('没有关注') || msg.contains('尚未关注');
  }

  static Future<bool> followUser({
    required String portrait,
    required String bduss,
    required String tbs,
  }) async {
    final normalized = _normalizePortrait(portrait);
    if (normalized.isEmpty || tbs.isEmpty) return false;
    final result = await postForm(
      '/c/c/user/follow',
      params: [MapEntry('portrait', normalized), MapEntry('tbs', tbs)],
      bduss: bduss,
    );
    if (_isWriteSuccess(result)) return true;
    return _isAlreadyFollowingUser(result);
  }

  static Future<bool> unfollowUser({
    required String portrait,
    required String bduss,
    required String tbs,
  }) async {
    final normalized = _normalizePortrait(portrait);
    if (normalized.isEmpty || tbs.isEmpty) return false;
    final result = await postForm(
      '/c/c/user/unfollow',
      params: [MapEntry('portrait', normalized), MapEntry('tbs', tbs)],
      bduss: bduss,
    );
    if (_isWriteSuccess(result)) return true;
    return _isAlreadyUnfollowingUser(result);
  }

  static String _normalizeForumName(String barName) {
    var name = barName.trim();
    if (name.endsWith('吧')) {
      name = name.substring(0, name.length - 1).trim();
    }
    return name;
  }

  static Future<bool> agreePost({
    required String tid,
    required String bduss,
    required String tbs,
    String? stoken,
    String? pid,
  }) async {
    return (await agreePostMessage(
          tid: tid,
          bduss: bduss,
          tbs: tbs,
          stoken: stoken,
          pid: pid,
        )) ==
        null;
  }

  /// 点赞主题帖（整帖，obj_type=3）。仅当明确传入有效首楼 [pid] 且与 tid 不同时才按楼层点赞。
  static Future<String?> agreePostMessage({
    required String tid,
    required String bduss,
    required String tbs,
    String? stoken,
    String? pid,
  }) async {
    final floorPid = _usableFloorPid(pid, tid);
    if (floorPid != null) {
      final err = await _opAgree(
        tid: tid,
        pid: floorPid,
        objType: 1,
        agreeType: 2,
        opType: 0,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
      );
      if (err == null || !_looksLikeMissingAgreeTarget(err)) return err;
    }
    return _opAgree(
      tid: tid,
      pid: '0',
      objType: 3,
      agreeType: 2,
      opType: 0,
      bduss: bduss,
      tbs: tbs,
      stoken: stoken,
    );
  }

  static Future<bool> disagreePost({
    required String tid,
    required String bduss,
    required String tbs,
    String? stoken,
    String? pid,
  }) async {
    return (await disagreePostMessage(
          tid: tid,
          bduss: bduss,
          tbs: tbs,
          stoken: stoken,
          pid: pid,
        )) ==
        null;
  }

  static Future<String?> disagreePostMessage({
    required String tid,
    required String bduss,
    required String tbs,
    String? stoken,
    String? pid,
  }) async {
    final floorPid = _usableFloorPid(pid, tid);
    if (floorPid != null) {
      final err = await _opAgree(
        tid: tid,
        pid: floorPid,
        objType: 1,
        agreeType: 5,
        opType: 0,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
      );
      if (err == null || !_looksLikeMissingAgreeTarget(err)) return err;
    }
    return _opAgree(
      tid: tid,
      pid: '0',
      objType: 3,
      agreeType: 5,
      opType: 0,
      bduss: bduss,
      tbs: tbs,
      stoken: stoken,
    );
  }

  static Future<bool> undoAgreePost({
    required String tid,
    required String bduss,
    required String tbs,
    String? stoken,
    String? pid,
  }) async {
    return (await undoAgreePostMessage(
          tid: tid,
          bduss: bduss,
          tbs: tbs,
          stoken: stoken,
          pid: pid,
        )) ==
        null;
  }

  static Future<String?> undoAgreePostMessage({
    required String tid,
    required String bduss,
    required String tbs,
    String? stoken,
    String? pid,
  }) async {
    final floorPid = _usableFloorPid(pid, tid);
    if (floorPid != null) {
      final err = await _opAgree(
        tid: tid,
        pid: floorPid,
        objType: 1,
        agreeType: 2,
        opType: 1,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
      );
      if (err == null || !_looksLikeMissingAgreeTarget(err)) return err;
    }
    return _opAgree(
      tid: tid,
      pid: '0',
      objType: 3,
      agreeType: 2,
      opType: 1,
      bduss: bduss,
      tbs: tbs,
      stoken: stoken,
    );
  }

  /// 点赞楼层回复（obj_type=1）。
  static Future<bool> agreeComment({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) async {
    return (await _opAgree(
          tid: tid,
          pid: pid,
          objType: 1,
          agreeType: 2,
          opType: 0,
          bduss: bduss,
          tbs: tbs,
          stoken: stoken,
        )) ==
        null;
  }

  static Future<String?> agreeCommentMessage({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) async {
    return _opAgree(
      tid: tid,
      pid: pid,
      objType: 1,
      agreeType: 2,
      opType: 0,
      bduss: bduss,
      tbs: tbs,
      stoken: stoken,
    );
  }

  static Future<bool> disagreeComment({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) async {
    return (await _opAgree(
          tid: tid,
          pid: pid,
          objType: 1,
          agreeType: 5,
          opType: 0,
          bduss: bduss,
          tbs: tbs,
          stoken: stoken,
        )) ==
        null;
  }

  static Future<bool> undoAgreeComment({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) async {
    return (await _opAgree(
          tid: tid,
          pid: pid,
          objType: 1,
          agreeType: 2,
          opType: 1,
          bduss: bduss,
          tbs: tbs,
          stoken: stoken,
        )) ==
        null;
  }

  static Future<String?> undoAgreeCommentMessage({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) async {
    return _opAgree(
      tid: tid,
      pid: pid,
      objType: 1,
      agreeType: 2,
      opType: 1,
      bduss: bduss,
      tbs: tbs,
      stoken: stoken,
    );
  }

  /// 点赞楼中楼（obj_type=2）。
  static Future<bool> agreeSubComment({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) async {
    return (await agreeSubCommentMessage(
          tid: tid,
          pid: pid,
          bduss: bduss,
          tbs: tbs,
          stoken: stoken,
        )) ==
        null;
  }

  static Future<String?> agreeSubCommentMessage({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) async {
    return _opAgree(
      tid: tid,
      pid: pid,
      objType: 2,
      agreeType: 2,
      opType: 0,
      bduss: bduss,
      tbs: tbs,
      stoken: stoken,
    );
  }

  static Future<bool> undoAgreeSubComment({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) async {
    return (await undoAgreeSubCommentMessage(
          tid: tid,
          pid: pid,
          bduss: bduss,
          tbs: tbs,
          stoken: stoken,
        )) ==
        null;
  }

  static Future<String?> undoAgreeSubCommentMessage({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) async {
    return _opAgree(
      tid: tid,
      pid: pid,
      objType: 2,
      agreeType: 2,
      opType: 1,
      bduss: bduss,
      tbs: tbs,
      stoken: stoken,
    );
  }

  /// 返回 `null` 表示成功，否则为失败原因。
  static Future<String?> _opAgree({
    required String tid,
    required String pid,
    required int objType,
    required int agreeType,
    required int opType,
    required String bduss,
    required String tbs,
    String? stoken,
  }) async {
    if (tid.isEmpty) return '参数无效';
    if (pid.isEmpty) return '参数无效';
    if (objType != 3 && (pid == '0' || int.tryParse(pid) == null)) {
      return '参数无效';
    }
    final cuid = await DeviceIdService.getCuidGalaxy2();
    final result = await postForm(
      '/c/c/agree/opAgree',
      params: [
        MapEntry('thread_id', tid),
        MapEntry('post_id', pid),
        MapEntry('obj_type', objType.toString()),
        MapEntry('agree_type', agreeType.toString()),
        MapEntry('op_type', opType.toString()),
        MapEntry('tbs', tbs),
        MapEntry('cuid', cuid),
      ],
      bduss: bduss,
      stoken: stoken,
    );
    if (_isWriteSuccess(result)) return null;
    debugPrint(
      '[TiebaAPI] opAgree failed: code=${result['error_code']} msg=${result['error_msg']}',
    );
    return _writeErrorMessage(result, '点赞失败');
  }

  static String? _postIdFrom(Map<dynamic, dynamic> map) {
    for (final key in ['post_id', 'pid', 'id']) {
      final raw = map[key];
      if (raw == null) continue;
      final text = raw.toString().trim();
      if (text.isEmpty || int.tryParse(text) == null) continue;
      return text;
    }
    return null;
  }

  static String? _firstFloorPid(
    Map<dynamic, dynamic> first, {
    required String threadId,
  }) {
    final tid = threadId.trim();
    for (final key in ['post_id', 'pid', 'id']) {
      final raw = first[key];
      if (raw == null) continue;
      final text = raw.toString().trim();
      if (text.isEmpty || int.tryParse(text) == null) continue;
      if (tid.isNotEmpty && text == tid) continue;
      return text;
    }
    return null;
  }

  static String? _usableFloorPid(String? pid, String tid) {
    final text = pid?.trim();
    if (text == null || text.isEmpty || text == '0') return null;
    if (int.tryParse(text) == null) return null;
    if (text == tid.trim()) return null;
    return text;
  }

  static bool _looksLikeMissingAgreeTarget(String message) {
    final t = message.trim();
    return t.contains('不存在') ||
        t.contains('找不到') ||
        t.contains('已删除') ||
        t.contains('非法');
  }

  static Future<Map<String, dynamic>> replySubPost({
    required String tid,
    required String pid,
    required String content,
    required String bduss,
    required String tbs,
    String? fname,
    int? fid,
    String? showName,
  }) async {
    return _replyPostProto(
      tid: tid,
      content: content,
      bduss: bduss,
      tbs: tbs,
      fname: fname ?? '',
      fid: fid ?? 0,
      showName: showName ?? '',
      parentPid: pid,
    );
  }

  static Future<List<String>> fetchFollowedBarNames(
    String bduss,
    String portrait,
  ) async {
    try {
      final result = await getWeb(
        '/c/f/pc/myForumList',
        params: [
          MapEntry('portrait', portrait),
          MapEntry('pn', '1'),
          MapEntry('rn', '100'),
          MapEntry('subapp_type', 'pc'),
          MapEntry('_client_type', '20'),
        ],
        bduss: bduss,
      );
      if (result['error_code'] == 0 || result['error_code'] == '0') {
        final data = result['data'];
        if (data != null) {
          final forums = data['forum_list'] ?? data['follow_forum'] ?? [];
          if (forums is List) {
            return forums
                .whereType<Map>()
                .map((f) => (f['forum_name'] ?? f['name'] ?? '').toString())
                .where((n) => n.isNotEmpty)
                .toList();
          }
        }
      }

      final appResult = await postForm(
        '/c/f/forum/like',
        params: [MapEntry('page_no', '1'), MapEntry('page_size', '100')],
        bduss: bduss,
      );
      if (appResult['error_code'] == 0 || appResult['error_code'] == '0') {
        final forumListRaw = appResult['forum_list'];
        final allNames = <String>[];
        if (forumListRaw is List) {
          allNames.addAll(
            forumListRaw
                .whereType<Map>()
                .map((f) => (f['name'] ?? f['forum_name'] ?? '').toString())
                .where((n) => n.isNotEmpty),
          );
        } else if (forumListRaw is Map) {
          for (final value in forumListRaw.values) {
            if (value is List) {
              allNames.addAll(
                value
                    .whereType<Map>()
                    .map((f) => (f['name'] ?? f['forum_name'] ?? '').toString())
                    .where((n) => n.isNotEmpty),
              );
            }
          }
        }
        if (allNames.isNotEmpty) return allNames;
      }
    } catch (_) {}
    return [];
  }

  static Future<List<AtItem>> getAts({
    int pn = 1,
    required String bduss,
    String? stoken,
  }) async {
    try {
      final params = <MapEntry<String, String>>[MapEntry('pn', pn.toString())];
      final result = await postForm(
        '/c/u/feed/atme',
        params: params,
        bduss: bduss,
        stoken: stoken,
      );
      if (result['error_code'] != 0 && result['error_code'] != '0') return [];
      final atList = _asList(result['at_list']) ?? [];
      return atList
          .whereType<Map<String, dynamic>>()
          .map((m) => AtItem.fromJson(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<ReplyItem>> getReplys({
    int pn = 1,
    required String bduss,
    String? stoken,
  }) async {
    try {
      final commonW = ProtobufWriter();
      commonW.writeInt32(1, 2);
      commonW.writeString(2, _clientVersion);
      commonW.writeString(10, bduss);
      final commonBytes = commonW.toBytes();

      final dataW = ProtobufWriter();
      dataW.writeString(1, pn.toString());
      dataW.writeMessage(3, commonBytes);
      final dataBytes = dataW.toBytes();

      final outerW = ProtobufWriter();
      outerW.writeMessage(1, dataBytes);
      final reqBytes = outerW.toBytes();

      final respBytes = await postProto(
        '/c/u/feed/replyme',
        reqBytes,
        cmdId: '303007',
        bduss: bduss,
        stoken: stoken,
      );
      return _parseReplys(respBytes);
    } catch (_) {
      return [];
    }
  }

  static List<ReplyItem> _parseReplys(Uint8List data) {
    final items = <ReplyItem>[];
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fieldNumber, wireType) = tag;
      if (wireType != 2) {
        reader.skipField(wireType);
        continue;
      }
      if (fieldNumber == 1) {
        reader.skipField(2);
      } else if (fieldNumber == 2) {
        final dataBytes = reader.readBytes();
        final dReader = ProtobufReader(dataBytes);
        while (dReader.hasMore) {
          final dTag = dReader.readTag();
          if (dTag == null) break;
          final (dFn, dWt) = dTag;
          if (dWt != 2) {
            dReader.skipField(dWt);
            continue;
          }
          if (dFn == 1) {
            dReader.skipField(2);
          } else if (dFn == 2) {
            final replyBytes = dReader.readBytes();
            final item = _parseSingleReply(replyBytes);
            if (item != null) items.add(item);
          } else {
            dReader.skipField(dWt);
          }
        }
      } else {
        reader.skipField(wireType);
      }
    }
    return items;
  }

  static String _decodeProtoUtf8(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static ReplyItem? _parseSingleReply(Uint8List data) {
    String text = '', fname = '';
    int tid = 0, pid = 0, ppid = 0, createTime = 0;
    bool isComment = false;
    int replyerId = 0, postUserId = 0, threadUserId = 0;
    String replyerName = '', postUserName = '', threadUserName = '';
    String? replyerPortrait, replyerNick, postUserNick, threadUserNick;

    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fn, wt) = tag;
      if (wt == 2) {
        final fieldBytes = reader.readBytes();
        if (fn == 5) {
          fname = _decodeProtoUtf8(fieldBytes);
        } else if (fn == 6) {
          text = _decodeProtoUtf8(fieldBytes);
        } else if (fn == 9) {
          final uReader = ProtobufReader(fieldBytes);
          while (uReader.hasMore) {
            final uTag = uReader.readTag();
            if (uTag == null) break;
            final (uFn, uWt) = uTag;
            if (uWt == 2) {
              final uStr = _decodeProtoUtf8(uReader.readBytes());
              if (uFn == 3) {
                replyerName = uStr;
              } else if (uFn == 4) {
                replyerNick = uStr;
              } else if (uFn == 5) {
                replyerPortrait = uStr;
              }
            } else if (uWt == 0 && uFn == 2) {
              replyerId = uReader.readVarint();
            } else {
              uReader.skipField(uWt);
            }
          }
        } else if (fn == 15) {
          final uReader = ProtobufReader(fieldBytes);
          while (uReader.hasMore) {
            final uTag = uReader.readTag();
            if (uTag == null) break;
            final (uFn, uWt) = uTag;
            if (uWt == 2) {
              final uStr = _decodeProtoUtf8(uReader.readBytes());
              if (uFn == 3) {
                postUserName = uStr;
              } else if (uFn == 4) {
                postUserNick = uStr;
              }
            } else if (uWt == 0 && uFn == 2) {
              postUserId = uReader.readVarint();
            } else {
              uReader.skipField(uWt);
            }
          }
        } else if (fn == 25) {
          final uReader = ProtobufReader(fieldBytes);
          while (uReader.hasMore) {
            final uTag = uReader.readTag();
            if (uTag == null) break;
            final (uFn, uWt) = uTag;
            if (uWt == 2) {
              final uStr = _decodeProtoUtf8(uReader.readBytes());
              if (uFn == 3) {
                threadUserName = uStr;
              } else if (uFn == 4) {
                threadUserNick = uStr;
              }
            } else if (uWt == 0 && uFn == 2) {
              threadUserId = uReader.readVarint();
            } else {
              uReader.skipField(uWt);
            }
          }
        }
      } else if (wt == 0) {
        final v = reader.readVarint();
        if (fn == 1) {
          tid = v;
        } else if (fn == 2) {
          pid = v;
        } else if (fn == 3) {
          createTime = v;
        } else if (fn == 7) {
          isComment = v != 0;
        } else if (fn == 14) {
          ppid = v;
        }
      } else {
        reader.skipField(wt);
      }
    }
    if (fname.isEmpty && tid == 0) return null;
    return ReplyItem(
      text: text,
      fname: fname,
      tid: tid,
      pid: pid,
      ppid: ppid,
      replyer: UserBrief(
        userId: replyerId,
        userName: replyerName,
        portrait: replyerPortrait,
        nickName: replyerNick,
      ),
      postUser: postUserId != 0
          ? UserBrief(
              userId: postUserId,
              userName: postUserName,
              nickName: postUserNick,
            )
          : null,
      threadAuthor: threadUserId != 0
          ? UserBrief(
              userId: threadUserId,
              userName: threadUserName,
              nickName: threadUserNick,
            )
          : null,
      isComment: isComment,
      createTime: createTime,
    );
  }

  static Map? _asMap(dynamic x) => x is Map ? x : null;
  static List? _asList(dynamic x) => x is List ? x : null;

  static List<Map<String, dynamic>> _extractThreadItemMaps(
    Map<String, dynamic> data,
  ) {
    final nested = _asMap(data['data']);
    for (final source in [
      data['thread_list'],
      nested?['thread_list'],
      data['post_list'],
      nested?['post_list'],
      data['user_post_list'],
      nested?['user_post_list'],
      data['content'],
      nested?['content'],
    ]) {
      final list = _asList(source);
      if (list != null && list.isNotEmpty) {
        return list
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    }

    for (final source in [
      data['feed_list'],
      nested?['feed_list'],
      _asMap(data['page_data'])?['feed_list'],
      _asMap(nested?['page_data'])?['feed_list'],
    ]) {
      final list = _asList(source);
      if (list == null) continue;
      final out = <Map<String, dynamic>>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final feed = _asMap(raw['feed']) ?? raw;
        final biz = _asMap(feed['business_info']);
        final item = biz ?? feed;
        final id = item['id'] ?? item['tid'];
        if (id != null && id.toString().isNotEmpty) {
          out.add(Map<String, dynamic>.from(item));
        }
      }
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  static Future<String?> fetchBarAvatarByFrs(String fname, String bduss) async {
    try {
      final result = await postForm(
        '/c/f/frs/frsBottom',
        params: [MapEntry('kw', fname)],
        bduss: bduss,
      );
      final avatar = _asMap(result['forum'])?['avatar']?.toString();
      if (avatar != null && avatar.isNotEmpty) return avatar;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> getForumId(String fname) async {
    try {
      final uri = Uri.parse(
        '$_webBaseUrl/f/commit/share/fnameShareApi',
      ).replace(queryParameters: {'ie': 'utf-8', 'fname': fname});
      final resp = await http
          .get(uri, headers: _webHeaders)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      final fidStr = _asMap(data['data'])?['fid']?.toString();
      return fidStr != null ? int.tryParse(fidStr) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<ThreadStoreMeta?> fetchThreadStoreMeta(
    String tid, {
    String? bduss,
    String? stoken,
  }) async {
    try {
      final params = <MapEntry<String, String>>[
        MapEntry('kz', tid),
        MapEntry('pn', '1'),
        MapEntry('rn', '1'),
        MapEntry('with_floor', '0'),
      ];
      final resp = await postForm(
        '/c/f/pb/page',
        params: params,
        bduss: bduss,
        stoken: stoken,
      );
      if (!_isApiSuccess(resp)) return null;
      final postList = _asList(resp['post_list']);
      if (postList == null || postList.isEmpty) return null;
      final first = _asMap(postList.first);
      if (first == null) return null;
      final pid = (first['id'] ?? first['pid'] ?? '').toString();
      if (pid.isEmpty) return null;

      final forum = _asMap(resp['forum']) ?? _asMap(first['forum']) ?? {};
      final rawFid = forum['id'] ?? forum['fid'];
      final fid = rawFid is int
          ? rawFid
          : int.tryParse(rawFid?.toString() ?? '');
      final barName = (forum['name'] ?? forum['fname'] ?? '').toString();

      return ThreadStoreMeta(pid: pid, fid: fid, barName: barName);
    } catch (e) {
      if (kDebugMode) debugPrint('fetchThreadStoreMeta failed: $e');
      return null;
    }
  }

  static Future<List<TiebaPost>> fetchServerFavorites({
    int page = 1,
    int pageSize = 200,
    String? bduss,
    String? stoken,
  }) async {
    try {
      final params = <MapEntry<String, String>>[
        MapEntry('page_no', page.toString()),
        MapEntry('page_size', pageSize.toString()),
      ];
      final resp = await postForm(
        '/c/c/favolite/favour_thread_list',
        params: params,
        bduss: bduss,
        stoken: stoken,
      );
      if (kDebugMode) {
        debugPrint(
          '[Favorite] list error_code=${resp['error_code']} keys=${resp.keys.take(8).toList()}',
        );
      }
      if (!_isApiSuccess(resp) && !_hasFavoriteListPayload(resp)) {
        return [];
      }
      final threadList = _extractFavoriteThreadList(resp);
      return _parseFavoriteThreadList(threadList);
    } catch (e) {
      if (kDebugMode) debugPrint('[Favorite] list failed: $e');
      return [];
    }
  }

  static bool _hasFavoriteListPayload(Map<String, dynamic> resp) {
    return _extractFavoriteThreadList(resp).isNotEmpty;
  }

  static List _extractFavoriteThreadList(Map<String, dynamic> resp) {
    final data = _asMap(resp['data']);
    return _asList(resp['thread_list']) ??
        _asList(data?['thread_list']) ??
        _asList(data?['store_thread_list']) ??
        _asList(resp['store_thread_list']) ??
        _asList(data?['favour_thread_list']) ??
        _asList(resp['favour_thread_list']) ??
        [];
  }

  static List<TiebaPost> _parseFavoriteThreadList(List threadList) {
    final posts = <TiebaPost>[];
    for (final item in threadList) {
      if (item is! Map) continue;
      final wrapper = Map<String, dynamic>.from(item);
      final thread =
          _asMap(wrapper['thread_info']) ??
          _asMap(wrapper['thread']) ??
          wrapper;
      final tid =
          (thread['tid'] ??
                  thread['id'] ??
                  thread['thread_id'] ??
                  wrapper['tid'] ??
                  wrapper['id'] ??
                  '')
              .toString();
      if (tid.isEmpty) continue;
      final rawFid =
          thread['fid'] ??
          thread['forum_id'] ??
          wrapper['fid'] ??
          wrapper['forum_id'];
      final fid = rawFid is int
          ? rawFid
          : int.tryParse(rawFid?.toString() ?? '');
      final ts =
          thread['last_time_int'] ??
          thread['create_time'] ??
          thread['time'] ??
          wrapper['last_time_int'];
      final tsInt = ts is int ? ts : int.tryParse(ts?.toString() ?? '');
      final createdAt = tsInt != null && tsInt > 1000000000
          ? DateTime.fromMillisecondsSinceEpoch(tsInt * 1000)
          : DateTime.now();
      posts.add(
        TiebaPost(
          id: tid,
          title:
              (thread['title'] ??
                      thread['thread_title'] ??
                      wrapper['title'] ??
                      '')
                  .toString(),
          author:
              (thread['author_name'] ??
                      _asMap(thread['author'])?['name'] ??
                      _asMap(wrapper['author'])?['name'] ??
                      '匿名')
                  .toString(),
          content: '',
          barName:
              (thread['fname'] ??
                      thread['forum_name'] ??
                      wrapper['fname'] ??
                      wrapper['forum_name'] ??
                      '')
                  .toString(),
          fid: fid,
          replyCount: thread['reply_num'] is int
              ? thread['reply_num'] ?? 0
              : int.tryParse(thread['reply_num']?.toString() ?? '') ?? 0,
          createdAt: createdAt,
          likes: _agreeNumFrom(thread),
          isFavorited: true,
        ),
      );
    }
    return posts;
  }

  static Future<bool> addServerFavorite({
    required String tid,
    required String tbs,
    required int fid,
    required String pid,
    String? bduss,
    String? stoken,
    String? barName,
  }) async {
    final payloads = <String>[
      jsonEncode([
        {'tid': tid, 'pid': pid, 'fid': fid, 'status': 1},
      ]),
      jsonEncode([
        {'tid': tid, 'pid': pid, 'fid': fid.toString(), 'status': 1},
      ]),
      jsonEncode([
        {
          'thread_id': tid,
          'post_id': pid,
          'forum_id': fid.toString(),
          'op_type': 1,
        },
      ]),
    ];

    for (final data in payloads) {
      try {
        final resp = await postForm(
          '/c/c/post/addstore',
          params: [MapEntry('data', data), MapEntry('tbs', tbs)],
          bduss: bduss,
          stoken: stoken,
        );
        if (kDebugMode) {
          debugPrint(
            '[Favorite] add error_code=${resp['error_code']} msg=${resp['error_msg']}',
          );
        }
        if (_isApiSuccess(resp) || _isAlreadyFavorited(resp)) return true;
      } catch (_) {}
    }

    if (barName != null && barName.isNotEmpty) {
      try {
        final resp = await postWebForm(
          '/f/commit/post/addStore',
          params: [
            MapEntry('ie', 'utf-8'),
            MapEntry('kw', barName),
            MapEntry('fid', fid.toString()),
            MapEntry('tid', tid),
            MapEntry('tbs', tbs),
          ],
          bduss: bduss,
          stoken: stoken,
        );
        if (kDebugMode) {
          debugPrint('[Favorite] web add error_code=${resp['error_code']}');
        }
        if (_isApiSuccess(resp) || _isAlreadyFavorited(resp)) return true;
        if (resp['no']?.toString() == '0') return true;
      } catch (_) {}
    }

    return false;
  }

  static Future<bool> removeServerFavorite({
    required String tid,
    required String tbs,
    int? fid,
    String? bduss,
    String? stoken,
    String? barName,
  }) async {
    try {
      final params = <MapEntry<String, String>>[
        MapEntry('tid', tid),
        MapEntry('tbs', tbs),
      ];
      if (fid != null) params.add(MapEntry('fid', fid.toString()));
      final resp = await postForm(
        '/c/c/post/rmstore',
        params: params,
        bduss: bduss,
        stoken: stoken,
      );
      if (kDebugMode) {
        debugPrint('[Favorite] remove error_code=${resp['error_code']}');
      }
      if (_isApiSuccess(resp)) return true;
      if (_isAlreadyUnfavorited(resp)) return true;
    } catch (_) {}

    if (barName != null && barName.isNotEmpty && fid != null) {
      try {
        final resp = await postWebForm(
          '/f/commit/post/delStore',
          params: [
            MapEntry('ie', 'utf-8'),
            MapEntry('kw', barName),
            MapEntry('fid', fid.toString()),
            MapEntry('tid', tid),
            MapEntry('tbs', tbs),
          ],
          bduss: bduss,
          stoken: stoken,
        );
        if (_isApiSuccess(resp)) return true;
        if (resp['no']?.toString() == '0') return true;
        if (_isAlreadyUnfavorited(resp)) return true;
      } catch (_) {}
    }

    return false;
  }

  static const hotBarFallback = [
    '抗压背锅',
    '孙笑川',
    'bilibili',
    '核战避难所',
    '2ch',
    '图拉丁',
    '吊图',
    '弱智',
    '航空母舰',
    '中国人口',
  ];

  static Future<Uint8List> postProto(
    String path,
    Uint8List protoData, {
    String? cmdId,
    String? bduss,
    String? stoken,
  }) async {
    final uri = cmdId != null ? '$_baseUrl$path?cmd=$cmdId' : '$_baseUrl$path';
    final boundary = '-*_r1999';
    final header =
        '--$boundary\r\nContent-Disposition: form-data; name="data"; filename="file"\r\nContent-Type: application/octet-stream\r\n\r\n';
    final footer = '\r\n--$boundary--\r\n';
    final bodyBytes = <int>[
      ...utf8.encode(header),
      ...protoData,
      ...utf8.encode(footer),
    ];
    final headers = <String, String>{
      'User-Agent': 'bdtb for Android 12.57.4.0',
      'x_bd_data_type': 'protobuf',
      'Connection': 'keep-alive',
      'Content-Type': 'multipart/form-data; boundary=$boundary',
    };
    if (bduss != null && bduss.isNotEmpty) {
      headers['Cookie'] = _authCookie(bduss, stoken);
    }
    final response = await http
        .post(Uri.parse(uri), headers: headers, body: bodyBytes)
        .timeout(const Duration(seconds: 15));
    return response.bodyBytes;
  }

  static Uint8List _buildCommonReq({
    String? bduss,
    String? tbs,
    String? stoken,
  }) {
    final w = ProtobufWriter();
    w.writeString(2, _clientVersion);
    w.writeString(3, 'dart_tieba');
    if (bduss != null) w.writeString(10, bduss);
    if (tbs != null) w.writeString(11, tbs);
    if (stoken != null && stoken.isNotEmpty) {
      w.writeString(30, stoken);
    }
    w.writeInt32(1, 2);
    return w.toBytes();
  }

  static Uint8List _buildFrsPageReq(
    String fname, {
    int pn = 0,
    int rn = 30,
    int sortType = 0,
    String? bduss,
  }) {
    final commonBytes = _buildCommonReq(bduss: bduss);
    final dataW = ProtobufWriter();
    dataW.writeString(1, fname);
    dataW.writeInt32(2, rn);
    dataW.writeInt32(3, rn + 5);
    dataW.writeInt32(15, pn);
    dataW.writeInt32(47, sortType);
    dataW.writeMessage(39, commonBytes);
    final w = ProtobufWriter();
    w.writeMessage(1, dataW.toBytes());
    return w.toBytes();
  }

  static List<TiebaPost> _parseFrsPageRes(Uint8List data, String fname) {
    final reader = ProtobufReader(data);
    final posts = <TiebaPost>[];
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fieldNumber, wireType) = tag;
      if (wireType == 2) {
        if (fieldNumber == 2) {
          final bytes = reader.readBytes();
          final dataReader = ProtobufReader(bytes);
          while (dataReader.hasMore) {
            final dataTag = dataReader.readTag();
            if (dataTag == null) break;
            final (dfn, dw) = dataTag;
            if (dw == 2 && dfn == 7) {
              final threadData = dataReader.readBytes();
              final thread = _parseThreadInfo(threadData, fname);
              if (thread != null) posts.add(thread);
            } else {
              dataReader.skipField(dw);
            }
          }
        } else {
          reader.skipField(wireType);
        }
      } else {
        reader.skipField(wireType);
      }
    }
    return posts;
  }

  static TiebaPost? _parseThreadInfo(Uint8List data, String fname) {
    final reader = ProtobufReader(data);
    String tid = '', title = '';
    String author = '匿名';
    String? authorAvatar;
    int? authorForumLevel;
    String? cover;
    int replyNum = 0, agree = 0;
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fieldNumber, wireType) = tag;
      switch (fieldNumber) {
        case 1:
          tid = reader.readVarint().toString();
          break;
        case 2:
          if (wireType == 2) {
            final userInfo = _parseUserInfo(reader.readBytes());
            if (userInfo != null) {
              author = userInfo.name;
              authorAvatar = _buildAvatarUrl(userInfo.portrait);
              if (userInfo.level > 0) authorForumLevel = userInfo.level;
            }
          } else {
            reader.skipField(wireType);
          }
          break;
        case 3:
          title = reader.readString();
          break;
        case 4:
          replyNum = reader.readVarint();
          break;
        case 126:
          if (wireType == 2) {
            final agreeData = reader.readBytes();
            agree = _parseAgreeNum(agreeData);
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          if (wireType == 2) {
            cover ??= _extractCoverFromProtoContent(reader.readBytes());
          } else {
            reader.skipField(wireType);
          }
      }
    }
    if (tid.isEmpty) return null;
    return TiebaPost(
      id: tid,
      title: title,
      author: author,
      authorAvatar: authorAvatar,
      cover: cover,
      content: '',
      barName: fname,
      replyCount: replyNum,
      createdAt: DateTime.now(),
      likes: agree,
      authorForumLevel: authorForumLevel,
    );
  }

  static ({String name, String? portrait, int level})? _parseUserInfo(
    Uint8List data,
  ) {
    final reader = ProtobufReader(data);
    String name = '';
    String? portrait;
    int level = 0;
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fn, wt) = tag;
      if (wt == 0) {
        if (fn == 23) {
          level = reader.readVarint();
        } else {
          reader.skipField(wt);
        }
      } else if (wt == 2) {
        try {
          final str = utf8.decode(reader.readBytes(), allowMalformed: true);
          if (fn == 3 && str.isNotEmpty) {
            name = str;
          } else if (fn == 4 && str.isNotEmpty && name.isEmpty) {
            name = str;
          } else if (fn == 5 && str.isNotEmpty) {
            portrait = str;
          } else if (fn == 15 && str.isNotEmpty && portrait == null) {
            portrait = str;
          }
        } catch (_) {
          reader.skipField(wt);
        }
      } else {
        reader.skipField(wt);
      }
    }
    if (name.isEmpty) return null;
    return (name: name, portrait: portrait, level: level);
  }

  static String? _extractCoverFromProtoContent(Uint8List data) {
    try {
      final reader = ProtobufReader(data);
      while (reader.hasMore) {
        final tag = reader.readTag();
        if (tag == null) break;
        final (fn, wt) = tag;
        if (wt == 2) {
          final url = _extractImageUrlFromContentElement(reader.readBytes());
          if (url != null) return url;
        } else {
          reader.skipField(wt);
        }
      }
    } catch (_) {}
    return null;
  }

  static String? _extractImageUrlFromContentElement(Uint8List data) {
    try {
      final reader = ProtobufReader(data);
      var type = 0;
      var text = '';
      while (reader.hasMore) {
        final tag = reader.readTag();
        if (tag == null) break;
        final (fn, wt) = tag;
        if (fn == 1 && wt == 0) {
          type = reader.readVarint();
        } else if (fn == 2 && wt == 2) {
          text = reader.readString();
        } else {
          reader.skipField(wt);
        }
      }
      if (type == 3 && text.isNotEmpty) {
        return _resolveImageUrl(text);
      }
    } catch (_) {}
    return null;
  }

  static int _parseAgreeNum(Uint8List data) {
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fn, wt) = tag;
      if (fn == 1 && wt == 0) return reader.readVarint();
      reader.skipField(wt);
    }
    return 0;
  }

  static Future<List<TiebaPost>> fetchBarThreads(
    String barName, {
    int page = 1,
    String? bduss,
    bool isGood = false,
  }) async {
    final formPosts = await fetchBarThreadsForm(
      barName,
      page: page,
      bduss: bduss,
      isGood: isGood,
    );
    if (formPosts.isNotEmpty) return formPosts;

    try {
      final reqData = _buildFrsPageReq(barName, pn: page - 1, bduss: bduss);
      final resData = await postProto(
        '/c/f/frs/page',
        reqData,
        cmdId: '301001',
      );
      if (resData.length < 10) {
        return [];
      }
      return parseFrsPagePostsAsync(resData, barName);
    } catch (_) {
      return [];
    }
  }

  static Future<PersonalizedFeedPage> fetchPersonalized({
    int loadType = 1,
    int page = 1,
    String? bduss,
  }) async {
    try {
      final params = <MapEntry<String, String>>[
        MapEntry('load_type', loadType.toString()),
        MapEntry('pn', page.toString()),
        MapEntry('page_thread_count', '15'),
        MapEntry('need_tags', '0'),
        MapEntry('pre_ad_thread_count', '0'),
        MapEntry('sug_count', '0'),
        MapEntry('tag_code', '0'),
        MapEntry('q_type', '1'),
        MapEntry('need_forumlist', '0'),
        MapEntry('new_net_type', '1'),
        MapEntry('new_install', '0'),
        MapEntry(
          'request_time',
          DateTime.now().millisecondsSinceEpoch.toString(),
        ),
        MapEntry('cuid_gid', ''),
        MapEntry('invoke_source', ''),
        MapEntry('_client_type', '2'),
      ];
      final result = await postFormHeavy(
        '/c/f/excellent/personalized',
        params: params,
        bduss: bduss,
      );
      if (result['error_code'] != 0 && result['error_code'] != '0') {
        return const PersonalizedFeedPage(posts: [], hasMore: false);
      }
      final posts = await parsePersonalizedPostsAsync(result);
      final hasMore = _parsePersonalizedHasMore(result, posts.length);
      return PersonalizedFeedPage(posts: posts, hasMore: hasMore);
    } catch (_) {
      return const PersonalizedFeedPage(posts: [], hasMore: false);
    }
  }

  static bool _parsePersonalizedHasMore(Map<String, dynamic> data, int count) {
    final page = _asMap(data['page']) ?? _asMap(data['page_info']);
    final raw = data['has_more'] ?? page?['has_more'] ?? data['has_next'];
    if (raw == 1 || raw == true || raw == '1') return true;
    if (raw == 0 || raw == false || raw == '0') return false;
    // 接口未返回 has_more 时，只要有帖子就继续尝试加载
    return count > 0;
  }

  static List<TiebaPost> _parsePersonalizedList(Map<String, dynamic> data) {
    final threadList = _extractThreadItemMaps(data);
    final userLevels = _collectForumUserLevels(data);
    final posts = <TiebaPost>[];
    for (final item in threadList) {
      final tid = (item['id'] ?? item['tid'] ?? '').toString();
      if (tid.isEmpty) continue;

      final authorMap = _asMap(item['author']) ?? {};
      final authorName = authorMap['name']?.toString() ?? '';
      final authorPortrait = authorMap['portrait']?.toString();
      final authorAvatar = _buildAvatarUrl(authorPortrait);

      String content = '';
      final abstractList = _asList(item['abstract']);
      if (abstractList != null) {
        for (final abs in abstractList) {
          if (abs is Map) {
            final text = abs['text']?.toString() ?? '';
            if (text.isNotEmpty) {
              if (content.isNotEmpty) content += '\n';
              content += text;
            }
          }
        }
      }

      var title = (item['title'] ?? '').toString();
      if (title.isEmpty) {
        title = content.isNotEmpty
            ? (content.length > 40 ? content.substring(0, 40) : content)
            : '无标题';
      }

      final replyNum = _intFrom(item['reply_num']);
      final agreeNum = _agreeNumFrom(item);
      final fname = (item['fname'] ?? '').toString();
      final rawFid = item['fid'];
      final fid = rawFid is int
          ? rawFid
          : int.tryParse(rawFid?.toString() ?? '');

      final rawTime = item['create_time'] ?? item['last_time_int'] ?? 0;
      final ts = rawTime is int
          ? rawTime
          : int.tryParse(rawTime.toString()) ?? 0;
      final levelFields = _authorForumLevelFields(item, userLevels);

      posts.add(
        TiebaPost(
          id: tid,
          title: title,
          author: authorName.isNotEmpty ? authorName : '匿名',
          authorAvatar: authorAvatar,
          authorPortrait: authorPortrait,
          cover: _extractThreadCover(item),
          content: content,
          video: _extractThreadVideo(item),
          barName: fname,
          fid: fid,
          replyCount: replyNum,
          likes: agreeNum,
          createdAt: ts > 1000000000
              ? DateTime.fromMillisecondsSinceEpoch(ts * 1000)
              : DateTime.now(),
          authorForumLevel: levelFields.authorForumLevel,
          authorForumLevelName: levelFields.authorForumLevelName,
        ),
      );
    }
    return posts;
  }

  static Future<List<TiebaPost>> fetchBarThreadsForm(
    String barName, {
    int page = 1,
    String? bduss,
    bool isGood = false,
  }) async {
    final pageData = await fetchBarFrsPage(
      barName,
      page: page,
      bduss: bduss,
      isGood: isGood,
    );
    return pageData?.posts ?? [];
  }

  /// 吧内帖子列表 + 首屏元数据（Tab、置顶、吧规等）。
  static Future<BarFrsPageResult?> fetchBarFrsPage(
    String barName, {
    int page = 1,
    String? bduss,
    bool isGood = false,
    bool parseContext = false,
  }) async {
    try {
      final result = await postForm(
        '/c/f/frs/page',
        params: [
          MapEntry('kw', barName.trim()),
          MapEntry('pn', page.toString()),
          MapEntry('rn', '30'),
          MapEntry('is_good', isGood ? '1' : '0'),
        ],
        bduss: bduss,
      );
      if (!_isApiSuccess(result)) return null;
      final posts = _parseFormThreadList(result, barName);
      final context = parseContext && page == 1 && !isGood
          ? _parseBarForumContextFromFrs(result, barName)
          : null;
      final hasMore = _parseFrsHasMore(result, posts.length);
      return BarFrsPageResult(posts: posts, context: context, hasMore: hasMore);
    } catch (_) {
      return null;
    }
  }

  static bool _parseFrsHasMore(Map<String, dynamic> data, int count) {
    final page = _asMap(data['page']) ?? _asMap(_asMap(data['data'])?['page']);
    final raw = data['has_more'] ?? page?['has_more'] ?? data['has_next'];
    if (raw == 1 || raw == true || raw == '1') return true;
    if (raw == 0 || raw == false || raw == '0') return false;
    return count >= 20;
  }

  static BarForumContext _parseBarForumContextFromFrs(
    Map<String, dynamic> data,
    String barName,
  ) {
    final forum =
        _asMap(data['forum']) ?? _asMap(_asMap(data['data'])?['forum']);
    final avatarRaw = forum?['avatar']?.toString();
    final avatarUrl = avatarRaw == null ? null : _resolveImageUrl(avatarRaw);

    final tabs = <String>[];
    final navTab =
        _asMap(data['nav_tab_info']) ??
        _asMap(_asMap(data['data'])?['nav_tab_info']);
    final tabList = _asList(navTab?['tab']) ?? _asList(data['tab_list']);
    if (tabList != null) {
      for (final raw in tabList) {
        if (raw is! Map) continue;
        final name = raw['tab_name']?.toString().trim() ?? '';
        if (name.isNotEmpty) tabs.add(name);
      }
    }
    if (tabs.isEmpty) tabs.addAll(['最新', '精华']);

    final ruleMap =
        _asMap(data['forum_rule']) ??
        _asMap(_asMap(data['data'])?['forum_rule']);
    var forumRule =
        ruleMap?['forum_rule']?.toString().trim() ??
        ruleMap?['content']?.toString().trim() ??
        ruleMap?['rule_info']?.toString().trim();
    if (forumRule != null && forumRule.isEmpty) forumRule = null;

    final pinned = <BarForumThreadBrief>[];
    for (final item in _extractThreadItemMaps(data)) {
      if (!_isTruthy(item['is_top'])) continue;
      final tid = (item['id'] ?? item['tid'] ?? '').toString();
      final title = (item['title'] ?? '').toString().trim();
      if (tid.isEmpty || title.isEmpty) continue;
      pinned.add(BarForumThreadBrief(id: tid, title: title));
    }

    final memberRaw = forum?['member_num'] ?? forum?['member_count'];
    return BarForumContext(
      barName: (forum?['name'] ?? barName).toString(),
      avatarUrl: avatarUrl,
      slogan: forum?['slogan']?.toString(),
      memberCount: _parseTbCount(memberRaw),
      tabs: tabs,
      forumRule: forumRule,
      pinnedThreads: pinned,
    );
  }

  static bool _isTruthy(dynamic value) {
    return value == 1 || value == '1' || value == true;
  }

  /// 当前账号在某吧今日是否已签到（forumGuide）。
  static Future<bool?> fetchBarSignedToday(
    String barName, {
    required String bduss,
    required String tbs,
  }) async {
    final target = _normalizeForumName(barName);
    if (target.isEmpty || tbs.isEmpty) return null;
    try {
      final fid = await getForumId(barName);
      final result = await postWebForm(
        '/c/f/forum/forumGuide',
        params: [
          MapEntry('tbs', tbs),
          MapEntry('sort_type', '3'),
          MapEntry('call_from', '3'),
          MapEntry('page_no', '1'),
          MapEntry('res_num', '200'),
        ],
        bduss: bduss,
      );
      if (!_isApiSuccess(result)) return null;
      final list = _asList(result['like_forum']);
      if (list == null) return null;
      for (final raw in list) {
        if (raw is! Map) continue;
        final itemFid = raw['forum_id'] ?? raw['id'];
        if (fid != null &&
            itemFid != null &&
            fid.toString() == itemFid.toString()) {
          return _isTruthy(raw['is_sign']);
        }
        final name = (raw['forum_name'] ?? raw['name'] ?? '').toString();
        if (_normalizeForumName(name) != target) continue;
        return _isTruthy(raw['is_sign']);
      }
    } catch (_) {}
    return null;
  }

  static Future<BarForumContext?> fetchBarForumContext(
    String barName, {
    String? bduss,
    String? portrait,
    String? tbs,
    bool? followed,
  }) async {
    final name = barName.trim();
    if (name.isEmpty) return null;

    final detailFuture = fetchForumDetail(name, bduss: bduss);
    final levelFuture =
        (bduss != null &&
            bduss.isNotEmpty &&
            portrait != null &&
            portrait.isNotEmpty)
        ? fetchUserForumLevel(barName: name, portrait: portrait, bduss: bduss)
        : Future<Map<String, dynamic>?>.value(null);
    final frsFuture = fetchBarFrsPage(name, bduss: bduss, parseContext: true);
    final signFuture =
        (bduss != null && bduss.isNotEmpty && tbs != null && tbs.isNotEmpty)
        ? fetchBarSignedToday(name, bduss: bduss, tbs: tbs)
        : Future<bool?>.value(null);

    final detail = await detailFuture;
    final level = await levelFuture;
    final frs = await frsFuture;
    final signed = await signFuture;

    var ctx =
        frs?.context ??
        BarForumContext(barName: name, tabs: const ['最新', '精华']);

    if (detail != null) {
      final avatar = detail['avatar']?.toString();
      ctx = ctx.copyWith(
        barName: detail['name']?.toString() ?? name,
        avatarUrl: avatar == null ? ctx.avatarUrl : _resolveImageUrl(avatar),
        slogan: detail['slogan']?.toString() ?? ctx.slogan,
        memberCount: _parseTbCount(detail['member_count']) > 0
            ? _parseTbCount(detail['member_count'])
            : ctx.memberCount,
      );
    }

    if (level != null) {
      ctx = ctx.copyWith(
        forumLevel: level['forum_level'] is int
            ? level['forum_level'] as int
            : int.tryParse(level['forum_level']?.toString() ?? '') ?? 0,
        forumLevelName: level['forum_level_name']?.toString() ?? '',
        currentExp: _parseTbCount(level['exp']),
        levelUpExp: _parseTbCount(level['levelup_exp']),
      );
    }

    final levelFollowed = level?['is_follow'];
    final levelSigned = level?['signed_today'];
    final resolvedFollowed = levelFollowed is bool
        ? levelFollowed
        : (followed ?? ctx.followed);
    final resolvedSigned = signed ?? (levelSigned is bool ? levelSigned : null);

    return ctx.copyWith(
      signedToday: resolvedSigned,
      followed: resolvedFollowed,
    );
  }

  static List<TiebaPost> _parseFormThreadList(
    Map<String, dynamic> data,
    String barName,
  ) {
    final threadList = _extractThreadItemMaps(data);
    final userLevels = _collectForumUserLevels(data);
    final posts = <TiebaPost>[];
    for (final item in threadList) {
      final tid = (item['id'] ?? item['tid'] ?? '').toString();
      final title = (item['title'] ?? '').toString();
      if (tid.isEmpty || title.isEmpty) continue;

      final authorMap = _asMap(item['author']) ?? {};
      final authorName =
          authorMap['name']?.toString() ??
          authorMap['name_show']?.toString() ??
          item['author_name']?.toString() ??
          '匿名';
      final authorPortrait =
          authorMap['portrait']?.toString() ??
          authorMap['user_portrait']?.toString();
      final authorAvatar = _buildAvatarUrl(authorPortrait);

      final cover =
          _extractThreadCover(item) ??
          _extractFirstImage(item['first_post_content']);
      final video = _extractThreadVideo(item);

      final replyNum = _intFrom(item['reply_num']);
      final agreeNum = _agreeNumFrom(item);
      final rawFid = item['fid'];
      final fid = rawFid is int
          ? rawFid
          : int.tryParse(rawFid?.toString() ?? '');
      final levelFields = _authorForumLevelFields(item, userLevels);

      posts.add(
        TiebaPost(
          id: tid,
          title: title,
          author: authorName,
          authorAvatar: authorAvatar,
          authorPortrait: authorPortrait,
          content: '',
          cover: cover ?? video?.coverSrc,
          fid: fid,
          video: video,
          barName: barName,
          replyCount: replyNum,
          createdAt: DateTime.now(),
          likes: agreeNum,
          authorForumLevel: levelFields.authorForumLevel,
          authorForumLevelName: levelFields.authorForumLevelName,
        ),
      );
    }
    return posts;
  }

  static String? _extractThreadCover(Map item) {
    final fromContent =
        _extractFirstImage(item['first_post_content']) ??
        _extractFirstImage(item['content']);
    if (fromContent != null) return fromContent;

    final fromMedia =
        _extractCoverFromMedia(item['media']) ??
        _extractCoverFromMedia(item['pic_info']);
    if (fromMedia != null) return fromMedia;

    final videoInfo = _asMap(item['video_info']);
    if (videoInfo != null) {
      for (final key in [
        'thumbnail_url',
        'first_frame_thumbnail',
        'small_thumbnail_url',
      ]) {
        final url = _resolveImageUrl(videoInfo[key]?.toString());
        if (url != null) return url;
      }
    }

    for (final key in ['cover_src', 'video_cover', 'meizhi_pic', 'cover']) {
      final url = _resolveImageUrl(item[key]?.toString());
      if (url != null) return url;
    }

    final abstractList = _asList(item['abstract']);
    if (abstractList != null) {
      for (final abs in abstractList) {
        if (abs is! Map) continue;
        final url = _resolveImageUrl(abs['src']?.toString());
        if (url != null) return url;
      }
    }

    return null;
  }

  static String? _extractCoverFromMedia(dynamic media) {
    if (media == null) return null;
    final items = media is List ? media : [media];
    for (final item in items) {
      if (item is! Map) continue;
      final url = _pickCoverImageUrl(item);
      if (url != null) return url;
    }
    return null;
  }

  static String? _pickCoverImageUrl(Map item) {
    final keys = DataSaverService.instance.enabled
        ? [
            'small_pic',
            'cdn_src',
            'src',
            'water_pic',
            'src_pic',
            'big_cdn_src',
            'big_src',
            'big_pic',
            'origin_pic',
            'dynamic_pic',
            'origin_src',
          ]
        : [
            'big_pic',
            'origin_pic',
            'dynamic_pic',
            'src_pic',
            'water_pic',
            'big_cdn_src',
            'cdn_src',
            'origin_src',
            'big_src',
            'src',
            'small_pic',
          ];
    for (final key in keys) {
      final url = _resolveImageUrl(item[key]?.toString());
      if (url != null) return url;
    }
    return null;
  }

  static String? _resolveImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.contains('/c/p/img')) {
      try {
        final src = Uri.parse(url).queryParameters['src'];
        if (src != null && src.isNotEmpty) {
          return _normalizeImageUrl(Uri.decodeComponent(src));
        }
      } catch (_) {}
    }
    return _normalizeImageUrl(url);
  }

  static String _normalizeImageUrl(String url) {
    if (DataSaverService.instance.enabled) {
      return CoverImageCache.thumbnailUrl(url);
    }
    return _upgradeCoverUrl(url);
  }

  static String? _resolveVideoUrl(String? url) => resolveTiebaVideoUrl(url);

  static String? _pickVideoPlayUrl(Map c) {
    for (final key in [
      'link',
      'video_url',
      'cdn_src',
      'big_cdn_src',
      'big_src',
      'play_url',
      'video_src',
    ]) {
      final raw = c[key]?.toString().trim();
      if (raw != null && raw.isNotEmpty) {
        final resolved = _resolveVideoUrl(raw);
        if (resolved != null) return resolved;
      }
    }
    return null;
  }

  static String? _pickVideoCoverUrl(Map c) {
    for (final key in [
      'src',
      'cover_src',
      'thumbnail_url',
      'first_frame_thumbnail',
      'small_thumbnail_url',
      'poster',
    ]) {
      final raw = c[key]?.toString();
      if (raw != null && raw.isNotEmpty) {
        return _resolveImageUrl(raw);
      }
    }
    return null;
  }

  static int _videoDurationFrom(dynamic raw) {
    final value = _intFrom(raw);
    if (value <= 0) return 0;
    // during_time 常为毫秒
    if (value > 36000) return (value / 1000).round();
    return value;
  }

  static TiebaVideo? _extractVideoFromInfo(Map? info) {
    if (info == null) return null;
    final playUrl = _resolveVideoUrl(
      info['video_url']?.toString() ??
          info['play_url']?.toString() ??
          info['link']?.toString() ??
          info['video_src']?.toString(),
    );
    final cover = _resolveImageUrl(
      info['thumbnail_url']?.toString() ??
          info['first_frame_thumbnail']?.toString() ??
          info['small_thumbnail_url']?.toString() ??
          info['cover_src']?.toString() ??
          info['poster']?.toString() ??
          info['src']?.toString(),
    );
    final width = _intFrom(info['width'] ?? info['video_width']);
    final height = _intFrom(info['height'] ?? info['video_height']);
    final duration = _videoDurationFrom(
      info['duration'] ?? info['during_time'] ?? info['video_duration'],
    );
    // 列表接口常只给封面/尺寸，不给 play_url
    final hasMarker =
        playUrl != null || width > 0 || cover != null || duration > 0;
    if (!hasMarker) return null;
    return TiebaVideo(
      src: playUrl ?? '',
      coverSrc: cover,
      duration: duration,
      width: width,
      height: height,
    );
  }

  static TiebaVideo? _extractVideoFromContentItem(Map c) {
    final type = c['type'];
    if (type != 5 && type != '5') return null;
    final playUrl = _pickVideoPlayUrl(c);
    if (playUrl == null) return null;
    return TiebaVideo(
      src: playUrl,
      coverSrc: _pickVideoCoverUrl(c),
      duration: _videoDurationFrom(c['during_time'] ?? c['duration']),
      width: _intFrom(c['width']),
      height: _intFrom(c['height']),
    );
  }

  static TiebaVideo? _extractVideoFromContent(dynamic content) {
    if (content == null) return null;
    final items = content is List
        ? content
        : content is Map
        ? [content]
        : null;
    if (items == null) return null;
    for (final item in items) {
      if (item is! Map) continue;
      final video = _extractVideoFromContentItem(item);
      if (video != null) return video;
    }
    return null;
  }

  static TiebaVideo? _extractThreadVideo(Map item) {
    final fromInfo =
        _extractVideoFromInfo(_asMap(item['video_info'])) ??
        _extractVideoFromContent(item['first_post_content']) ??
        _extractVideoFromContent(item['content']);
    if (fromInfo != null) return fromInfo;
    // thread_type 40 = 视频帖（列表里可能只有类型标记）
    if (_intFrom(item['thread_type']) == 40) {
      final cover = _extractThreadCover(item);
      if (cover != null) {
        return TiebaVideo(src: '', coverSrc: cover);
      }
    }
    return null;
  }

  static String _videoMarkdown(TiebaVideo video) {
    final cover = video.coverSrc ?? '';
    final duration = video.duration > 0 ? '|${video.duration}' : '';
    final alt = cover.isNotEmpty ? 'video:$cover$duration' : 'video$duration';
    return '\n![$alt](${video.src})\n';
  }

  static String _upgradeCoverUrl(String url) {
    if (!url.contains('imgsrc.baidu.com/forum/')) return url;
    return url.replaceAllMapped(RegExp(r'w%3d(\d+)', caseSensitive: false), (
      match,
    ) {
      final width = int.tryParse(match.group(1) ?? '') ?? 0;
      if (width > 0 && width < 800) return 'w%3d960';
      return match.group(0)!;
    });
  }

  static String? _extractFirstImage(dynamic content) {
    if (content == null) return null;
    List<dynamic> items;
    if (content is List) {
      items = content;
    } else if (content is Map) {
      items = [content];
    } else {
      return null;
    }
    for (final item in items) {
      if (item is! Map) continue;
      final type = item['type'];
      if (type != null && type != 3 && type != '3') continue;
      final url = _pickCoverImageUrl(item);
      if (url != null) return url;
    }
    return null;
  }

  static String? _buildAvatarUrl(String? portrait) {
    if (portrait == null || portrait.isEmpty) return null;
    if (portrait.startsWith('http')) return portrait;
    return 'https://himg.bdimg.com/sys/portrait/item/$portrait';
  }

  static bool _isAgreed(dynamic item) {
    if (item is! Map) return false;
    if (item['is_agreed'] == 1 || item['is_agreed'] == true) return true;
    final agreeObj = item['agree'];
    if (agreeObj is Map) {
      if (agreeObj['is_agreed'] == 1 || agreeObj['is_agreed'] == true) {
        return true;
      }
    }
    return false;
  }

  /// 从帖子/评论 JSON 解析点赞数（兼容 agree_num 字符串与 agree 嵌套对象）。
  static int _agreeNumFrom(dynamic item) {
    if (item is! Map) return 0;
    final agreeObj = item['agree'];
    if (agreeObj is Map) {
      final nested = _intFrom(
        agreeObj['agree_num'] ?? agreeObj['num'] ?? agreeObj['total'],
      );
      if (nested > 0) return nested;
    }
    return _intFrom(item['agree_num'] ?? item['like_num']);
  }

  static int _resolveFirstPostAgreeNum(Map first, Map? thread) {
    final fromPost = _agreeNumFrom(first);
    if (fromPost > 0) return fromPost;
    if (thread != null) {
      return _agreeNumFrom(thread);
    }
    return 0;
  }

  static Future<TiebaPostDetail?> fetchPostDetail(
    String tid, {
    int page = 1,
    String? bduss,
    String? stoken,
  }) async {
    try {
      final batch = detailCommentPageSize;
      final params = <MapEntry<String, String>>[
        MapEntry('kz', tid),
        MapEntry('pn', page.toString()),
        MapEntry('rn', batch.toString()),
        MapEntry('with_floor', '1'),
        MapEntry('floor_page_size', batch.toString()),
        MapEntry('sub_floor_page_size', batch.toString()),
        MapEntry('sub_floor_pn', '1'),
      ];
      final resp = await postFormHeavy(
        '/c/f/pb/page',
        params: params,
        bduss: bduss,
        stoken: stoken,
      );
      if (!_isApiSuccess(resp)) return null;
      return parsePostDetailAsync(resp, tid, page: page);
    } catch (_) {
      return null;
    }
  }

  static int? _optionalIntField(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static ({int level, String? levelName})? _forumLevelFromUserMap(
    Map<int, ({int level, String? levelName})> userLevels,
    Map post,
  ) {
    final authorMap = _asMap(post['author']);
    final userMap = _asMap(post['user']);
    final authorId =
        _optionalIntField(post['author_id']) ??
        _optionalIntField(post['user_id']) ??
        _optionalIntField(authorMap?['id']) ??
        _optionalIntField(authorMap?['user_id']) ??
        _optionalIntField(userMap?['id']) ??
        _optionalIntField(userMap?['user_id']);
    if (authorId != null && userLevels.containsKey(authorId)) {
      final info = userLevels[authorId]!;
      if (info.level > 0 || (info.levelName?.isNotEmpty ?? false)) {
        return info;
      }
    }
    for (final source in [userMap, authorMap]) {
      if (source == null) continue;
      final level = _optionalIntField(source['level_id']) ?? 0;
      final levelName = source['level_name']?.toString().trim();
      if (level > 0 || (levelName?.isNotEmpty ?? false)) {
        return (
          level: level,
          levelName: levelName?.isNotEmpty == true ? levelName : null,
        );
      }
    }
    return null;
  }

  static Map<int, ({int level, String? levelName})> _collectForumUserLevels(
    Map<String, dynamic> data,
  ) {
    final merged = <int, ({int level, String? levelName})>{};
    void absorb(dynamic raw) {
      merged.addAll(_forumLevelMapFromUserList(raw));
    }

    absorb(data['user_list']);
    final nested = _asMap(data['data']);
    absorb(nested?['user_list']);
    absorb(_asMap(data['page_data'])?['user_list']);
    absorb(_asMap(nested?['page_data'])?['user_list']);

    for (final source in [
      data['feed_list'],
      nested?['feed_list'],
      _asMap(data['page_data'])?['feed_list'],
      _asMap(nested?['page_data'])?['feed_list'],
    ]) {
      final list = _asList(source);
      if (list == null) continue;
      for (final raw in list) {
        if (raw is! Map) continue;
        final feed = _asMap(raw['feed']) ?? raw;
        absorb(feed['user_list']);
        absorb(_asMap(feed['business_info'])?['user_list']);
      }
    }
    return merged;
  }

  /// 推荐流等接口常不带吧内等级，按吧名 + 头像批量补拉。
  static Future<void> enrichPostsForumLevels(
    List<TiebaPost> posts, {
    String? bduss,
    String? stoken,
    int maxConcurrent = 5,
    int? maxLookups,
  }) async {
    if (posts.isEmpty) return;

    final grouped = <String, List<TiebaPost>>{};
    for (final post in posts) {
      if (post.authorForumLevel != null && post.authorForumLevel! > 0) {
        continue;
      }
      if (post.authorForumLevelName?.trim().isNotEmpty == true) {
        continue;
      }
      final barName = post.barName.trim();
      final portrait =
          post.authorPortrait ?? portraitFromAvatarUrl(post.authorAvatar);
      if (barName.isEmpty || portrait == null || portrait.isEmpty) continue;
      final key = '$barName\x00$portrait';
      grouped.putIfAbsent(key, () => []).add(post);
    }
    if (grouped.isEmpty) return;

    var entries = grouped.entries.toList();
    if (maxLookups != null && entries.length > maxLookups) {
      entries = entries.take(maxLookups).toList();
    }

    for (var i = 0; i < entries.length; i += maxConcurrent) {
      final batch = entries.skip(i).take(maxConcurrent);
      await Future.wait(
        batch.map((entry) async {
          final sep = entry.key.indexOf('\x00');
          if (sep <= 0) return;
          final barName = entry.key.substring(0, sep);
          final portrait = entry.key.substring(sep + 1);
          final level = await fetchUserForumLevel(
            barName: barName,
            portrait: portrait,
            bduss: bduss,
            stoken: stoken,
          );
          if (level == null) return;
          final forumLevel = level['forum_level'];
          final parsedLevel = forumLevel is int
              ? forumLevel
              : int.tryParse(forumLevel?.toString() ?? '');
          final levelName = level['forum_level_name']?.toString().trim();
          if ((parsedLevel == null || parsedLevel <= 0) &&
              (levelName == null || levelName.isEmpty)) {
            return;
          }
          for (final post in entry.value) {
            post.authorForumLevel = parsedLevel;
            post.authorForumLevelName = levelName?.isNotEmpty == true
                ? levelName
                : null;
          }
        }),
      );
    }
  }

  static Map<int, ({int level, String? levelName})> _forumLevelMapFromUserList(
    dynamic raw,
  ) {
    final map = <int, ({int level, String? levelName})>{};
    if (raw is! List) return map;
    for (final item in raw) {
      if (item is! Map) continue;
      final uid = _optionalIntField(item['id']);
      if (uid == null || uid <= 0) continue;
      final level = _optionalIntField(item['level_id']) ?? 0;
      final levelName = item['level_name']?.toString().trim();
      map[uid] = (
        level: level,
        levelName: levelName?.isNotEmpty == true ? levelName : null,
      );
    }
    return map;
  }

  static ({int? authorForumLevel, String? authorForumLevelName})
  _authorForumLevelFields(
    Map item,
    Map<int, ({int level, String? levelName})> userLevels,
  ) {
    final info = _forumLevelFromUserMap(userLevels, item);
    if (info == null) {
      return (authorForumLevel: null, authorForumLevelName: null);
    }
    if (info.level <= 0 && (info.levelName?.isEmpty ?? true)) {
      return (authorForumLevel: null, authorForumLevelName: null);
    }
    return (
      authorForumLevel: info.level > 0 ? info.level : null,
      authorForumLevelName: info.levelName,
    );
  }

  static TiebaPostDetail? _parseFormPostDetail(
    Map<String, dynamic> data,
    String tid, {
    int page = 1,
  }) {
    final postList = data['post_list'] as List?;
    if (postList == null || postList.isEmpty) return null;

    final userLevels = _forumLevelMapFromUserList(data['user_list']);

    final first = postList[0];
    final authorMap = first['author'] as Map? ?? {};
    final authorName = authorMap['name']?.toString() ?? '匿名';
    final authorPortrait = authorMap['portrait']?.toString();
    final authorAvatar = _buildAvatarUrl(authorPortrait);

    final threadMap = first['thread'] as Map? ?? {};
    final forumMap = data['forum'] as Map? ?? first['forum'] as Map? ?? {};
    final title = (first['title'] ?? threadMap['title'] ?? '').toString();
    final barName =
        (threadMap['fname'] ?? forumMap['name'] ?? forumMap['fname'] ?? '')
            .toString();
    final rawFid =
        forumMap['id'] ??
        forumMap['fid'] ??
        threadMap['fid'] ??
        threadMap['forum_id'];
    final fid = rawFid is int ? rawFid : int.tryParse(rawFid?.toString() ?? '');
    final replyNum = threadMap['reply_num'] ?? postList.length - 1;
    final firstTime = first['time'] is int ? first['time'] as int : 0;

    final rawContent = first['content'];
    final video =
        _extractVideoFromInfo(_asMap(first['video_info'])) ??
        _extractVideoFromInfo(_asMap(threadMap['video_info'])) ??
        _extractVideoFromContent(rawContent);
    var content = _extractFormContent(rawContent);
    if (video != null && !content.contains('![video')) {
      content = '$content${_videoMarkdown(video)}';
    }

    final comments = <TiebaComment>[];
    final startIndex = page == 1 ? 1 : 0;
    for (int i = startIndex; i < postList.length; i++) {
      final p = postList[i];
      if (p is! Map) continue;
      final cAuthor =
          (p['author'] as Map?)?['name']?.toString() ?? '用户${i + 1}';
      final cAuthorPortrait = (p['author'] as Map?)?['portrait']?.toString();
      final cAuthorAvatar = _buildAvatarUrl(cAuthorPortrait);
      final cContentRaw = _extractFormContent(p['content']);
      final cContent = cContentRaw.isNotEmpty
          ? cContentRaw
          : (p['content'] != null ? '[图片/表情]' : '');
      if (cContent.isEmpty) continue;
      final cTime = p['time'] is int ? p['time'] as int : 0;

      final subComments = <TiebaSubComment>[];
      final subPostListRaw = p['sub_post_list'];
      List<dynamic> subPostList = [];
      if (subPostListRaw is Map) {
        subPostList = subPostListRaw['sub_post_list'] as List? ?? [];
      } else if (subPostListRaw is List) {
        subPostList = subPostListRaw;
      }
      for (final sub in subPostList) {
        if (sub is! Map) continue;
        final subAuthor =
            (sub['author'] as Map?)?['name']?.toString() ??
            (sub['author'] as Map?)?['user_name']?.toString() ??
            '匿名';
        final subAuthorPortrait =
            (sub['author'] as Map?)?['portrait']?.toString() ??
            (sub['author'] as Map?)?['user_portrait']?.toString();
        final subAuthorAvatar = _buildAvatarUrl(subAuthorPortrait);
        final contentRaw = sub['content'] ?? sub['text'] ?? '';
        final subContent = _extractFormContent(contentRaw);
        if (subContent.isEmpty) continue;
        final subId = _postIdFrom(sub);
        if (subId == null || subId.isEmpty) continue;
        final subTime = sub['time'] is int ? sub['time'] as int : 0;
        final subLevel = _forumLevelFromUserMap(userLevels, sub);
        subComments.add(
          TiebaSubComment(
            id: subId,
            author: subAuthor,
            authorAvatar: subAuthorAvatar,
            content: subContent,
            createdAt: subTime > 0
                ? DateTime.fromMillisecondsSinceEpoch(subTime * 1000)
                : DateTime.now(),
            isLiked: _isAgreed(sub),
            likes: _agreeNumFrom(sub),
            forumLevel: subLevel?.level,
            forumLevelName: subLevel?.levelName,
          ),
        );
      }

      final floorFallback = page == 1
          ? i + 1
          : (page - 1) * detailCommentPageSize + i + 1;
      final postId = _postIdFrom(p);
      if (postId == null) continue;
      final commentLevel = _forumLevelFromUserMap(userLevels, p);
      comments.add(
        TiebaComment(
          id: postId,
          author: cAuthor,
          authorAvatar: cAuthorAvatar,
          content: cContent,
          createdAt: cTime > 0
              ? DateTime.fromMillisecondsSinceEpoch(cTime * 1000)
              : DateTime.now(),
          floor:
              (p['floor'] is int
                  ? p['floor'] as int
                  : int.tryParse(p['floor']?.toString() ?? '')) ??
              floorFallback,
          likes: _agreeNumFrom(p),
          isLiked: _isAgreed(p),
          subComments: subComments,
          subPostNumber: (p['sub_post_number'] ?? 0) is int
              ? p['sub_post_number'] ?? 0
              : 0,
          forumLevel: commentLevel?.level,
          forumLevelName: commentLevel?.levelName,
        ),
      );
    }

    final pageInfo = data['page'] as Map? ?? {};
    final hasMoreRaw = pageInfo['has_more'];
    final hasMore = hasMoreRaw == 1 || hasMoreRaw == true || hasMoreRaw == '1';
    final parsedReplyNum = replyNum is int
        ? replyNum
        : int.tryParse(replyNum?.toString() ?? '') ?? 0;
    final totalRaw = pageInfo['total_num'] ?? pageInfo['total_count'];
    final pageTotal = totalRaw is int
        ? totalRaw
        : int.tryParse(totalRaw?.toString() ?? '') ?? 0;
    // page.total_num 常为分页大小（如 30），优先用帖子的 reply_num
    final totalComments = parsedReplyNum > 0
        ? parsedReplyNum
        : (pageTotal > comments.length ? pageTotal : comments.length);

    final firstPostPid =
        _firstFloorPid(first, threadId: (threadMap['id'] ?? tid).toString()) ??
        '';

    return TiebaPostDetail(
      post: TiebaPost(
        id: tid,
        title: title,
        author: authorName,
        authorAvatar: authorAvatar,
        authorPortrait: authorPortrait,
        content: content,
        cover: _extractFirstImage(rawContent) ?? video?.coverSrc,
        video: video,
        barName: barName,
        fid: fid,
        replyCount: replyNum is int ? replyNum : 0,
        createdAt: firstTime > 0
            ? DateTime.fromMillisecondsSinceEpoch(firstTime * 1000)
            : DateTime.now(),
        likes: _resolveFirstPostAgreeNum(first, threadMap),
        isLiked: _isAgreed(first),
        isFavorited:
            _isStored(first['is_store']) ||
            _isStored(threadMap['is_store']) ||
            _isStored(forumMap['is_store']),
      ),
      comments: comments,
      hasMore: hasMore,
      totalComments: totalComments,
      firstPostPid: firstPostPid.isNotEmpty ? firstPostPid : null,
    );
  }

  static Future<List<TiebaSubComment>> fetchMoreSubComments(
    String tid,
    String pid, {
    String? bduss,
    String? stoken,
    int page = 1,
  }) async {
    try {
      final dataW = ProtobufWriter();
      dataW.writeInt64(1, int.parse(tid)); // kz
      dataW.writeInt64(2, int.parse(pid)); // pid
      dataW.writeInt32(4, page); // pn

      final outerW = ProtobufWriter();
      outerW.writeMessage(1, dataW.toBytes());
      final reqBytes = outerW.toBytes();

      final respBytes = await postProto(
        '/c/f/pb/floor',
        reqBytes,
        cmdId: '302002',
        bduss: bduss,
        stoken: stoken,
      );
      if (respBytes.length > 10) {
        return _parseFloorResp(respBytes);
      }
    } catch (e) {
      debugPrint('[TiebaAPI] fetchMoreSubComments error: $e');
    }
    return [];
  }

  static List<TiebaSubComment> _parseFloorResp(Uint8List data) {
    try {
      final reader = ProtobufReader(data);
      while (reader.hasMore) {
        final tag = reader.readTag();
        if (tag == null) break;
        final (fieldNumber, wireType) = tag;
        if (wireType == 2 && fieldNumber == 2) {
          final dataBytes = reader.readBytes();
          return _parseFloorDataRes(dataBytes);
        } else {
          reader.skipField(wireType);
        }
      }
    } catch (e) {
      debugPrint('[TiebaAPI] _parseFloorResp exception: $e');
    }
    return [];
  }

  static List<TiebaSubComment> _parseFloorDataRes(Uint8List data) {
    try {
      final reader = ProtobufReader(data);
      final allSubs = <TiebaSubComment>[];
      while (reader.hasMore) {
        final tag = reader.readTag();
        if (tag == null) break;
        final (fieldNumber, wireType) = tag;
        if (wireType == 2 && fieldNumber == 4) {
          final subBytes = reader.readBytes();
          final sub = _parseSubPostProto(subBytes);
          if (sub != null) allSubs.add(sub);
        } else {
          reader.skipField(wireType);
        }
      }
      return allSubs;
    } catch (e) {
      debugPrint('[TiebaAPI] _parseFloorDataRes exception: $e');
    }
    return [];
  }

  static TiebaSubComment? _parseSubPostProto(Uint8List data) {
    try {
      final reader = ProtobufReader(data);
      String id = '', author = '', content = '';
      String? portrait;
      int time = 0, agreeNum = 0;
      bool isAgreed = false;
      while (reader.hasMore) {
        final tag = reader.readTag();
        if (tag == null) break;
        final (fn, wt) = tag;
        switch (fn) {
          case 1:
            if (wt == 0) {
              id = reader.readVarint().toString();
            } else {
              reader.skipField(wt);
            }
            break;
          case 2:
            if (wt == 2) {
              final contentData = reader.readBytes();
              final elem = _parseContentElement(contentData);
              if (elem.isNotEmpty) {
                if (content.isNotEmpty) content += '\n';
                content += elem;
              }
            } else {
              reader.skipField(wt);
            }
            break;
          case 3:
            if (wt == 0) {
              time = reader.readVarint();
            } else {
              reader.skipField(wt);
            }
            break;
          case 5:
            reader.skipField(wt);
            break;
          case 9:
            if (wt == 2) {
              final agreeData = reader.readBytes();
              final aReader = ProtobufReader(agreeData);
              while (aReader.hasMore) {
                final aTag = aReader.readTag();
                if (aTag == null) break;
                final (afn, awt) = aTag;
                if (awt == 0) {
                  if (afn == 1) agreeNum = aReader.readVarint();
                  if (afn == 2) isAgreed = aReader.readVarint() == 1;
                } else {
                  aReader.skipField(awt);
                }
              }
            } else {
              reader.skipField(wt);
            }
            break;
          case 7:
            if (wt == 2) {
              final authorData = reader.readBytes();
              final aReader = ProtobufReader(authorData);
              while (aReader.hasMore) {
                final aTag = aReader.readTag();
                if (aTag == null) break;
                final (afn, awt) = aTag;
                if (awt == 2) {
                  try {
                    final bytes = aReader.readBytes();
                    final str = utf8.decode(bytes, allowMalformed: true);
                    if (afn == 3 && str.isNotEmpty) author = str;
                    if (afn == 4 && str.isNotEmpty && author.isEmpty)
                      author = str;
                    if (afn == 5 && str.isNotEmpty) portrait = str;
                  } catch (_) {}
                } else {
                  aReader.skipField(awt);
                }
              }
            } else {
              reader.skipField(wt);
            }
            break;
          default:
            reader.skipField(wt);
        }
      }
      if (content.isEmpty) return null;
      return TiebaSubComment(
        id: id,
        author: author.isNotEmpty ? author : '匿名',
        authorAvatar: _buildAvatarUrl(portrait),
        content: content,
        createdAt: time > 1000000000
            ? DateTime.fromMillisecondsSinceEpoch(time * 1000)
            : (time > 0
                  ? DateTime.fromMillisecondsSinceEpoch(time * 1000)
                  : DateTime.now()),
        likes: agreeNum,
        isLiked: isAgreed,
      );
    } catch (_) {}
    return null;
  }

  static String _parseContentElement(Uint8List data) {
    try {
      final reader = ProtobufReader(data);
      int type = 0;
      String text = '';
      String link = '';
      String coverSrc = '';
      int duration = 0;
      int width = 0;
      int height = 0;
      while (reader.hasMore) {
        final tag = reader.readTag();
        if (tag == null) break;
        final (fn, wt) = tag;
        if (fn == 1 && wt == 0) {
          type = reader.readVarint();
        } else if (fn == 2 && wt == 2) {
          try {
            final bytes = reader.readBytes();
            text = utf8.decode(bytes, allowMalformed: true);
          } catch (_) {}
        } else if (fn == 3 && wt == 2) {
          link = reader.readString();
        } else if (fn == 4 && wt == 2) {
          coverSrc = reader.readString();
        } else if (fn == 13 && wt == 0) {
          duration = reader.readVarint();
        } else if (fn == 18 && wt == 0) {
          width = reader.readVarint();
        } else if (fn == 19 && wt == 0) {
          height = reader.readVarint();
        } else {
          reader.skipField(wt);
        }
      }
      if (type == 2) {
        if (text.isEmpty) return '';
        final md = TiebaEmoticon.markdownFromContentFields(text: text);
        if (md != null) return md;
        return '[$text]';
      }
      if (type == 3) {
        if (text.isEmpty) return '';
        return '![image]($text)';
      }
      if (type == 5) {
        final playUrl = _resolveVideoUrl(
          link.isNotEmpty ? link : (text.isNotEmpty ? text : null),
        );
        if (playUrl != null) {
          return _videoMarkdown(
            TiebaVideo(
              src: playUrl,
              coverSrc: _resolveImageUrl(coverSrc.isNotEmpty ? coverSrc : null),
              duration: _videoDurationFrom(duration),
              width: width,
              height: height,
            ),
          );
        }
        return '';
      }
      if (text.isEmpty) return '';
      return text;
    } catch (_) {}
    return '';
  }

  // ignore: unused_element
  static TiebaSubComment? _parseFloorItemProto(Uint8List data) {
    final reader = ProtobufReader(data);
    String id = '', author = '', content = '';
    String? portrait;
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fn, wt) = tag;
      switch (fn) {
        case 1:
          id = reader.readVarint().toString();
          break;
        case 3:
          if (wt == 2) {
            final nameData = reader.readBytes();
            final nameReader = ProtobufReader(nameData);
            while (nameReader.hasMore) {
              final nTag = nameReader.readTag();
              if (nTag == null) break;
              final (nfn, nwt) = nTag;
              if (nwt == 2) {
                try {
                  final str = _decodeProtoUtf8(nameReader.readBytes());
                  if (nfn == 1) author = str;
                  if (nfn == 9) portrait = str;
                } catch (_) {
                  nameReader.skipField(nwt);
                }
              } else {
                nameReader.skipField(nwt);
              }
            }
          } else {
            reader.skipField(wt);
          }
          break;
        case 4:
          if (wt == 2) {
            final contentData = reader.readBytes();
            content = _parseProtoContent(contentData);
          } else {
            reader.skipField(wt);
          }
          break;
        default:
          reader.skipField(wt);
      }
    }
    if (id.isEmpty || content.isEmpty) return null;
    return TiebaSubComment(
      id: id,
      author: author.isNotEmpty ? author : '匿名',
      authorAvatar: _buildAvatarUrl(portrait),
      content: content,
      createdAt: DateTime.now(),
    );
  }

  static String _parseProtoContent(Uint8List data) {
    final reader = ProtobufReader(data);
    final parts = <String>[];
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fn, wt) = tag;
      if (wt == 2) {
        try {
          final str = _decodeProtoUtf8(reader.readBytes());
          if (fn == 1 && str.isNotEmpty) parts.add(str);
        } catch (_) {
          reader.skipField(wt);
        }
      } else {
        reader.skipField(wt);
      }
    }
    return parts.join('');
  }

  static String _formatEmojiContentItem(Map c) {
    final text = c['text']?.toString() ?? '';
    final name = c['c']?.toString() ?? '';
    final directUrl = c['url'] ?? c['src'] ?? c['cdn_src'];
    final md = TiebaEmoticon.markdownFromContentFields(
      text: text,
      name: name,
      url: directUrl?.toString(),
    );
    if (md != null) return md;
    if (name.isNotEmpty) return '[$name]';
    return '';
  }

  static String _extractFormContent(dynamic content) {
    if (content == null) return '';
    if (content is String) {
      return TiebaEmoticon.replaceBracketEmoticons(content);
    }
    if (content is Map) {
      final text =
          content['text']?.toString() ?? content['content']?.toString() ?? '';
      if (text.isNotEmpty) {
        return TiebaEmoticon.replaceBracketEmoticons(text);
      }
      return '';
    }
    if (content is List) {
      final joined = content
          .whereType<Map>()
          .map((c) {
            final type = c['type'];
            if (type == 2) {
              return _formatEmojiContentItem(c);
            }
            if (type == 3) {
              final keys = DataSaverService.instance.enabled
                  ? ['cdn_src', 'src', 'origin_src', 'big_cdn_src', 'big_src']
                  : ['big_cdn_src', 'origin_src', 'src', 'cdn_src'];
              String? imgUrl;
              for (final key in keys) {
                final raw = c[key];
                if (raw != null && raw.toString().isNotEmpty) {
                  imgUrl = raw.toString();
                  break;
                }
              }
              if (imgUrl != null) {
                final resolved = _resolveImageUrl(imgUrl) ?? imgUrl;
                return '\n![图片]($resolved)\n';
              }
              final emoticon = c['c']?.toString() ?? '';
              if (emoticon.isNotEmpty) {
                final md = TiebaEmoticon.markdownFromContentFields(
                  name: emoticon,
                );
                if (md != null) return md;
                return '[$emoticon]';
              }
              return '';
            }
            if (type == 5 || type == '5') {
              final video = _extractVideoFromContentItem(c);
              if (video != null) return _videoMarkdown(video);
              return '';
            }
            return (c['text'] ?? '').toString();
          })
          .where((t) => t.isNotEmpty)
          .join('');
      return TiebaEmoticon.replaceBracketEmoticons(joined);
    }
    return TiebaEmoticon.replaceBracketEmoticons(content.toString());
  }

  static Future<Map<String, dynamic>> getMo(
    String path, {
    Map<String, String> query = const {},
    String? bduss,
  }) async {
    final headers = Map<String, String>.from(_webHeaders);
    if (bduss != null && bduss.isNotEmpty) {
      headers['Cookie'] = _authCookie(bduss, null);
    }
    final uri = Uri.parse('$_webBaseUrl$path').replace(queryParameters: query);
    final resp = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return {'error_code': resp.statusCode};
    try {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return {'error_code': resp.statusCode};
    }
  }

  static List<TiebaPost> _postsFromSearchPayload(Map<String, dynamic> data) {
    final userLevels = _forumLevelMapFromUserList(
      data['user_list'] ?? _asMap(data['data'])?['user_list'],
    );
    final items = _extractThreadItemMaps(data);
    if (items.isNotEmpty) {
      return items
          .map((item) {
            final tid = (item['id'] ?? item['tid'] ?? '').toString();
            final title = (item['title'] ?? '').toString();
            final user = _asMap(item['user']);
            final authorMap = _asMap(item['author']) ?? {};
            final author =
                user?['show_nickname']?.toString() ??
                user?['user_name']?.toString() ??
                authorMap['name']?.toString() ??
                authorMap['show_nickname']?.toString() ??
                '匿名';
            final levelFields = _authorForumLevelFields(item, userLevels);
            return TiebaPost(
              id: tid,
              title: title.isNotEmpty ? title : '无标题',
              author: author,
              authorAvatar: _buildAvatarUrl(
                user?['portrait']?.toString() ??
                    authorMap['portrait']?.toString(),
              ),
              content: '',
              barName: (item['fname'] ?? item['forum_name'] ?? '').toString(),
              replyCount: _intFrom(item['post_num'] ?? item['reply_num']),
              createdAt: DateTime.now(),
              likes: _intFrom(item['like_num'] ?? item['agree_num']),
              authorForumLevel: levelFields.authorForumLevel,
              authorForumLevelName: levelFields.authorForumLevelName,
            );
          })
          .where((p) => p.id.isNotEmpty)
          .toList();
    }

    final dataNode = _asMap(data['data']);
    final list =
        _asList(data['thread_list']) ??
        _asList(dataNode?['thread_list']) ??
        _asList(data['post_list']) ??
        _asList(dataNode?['post_list']) ??
        [];
    final posts = <TiebaPost>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final tid = (item['tid'] ?? item['id'] ?? '').toString();
      if (tid.isEmpty) continue;
      final user = _asMap(item['user']);
      final authorMap = _asMap(item['author']);
      final author =
          user?['show_nickname']?.toString() ??
          user?['user_name']?.toString() ??
          authorMap?['name']?.toString() ??
          item['author_name']?.toString() ??
          (item['author'] is String ? item['author'].toString() : '匿名');
      final levelFields = _authorForumLevelFields(item, userLevels);
      posts.add(
        TiebaPost(
          id: tid,
          title: (item['title'] ?? item['abstract'] ?? '无标题').toString(),
          author: author,
          authorAvatar: _buildAvatarUrl(user?['portrait']?.toString()),
          content: '',
          barName: (item['fname'] ?? item['forum_name'] ?? '').toString(),
          replyCount: _intFrom(item['post_num'] ?? item['reply_num']),
          createdAt: DateTime.now(),
          likes: _intFrom(item['like_num'] ?? item['agree_num']),
          authorForumLevel: levelFields.authorForumLevel,
          authorForumLevelName: levelFields.authorForumLevelName,
        ),
      );
    }
    return posts;
  }

  static int _intFrom(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, dynamic>? _normalizeForumSearchItem(dynamic raw) {
    if (raw is! Map) return null;
    var map = Map<String, dynamic>.from(raw);
    final cardData = _asMap(map['card_data']);
    if (cardData != null) {
      map = Map<String, dynamic>.from(cardData);
    }
    final name =
        (map['forum_name'] ?? map['name'] ?? map['forum_name_show'] ?? '')
            .toString()
            .trim();
    if (name.isEmpty) return null;
    return {
      'name': name,
      'member_count':
          map['concern_num_ori'] ??
          map['concern_num'] ??
          map['member_num'] ??
          map['member_count'],
      'post_count': map['post_num_ori'] ?? map['post_num'] ?? map['thread_num'],
      'slogan': (map['slogan'] ?? map['intro'] ?? '').toString(),
      'avatar': map['avatar']?.toString(),
    };
  }

  static List<Map<String, dynamic>> _forumsFromSearchPayload(
    Map<String, dynamic> data,
  ) {
    final dataNode = _asMap(data['data']);
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addRaw(dynamic raw) {
      final normalized = _normalizeForumSearchItem(raw);
      if (normalized == null) return;
      final name = normalized['name'] as String;
      if (!seen.add(name)) return;
      out.add(normalized);
    }

    for (final raw
        in _asList(data['forum_list']) ??
            _asList(dataNode?['forum_list']) ??
            const []) {
      addRaw(raw);
    }

    if (dataNode != null) {
      addRaw(dataNode['exactMatch']);
      for (final raw in _asList(dataNode['fuzzyMatch']) ?? const []) {
        addRaw(raw);
      }
      for (final card in _asList(dataNode['confCard']) ?? const []) {
        addRaw(card);
      }
    }

    return out;
  }

  /// 搜索帖子（全局或吧内），对应 TiebaLite `/mo/q/search/thread`。
  static Future<List<TiebaPost>> searchThreads({
    required String query,
    String? barName,
    int page = 1,
    String? bduss,
  }) async {
    if (query.trim().isEmpty) return [];
    try {
      final moQuery = <String, String>{
        'word': query.trim(),
        'rn': '20',
        'pn': page.toString(),
        'sm': '1',
        'only_thread': '0',
      };
      if (barName != null && barName.trim().isNotEmpty) {
        moQuery['kw'] = barName.trim();
      }
      final mo = await getMo(
        '/mo/q/search/thread',
        query: moQuery,
        bduss: bduss,
      );
      final moPosts = _postsFromSearchPayload(mo);
      if (moPosts.isNotEmpty) return moPosts;

      if (barName != null && barName.trim().isNotEmpty) {
        final result = await postForm(
          '/c/s/searchpost',
          params: [
            MapEntry('word', query.trim()),
            MapEntry('kw', barName.trim()),
            MapEntry('pn', page.toString()),
            MapEntry('only_thread', '0'),
            MapEntry('sm', '1'),
          ],
          bduss: bduss,
        );
        if (result['error_code'] == 0 || result['error_code'] == '0') {
          return _postsFromSearchPayload(result);
        }
      }
    } catch (_) {}
    return [];
  }

  /// 搜索贴吧，对应 TiebaLite `/mo/q/search/forum`。
  static Future<List<Map<String, dynamic>>> searchForums({
    required String query,
    int page = 1,
    String? bduss,
  }) async {
    if (query.trim().isEmpty) return [];
    try {
      final result = await getMo(
        '/mo/q/search/forum',
        query: {'word': query.trim(), 'rn': '20', 'pn': page.toString()},
        bduss: bduss,
      );
      return _forumsFromSearchPayload(result);
    } catch (_) {
      return [];
    }
  }

  /// 吧详情，对应 aiotieba `get_forum` / TiebaLite `frsBottom`。
  static Future<Map<String, dynamic>?> fetchForumDetail(
    String barName, {
    String? bduss,
  }) async {
    if (barName.trim().isEmpty) return null;
    try {
      final result = await postForm(
        '/c/f/frs/frsBottom',
        params: [MapEntry('kw', barName.trim())],
        bduss: bduss,
      );
      if (result['error_code'] != 0 && result['error_code'] != '0') return null;
      final forum = _asMap(result['forum']);
      if (forum == null) return null;
      return {
        'name': (forum['name'] ?? barName).toString(),
        'fid': forum['id'] ?? forum['fid'],
        'member_count': forum['member_num'] ?? forum['member_count'],
        'post_count': forum['post_num'] ?? forum['thread_num'],
        'slogan': forum['slogan']?.toString() ?? '',
        'avatar': forum['avatar']?.toString(),
      };
    } catch (_) {
      return null;
    }
  }

  /// 当前登录用户信息，对应 aiotieba `get_self_info`。
  static Future<Map<String, dynamic>?> fetchSelfProfile({
    required String bduss,
  }) {
    return fetchUserProfile(bduss: bduss);
  }

  static Future<Map<String, dynamic>> _getWebJson(
    String path, {
    required List<MapEntry<String, String>> params,
    String? bduss,
    String? stoken,
  }) async {
    final uri = Uri.parse(
      '$_webBaseUrl$path',
    ).replace(queryParameters: {for (final e in params) e.key: e.value});
    final headers = Map<String, String>.from(_webHeaders);
    if (bduss != null && bduss.isNotEmpty) {
      headers['Cookie'] = _authCookie(bduss, stoken);
    }
    final resp = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return {'error_code': resp.statusCode};
    try {
      final body = jsonDecode(resp.body);
      if (body is Map<String, dynamic>) return body;
      if (body is Map) return Map<String, dynamic>.from(body);
      return {'error_code': -1};
    } catch (_) {
      return {'error_code': resp.statusCode, 'raw': resp.body};
    }
  }

  static String _normalizePortrait(String portrait) {
    final trimmed = portrait.trim();
    if (trimmed.isEmpty) return trimmed;
    final queryIndex = trimmed.indexOf('?');
    return queryIndex >= 0 ? trimmed.substring(0, queryIndex) : trimmed;
  }

  static int _parseTbCount(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value.toString().trim();
    if (text.isEmpty || text == '-') return 0;
    if (text.endsWith('万')) {
      final numPart = double.tryParse(text.replaceAll('万', ''));
      return numPart == null ? 0 : (numPart * 10000).round();
    }
    return int.tryParse(text) ?? 0;
  }

  /// Web 用户资料面板，对应 aiotieba `get_uinfo_panel`（`/home/get/panel`）。
  static Future<Map<String, dynamic>?> _fetchUserPanel({
    String? portrait,
    String? userName,
    String? bduss,
  }) async {
    final params = <MapEntry<String, String>>[];
    if (portrait != null && portrait.trim().isNotEmpty) {
      params.add(MapEntry('id', _normalizePortrait(portrait)));
    } else if (userName != null && userName.trim().isNotEmpty) {
      params.add(MapEntry('un', userName.trim()));
    } else {
      return null;
    }
    final result = await _getWebJson(
      '/home/get/panel',
      params: params,
      bduss: bduss,
    );
    return _parseUserPanelMap(result);
  }

  /// 通过用户名反查 portrait，对应 aiotieba `get_uinfo_user_json`。
  static Future<Map<String, dynamic>?> _fetchUserJsonByName(
    String userName,
  ) async {
    final result = await _getWebJson(
      '/i/sys/user_json',
      params: [MapEntry('un', userName.trim()), MapEntry('ie', 'utf-8')],
    );
    final creator = _asMap(result['creator']);
    if (creator == null) return null;
    final portrait = _normalizePortrait(
      creator['portrait']?.toString() ??
          creator['itieba_portrait']?.toString() ??
          '',
    );
    final userNameResolved =
        creator['name']?.toString() ??
        creator['user_name']?.toString() ??
        userName;
    if (portrait.isEmpty && userNameResolved.isEmpty) return null;
    return {
      'user_id': creator['id'] ?? creator['user_id'],
      'user_name': userNameResolved,
      'nick_name':
          creator['show_nickname'] ?? creator['name_show'] ?? userNameResolved,
      'portrait': portrait,
    };
  }

  static Map<String, dynamic>? _parseUserPanelMap(Map<String, dynamic> result) {
    final no = result['no']?.toString() ?? '';
    if (no.isNotEmpty && no != '0') return null;
    final data = _asMap(result['data']);
    if (data == null) return null;

    final portrait = _normalizePortrait(data['portrait']?.toString() ?? '');
    final userName = data['name']?.toString() ?? '';
    if (portrait.isEmpty && userName.isEmpty) return null;

    final vipInfo = _asMap(data['vipInfo']);
    final isVip = vipInfo != null && vipInfo['v_status']?.toString() == '3';
    final tbAgeRaw = data['tb_age']?.toString() ?? '';
    final forumAge = tbAgeRaw.isEmpty || tbAgeRaw == '-'
        ? null
        : double.tryParse(tbAgeRaw);

    return {
      'user_id': data['id'] ?? data['user_id'],
      'user_name': userName,
      'nick_name': data['show_nickname'] ?? data['name_show'] ?? userName,
      'portrait': portrait,
      'post_num': _parseTbCount(data['post_num']),
      'fans_num': _parseTbCount(data['followed_count']),
      'follow_num': _parseTbCount(data['follow_num'] ?? data['follow_count']),
      'intro': data['intro']?.toString(),
      'forum_age': forumAge,
      'is_vip': isVip,
    };
  }

  /// 账号成长等级（glevel），对应 `/c/u/user/profile` protobuf。
  static Future<int?> fetchUserGrowthLevel({
    String? portrait,
    String? userId,
    String? bduss,
    String? stoken,
  }) async {
    final normalizedPortrait = portrait != null && portrait.trim().isNotEmpty
        ? _normalizePortrait(portrait)
        : '';
    final parsedUid = int.tryParse(userId?.trim() ?? '');
    if (normalizedPortrait.isEmpty && parsedUid == null) return null;
    try {
      final req = _buildProfileReq(
        userId: parsedUid,
        portrait: parsedUid == null ? normalizedPortrait : null,
        bduss: bduss,
        stoken: stoken,
      );
      final bytes = await postProto(
        '/c/u/user/profile',
        req,
        cmdId: '303012',
        bduss: bduss,
        stoken: stoken,
      );
      final map = _parseProfileProtoToMap(bytes);
      if (map != null) {
        final level = map['growth_level'];
        if (level is int && level > 0) return level;
      }
      return _parseProfileGrowthLevel(bytes);
    } catch (e) {
      debugPrint('[TiebaAPI] fetchUserGrowthLevel error: $e');
      return null;
    }
  }

  /// 用户在指定吧内的等级，对应 `/c/f/forum/getUserForumLevelInfo`。
  static Future<Map<String, dynamic>?> fetchUserForumLevel({
    required String barName,
    required String portrait,
    String? bduss,
    String? stoken,
  }) async {
    final name = barName.trim();
    final normalized = _normalizePortrait(portrait);
    if (name.isEmpty || normalized.isEmpty) return null;
    try {
      final fid = await getForumId(name);
      if (fid == null) return null;
      final result = await postForm(
        '/c/f/forum/getUserForumLevelInfo',
        params: [
          MapEntry('forum_id', fid.toString()),
          MapEntry('friend_portrait', normalized),
        ],
        bduss: bduss,
        stoken: stoken,
      );
      if (!_isApiSuccess(result)) return null;
      final data = _asMap(result['data']);
      if (data == null) return null;
      final userForum = _asMap(data['user_forum_info']);
      if (userForum == null) return null;
      final forum = _asMap(data['forum_info']);
      final level = int.tryParse(userForum['level_id']?.toString() ?? '') ?? 0;
      final levelName = userForum['level_name']?.toString().trim() ?? '';
      final isFollow = _isTruthy(userForum['is_follow']);
      final daySignNo =
          int.tryParse(userForum['day_sign_no']?.toString() ?? '') ?? 0;
      final signedToday = _isTruthy(userForum['is_sign']) || daySignNo > 0;
      if (level <= 0 && levelName.isEmpty && !isFollow && !signedToday) {
        return null;
      }
      return {
        'bar_name': forum?['forum_name']?.toString() ?? name,
        'forum_level': level,
        'forum_level_name': levelName,
        'exp': userForum['cur_score'],
        'levelup_exp': userForum['levelup_score'],
        'is_follow': isFollow,
        'signed_today': signedToday,
      };
    } catch (e) {
      debugPrint('[TiebaAPI] fetchUserForumLevel error: $e');
      return null;
    }
  }

  static Uint8List _buildProfileReq({
    int? userId,
    String? portrait,
    String? bduss,
    String? stoken,
  }) {
    final commonBytes = _buildCommonReq(bduss: bduss, stoken: stoken);
    final dataW = ProtobufWriter();
    if (userId != null) {
      dataW.writeInt64(1, userId);
    }
    dataW.writeInt32(2, 1);
    dataW.writeMessage(9, commonBytes);
    dataW.writeInt32(15, 1);
    if (portrait != null && portrait.isNotEmpty) {
      dataW.writeString(16, portrait);
    }
    final outerW = ProtobufWriter();
    outerW.writeMessage(1, dataW.toBytes());
    return outerW.toBytes();
  }

  static int? _parseProfileGrowthLevel(Uint8List data) {
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (field == 2 && wire == 2) {
        final level = _parseProfileDataGrowth(reader.readBytes());
        if (level != null) return level;
      } else {
        reader.skipField(wire);
      }
    }
    return null;
  }

  static int? _parseProfileDataGrowth(Uint8List data) {
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (field == 1 && wire == 2) {
        final level = _parseUserGrowthFromUser(reader.readBytes());
        if (level != null) return level;
      } else {
        reader.skipField(wire);
      }
    }
    return null;
  }

  static int? _parseUserGrowthFromUser(Uint8List data) {
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (field == 137 && wire == 2) {
        return _parseUserGrowthLevelId(reader.readBytes());
      } else {
        reader.skipField(wire);
      }
    }
    return null;
  }

  static int? _parseUserGrowthLevelId(Uint8List data) {
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (field == 1 && wire == 0) {
        return reader.readVarint();
      } else {
        reader.skipField(wire);
      }
    }
    return null;
  }

  /// 当前登录账号是否已关注该用户（需 BDUSS；对应 User.is_friend）。
  static Future<bool?> fetchUserIsFollowedByMe({
    required String portrait,
    String? userId,
    String? bduss,
    String? stoken,
  }) async {
    if (bduss == null || bduss.isEmpty) return null;
    final normalizedPortrait = portrait.trim().isNotEmpty
        ? _normalizePortrait(portrait)
        : '';
    final parsedUid = int.tryParse(userId?.trim() ?? '');
    if (normalizedPortrait.isEmpty && parsedUid == null) return null;
    try {
      final req = _buildProfileReq(
        userId: parsedUid,
        portrait: parsedUid == null ? normalizedPortrait : null,
        bduss: bduss,
        stoken: stoken,
      );
      final bytes = await postProto(
        '/c/u/user/profile',
        req,
        cmdId: '303012',
        bduss: bduss,
        stoken: stoken,
      );
      return _parseProfileIsFriend(bytes);
    } catch (e) {
      debugPrint('[TiebaAPI] fetchUserIsFollowedByMe error: $e');
      return null;
    }
  }

  static bool? _parseProfileIsFriend(Uint8List data) {
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (field == 2 && wire == 2) {
        return _parseProfileDataIsFriend(reader.readBytes());
      } else {
        reader.skipField(wire);
      }
    }
    return null;
  }

  static bool? _parseProfileDataIsFriend(Uint8List data) {
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (field == 1 && wire == 2) {
        return _parseUserIsFriendFromUser(reader.readBytes());
      } else {
        reader.skipField(wire);
      }
    }
    return null;
  }

  static bool? _parseUserIsFriendFromUser(Uint8List data) {
    final reader = ProtobufReader(data);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (field == 46 && wire == 0) {
        return reader.readVarint() > 0;
      } else {
        reader.skipField(wire);
      }
    }
    return null;
  }

  /// Lite / aiotieba 同款：`/c/u/user/profile` protobuf 资料（含 uid、glevel）。
  static Future<Map<String, dynamic>?> _fetchUserProfileProto({
    int? userId,
    String? portrait,
    String? bduss,
    String? stoken,
  }) async {
    final normalizedPortrait = portrait != null && portrait.trim().isNotEmpty
        ? _normalizePortrait(portrait)
        : '';
    if ((userId == null || userId <= 0) && normalizedPortrait.isEmpty) {
      return null;
    }
    try {
      final req = _buildProfileReq(
        userId: userId != null && userId > 0 ? userId : null,
        portrait: userId != null && userId > 0 ? null : normalizedPortrait,
        bduss: bduss,
        stoken: stoken,
      );
      final bytes = await postProto(
        '/c/u/user/profile',
        req,
        cmdId: '303012',
        bduss: bduss,
        stoken: stoken,
      );
      return _parseProfileProtoToMap(bytes);
    } catch (e) {
      debugPrint('[TiebaAPI] _fetchUserProfileProto error: $e');
      return null;
    }
  }

  static Map<String, dynamic>? _parseProfileProtoToMap(Uint8List bytes) {
    if (bytes.isEmpty) return null;

    final reader = ProtobufReader(bytes);
    Uint8List? dataBytes;
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (field == 1 && wire == 2) {
        final errno = _parseProtoErrorNo(reader.readBytes());
        if (errno != null && errno != 0) return null;
      } else if (field == 2 && wire == 2) {
        dataBytes = reader.readBytes();
      } else {
        reader.skipField(wire);
      }
    }
    if (dataBytes == null) return null;

    final dataReader = ProtobufReader(dataBytes);
    while (dataReader.hasMore) {
      final tag = dataReader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (field == 1 && wire == 2) {
        return _parseUserProtoToMap(dataReader.readBytes());
      }
      dataReader.skipField(wire);
    }
    return null;
  }

  static Map<String, dynamic>? _parseUserProtoToMap(Uint8List bytes) {
    if (bytes.isEmpty) return null;

    final out = <String, dynamic>{};
    final reader = ProtobufReader(bytes);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      switch (field) {
        case 2 when wire == 0:
          final id = reader.readVarint();
          if (id > 0) out['user_id'] = id.toString();
        case 3 when wire == 2:
          out['user_name'] = reader.readString();
        case 4 when wire == 2:
          out['nick_name'] = reader.readString();
        case 5 when wire == 2:
          out['portrait'] = _normalizePortrait(reader.readString());
        case 30 when wire == 0:
          out['fans_num'] = reader.readVarint();
        case 31 when wire == 0:
          out['follow_num'] = reader.readVarint();
        case 34 when wire == 2:
          out['intro'] = reader.readString();
        case 37 when wire == 0:
          out['post_num'] = reader.readVarint();
        case 38 when wire == 2:
          final age = reader.readString();
          if (age.isNotEmpty && age != '-') {
            out['forum_age'] = double.tryParse(age);
          }
        case 137 when wire == 0:
          final growth = reader.readVarint();
          if (growth > 0) out['growth_level'] = growth;
        case 137 when wire == 2:
          final growth = _parseUserGrowthLevelId(reader.readBytes());
          if (growth != null && growth > 0) {
            out['growth_level'] = growth;
          }
        default:
          reader.skipField(wire);
      }
    }

    final hasId = out['user_id']?.toString().isNotEmpty ?? false;
    final hasPortrait = out['portrait']?.toString().isNotEmpty ?? false;
    final hasName = out['user_name']?.toString().isNotEmpty ?? false;
    if (!hasId && !hasPortrait && !hasName) return null;
    return out;
  }

  static Map<String, dynamic> _mergeUserProfileMaps(
    Map<String, dynamic> primary,
    Map<String, dynamic> secondary,
  ) {
    final merged = Map<String, dynamic>.from(secondary);
    for (final entry in primary.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      if (value is num &&
          value == 0 &&
          (entry.key == 'post_num' ||
              entry.key == 'fans_num' ||
              entry.key == 'follow_num')) {
        continue;
      }
      merged[entry.key] = value;
    }
    return merged;
  }

  /// 任意用户资料：portrait / uid / user_name 三选一（Lite 用户主页）。
  static Future<Map<String, dynamic>?> fetchUserProfile({
    String? bduss,
    String? stoken,
    String? portrait,
    String? userId,
    String? userName,
  }) async {
    try {
      var resolvedPortrait = portrait != null && portrait.trim().isNotEmpty
          ? _normalizePortrait(portrait)
          : null;
      var resolvedUserName = userName != null && userName.trim().isNotEmpty
          ? userName.trim()
          : null;
      var resolvedUid = int.tryParse(userId?.trim() ?? '');

      if (resolvedUserName != null) {
        final jsonUser = await _fetchUserJsonByName(resolvedUserName);
        if (jsonUser != null) {
          resolvedPortrait ??= _normalizePortrait(
            jsonUser['portrait']?.toString() ?? '',
          );
          if (resolvedUid == null || resolvedUid <= 0) {
            resolvedUid = int.tryParse(jsonUser['user_id']?.toString() ?? '');
          }
        }
      }

      Map<String, dynamic>? proto;
      if (resolvedUid != null && resolvedUid > 0) {
        proto = await _fetchUserProfileProto(
          userId: resolvedUid,
          bduss: bduss,
          stoken: stoken,
        );
      } else if (resolvedPortrait != null && resolvedPortrait.isNotEmpty) {
        proto = await _fetchUserProfileProto(
          portrait: resolvedPortrait,
          bduss: bduss,
          stoken: stoken,
        );
        final protoUid = int.tryParse(proto?['user_id']?.toString() ?? '');
        if (protoUid != null && protoUid > 0) {
          resolvedUid = protoUid;
        }
      }

      Map<String, dynamic>? panel;
      if (resolvedPortrait != null && resolvedPortrait.isNotEmpty) {
        panel = await _fetchUserPanel(portrait: resolvedPortrait, bduss: bduss);
      } else if (resolvedUserName != null) {
        panel = await _fetchUserPanel(userName: resolvedUserName, bduss: bduss);
        resolvedPortrait ??= _normalizePortrait(
          panel?['portrait']?.toString() ?? '',
        );
      } else if (resolvedUid != null && resolvedUid > 0) {
        panel = await _fetchUserPanel(
          userName: resolvedUid.toString(),
          bduss: bduss,
        );
      }

      if (proto != null && panel != null) {
        return _mergeUserProfileMaps(proto, panel);
      }
      if (proto != null) return proto;
      if (panel != null) {
        if ((resolvedUid == null || resolvedUid <= 0) &&
            resolvedPortrait != null &&
            resolvedPortrait.isNotEmpty) {
          final retry = await _fetchUserProfileProto(
            portrait: resolvedPortrait,
            bduss: bduss,
            stoken: stoken,
          );
          if (retry != null) return _mergeUserProfileMaps(retry, panel);
        }
        return panel;
      }

      if (resolvedUserName != null) {
        final jsonUser = await _fetchUserJsonByName(resolvedUserName);
        if (jsonUser != null) return jsonUser;
      }

      if (bduss != null &&
          bduss.isNotEmpty &&
          resolvedPortrait == null &&
          resolvedUserName == null &&
          (userId == null || userId.trim().isEmpty)) {
        final login = await getTbs(bduss);
        final user = _asMap(login['user']);
        if (user != null) {
          final selfPortrait = _normalizePortrait(
            user['portrait']?.toString() ?? '',
          );
          final selfUid = int.tryParse(
            (user['id'] ?? user['user_id'])?.toString() ?? '',
          );
          final selfProto = await _fetchUserProfileProto(
            userId: selfUid != null && selfUid > 0 ? selfUid : null,
            portrait: selfPortrait.isNotEmpty ? selfPortrait : null,
            bduss: bduss,
            stoken: stoken,
          );
          if (selfProto != null) {
            if (selfPortrait.isNotEmpty) {
              final selfPanel = await _fetchUserPanel(
                portrait: selfPortrait,
                bduss: bduss,
              );
              if (selfPanel != null) {
                return _mergeUserProfileMaps(selfProto, selfPanel);
              }
            }
            return selfProto;
          }
          if (selfPortrait.isNotEmpty) {
            final selfPanel = await _fetchUserPanel(
              portrait: selfPortrait,
              bduss: bduss,
            );
            if (selfPanel != null) return selfPanel;
          }
          return {
            'user_id': user['id'] ?? user['user_id'],
            'user_name': user['name'] ?? user['user_name'],
            'nick_name': user['name_show'] ?? user['nick_name'],
            'portrait': selfPortrait,
            'post_num': user['post_num'],
            'fans_num': user['fans_num'],
            'follow_num': user['follow_num'],
          };
        }
      }
      return null;
    } catch (e) {
      debugPrint('[TiebaAPI] fetchUserProfile error: $e');
      return null;
    }
  }

  static String? portraitFromAvatarUrl(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) return null;
    const prefixes = [
      'https://himg.bdimg.com/sys/portrait/item/',
      'http://himg.bdimg.com/sys/portrait/item/',
      'https://tb.himg.baidu.com/sys/portraith/item/',
      'http://tb.himg.baidu.com/sys/portraith/item/',
      'https://tb.himg.baidu.com/sys/portrait/item/',
      'http://tb.himg.baidu.com/sys/portrait/item/',
    ];
    for (final prefix in prefixes) {
      if (avatarUrl.startsWith(prefix)) {
        return _normalizePortrait(avatarUrl.substring(prefix.length));
      }
    }
    if (avatarUrl.startsWith('tb.')) {
      return _normalizePortrait(avatarUrl);
    }
    return null;
  }

  /// 用户主题帖/回帖，对应 aiotieba `get_user_threads` / `get_user_posts`。
  static Future<List<TiebaPost>> fetchUserPosts({
    String? portrait,
    String? userId,
    String? userName,
    int page = 1,
    bool threadsOnly = true,
    String? bduss,
    String? stoken,
  }) async {
    try {
      final normalizedPortrait = portrait != null && portrait.trim().isNotEmpty
          ? _normalizePortrait(portrait)
          : '';
      final normalizedUserName = userName?.trim() ?? '';

      final uid = await _resolveFeedUserId(
        userId: userId,
        portrait: normalizedPortrait.isNotEmpty ? normalizedPortrait : null,
        userName: normalizedUserName.isNotEmpty ? normalizedUserName : null,
        bduss: bduss,
        stoken: stoken,
      );

      if (uid != null && uid > 0) {
        final req = _buildUserPostReq(
          uid: uid,
          pn: page,
          rn: 20,
          threadsOnly: threadsOnly,
          bduss: bduss,
          stoken: stoken,
        );
        final bytes = await postProto(
          '/c/u/feed/userpost',
          req,
          cmdId: '303002',
          bduss: bduss,
          stoken: stoken,
        );
        final posts = _parseUserPostProtoResponse(
          bytes,
          threadsOnly: threadsOnly,
        );
        if (posts.isNotEmpty) return posts;
      }

      if (normalizedPortrait.isNotEmpty) {
        final pcPosts = await _fetchUserFeedViaPcWeb(
          portrait: normalizedPortrait,
          userName: normalizedUserName,
          page: page,
          threadsOnly: threadsOnly,
          bduss: bduss,
          stoken: stoken,
        );
        if (pcPosts.isNotEmpty) return pcPosts;
      }

      return const [];
    } catch (e) {
      debugPrint('[TiebaAPI] fetchUserPosts error: $e');
      return const [];
    }
  }

  /// 用户关注的贴吧列表（`/c/f/forum/like` + PC 兜底）。
  static Future<({List<UserFollowedForum> items, bool hasMore})>
  fetchUserFollowForums({
    int userId = 0,
    String? portrait,
    String? userName,
    int page = 1,
    int pageSize = 30,
    String? bduss,
    String? stoken,
  }) async {
    try {
      var uid = userId;
      var normalizedPortrait = portrait != null && portrait.trim().isNotEmpty
          ? _normalizePortrait(portrait)
          : '';
      final normalizedUserName = userName?.trim() ?? '';

      if (uid <= 0 || normalizedPortrait.isEmpty) {
        final profile = await fetchUserProfile(
          bduss: bduss,
          stoken: stoken,
          portrait: normalizedPortrait.isNotEmpty ? normalizedPortrait : null,
          userName: normalizedUserName.isNotEmpty ? normalizedUserName : null,
          userId: uid > 0 ? uid.toString() : null,
        );
        if (profile != null) {
          if (uid <= 0) {
            uid = int.tryParse(profile['user_id']?.toString() ?? '') ?? 0;
          }
          if (normalizedPortrait.isEmpty) {
            normalizedPortrait = _normalizePortrait(
              profile['portrait']?.toString() ?? '',
            );
          }
        }
      }

      if (uid > 0 && bduss != null && bduss.isNotEmpty) {
        final result = await postForm(
          '/c/f/forum/like',
          params: [
            MapEntry('friend_uid', uid.toString()),
            MapEntry('page_no', page.toString()),
            MapEntry('page_size', pageSize.toString()),
          ],
          bduss: bduss,
          stoken: stoken,
        );
        if (_isApiSuccess(result)) {
          final parsed = _parseUserFollowForumsPayload(result);
          if (parsed.items.isNotEmpty) return parsed;
        }
      }

      if (normalizedPortrait.isEmpty) {
        return (items: const <UserFollowedForum>[], hasMore: false);
      }

      return _fetchUserFollowForumsPcWeb(
        portrait: normalizedPortrait,
        page: page,
        pageSize: pageSize,
        bduss: bduss,
        stoken: stoken,
      );
    } catch (e) {
      debugPrint('[TiebaAPI] fetchUserFollowForums error: $e');
      return (items: const <UserFollowedForum>[], hasMore: false);
    }
  }

  static ({List<UserFollowedForum> items, bool hasMore})
  _parseUserFollowForumsPayload(Map<String, dynamic> result) {
    final candidates = <Map<String, dynamic>>[result];
    final nested = _asMap(result['data']);
    if (nested != null) {
      candidates.add(Map<String, dynamic>.from(nested));
    }
    for (final source in candidates) {
      final parsed = _parseFollowForumsFromMap(source);
      if (parsed.items.isNotEmpty) return parsed;
    }
    return (items: const <UserFollowedForum>[], hasMore: false);
  }

  static ({List<UserFollowedForum> items, bool hasMore})
  _parseFollowForumsFromMap(Map<String, dynamic> source) {
    final forums = <UserFollowedForum>[];

    void addForum(Map map) {
      final normalized = Map<String, dynamic>.from(map);
      final name = (normalized['forum_name'] ?? normalized['name'] ?? '')
          .toString()
          .trim();
      if (name.isEmpty) return;
      forums.add(
        UserFollowedForum(
          id: (normalized['forum_id'] ?? normalized['id'] ?? '').toString(),
          name: name,
          level:
              int.tryParse(
                (normalized['level_id'] ?? normalized['level'] ?? '')
                    .toString(),
              ) ??
              0,
        ),
      );
    }

    final forumList = source['forum_list'];
    if (forumList is Map) {
      for (final key in ['non-gconforum', 'gconforum']) {
        final raw = forumList[key];
        if (raw is! List) continue;
        for (final item in raw) {
          final map = _asMap(item);
          if (map != null) addForum(map);
        }
      }
    } else if (forumList is List) {
      for (final item in forumList) {
        final map = _asMap(item);
        if (map != null) addForum(map);
      }
    }

    if (forums.isEmpty) {
      final like = source['like'];
      if (like is List) {
        for (final item in like) {
          final map = _asMap(item);
          if (map != null) addForum(map);
        }
      }
    }

    if (forums.isEmpty) {
      for (final alt in [source['follow_forum'], source['follow_forums']]) {
        if (alt is! List) continue;
        for (final item in alt) {
          final map = _asMap(item);
          if (map != null) addForum(map);
        }
      }
    }

    final hasMore = _isTruthy(source['has_more']);
    return (items: forums, hasMore: hasMore);
  }

  static ({List<UserFollowedForum> items, bool hasMore})
  _parsePcFollowForumListPayload(Map<String, dynamic> result) {
    final code = result['error_code'];
    if (code != 0 && code != '0' && code != null) {
      return (items: const <UserFollowedForum>[], hasMore: false);
    }

    final data = _asMap(result['data']);
    if (data == null) {
      return (items: const <UserFollowedForum>[], hasMore: false);
    }

    final forums = <UserFollowedForum>[];

    final like = data['like'];
    if (like is List) {
      for (final item in like) {
        final map = _asMap(item);
        if (map == null) continue;
        final name = map['forum_name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        forums.add(
          UserFollowedForum(
            id: map['forum_id']?.toString() ?? '',
            name: name,
            level: int.tryParse(map['level_id']?.toString() ?? '') ?? 0,
          ),
        );
      }
    }

    if (forums.isEmpty) {
      for (final source in [data['forum_list'], data['follow_forum']]) {
        if (source is List) {
          for (final item in source) {
            final map = _asMap(item);
            if (map == null) continue;
            final name = (map['forum_name'] ?? map['name'] ?? '')
                .toString()
                .trim();
            if (name.isEmpty) continue;
            forums.add(
              UserFollowedForum(
                id: (map['forum_id'] ?? map['id'] ?? '').toString(),
                name: name,
                level:
                    int.tryParse(
                      (map['level_id'] ?? map['level'] ?? '').toString(),
                    ) ??
                    0,
              ),
            );
          }
        }
      }
    }

    return (items: forums, hasMore: _isTruthy(data['has_more']));
  }

  static Future<({List<UserFollowedForum> items, bool hasMore})>
  _fetchUserFollowForumsPcWeb({
    required String portrait,
    required int page,
    required int pageSize,
    String? bduss,
    String? stoken,
  }) async {
    final params = [
      MapEntry('portrait', portrait),
      MapEntry('pn', page.toString()),
      MapEntry('rn', pageSize.toString()),
      MapEntry('subapp_type', 'pc'),
      MapEntry('_client_type', '20'),
    ];

    try {
      final signed = await _getPcWebJson(
        '/c/f/pc/myForumList',
        params: params,
        bduss: bduss,
        stoken: stoken,
      );
      final parsed = _parsePcFollowForumListPayload(signed);
      if (parsed.items.isNotEmpty) return parsed;

      final web = await getWeb(
        '/c/f/pc/myForumList',
        params: params,
        bduss: bduss,
      );
      return _parsePcFollowForumListPayload(web);
    } catch (e) {
      debugPrint('[TiebaAPI] _fetchUserFollowForumsPcWeb error: $e');
      return (items: const <UserFollowedForum>[], hasMore: false);
    }
  }

  static Future<int?> _resolveFeedUserId({
    String? userId,
    String? portrait,
    String? userName,
    String? bduss,
    String? stoken,
  }) async {
    final parsed = int.tryParse(userId?.trim() ?? '');
    if (parsed != null && parsed > 0) return parsed;

    final normalizedPortrait = portrait != null && portrait.trim().isNotEmpty
        ? _normalizePortrait(portrait)
        : '';
    final normalizedUserName = userName?.trim() ?? '';
    if (normalizedPortrait.isEmpty && normalizedUserName.isEmpty) return null;

    final profile = await fetchUserProfile(
      bduss: bduss,
      stoken: stoken,
      portrait: normalizedPortrait.isNotEmpty ? normalizedPortrait : null,
      userName: normalizedUserName.isNotEmpty ? normalizedUserName : null,
      userId: userId,
    );
    final fromProfile = int.tryParse(profile?['user_id']?.toString() ?? '');
    if (fromProfile != null && fromProfile > 0) return fromProfile;
    return null;
  }

  static Future<List<TiebaPost>> _fetchUserFeedViaPcWeb({
    required String portrait,
    String userName = '',
    required int page,
    required bool threadsOnly,
    String? bduss,
    String? stoken,
  }) async {
    final params = [
      MapEntry('portrait', portrait),
      MapEntry('pn', page.toString()),
      MapEntry('rn', '20'),
      MapEntry('type', threadsOnly ? '1' : '2'),
      MapEntry('un', userName),
      MapEntry('subapp_type', 'pc'),
      MapEntry('_client_type', '20'),
    ];

    try {
      for (final fetch in [
        () => _getPcWebJson(
          '/c/u/feed/myThread',
          params: params,
          bduss: bduss,
          stoken: stoken,
        ),
        () => getWeb('/c/u/feed/myThread', params: params, bduss: bduss),
      ]) {
        final result = await fetch();
        final code = result['error_code'];
        if (code != 0 && code != '0') continue;
        if (threadsOnly) {
          final posts = _postsFromUserFeedPayload(result);
          if (posts.isNotEmpty) return posts;
        } else {
          final posts = _postsFromPcReplyFeedPayload(result);
          if (posts.isNotEmpty) return posts;
        }
      }
      return const [];
    } catch (e) {
      debugPrint('[TiebaAPI] _fetchUserFeedViaPcWeb error: $e');
      return const [];
    }
  }

  static Uint8List _buildUserPostReq({
    required int uid,
    required int pn,
    required int rn,
    required bool threadsOnly,
    String? bduss,
    String? stoken,
  }) {
    final commonW = ProtobufWriter();
    commonW.writeString(2, _clientVersion);
    commonW.writeString(3, 'dart_tieba');
    if (bduss != null && bduss.isNotEmpty) {
      commonW.writeString(10, bduss);
    }
    if (stoken != null && stoken.isNotEmpty) {
      commonW.writeString(30, stoken);
    }
    commonW.writeInt32(1, 2);

    final dataW = ProtobufWriter();
    dataW.writeInt64(1, uid);
    dataW.writeInt32(2, rn);
    dataW.writeInt32(5, 1);
    dataW.writeInt32(26, pn);
    dataW.writeInt32(33, threadsOnly ? 2 : 1);
    if (threadsOnly) {
      dataW.writeInt32(4, 1);
    }
    dataW.writeMessage(27, commonW.toBytes());

    final outerW = ProtobufWriter();
    outerW.writeMessage(1, dataW.toBytes());
    return outerW.toBytes();
  }

  static List<TiebaPost> _parseUserPostProtoResponse(
    Uint8List bytes, {
    required bool threadsOnly,
  }) {
    if (bytes.isEmpty) return const [];

    final reader = ProtobufReader(bytes);
    Uint8List? dataBytes;
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (field == 1 && wire == 2) {
        final errorBytes = reader.readBytes();
        final errno = _parseProtoErrorNo(errorBytes);
        if (errno != null && errno != 0) {
          debugPrint('[TiebaAPI] userpost errno=$errno');
          return const [];
        }
      } else if (field == 2 && wire == 2) {
        dataBytes = reader.readBytes();
      } else {
        reader.skipField(wire);
      }
    }
    if (dataBytes == null) return const [];

    final dataReader = ProtobufReader(dataBytes);
    final posts = <TiebaPost>[];
    _UserFeedIdentity? sharedIdentity;
    while (dataReader.hasMore) {
      final tag = dataReader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (field == 1 && wire == 2) {
        final itemBytes = dataReader.readBytes();
        final info = _parsePostInfoListFields(itemBytes);
        if (info.displayAuthor.isNotEmpty) {
          sharedIdentity = _UserFeedIdentity.fromInfo(info);
        }
        posts.addAll(
          _postsFromPostInfoListBytes(
            itemBytes,
            threadsOnly: threadsOnly,
            sharedIdentity: sharedIdentity,
          ),
        );
      } else {
        dataReader.skipField(wire);
      }
    }
    return posts;
  }

  static int? _parseProtoErrorNo(Uint8List bytes) {
    final reader = ProtobufReader(bytes);
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (field == 1 && wire == 0) return reader.readVarint();
      reader.skipField(wire);
    }
    return null;
  }

  static List<TiebaPost> _postsFromPostInfoListBytes(
    Uint8List bytes, {
    required bool threadsOnly,
    _UserFeedIdentity? sharedIdentity,
  }) {
    final info = _parsePostInfoListFields(bytes);
    final author = info.displayAuthor.isNotEmpty
        ? info.displayAuthor
        : (sharedIdentity?.displayAuthor.isNotEmpty == true
              ? sharedIdentity!.displayAuthor
              : '用户');
    final portrait = info.userPortrait.isNotEmpty
        ? info.userPortrait
        : (sharedIdentity?.userPortrait ?? '');

    if (threadsOnly) {
      final tid = info.threadId > 0
          ? info.threadId.toString()
          : (info.postId > 0 ? info.postId.toString() : '');
      if (tid.isEmpty) return const [];

      final body = _postInfoBodyText(info).trim();
      final title = info.title.trim();
      final content = title.isNotEmpty
          ? (body.isNotEmpty && body != title ? '$title\n$body' : title)
          : body;

      return [
        TiebaPost(
          id: tid,
          title: title.isNotEmpty ? title : (body.isNotEmpty ? body : '无标题'),
          author: author,
          authorAvatar: _buildAvatarUrl(portrait.isNotEmpty ? portrait : null),
          authorPortrait: _normalizePortraitIfPresent(portrait),
          content: content,
          barName: info.forumName,
          replyCount: info.replyNum,
          createdAt: info.createdAt,
          likes: info.agreeNum,
        ),
      ];
    }

    final results = <TiebaPost>[];
    final threadTitle = info.title.trim();
    for (final block in info.contentBlocks) {
      final entry = _parsePostInfoContentEntry(block);
      final text = entry.text.trim();
      if (text.isEmpty && threadTitle.isEmpty) continue;
      final tid = info.threadId > 0
          ? info.threadId.toString()
          : (entry.postId > 0
                ? entry.postId.toString()
                : info.postId.toString());
      if (tid.isEmpty) continue;
      results.add(
        TiebaPost(
          id: tid,
          title: threadTitle.isNotEmpty
              ? threadTitle
              : (text.length > 48 ? '${text.substring(0, 48)}…' : text),
          author: author,
          authorAvatar: _buildAvatarUrl(portrait.isNotEmpty ? portrait : null),
          authorPortrait: _normalizePortraitIfPresent(portrait),
          content: text,
          barName: info.forumName,
          replyCount: info.replyNum,
          createdAt: entry.createTime > 0
              ? DateTime.fromMillisecondsSinceEpoch(entry.createTime * 1000)
              : info.createdAt,
          likes: info.agreeNum,
        ),
      );
    }
    return results;
  }

  static _ParsedPostInfoContent _parsePostInfoContentEntry(Uint8List bytes) {
    final reader = ProtobufReader(bytes);
    final parsed = _ParsedPostInfoContent();
    final textParts = <String>[];
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      switch (field) {
        case 1:
          if (wire == 2) {
            final text = _parseContentElement(reader.readBytes());
            if (text.isNotEmpty) textParts.add(text);
          } else {
            reader.skipField(wire);
          }
        case 2:
          parsed.createTime = reader.readVarint();
        case 4:
          parsed.postId = reader.readVarint();
        default:
          reader.skipField(wire);
      }
    }
    parsed.text = _normalizeUserFeedContent(textParts.join());
    return parsed;
  }

  static String? _normalizePortraitIfPresent(String portrait) {
    final trimmed = portrait.trim();
    if (trimmed.isEmpty) return null;
    return _normalizePortrait(trimmed);
  }

  static _ParsedPostInfoList _parsePostInfoListFields(Uint8List bytes) {
    final reader = ProtobufReader(bytes);
    final parsed = _ParsedPostInfoList();
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      switch (field) {
        case 1:
          parsed.forumId = reader.readVarint();
        case 2:
          parsed.threadId = reader.readVarint();
        case 3:
          parsed.postId = reader.readVarint();
        case 5:
          parsed.createTime = reader.readVarint();
        case 6:
          parsed.forumName = reader.readString();
        case 7:
          parsed.title = reader.readString();
        case 8:
          parsed.contentBlocks.add(reader.readBytes());
        case 10:
          parsed.userName = reader.readString();
        case 17:
          parsed.replyNum = reader.readVarint();
        case 18:
          parsed.userId = reader.readVarint();
        case 19:
          parsed.userPortrait = reader.readString();
        case 35:
          parsed.nameShow = reader.readString();
        case 40:
          parsed.agreeNum = _parseAgreeNum(reader.readBytes());
        case 49:
          parsed.firstPostFragments.addAll(
            _parsePbContentFragments(reader.readBytes()),
          );
        default:
          reader.skipField(wire);
      }
    }
    return parsed;
  }

  static List<String> _parsePbContentFragments(Uint8List bytes) {
    final reader = ProtobufReader(bytes);
    final texts = <String>[];
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (field == 1 && wire == 2) {
        final text = _parsePostContentBytes(reader.readBytes());
        if (text.isNotEmpty) texts.add(text);
      } else {
        reader.skipField(wire);
      }
    }
    return texts;
  }

  static String _extractPostInfoContentText(Uint8List bytes) {
    return _parsePostContentBytes(bytes);
  }

  /// 用户主页 / 楼中楼共用的正文分片解析（支持文字、表情、图片等 type）。
  static String _parsePostContentBytes(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    final direct = _parseContentElement(bytes);
    if (direct.isNotEmpty) return direct;

    final reader = ProtobufReader(bytes);
    final parts = <String>[];
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (wire != 2) {
        reader.skipField(wire);
        continue;
      }
      final chunk = reader.readBytes();
      if (field == 1 || field == 2) {
        final parsed = _parseContentElement(chunk);
        if (parsed.isNotEmpty) {
          parts.add(parsed);
        } else {
          final nested = _parsePostContentContainer(chunk);
          if (nested.isNotEmpty) parts.add(nested);
        }
      }
    }
    return parts.join();
  }

  static String _parsePostContentContainer(Uint8List bytes) {
    final reader = ProtobufReader(bytes);
    final parts = <String>[];
    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (field, wire) = tag;
      if (wire == 2 && (field == 1 || field == 2)) {
        final parsed = _parseContentElement(reader.readBytes());
        if (parsed.isNotEmpty) parts.add(parsed);
      } else {
        reader.skipField(wire);
      }
    }
    return parts.join();
  }

  static String _normalizeUserFeedContent(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';

    if (text.contains('post_content') &&
        (text.contains('type:') || text.contains('"type"'))) {
      final recovered = _recoverTextFromContentDump(text);
      if (recovered.isNotEmpty) {
        text = recovered;
      } else {
        return '';
      }
    }

    return TiebaEmoticon.replaceBracketEmoticons(text);
  }

  /// 兜底：正文被 Map/List toString 成 `{post_content: [{type: 0, text: ...}]}`。
  static String _recoverTextFromContentDump(String dump) {
    final parts = <String>[];
    for (final match in RegExp(
      r'''(?:text|"text")\s*[:=]\s*"?([^",}\]]+)"?''',
    ).allMatches(dump)) {
      final t = match.group(1)?.trim();
      if (t != null && t.isNotEmpty && t != 'null') parts.add(t);
    }
    for (final match in RegExp(
      r'''(?:^|[,{]\s*)c\s*:\s*([^,}\]]+)''',
    ).allMatches(dump)) {
      final name = match.group(1)?.trim();
      if (name == null || name.isEmpty) continue;
      final md = TiebaEmoticon.toMarkdown(name);
      parts.add(md.isNotEmpty ? md : '[$name]');
    }
    return parts.join();
  }

  static String _resolveUserFeedItemContent(Map<String, dynamic> item) {
    for (final key in ['content', 'text', 'post_content']) {
      final raw = item[key];
      if (raw == null) continue;
      if (raw is Map || raw is List) {
        final parsed = _normalizeUserFeedContent(_extractFormContent(raw));
        if (parsed.isNotEmpty) return parsed;
      } else if (raw is String && raw.trim().isNotEmpty) {
        final parsed = _normalizeUserFeedContent(raw);
        if (parsed.isNotEmpty) return parsed;
      }
    }

    final abstractList = _asList(item['abstract']);
    if (abstractList != null) {
      final buffer = StringBuffer();
      for (final abs in abstractList) {
        if (abs is Map) {
          final parsed = _normalizeUserFeedContent(_extractFormContent(abs));
          if (parsed.isEmpty) continue;
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(parsed);
        } else if (abs is String && abs.trim().isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(_normalizeUserFeedContent(abs));
        }
      }
      if (buffer.isNotEmpty) return buffer.toString();
    }

    final abstractRaw = item['abstract'];
    if (abstractRaw is String && abstractRaw.trim().isNotEmpty) {
      return _normalizeUserFeedContent(abstractRaw);
    }
    return '';
  }

  static String _postInfoBodyText(_ParsedPostInfoList info) {
    final fromBlocks = info.contentBlocks
        .map(_extractPostInfoContentText)
        .where((t) => t.trim().isNotEmpty)
        .join('\n');
    if (fromBlocks.trim().isNotEmpty) {
      return _normalizeUserFeedContent(fromBlocks);
    }
    return _normalizeUserFeedContent(info.firstPostFragments.join());
  }

  static List<TiebaPost> _postsFromUserFeedPayload(Map<String, dynamic> data) {
    final fromSearch = _postsFromSearchPayload(data);
    if (fromSearch.isNotEmpty) return fromSearch;

    final items = _extractThreadItemMaps(data);
    if (items.isNotEmpty) {
      return items
          .map(_postFromUserFeedItem)
          .where((p) => p.id.isNotEmpty)
          .toList();
    }

    return _postsFromPcReplyFeedPayload(data);
  }

  static List<TiebaPost> _postsFromPcReplyFeedPayload(
    Map<String, dynamic> data,
  ) {
    final nested = _asMap(data['data']);
    final list = _asList(nested?['list']) ?? _asList(data['list']);
    if (list == null || list.isEmpty) return const [];

    final posts = <TiebaPost>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final postInfoRaw = _asMap(item['post_info']);
      if (postInfoRaw == null) continue;
      final postInfo = Map<String, dynamic>.from(postInfoRaw);

      final threadInfo =
          _asMap(postInfo['thread_info']) ?? _asMap(item['thread_info']);
      final tid =
          (threadInfo?['id'] ??
                  threadInfo?['tid'] ??
                  postInfo['tid'] ??
                  postInfo['thread_id'] ??
                  '')
              .toString();
      if (tid.isEmpty) continue;

      final content = _resolveUserFeedItemContent(postInfo);
      final title = (threadInfo?['title'] ?? item['title'] ?? '').toString();
      final authorMap = _asMap(postInfo['author']);
      final author =
          authorMap?['name_show']?.toString() ??
          authorMap?['show_nickname']?.toString() ??
          authorMap?['name']?.toString() ??
          '用户';
      final createTime = _intFrom(postInfo['time'] ?? postInfo['create_time']);

      posts.add(
        TiebaPost(
          id: tid,
          title: title.isNotEmpty
              ? title
              : (content.isNotEmpty
                    ? (content.length > 48
                          ? '${content.substring(0, 48)}…'
                          : content)
                    : '无标题'),
          author: author,
          authorAvatar: _buildAvatarUrl(authorMap?['portrait']?.toString()),
          authorPortrait: _normalizePortraitIfPresent(
            authorMap?['portrait']?.toString() ?? '',
          ),
          content: content,
          barName:
              (threadInfo?['fname'] ??
                      threadInfo?['forum_name'] ??
                      postInfo['fname'] ??
                      '')
                  .toString(),
          replyCount: _intFrom(
            threadInfo?['reply_num'] ?? threadInfo?['post_num'],
          ),
          createdAt: createTime > 0
              ? DateTime.fromMillisecondsSinceEpoch(createTime * 1000)
              : DateTime.now(),
          likes: _intFrom(postInfo['agree_num'] ?? postInfo['like_num']),
        ),
      );
    }
    return posts;
  }

  static TiebaPost _postFromUserFeedItem(Map<String, dynamic> item) {
    final thread = _asMap(item['thread']) ?? _asMap(item['thread_info']);
    final tid =
        (item['tid'] ??
                item['thread_id'] ??
                thread?['id'] ??
                thread?['tid'] ??
                item['id'] ??
                '')
            .toString();
    final title =
        (item['title'] ?? item['thread_title'] ?? thread?['title'] ?? '')
            .toString();
    final content = _resolveUserFeedItemContent(item);
    final user = _asMap(item['author']) ?? _asMap(item['user']);
    final author =
        user?['name_show']?.toString() ??
        user?['show_nickname']?.toString() ??
        user?['name']?.toString() ??
        user?['user_name']?.toString() ??
        item['author_name']?.toString() ??
        '匿名';

    return TiebaPost(
      id: tid,
      title: title.isNotEmpty ? title : (content.isNotEmpty ? content : '无标题'),
      author: author,
      authorAvatar: _buildAvatarUrl(user?['portrait']?.toString()),
      content: content,
      barName:
          (item['fname'] ??
                  item['forum_name'] ??
                  thread?['fname'] ??
                  thread?['forum_name'] ??
                  '')
              .toString(),
      replyCount: _intFrom(
        item['post_num'] ?? item['reply_num'] ?? thread?['reply_num'],
      ),
      createdAt: DateTime.now(),
      likes: _intFrom(item['like_num'] ?? item['agree_num']),
    );
  }

  /// Isolate 入口：protobuf 吧内列表解析。
  static List<TiebaPost> parseFrsPageResponse(Uint8List data, String fname) =>
      _parseFrsPageRes(data, fname);

  static List<TiebaPost> parsePersonalizedResponse(Map<String, dynamic> data) =>
      _parsePersonalizedList(data);

  static TiebaPostDetail? parsePostDetailResponse(
    Map<String, dynamic> data,
    String tid, {
    int page = 1,
  }) => _parseFormPostDetail(data, tid, page: page);
}

class _FrsParseArgs {
  final Uint8List data;
  final String barName;

  const _FrsParseArgs(this.data, this.barName);
}

class _PostDetailParseArgs {
  final Map<String, dynamic> data;
  final String tid;
  final int page;

  const _PostDetailParseArgs(this.data, this.tid, this.page);
}

List<TiebaPost> _parseFrsPageIsolate(_FrsParseArgs args) =>
    TiebaClient.parseFrsPageResponse(args.data, args.barName);

List<TiebaPost> _parsePersonalizedIsolate(Map<String, dynamic> data) =>
    TiebaClient.parsePersonalizedResponse(data);

TiebaPostDetail? _parsePostDetailIsolate(_PostDetailParseArgs args) =>
    TiebaClient.parsePostDetailResponse(args.data, args.tid, page: args.page);

Map<String, dynamic> _decodeJsonMapIsolate(String body) =>
    jsonDecode(body) as Map<String, dynamic>;

Future<List<TiebaPost>> parseFrsPagePostsAsync(
  Uint8List data,
  String barName,
) => compute(_parseFrsPageIsolate, _FrsParseArgs(data, barName));

Future<List<TiebaPost>> parsePersonalizedPostsAsync(
  Map<String, dynamic> data,
) => compute(_parsePersonalizedIsolate, data);

Future<TiebaPostDetail?> parsePostDetailAsync(
  Map<String, dynamic> data,
  String tid, {
  int page = 1,
}) => compute(_parsePostDetailIsolate, _PostDetailParseArgs(data, tid, page));

class _UserFeedIdentity {
  final String userName;
  final String nameShow;
  final String userPortrait;

  const _UserFeedIdentity({
    required this.userName,
    required this.nameShow,
    required this.userPortrait,
  });

  factory _UserFeedIdentity.fromInfo(_ParsedPostInfoList info) {
    return _UserFeedIdentity(
      userName: info.userName,
      nameShow: info.nameShow,
      userPortrait: info.userPortrait,
    );
  }

  String get displayAuthor {
    final show = nameShow.trim();
    if (show.isNotEmpty) return show;
    final name = userName.trim();
    if (name.isNotEmpty) return name;
    return '';
  }
}

class _ParsedPostInfoContent {
  int postId = 0;
  int createTime = 0;
  String text = '';
}

class _ParsedPostInfoList {
  int forumId = 0;
  int threadId = 0;
  int postId = 0;
  int createTime = 0;
  int replyNum = 0;
  int userId = 0;
  int agreeNum = 0;
  String forumName = '';
  String title = '';
  String userName = '';
  String nameShow = '';
  String userPortrait = '';
  final List<Uint8List> contentBlocks = [];
  final List<String> firstPostFragments = [];

  String get displayAuthor {
    final show = nameShow.trim();
    if (show.isNotEmpty) return show;
    final name = userName.trim();
    if (name.isNotEmpty) return name;
    return '';
  }

  DateTime get createdAt => createTime > 0
      ? DateTime.fromMillisecondsSinceEpoch(createTime * 1000)
      : DateTime.now();
}

class ThreadStoreMeta {
  final String pid;
  final int? fid;
  final String barName;

  const ThreadStoreMeta({required this.pid, this.fid, this.barName = ''});
}

class PersonalizedFeedPage {
  final List<TiebaPost> posts;
  final bool hasMore;

  const PersonalizedFeedPage({required this.posts, required this.hasMore});
}
