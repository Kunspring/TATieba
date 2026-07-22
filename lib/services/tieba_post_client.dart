import 'dart:typed_data';

import '../models/tieba_post.dart';
import '../models/bar_forum_context.dart';

import 'tieba_client.dart';

/// Post, feed, search, and interaction operations.
///
/// All methods delegate to [TiebaClient]. This class provides a
/// domain-organized API surface for post-related operations.
class TiebaPostClient {
  TiebaPostClient._();

  // -- create / reply --

  static Future<Map<String, dynamic>> createPost({
    required String barName,
    required String title,
    required String content,
    required String bduss,
    required String tbs,
  }) =>
      TiebaClient.createPost(
        barName: barName,
        title: title,
        content: content,
        bduss: bduss,
        tbs: tbs,
      );

  static Future<Map<String, dynamic>> replyPost({
    required String tid,
    required String content,
    required String bduss,
    required String tbs,
    String? fname,
    int? fid,
    String? showName,
  }) =>
      TiebaClient.replyPost(
        tid: tid,
        content: content,
        bduss: bduss,
        tbs: tbs,
        fname: fname,
        fid: fid,
        showName: showName,
      );

  static Future<Map<String, dynamic>> replySubPost({
    required String tid,
    required String pid,
    required String content,
    required String bduss,
    required String tbs,
    String? fname,
    int? fid,
    String? showName,
  }) =>
      TiebaClient.replySubPost(
        tid: tid,
        pid: pid,
        content: content,
        bduss: bduss,
        tbs: tbs,
        fname: fname,
        fid: fid,
        showName: showName,
      );

  // -- agree / disagree (post) --

  static Future<bool> agreePost({
    required String tid,
    required String bduss,
    required String tbs,
    String? stoken,
    String? pid,
  }) =>
      TiebaClient.agreePost(
        tid: tid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
        pid: pid,
      );

  static Future<String?> agreePostMessage({
    required String tid,
    required String bduss,
    required String tbs,
    String? stoken,
    String? pid,
  }) =>
      TiebaClient.agreePostMessage(
        tid: tid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
        pid: pid,
      );

  static Future<bool> disagreePost({
    required String tid,
    required String bduss,
    required String tbs,
    String? stoken,
    String? pid,
  }) =>
      TiebaClient.disagreePost(
        tid: tid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
        pid: pid,
      );

  static Future<String?> disagreePostMessage({
    required String tid,
    required String bduss,
    required String tbs,
    String? stoken,
    String? pid,
  }) =>
      TiebaClient.disagreePostMessage(
        tid: tid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
        pid: pid,
      );

  static Future<bool> undoAgreePost({
    required String tid,
    required String bduss,
    required String tbs,
    String? stoken,
    String? pid,
  }) =>
      TiebaClient.undoAgreePost(
        tid: tid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
        pid: pid,
      );

  static Future<String?> undoAgreePostMessage({
    required String tid,
    required String bduss,
    required String tbs,
    String? stoken,
    String? pid,
  }) =>
      TiebaClient.undoAgreePostMessage(
        tid: tid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
        pid: pid,
      );

  // -- agree / disagree (comment) --

  static Future<bool> agreeComment({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) =>
      TiebaClient.agreeComment(
        tid: tid,
        pid: pid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
      );

  static Future<String?> agreeCommentMessage({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) =>
      TiebaClient.agreeCommentMessage(
        tid: tid,
        pid: pid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
      );

  static Future<bool> disagreeComment({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) =>
      TiebaClient.disagreeComment(
        tid: tid,
        pid: pid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
      );

  static Future<bool> undoAgreeComment({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) =>
      TiebaClient.undoAgreeComment(
        tid: tid,
        pid: pid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
      );

  static Future<String?> undoAgreeCommentMessage({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) =>
      TiebaClient.undoAgreeCommentMessage(
        tid: tid,
        pid: pid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
      );

  // -- agree / disagree (sub-comment) --

  static Future<bool> agreeSubComment({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) =>
      TiebaClient.agreeSubComment(
        tid: tid,
        pid: pid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
      );

  static Future<String?> agreeSubCommentMessage({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) =>
      TiebaClient.agreeSubCommentMessage(
        tid: tid,
        pid: pid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
      );

  static Future<bool> undoAgreeSubComment({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) =>
      TiebaClient.undoAgreeSubComment(
        tid: tid,
        pid: pid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
      );

  static Future<String?> undoAgreeSubCommentMessage({
    required String tid,
    required String pid,
    required String bduss,
    required String tbs,
    String? stoken,
  }) =>
      TiebaClient.undoAgreeSubCommentMessage(
        tid: tid,
        pid: pid,
        bduss: bduss,
        tbs: tbs,
        stoken: stoken,
      );

  // -- feed / threads --

  static Future<List<TiebaPost>> fetchBarThreads(
    String barName, {
    int page = 1,
    String? bduss,
    bool isGood = false,
  }) =>
      TiebaClient.fetchBarThreads(
        barName,
        page: page,
        bduss: bduss,
        isGood: isGood,
      );

  static Future<PersonalizedFeedPage> fetchPersonalized({
    int loadType = 1,
    int page = 1,
    String? bduss,
  }) =>
      TiebaClient.fetchPersonalized(
        loadType: loadType,
        page: page,
        bduss: bduss,
      );

  static Future<List<TiebaPost>> fetchBarThreadsForm(
    String barName, {
    int page = 1,
    String? bduss,
    bool isGood = false,
  }) =>
      TiebaClient.fetchBarThreadsForm(
        barName,
        page: page,
        bduss: bduss,
        isGood: isGood,
      );

  static Future<BarFrsPageResult?> fetchBarFrsPage(
    String barName, {
    int page = 1,
    String? bduss,
    bool isGood = false,
    bool parseContext = false,
  }) =>
      TiebaClient.fetchBarFrsPage(
        barName,
        page: page,
        bduss: bduss,
        isGood: isGood,
        parseContext: parseContext,
      );

  // -- detail --

  static Future<TiebaPostDetail?> fetchPostDetail(
    String tid, {
    int page = 1,
    String? bduss,
    String? stoken,
  }) =>
      TiebaClient.fetchPostDetail(
        tid,
        page: page,
        bduss: bduss,
        stoken: stoken,
      );

  static Future<List<TiebaSubComment>> fetchMoreSubComments(
    String tid,
    String pid, {
    int page = 1,
    String? bduss,
    String? stoken,
  }) =>
      TiebaClient.fetchMoreSubComments(
        tid,
        pid,
        page: page,
        bduss: bduss,
        stoken: stoken,
      );

  // -- search --

  static Future<List<TiebaPost>> searchThreads({
    required String query,
    String? barName,
    int page = 1,
    String? bduss,
  }) =>
      TiebaClient.searchThreads(
        query: query,
        barName: barName,
        page: page,
        bduss: bduss,
      );

  static Future<List<Map<String, dynamic>>> searchForums({
    required String query,
    int page = 1,
    String? bduss,
  }) =>
      TiebaClient.searchForums(
        query: query,
        page: page,
        bduss: bduss,
      );

  static Future<Map<String, dynamic>?> fetchForumDetail(
    String barName, {
    String? bduss,
  }) =>
      TiebaClient.fetchForumDetail(barName, bduss: bduss);

  // -- parse helpers (isolate-based async) --

  static List<TiebaPost> parseFrsPageResponse(
    Uint8List data,
    String fname,
  ) =>
      TiebaClient.parseFrsPageResponse(data, fname);

  static List<TiebaPost> parsePersonalizedResponse(
    Map<String, dynamic> data,
  ) =>
      TiebaClient.parsePersonalizedResponse(data);

  static TiebaPostDetail? parsePostDetailResponse(
    Map<String, dynamic> data,
    String tid, {
    int page = 1,
  }) =>
      TiebaClient.parsePostDetailResponse(data, tid, page: page);

  // -- enrichment --

  static Future<void> enrichPostsForumLevels(
    List<TiebaPost> posts, {
    String? bduss,
    int maxConcurrent = 5,
  }) =>
      TiebaClient.enrichPostsForumLevels(
        posts,
        bduss: bduss,
        maxConcurrent: maxConcurrent,
      );
}
