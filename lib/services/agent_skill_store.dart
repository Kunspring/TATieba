import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// AI 保存的可复用工具编排（技能配方）。
class AgentSkill {
  final String name;
  final String description;
  final List<Map<String, dynamic>> steps;
  final DateTime updatedAt;

  const AgentSkill({
    required this.name,
    required this.description,
    required this.steps,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'steps': steps,
    'updated_at': updatedAt.toIso8601String(),
  };

  factory AgentSkill.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    final steps = rawSteps is List
        ? rawSteps
              .whereType<Map>()
              .map((s) => Map<String, dynamic>.from(s))
              .toList()
        : <Map<String, dynamic>>[];
    final updatedRaw = json['updated_at']?.toString();
    return AgentSkill(
      name: json['name']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      steps: steps,
      updatedAt: updatedRaw != null
          ? DateTime.tryParse(updatedRaw) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// 持久化 [AgentSkill] 配方。
abstract final class AgentSkillStore {
  AgentSkillStore._();

  static const _prefKey = 'agent_skills_v1';
  static const maxSkills = 24;

  static Future<List<AgentSkill>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((m) => AgentSkill.fromJson(Map<String, dynamic>.from(m)))
          .where((s) => s.name.isNotEmpty && s.steps.isNotEmpty)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return const [];
    }
  }

  static Future<AgentSkill?> get(String name) async {
    final key = name.trim();
    if (key.isEmpty) return null;
    final all = await list();
    for (final skill in all) {
      if (skill.name == key) return skill;
    }
    return null;
  }

  static Future<void> save(AgentSkill skill) async {
    final name = skill.name.trim();
    if (name.isEmpty || skill.steps.isEmpty) {
      throw ArgumentError('技能名称与步骤不能为空');
    }
    final all = await list();
    final next = all.where((s) => s.name != name).toList()
      ..insert(0, skill.copyWith(name: name));
    if (next.length > maxSkills) {
      next.removeRange(maxSkills, next.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey,
      jsonEncode(next.map((s) => s.toJson()).toList()),
    );
  }

  static Future<bool> delete(String name) async {
    final key = name.trim();
    if (key.isEmpty) return false;
    final all = await list();
    final next = all.where((s) => s.name != key).toList();
    if (next.length == all.length) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey,
      jsonEncode(next.map((s) => s.toJson()).toList()),
    );
    return true;
  }
}

extension on AgentSkill {
  AgentSkill copyWith({
    String? name,
    String? description,
    List<Map<String, dynamic>>? steps,
    DateTime? updatedAt,
  }) {
    return AgentSkill(
      name: name ?? this.name,
      description: description ?? this.description,
      steps: steps ?? this.steps,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
