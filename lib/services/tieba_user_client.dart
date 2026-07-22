import '../models/tieba_post.dart';
import '../models/user_followed_forum.dart';

import 'tieba_client.dart';

/// User profile, growth/forum level, follow, and user posts operations.
///
/// All methods delegate to [TiebaClient]. This class provides a
/// domain-organized API surface for user-related operations.
class TiebaUserClient {
  TiebaUserClient._();

  // -- follow --

  static Future<bool> followUser({
    required String portrait,
    required String bduss,
    required String tbs,
  }) =>
      TiebaClient.followUser(portrait: portrait, bduss: bduss, tbs: tbs);

  static Future<bool> unfollowUser({
    required String portrait,
    required String bduss,
    required String tbs,
  }) =>
      TiebaClient.unfollowUser(portrait: portrait, bduss: bduss, tbs: tbs);

  static Future<bool?> fetchUserIsFollowedByMe({
    required String portrait,
    String? userId,
    String? bduss,
    String? stoken,
  }) =>
      TiebaClient.fetchUserIsFollowedByMe(
        portrait: portrait,
        userId: userId,
        bduss: bduss,
        stoken: stoken,
      );

  // -- profile --

  static Future<Map<String, dynamic>?> fetchUserProfile({
    String? bduss,
    String? stoken,
    String? portrait,
    String? userId,
    String? userName,
  }) =>
      TiebaClient.fetchUserProfile(
        bduss: bduss,
        stoken: stoken,
        portrait: portrait,
        userId: userId,
        userName: userName,
      );

  // -- levels --

  static Future<int?> fetchUserGrowthLevel({
    String? portrait,
    String? userId,
    String? bduss,
    String? stoken,
  }) =>
      TiebaClient.fetchUserGrowthLevel(
        portrait: portrait,
        userId: userId,
        bduss: bduss,
        stoken: stoken,
      );

  static Future<Map<String, dynamic>?> fetchUserForumLevel({
    required String barName,
    required String portrait,
    String? bduss,
    String? stoken,
  }) =>
      TiebaClient.fetchUserForumLevel(
        barName: barName,
        portrait: portrait,
        bduss: bduss,
        stoken: stoken,
      );

  // -- user content --

  static Future<List<TiebaPost>> fetchUserPosts({
    String? portrait,
    String? userId,
    String? userName,
    int page = 1,
    bool threadsOnly = true,
    String? bduss,
    String? stoken,
  }) =>
      TiebaClient.fetchUserPosts(
        portrait: portrait,
        userId: userId,
        userName: userName,
        page: page,
        threadsOnly: threadsOnly,
        bduss: bduss,
        stoken: stoken,
      );

  static Future<({List<UserFollowedForum> items, bool hasMore})>
  fetchUserFollowForums({
    int userId = 0,
    String? portrait,
    String? userName,
    int page = 1,
    int pageSize = 30,
    String? bduss,
    String? stoken,
  }) =>
      TiebaClient.fetchUserFollowForums(
        userId: userId,
        portrait: portrait,
        userName: userName,
        page: page,
        pageSize: pageSize,
        bduss: bduss,
        stoken: stoken,
      );
}
