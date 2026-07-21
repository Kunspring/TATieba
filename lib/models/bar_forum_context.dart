import 'tieba_post.dart';
import '../utils/forum_level_style.dart';

class BarForumThreadBrief {
  final String id;
  final String title;

  const BarForumThreadBrief({required this.id, required this.title});
}

enum BarFrsTab { latest, good }

extension BarFrsTabLabel on BarFrsTab {
  String get label => switch (this) {
    BarFrsTab.latest => '最新',
    BarFrsTab.good => '精华',
  };

  bool get isGood => this == BarFrsTab.good;
}

/// 进入某个吧时的汇总信息（顶栏信息块）。
class BarForumContext {
  final String barName;
  final String? avatarUrl;
  final String? slogan;
  final int? memberCount;
  final int forumLevel;
  final String forumLevelName;
  final int currentExp;
  final int levelUpExp;
  final bool? signedToday;
  final bool followed;
  final List<String> tabs;
  final String? forumRule;
  final List<BarForumThreadBrief> pinnedThreads;

  const BarForumContext({
    required this.barName,
    this.avatarUrl,
    this.slogan,
    this.memberCount,
    this.forumLevel = 0,
    this.forumLevelName = '',
    this.currentExp = 0,
    this.levelUpExp = 0,
    this.signedToday,
    this.followed = false,
    this.tabs = const ['最新', '精华'],
    this.forumRule,
    this.pinnedThreads = const [],
  });

  double get expProgress {
    if (levelUpExp <= 0) return 0;
    return (currentExp / levelUpExp).clamp(0.0, 1.0);
  }

  String get levelLabel => ForumLevelStyle.displayLabel(
    level: forumLevel,
    levelName: forumLevelName,
  );

  BarForumContext copyWith({
    String? barName,
    String? avatarUrl,
    String? slogan,
    int? memberCount,
    int? forumLevel,
    String? forumLevelName,
    int? currentExp,
    int? levelUpExp,
    bool? signedToday,
    bool? followed,
    List<String>? tabs,
    String? forumRule,
    List<BarForumThreadBrief>? pinnedThreads,
  }) {
    return BarForumContext(
      barName: barName ?? this.barName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      slogan: slogan ?? this.slogan,
      memberCount: memberCount ?? this.memberCount,
      forumLevel: forumLevel ?? this.forumLevel,
      forumLevelName: forumLevelName ?? this.forumLevelName,
      currentExp: currentExp ?? this.currentExp,
      levelUpExp: levelUpExp ?? this.levelUpExp,
      signedToday: signedToday ?? this.signedToday,
      followed: followed ?? this.followed,
      tabs: tabs ?? this.tabs,
      forumRule: forumRule ?? this.forumRule,
      pinnedThreads: pinnedThreads ?? this.pinnedThreads,
    );
  }
}

class BarFrsPageResult {
  final List<TiebaPost> posts;
  final BarForumContext? context;
  final bool hasMore;

  const BarFrsPageResult({
    required this.posts,
    this.context,
    this.hasMore = true,
  });
}
