import '../models/tieba_post.dart';
import '../models/bar_forum_context.dart';

import 'tieba_client.dart';

/// Forum/bar, notification, and server-side favorites operations.
///
/// All methods delegate to [TiebaClient]. This class provides a
/// domain-organized API surface for forum-related operations.
class TiebaForumClient {
  TiebaForumClient._();

  // -- bar following --

  static Future<bool> followBar(
    String barName,
    String bduss,
    String tbs,
  ) =>
      TiebaClient.followBar(barName, bduss, tbs);

  static Future<bool> unfollowBar(
    String barName,
    String bduss,
    String tbs,
  ) =>
      TiebaClient.unfollowBar(barName, bduss, tbs);

  // -- forum info --

  static Future<int?> getForumId(String fname) =>
      TiebaClient.getForumId(fname);

  static Future<String?> fetchBarAvatarByFrs(
    String fname,
    String bduss,
  ) =>
      TiebaClient.fetchBarAvatarByFrs(fname, bduss);

  static Future<BarForumContext?> fetchBarForumContext(
    String barName, {
    String? bduss,
    String? portrait,
    String? tbs,
    bool? followed,
  }) =>
      TiebaClient.fetchBarForumContext(
        barName,
        bduss: bduss,
        portrait: portrait,
        tbs: tbs,
        followed: followed,
      );

  static Future<bool?> fetchBarSignedToday(
    String barName, {
    required String bduss,
    required String tbs,
  }) =>
      TiebaClient.fetchBarSignedToday(barName, bduss: bduss, tbs: tbs);

  static Future<ThreadStoreMeta?> fetchThreadStoreMeta(
    String tid, {
    String? bduss,
    String? stoken,
  }) =>
      TiebaClient.fetchThreadStoreMeta(tid, bduss: bduss, stoken: stoken);

  static Future<List<TiebaPost>> fetchServerFavorites({
    int page = 1,
    int pageSize = 200,
    String? bduss,
    String? stoken,
  }) =>
      TiebaClient.fetchServerFavorites(
        page: page,
        pageSize: pageSize,
        bduss: bduss,
        stoken: stoken,
      );

  // -- server-side favorites --

  static Future<bool> addServerFavorite({
    required String tid,
    required String tbs,
    required int fid,
    required String pid,
    String? bduss,
    String? stoken,
    String? barName,
  }) =>
      TiebaClient.addServerFavorite(
        tid: tid,
        tbs: tbs,
        fid: fid,
        pid: pid,
        bduss: bduss,
        stoken: stoken,
        barName: barName,
      );

  static Future<bool> removeServerFavorite({
    required String tid,
    required String tbs,
    int? fid,
    String? bduss,
    String? stoken,
    String? barName,
  }) =>
      TiebaClient.removeServerFavorite(
        tid: tid,
        tbs: tbs,
        fid: fid,
        bduss: bduss,
        stoken: stoken,
        barName: barName,
      );

  // -- notifications --

  static Future<List<AtItem>> getAts({
    int pn = 1,
    required String bduss,
    String? stoken,
  }) =>
      TiebaClient.getAts(pn: pn, bduss: bduss, stoken: stoken);

  static Future<List<ReplyItem>> getReplys({
    int pn = 1,
    required String bduss,
    String? stoken,
  }) =>
      TiebaClient.getReplys(pn: pn, bduss: bduss, stoken: stoken);

  // -- sign-in --

  static Future<bool> signInBar(
    String barName,
    String bduss,
    String tbs,
  ) =>
      TiebaClient.signInBar(barName, bduss, tbs);
}
