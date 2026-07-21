/// 用户关注的贴吧（用户主页「关注的吧」Tab）。
class UserFollowedForum {
  final String id;
  final String name;
  final int level;

  const UserFollowedForum({
    required this.id,
    required this.name,
    this.level = 0,
  });
}
