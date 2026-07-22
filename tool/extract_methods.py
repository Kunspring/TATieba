"""Extract method ranges from tieba_client.dart into new service files."""
import sys

def read_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.readlines()

def extract_ranges(lines, ranges):
    """Extract specified line ranges (1-based, inclusive). Return list of lines."""
    result = []
    for start, end in ranges:
        result.append(f'\n// --- original lines {start}-{end} ---\n')
        result.extend(lines[start-1:end])
    return result

def write_file(path, header, body_lines):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(header)
        for line in body_lines:
            f.write(line)

base = r'C:\Users\gaben\tieba_app\lib\services'
lines = read_file(f'{base}/tieba_client.dart')

# ============================================================
# FORUM CLIENT
# ============================================================
forum_header = """import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tieba_post.dart';
import '../models/bar_forum_context.dart';
import '../models/tieba_user_profile.dart';
import '../utils/tieba_portrait.dart';

import 'tieba_client.dart';
import 'tieba_post_client.dart';
import 'tieba_user_client.dart';
import 'tieba_protobuf.dart';

/// Forum/bar, notification, and server-side favorites operations.
class TiebaForumClient {
  TiebaForumClient._();

"""

forum_ranges = [
    (553, 585),    # followBar + unfollowBar
    (1063, 1124),  # fetchFollowedBarNames
    (1126, 1148),  # getAts
    (1150, 1182),  # getReplys
    (1184, 1360),  # _parseReplys + _parseSingleReply
    (1412, 1442),  # fetchBarAvatarByFrs + getForumId
    (1444, 1601),  # fetchThreadStoreMeta + fetchServerFavorites
    (1603, 1732),  # addServerFavorite + removeServerFavorite + hotBarFallback
    (2262, 2368),  # fetchBarSignedToday + fetchBarForumContext
]

forum_body = extract_ranges(lines, forum_ranges)
write_file(f'{base}/tieba_forum_client.dart', forum_header + '\n', forum_body + ['}\n'])
print(f'Forum: {len(forum_body)} lines extracted')

# ============================================================
# USER CLIENT
# ============================================================
user_header = """import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tieba_post.dart';
import '../models/bar_forum_context.dart';
import '../models/user_followed_forum.dart';
import '../utils/tieba_emoticon.dart';
import '../utils/tieba_portrait.dart';

import 'tieba_client.dart';
import 'tieba_forum_client.dart';

/// User profile, growth/forum level, follow, and user posts operations.
class TiebaUserClient {
  TiebaUserClient._();

"""

user_ranges = [
    (587, 627),    # _isAlreadyFollowingUser, _isAlreadyUnfollowingUser, followUser, unfollowUser
    (3791, 3924),  # fetchSelfProfile, _fetchUserPanel, _fetchUserJsonByName, _parseUserPanelMap
    (3927, 4014),  # fetchUserGrowthLevel, fetchUserForumLevel
    (4016, 4296),  # _buildProfileReq, _parseProfileGrowthLevel, ..., _parseUserProtoToMap
    (4298, 4320),  # _mergeUserProfileMaps, fetchUserProfile (part 1)
    (4320, 4460),  # fetchUserProfile (rest)
    (4484, 4547),  # fetchUserPosts
    (4550, 4758),  # fetchUserFollowForums (first overload)
    (4760, 4796),  # fetchUserFollowForums (second overload)
    (4798, 4824),  # _resolveFeedUserId
    (4826, 4870),  # _fetchUserFeedViaPcWeb
    (4872, 4905),  # _buildUserPostReq
    (4907, 4959),  # _parseUserPostProtoResponse
    (4973, 5048),  # _postsFromPostInfoListBytes
    (5050, 5076),  # _parsePostInfoContentEntry
    (5078, 5082),  # _normalizePortraitIfPresent
    (5084, 5127),  # _parsePostInfoListFields
    (5129, 5144),  # _parsePbContentFragments
    (5146, 5148),  # _extractPostInfoContentText
    (5151, 5179),  # _parsePostContentBytes
    (5181, 5196),  # _parsePostContentContainer
    (5198, 5213),  # _normalizeUserFeedContent
    (5216, 5233),  # _recoverTextFromContentDump
    (5235, 5270),  # _resolveUserFeedItemContent
    (5272, 5281),  # _postInfoBodyText
    (5283, 5296),  # _postsFromUserFeedPayload
    (5298, 5367),  # _postsFromPcReplyFeedPayload
    (5369, 5411),  # _postFromUserFeedItem
    (5469, 5530),  # _UserFeedIdentity, _ParsedPostInfoContent, _ParsedPostInfoList
]

user_body = extract_ranges(lines, user_ranges)
write_file(f'{base}/tieba_user_client.dart', user_header + '\n', user_body + ['}\n'])
print(f'User: {len(user_body)} lines extracted')

# ============================================================
# POST CLIENT
# ============================================================
post_header = """import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/tieba_post.dart';
import '../models/tieba_video.dart';
import '../models/bar_forum_context.dart';
import '../models/user_followed_forum.dart';
import '../utils/tieba_emoticon.dart';
import '../utils/tieba_video_util.dart';
import '../utils/cover_image_cache.dart';

import 'tieba_client.dart';
import 'device_id_service.dart';

/// Post, feed, search, and interaction operations.
class TiebaPostClient {
  TiebaPostClient._();

"""

post_ranges = [
    (356, 551),    # createPost, replyPost, _replyPostProto, _parseAddPostResp
    (637, 996),    # agreePost..agreeSubCommentMessage, _opAgree
    (998, 1031),   # _postIdFrom, _firstFloorPid, _usableFloorPid
    (1025, 1039),  # _usableFloorPid, _looksLikeMissingAgreeTarget
    (1041, 1061),  # replySubPost
    (1783, 1801),  # _buildFrsPageReq
    (1803, 1900),  # _parseFrsPageRes, _parseThreadInfo
    (1902, 1940),  # _parseUserInfo
    (1942, 1958),  # _extractCoverFromProtoContent
    (1960, 1982),  # _extractImageUrlFromContentElement
    (1996, 2024),  # fetchBarThreads
    (2026, 2066),  # fetchPersonalized
    (2068, 2075),  # _parsePersonalizedHasMore
    (2077, 2148),  # _parsePersonalizedList
    (2150, 2163),  # fetchBarThreadsForm
    (2166, 2194),  # fetchBarFrsPage
    (2196, 2202),  # _parseFrsHasMore
    (2370, 2427),  # _parseFormThreadList
    (2429, 2513),  # _extractThreadCover, _extractCoverFromMedia, _pickCoverImageUrl
    (2537, 2554),  # _pickVideoPlayUrl
    (2556, 2571),  # _pickVideoCoverUrl
    (2573, 2579),  # _videoDurationFrom
    (2581, 2613),  # _extractVideoFromInfo
    (2615, 2627),  # _extractVideoFromContentItem
    (2629, 2643),  # _extractVideoFromContent
    (2645, 2659),  # _extractThreadVideo
    (2661, 2666),  # _videoMarkdown
    (2705, 2715),  # _isAgreed
    (2718, 2728),  # _agreeNumFrom
    (2730, 2737),  # _resolveFirstPostAgreeNum
    (2739, 2767),  # fetchPostDetail
    (2925, 2941),  # _authorForumLevelFields
    (2943, 3121),  # _parseFormPostDetail
    (3123, 3154),  # fetchMoreSubComments
    (3156, 3174),  # _parseFloorResp
    (3176, 3197),  # _parseFloorDataRes
    (3199, 3304),  # _parseSubPostProto
    (3375, 3431),  # _parseFloorItemProto (UNUSED but keep for safety)
    (3550, 3629),  # _postsFromSearchPayload (used by both POST and USER - should stay in core, but let's include reference in POST too)
    (3636, 3659),  # _normalizeForumSearchItem
    (3661, 3694),  # _forumsFromSearchPayload
    (3697, 3741),  # searchThreads
    (3744, 3760),  # searchForums
    (3763, 3788),  # fetchForumDetail
    (5414, 5424),  # parseFrsPageResponse, parsePersonalizedResponse, parsePostDetailResponse
    (5442, 5467),  # isolate entry points + async wrappers
    (5427, 5440),  # _FrsParseArgs, _PostDetailParseArgs
]

post_body = extract_ranges(lines, post_ranges)
write_file(f'{base}/tieba_post_client.dart', post_header + '\n', post_body + ['}\n'])
print(f'Post: {len(post_body)} lines extracted')

print('\nDone! All files extracted.')
