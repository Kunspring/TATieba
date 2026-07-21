import 'dart:async';

import 'package:flutter/material.dart';

import '../models/agent_memory_entry.dart';
import '../services/agent_config_service.dart';
import '../services/browse_distill_service.dart';
import '../services/agent_memory_service.dart';
import '../services/agent_voice_service.dart';
import '../services/xunfei_config_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
import '../theme/app_glass.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_toast.dart';

class AgentConfigPage extends StatefulWidget {
  const AgentConfigPage({super.key});

  @override
  State<AgentConfigPage> createState() => _AgentConfigPageState();
}

class _AgentConfigPageState extends State<AgentConfigPage> {
  final _apiKeyCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _serperKeyCtrl = TextEditingController();
  final _xunfeiAppIdCtrl = TextEditingController();
  final _xunfeiApiKeyCtrl = TextEditingController();
  final _xunfeiApiSecretCtrl = TextEditingController();
  bool _loading = true;
  bool _advancedOpen = false;
  String _model = DeepSeekDefaults.model;
  bool _browseDistill = true;
  bool _browseLlmPolish = true;
  bool _memoryEnabled = true;
  bool _memoryLlmExtract = true;
  bool _memoryListOpen = false;
  bool _voiceAutoSend = true;
  bool _voiceReadReply = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _serperKeyCtrl.dispose();
    _xunfeiAppIdCtrl.dispose();
    _xunfeiApiKeyCtrl.dispose();
    _xunfeiApiSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await AgentConfigService.load();
    final xunfei = await XunfeiConfigService.load();
    await BrowseDistillService.instance.loadPrefs();
    await AgentMemoryService.instance.loadPrefs();
    await AgentVoiceService.instance.loadPrefs();
    if (!mounted) return;
    setState(() {
      _apiKeyCtrl.text = config.apiKey;
      _baseUrlCtrl.text = config.baseUrl;
      _serperKeyCtrl.text = config.serperApiKey;
      _xunfeiAppIdCtrl.text = xunfei.appId;
      _xunfeiApiKeyCtrl.text = xunfei.apiKey;
      _xunfeiApiSecretCtrl.text = xunfei.apiSecret;
      _model = config.model.isNotEmpty ? config.model : DeepSeekDefaults.model;
      _advancedOpen =
          config.baseUrl != DeepSeekDefaults.baseUrl ||
          config.model != DeepSeekDefaults.model;
      _browseDistill = BrowseDistillService.instance.enabled;
      _browseLlmPolish = BrowseDistillService.instance.llmPolishEnabled;
      _memoryEnabled = AgentMemoryService.instance.enabled;
      _memoryLlmExtract = AgentMemoryService.instance.llmExtractEnabled;
      _voiceAutoSend = AgentVoiceService.instance.voiceAutoSend;
      _voiceReadReply = AgentVoiceService.instance.voiceReadReply;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final key = _apiKeyCtrl.text.trim();
    if (key.isEmpty) {
      showAppToast(context, '请填写 API Key', type: AppToastType.error);
      return;
    }

    await AgentConfigService.save(
      AgentConfig(
        baseUrl: _baseUrlCtrl.text.trim().isEmpty
            ? DeepSeekDefaults.baseUrl
            : _baseUrlCtrl.text,
        apiKey: key,
        model: _model,
        serperApiKey: _serperKeyCtrl.text.trim(),
      ),
    );
    await XunfeiConfigService.save(
      XunfeiConfig(
        appId: _xunfeiAppIdCtrl.text.trim(),
        apiKey: _xunfeiApiKeyCtrl.text.trim(),
        apiSecret: _xunfeiApiSecretCtrl.text.trim(),
      ),
    );
    unawaited(AgentVoiceService.instance.warmUp());
    if (!mounted) return;
    showAppToast(context, '已保存', type: AppToastType.success);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.scaffold,
      appBar: GlassAppBar(
        companionLayoutKey: 'agent-config',
        titleText: '助手设置',
        title: Text('助手设置', style: AppFonts.title(color: colors.textPrimary)),
      ),
      body: LoadingFadeView(
        loading: _loading,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'API Key',
                    style: AppFonts.caption(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _apiKeyCtrl,
                    obscureText: false,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    enableSuggestions: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    autofillHints: const [],
                    decoration: const InputDecoration(hintText: 'sk-...'),
                  ),
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(top: 8),
                      title: Text(
                        '高级',
                        style: AppFonts.caption(color: colors.textSecondary),
                      ),
                      initiallyExpanded: _advancedOpen,
                      onExpansionChanged: (v) =>
                          setState(() => _advancedOpen = v),
                      children: [
                        Text(
                          'API 地址',
                          style: AppFonts.caption(color: colors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _baseUrlCtrl,
                          decoration: InputDecoration(
                            hintText: DeepSeekDefaults.baseUrl,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '模型',
                          style: AppFonts.caption(color: colors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: DeepSeekDefaults.models.map((model) {
                            final selected = _model == model;
                            return FilterChip(
                              label: Text(model),
                              selected: selected,
                              onSelected: (_) => setState(() => _model = model),
                              showCheckmark: false,
                              labelStyle: AppFonts.caption(
                                color: selected
                                    ? colors.textPrimary
                                    : colors.textSecondary,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Serper API Key',
                          style: AppFonts.caption(color: colors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _serperKeyCtrl,
                          obscureText: false,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.none,
                          autocorrect: false,
                          enableSuggestions: false,
                          smartDashesType: SmartDashesType.disabled,
                          smartQuotesType: SmartQuotesType.disabled,
                          autofillHints: const [],
                          decoration: const InputDecoration(hintText: '可选'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '浏览蒸馏',
                    style: AppFonts.caption(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '记住逛过的帖',
                      style: AppFonts.body(color: colors.textPrimary),
                    ),
                    value: _browseDistill,
                    onChanged: (v) async {
                      setState(() => _browseDistill = v);
                      await BrowseDistillService.instance.setEnabled(v);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '聊天前少量润色',
                      style: AppFonts.body(color: colors.textPrimary),
                    ),
                    value: _browseLlmPolish,
                    onChanged: _browseDistill
                        ? (v) async {
                            setState(() => _browseLlmPolish = v);
                            await BrowseDistillService.instance.setLlmPolish(v);
                          }
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '语音交互',
                    style: AppFonts.caption(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '松手自动发送',
                      style: AppFonts.body(color: colors.textPrimary),
                    ),
                    value: _voiceAutoSend,
                    onChanged: (v) async {
                      setState(() => _voiceAutoSend = v);
                      await AgentVoiceService.instance.savePrefs(autoSend: v);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '朗读 AI 回复',
                      style: AppFonts.body(color: colors.textPrimary),
                    ),
                    value: _voiceReadReply,
                    onChanged: (v) async {
                      setState(() => _voiceReadReply = v);
                      await AgentVoiceService.instance.savePrefs(readReply: v);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '讯飞语音识别',
                    style: AppFonts.caption(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _xunfeiAppIdCtrl,
                    decoration: const InputDecoration(hintText: 'AppID'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _xunfeiApiKeyCtrl,
                    decoration: const InputDecoration(hintText: 'APIKey'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _xunfeiApiSecretCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'APISecret'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '在讯飞开放平台创建应用并开通「语音听写（流式版）」后填写',
                    style: AppFonts.caption(color: colors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '长期记忆',
                    style: AppFonts.caption(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '启用长期记忆',
                      style: AppFonts.body(color: colors.textPrimary),
                    ),
                    value: _memoryEnabled,
                    onChanged: (v) async {
                      setState(() => _memoryEnabled = v);
                      await AgentMemoryService.instance.setEnabled(v);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '对话后自动提炼',
                      style: AppFonts.body(color: colors.textPrimary),
                    ),
                    value: _memoryLlmExtract,
                    onChanged: _memoryEnabled
                        ? (v) async {
                            setState(() => _memoryLlmExtract = v);
                            await AgentMemoryService.instance.setLlmExtract(v);
                          }
                        : null,
                  ),
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 4),
                      title: Text(
                        '已记住 ${AgentMemoryService.instance.entries.length} 条',
                        style: AppFonts.caption(color: colors.textSecondary),
                      ),
                      initiallyExpanded: _memoryListOpen,
                      onExpansionChanged: (v) =>
                          setState(() => _memoryListOpen = v),
                      children: [
                        if (AgentMemoryService.instance.entries.isEmpty)
                          const SizedBox(height: 4)
                        else
                          ...AgentMemoryService.instance.entries
                              .take(12)
                              .map(
                                (e) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text(
                                    e.content,
                                    style: AppFonts.body(
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${e.category.label}'
                                    '${e.confidence < 85 ? ' · ${e.trustHint}(${e.confidence})' : ''}',
                                    style: AppFonts.caption(
                                      color: colors.textMuted,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: colors.textMuted,
                                    ),
                                    onPressed: () async {
                                      await AgentMemoryService.instance.remove(
                                        e.id,
                                      );
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                ),
                              ),
                        if (AgentMemoryService.instance.entries.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () async {
                                await AgentMemoryService.instance.clear();
                                if (mounted) setState(() {});
                              },
                              child: const Text('清空全部'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('保存')),
          ],
        ),
      ),
    );
  }
}
