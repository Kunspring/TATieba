import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart';

import 'package:flutter/scheduler.dart';

import 'package:flutter/services.dart';

import '../services/agent_voice_service.dart';

import '../theme/app_colors.dart' show AppColorScheme, AppColors;

import '../theme/app_fonts.dart';

import '../utils/app_lifecycle_gate.dart';

typedef VoiceHoldVisualChanged =
    void Function({
      required bool active,
      required bool cancelArmed,
      required bool arming,
      required bool startFailed,
      required bool waveActive,
    });

/// 输入框与语音态转场参数（框内 switch、转写区、列表留白共用）。
abstract final class VoiceComposerMotion {
  VoiceComposerMotion._();

  static const Duration switchIn = Duration(milliseconds: 220);
  static const Duration switchOut = Duration(milliseconds: 400);
  static const double activeScale = 1.03;
  static const Duration longPressDelay = Duration(milliseconds: 400);
}

/// 语音态：整框略放大 + 流动边框 + 框内声纹 + 上方飘散转写。

class VoiceComposerVisualShell extends StatefulWidget {
  final bool active;

  final bool cancelArmed;

  final AppColorScheme colors;

  final Widget child;

  const VoiceComposerVisualShell({
    super.key,

    required this.active,

    required this.cancelArmed,

    required this.colors,

    required this.child,
  });

  @override
  State<VoiceComposerVisualShell> createState() =>
      _VoiceComposerVisualShellState();
}

class _VoiceComposerVisualShellState extends State<VoiceComposerVisualShell>
    with TickerProviderStateMixin {
  late final AnimationController _borderCtrl;
  late final AnimationController _presentCtrl;

  @override
  void initState() {
    super.initState();

    _borderCtrl = AnimationController(
      vsync: this,

      duration: const Duration(milliseconds: 3200),
    );

    _presentCtrl = AnimationController(
      vsync: this,

      duration: VoiceComposerMotion.switchIn,
    );

    if (widget.active) _presentCtrl.value = 1.0;

    _syncBorder();
  }

  @override
  void didUpdateWidget(covariant VoiceComposerVisualShell oldWidget) {
    super.didUpdateWidget(oldWidget);

    _syncPresent(oldWidget.active);

    _syncBorder();

    if (oldWidget.cancelArmed != widget.cancelArmed) {
      setState(() {});
    }
  }

  void _syncPresent(bool wasActive) {
    if (!AppLifecycleGate.effectsEnabled) {
      _presentCtrl.value = widget.active ? 1.0 : 0.0;

      return;
    }

    if (widget.active && !wasActive) {
      _presentCtrl.duration = VoiceComposerMotion.switchIn;

      if (_presentCtrl.isAnimating) _presentCtrl.stop();

      _presentCtrl.forward(from: 0.0);
    } else if (!widget.active && wasActive) {
      _presentCtrl.duration = VoiceComposerMotion.switchOut;

      _presentCtrl.reverse(from: _presentCtrl.value);
    } else if (!widget.active) {
      _presentCtrl.value = 0;
    } else if (widget.active) {
      _presentCtrl.value = 1.0;
    }
  }

  void _syncBorder() {
    if (!AppLifecycleGate.effectsEnabled) {
      _borderCtrl.stop();

      return;
    }

    if (widget.active) {
      if (!_borderCtrl.isAnimating) _borderCtrl.repeat();
    } else {
      _borderCtrl.stop();

      _borderCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _borderCtrl.dispose();

    _presentCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(28);

    return AnimatedBuilder(
      animation: _presentCtrl,

      builder: (context, child) {
        final t = AppLifecycleGate.effectsEnabled
            ? Curves.easeOutCubic.transform(_presentCtrl.value)
            : (widget.active ? 1.0 : 0.0);

        Widget body = child!;

        if (widget.active || t > 0.001) {
          body = AnimatedBuilder(
            animation: _borderCtrl,

            builder: (context, inner) {
              return CustomPaint(
                painter: _FlowingBorderPainter(
                  progress: _borderCtrl.value,

                  radius: 28,

                  accent: widget.cancelArmed
                      ? AppColors.error
                      : widget.colors.primary,

                  isDark: Theme.of(context).brightness == Brightness.dark,

                  activation: t,
                ),

                child: Padding(
                  padding: const EdgeInsets.all(2.5),

                  child: inner,
                ),
              );
            },

            child: ClipRRect(borderRadius: borderRadius, child: child),
          );
        }

        final scale = 1.0 + t * (VoiceComposerMotion.activeScale - 1.0);

        return Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: body,
        );
      },

      child: widget.child,
    );
  }
}

class _FlowingBorderPainter extends CustomPainter {
  final double progress;
  final double radius;
  final Color accent;
  final bool isDark;
  final double activation;

  _FlowingBorderPainter({
    required this.progress,
    required this.radius,
    required this.accent,
    required this.isDark,
    this.activation = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // 对称色标 + 旋转 transform，避免 repeat 首尾颜色/相位不一致导致跳变。
    // activation 与整框放大共用同一缓动，使流动边框随转场淡入淡出而非硬闪。
    final dim = accent.withValues(alpha: (isDark ? 0.14 : 0.10) * activation);
    final mid = accent.withValues(alpha: (isDark ? 0.82 : 0.72) * activation);
    final peak = Colors.white.withValues(
      alpha: (isDark ? 0.52 : 0.42) * activation,
    );
    final sweep = SweepGradient(
      center: Alignment.center,
      startAngle: 0,
      endAngle: math.pi * 2,
      colors: [dim, mid, peak, mid, dim],
      stops: const [0.0, 0.24, 0.5, 0.76, 1.0],
      transform: GradientRotation(progress * math.pi * 2),
    );

    final stroke = Paint()
      ..shader = sweep.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawRRect(rrect.deflate(1.1), stroke);

    final glow = Paint()
      ..shader = sweep.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(rrect.deflate(1.1), glow);
  }

  @override
  bool shouldRepaint(covariant _FlowingBorderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accent != accent ||
        oldDelegate.isDark != isDark ||
        oldDelegate.activation != activation;
  }
}

/// 输入框上方：当前转写若隐若现，旧字随风上飘消散。

class DriftingVoiceTranscript extends StatefulWidget {
  final String text;

  final AppColorScheme colors;

  final bool cancelArmed;

  const DriftingVoiceTranscript({
    super.key,

    required this.text,

    required this.colors,

    required this.cancelArmed,
  });

  @override
  State<DriftingVoiceTranscript> createState() =>
      _DriftingVoiceTranscriptState();
}

class _DriftShard {
  final String text;
  final double xJitter;
  final double driftSpeed;
  double age = 0;

  _DriftShard({
    required this.text,
    required this.xJitter,
    required this.driftSpeed,
  });
}

class _DriftingVoiceTranscriptState extends State<DriftingVoiceTranscript>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tick;

  String _lastCommitted = '';

  final _shards = <_DriftShard>[];

  final _rng = math.Random();

  @override
  void initState() {
    super.initState();

    _lastCommitted = widget.text.trim();

    _tick = AnimationController(
      vsync: this,

      duration: const Duration(seconds: 1),
    );

    if (AppLifecycleGate.effectsEnabled) {
      _tick.repeat();
    }

    _tick.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant DriftingVoiceTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);

    final next = widget.text.trim();

    final prev = _lastCommitted;

    if (next != prev && prev.isNotEmpty) {
      _spawnShard(prev, next);
    }

    _lastCommitted = next;
  }

  void _spawnShard(String prev, String next) {
    if (!AppLifecycleGate.effectsEnabled) return;

    var fragment = prev;

    if (next.startsWith(prev) && next.length > prev.length) {
      return;
    }

    if (prev.length > next.length) {
      fragment = prev.substring(next.length).trim();
    }

    if (fragment.isEmpty || fragment.length < 2) return;

    if (fragment.length > 24) {
      fragment = fragment.substring(fragment.length - 24);
    }

    _shards.add(
      _DriftShard(
        text: fragment,

        xJitter: (_rng.nextDouble() - 0.5) * 36,

        driftSpeed: 0.35 + _rng.nextDouble() * 0.55,
      ),
    );

    if (_shards.length > 10) {
      _shards.removeRange(0, _shards.length - 10);
    }
  }

  void _onTick() {
    if (!mounted || _shards.isEmpty) return;

    const dt = 1 / 60.0;

    for (final shard in _shards) {
      shard.age += dt * shard.driftSpeed;
    }

    _shards.removeWhere((s) => s.age >= 1.05);
  }

  @override
  void dispose() {
    _tick.removeListener(_onTick);

    _tick.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.text.trim();

    return SizedBox(
      height: 92,

      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),

        child: Align(
          alignment: Alignment.topCenter,

          child: Stack(
            clipBehavior: Clip.none,

            alignment: Alignment.topCenter,

            children: [
              if (!widget.cancelArmed)
                AnimatedBuilder(
                  animation: _tick,
                  builder: (context, _) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final shard in _shards)
                          _DriftShardText(
                            shard: shard,
                            color: widget.colors.textSecondary,
                          ),
                      ],
                    );
                  },
                ),

              if (widget.cancelArmed)
                Column(
                  mainAxisSize: MainAxisSize.min,

                  children: [
                    Text(
                      '上滑取消',

                      style: AppFonts.title(color: AppColors.error).copyWith(
                        fontSize: 17,

                        height: 1.3,

                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    if (current.isNotEmpty) ...[
                      const SizedBox(height: 6),

                      Text(
                        current,

                        maxLines: 2,

                        overflow: TextOverflow.ellipsis,

                        textAlign: TextAlign.center,

                        style: AppFonts.body(color: widget.colors.textPrimary)
                            .copyWith(
                              fontSize: 15,

                              height: 1.35,

                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ],
                )
              else if (current.isNotEmpty)
                AnimatedBuilder(
                  animation: _tick,

                  builder: (context, child) {
                    return Opacity(
                      opacity:
                          0.92 +
                          (math.sin(_tick.value * math.pi * 2) + 1) * 0.04,

                      child: Transform.translate(
                        offset: Offset(
                          math.sin(_tick.value * math.pi * 2) * 1.5,

                          math.sin(_tick.value * math.pi * 4) * 1.0,
                        ),

                        child: child,
                      ),
                    );
                  },

                  child: Text(
                    current,

                    maxLines: 2,

                    overflow: TextOverflow.ellipsis,

                    textAlign: TextAlign.center,

                    style:
                        AppFonts.title(
                          color: widget.cancelArmed
                              ? AppColors.error
                              : widget.colors.textPrimary,
                        ).copyWith(
                          fontSize: 17,

                          height: 1.4,

                          fontWeight: FontWeight.w600,
                        ),
                  ),
                )
              else
                Text(
                  widget.cancelArmed ? '上滑取消' : '正在听…',

                  style:
                      AppFonts.body(
                        color: widget.cancelArmed
                            ? AppColors.error
                            : widget.colors.textSecondary,
                      ).copyWith(
                        fontSize: 15,

                        fontWeight: widget.cancelArmed
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriftShardText extends StatelessWidget {
  final _DriftShard shard;

  final Color color;

  const _DriftShardText({required this.shard, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = shard.age.clamp(0.0, 1.0);

    final opacity = (1 - t) * 0.72;

    final rise = t * 52;

    final sway = math.sin(t * math.pi * 3 + shard.xJitter) * (8 + t * 12);

    return Positioned(
      bottom: 8 + rise,

      left: 0,

      right: 0,

      child: Transform.translate(
        offset: Offset(shard.xJitter + sway, 0),

        child: Opacity(
          opacity: opacity,

          child: Text(
            shard.text,

            maxLines: 1,

            overflow: TextOverflow.fade,

            textAlign: TextAlign.center,

            style: AppFonts.caption(
              color: color,
            ).copyWith(letterSpacing: 0.6, fontStyle: FontStyle.italic),
          ),
        ),
      ),
    );
  }
}

/// 输入框内声纹（无底色、无边框、无提示文字）。
class VoiceInputWaveInterior extends StatelessWidget {
  final bool active;
  final bool cancelArmed;
  final bool startFailed;
  final AppColorScheme colors;

  const VoiceInputWaveInterior({
    super.key,
    required this.active,
    required this.cancelArmed,
    this.startFailed = false,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final accent = cancelArmed || startFailed
        ? AppColors.error
        : colors.primary;

    return _XiaomiVoiceWave(
      color: accent,
      active: active,
      cancelArmed: cancelArmed,
      levelListenable: AgentVoiceService.instance.soundLevelNotifier,
    );
  }
}

/// 小米录音风格：三条正弦波纹，两端收敛，随音量起伏、随时间流动。
/// 参考 RecordVoiceView/RecordViewLine.java (UCodeUStory/RecordVoiceView)。
class _XiaomiVoiceWave extends StatefulWidget {
  final Color color;
  final bool active;
  final bool cancelArmed;
  final ValueListenable<double> levelListenable;

  const _XiaomiVoiceWave({
    required this.color,
    required this.active,
    this.cancelArmed = false,
    required this.levelListenable,
  });

  @override
  State<_XiaomiVoiceWave> createState() => _XiaomiVoiceWaveState();
}

class _XiaomiVoiceWaveState extends State<_XiaomiVoiceWave>
    with SingleTickerProviderStateMixin {
  static const _attackTau = 0.08;
  static const _releaseTau = 0.15;
  static const _silenceGate = 0.04;

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  double _targetLevel = 0;
  double _displayLevel = 0;
  double _flowOffset = 0;

  @override
  void initState() {
    super.initState();
    _targetLevel = widget.levelListenable.value.clamp(0.0, 1.0);
    widget.levelListenable.addListener(_onTargetLevel);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _XiaomiVoiceWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.levelListenable != widget.levelListenable) {
      oldWidget.levelListenable.removeListener(_onTargetLevel);
      widget.levelListenable.addListener(_onTargetLevel);
      _onTargetLevel();
    }
    if (oldWidget.cancelArmed != widget.cancelArmed) {
      setState(() {});
    }
    _syncTicker();
  }

  void _onTargetLevel() {
    _targetLevel = widget.levelListenable.value.clamp(0.0, 1.0);
  }

  void _syncTicker() {
    // 退出语音态后保留 ticker，让声纹随 release 时间常数平滑衰减到 0 再停止，
    // 避免松手瞬间声纹被压平、与转场淡出错位。
    if (widget.active || _displayLevel > 0.01) {
      _ticker ??= createTicker(_onTick)..start();
      return;
    }
    _ticker?.stop();
    _ticker = null;
    _lastTick = Duration.zero;
    _displayLevel = 0;
    _flowOffset = 0;
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final dt = elapsed == _lastTick
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.12) return;

    // 停止说话后目标归零，声纹随 release 时间常数自然衰减而非瞬间压平。
    final target = widget.active
        ? (_targetLevel < _silenceGate ? 0.0 : _targetLevel)
        : 0.0;
    final tau = target > _displayLevel ? _attackTau : _releaseTau;
    final step = 1 - math.exp(-dt / tau);
    _displayLevel += (target - _displayLevel) * step;

    if (_displayLevel < 0.008) {
      _displayLevel = 0;
    }

    final flowSpeed = _displayLevel < 0.02 ? 0.0 : 0.1 + _displayLevel * 0.9;
    _flowOffset += dt * 10.0 * flowSpeed;

    setState(() {});

    // 退出且已衰减到 0 时停止 ticker，避免空转。
    if (!widget.active && _displayLevel <= 0.001) {
      _ticker?.stop();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    widget.levelListenable.removeListener(_onTargetLevel);
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _XiaomiVoiceWavePainter(
        color: widget.color,
        active: widget.active,
        cancelArmed: widget.cancelArmed,
        volume: _displayLevel,
        flowOffset: _flowOffset,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _XiaomiVoiceWavePainter extends CustomPainter {
  static const _pointCount = 88;
  static const _shakeRatios = [1.5, 2.5, 1.5];
  static const _linePhaseOffsets = [0.0, 1.5, 3.0];
  static const _lineAlphas = [0.38, 0.92, 0.52];
  static const _lineWidths = [1.8, 2.4, 1.8];

  final Color color;
  final bool active;
  final bool cancelArmed;
  final double volume;
  final double flowOffset;

  _XiaomiVoiceWavePainter({
    required this.color,
    required this.active,
    this.cancelArmed = false,
    required this.volume,
    required this.flowOffset,
  });

  /// 两端收敛：中间振幅最大，左右端点贴在中线（模仿 convergenFunction）。
  double _convergeEnvelope(int index, int count) {
    final mid = (count - 1) / 2.0;
    final dist = (index - mid).abs();
    return (1 - dist / mid).clamp(0.0, 1.0);
  }

  double _waveOffset(int lineIndex) {
    return _linePhaseOffsets[lineIndex];
  }

  double _calcY({
    required double x,
    required double timeOffset,
    required double envelope,
    required double shakeRatio,
    required double linePhase,
    required double centerY,
    required double amplitude,
  }) {
    final rad = x * math.pi / 180 + linePhase;
    final fx = math.sin(rad + timeOffset);
    return centerY - fx * envelope * shakeRatio * amplitude;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final centerY = size.height * 0.5;
    final dx = size.width / (_pointCount - 1);
    final timeOffset = flowOffset;
    // 退出阶段仍用衰减中的 volume 驱动，使声纹随转场自然缩小而非瞬间归零。
    final level = volume.clamp(0.0, 1.0);
    final amplitude =
        size.height * 0.42 * (cancelArmed ? math.max(level, 0.28) : level);
    final visibility = (0.15 + 0.85 * level).clamp(0.0, 1.0);

    // 退出且已衰减到 0 时不再绘制静止基线，避免转场中残留一条横线。
    if (level < 0.015 && !active) return;

    if (level < 0.015) {
      final idlePaint = Paint()
        ..color = color.withValues(alpha: cancelArmed ? 0.78 : 0.22)
        ..strokeWidth = cancelArmed ? 2.0 : 1.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(0, centerY),
        Offset(size.width, centerY),
        idlePaint,
      );
      return;
    }

    for (var line = 0; line < 3; line++) {
      final alphaBoost = cancelArmed ? 1.18 : 1.0;
      final paint = Paint()
        ..color = color.withValues(
          alpha: (_lineAlphas[line] * visibility * alphaBoost).clamp(0.0, 1.0),
        )
        ..strokeWidth = _lineWidths[line]
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      final path = Path();
      for (var i = 0; i < _pointCount; i++) {
        final x = dx * i;
        final y = _calcY(
          x: x,
          timeOffset: timeOffset,
          envelope: _convergeEnvelope(i, _pointCount),
          shakeRatio: _shakeRatios[line],
          linePhase: _waveOffset(line),
          centerY: centerY,
          amplitude: amplitude,
        );
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _XiaomiVoiceWavePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.active != active ||
        oldDelegate.cancelArmed != cancelArmed ||
        oldDelegate.volume != volume ||
        (oldDelegate.flowOffset - flowOffset).abs() > 0.001;
  }
}

/// 长按区域：空输入时长按说话、松手结束；有字时长按留给 [TextField] 编辑菜单。

class AgentVoiceHoldDetector extends StatefulWidget {
  final bool enabled;

  final bool listening;

  final TextEditingController textController;

  final AppColorScheme colors;

  final Widget child;

  final FocusNode? focusNode;

  final Future<bool> Function() onHoldStart;

  final Future<void> Function() onHoldEnd;

  final Future<void> Function() onHoldCancel;

  final VoiceHoldVisualChanged? onVisualChanged;

  final double interiorHeight;

  const AgentVoiceHoldDetector({
    super.key,

    required this.enabled,

    required this.listening,

    required this.textController,

    required this.colors,

    this.focusNode,

    required this.child,

    required this.onHoldStart,

    required this.onHoldEnd,

    required this.onHoldCancel,

    this.onVisualChanged,

    this.interiorHeight = 44,
  });

  @override
  State<AgentVoiceHoldDetector> createState() => _AgentVoiceHoldDetectorState();
}

class _AgentVoiceHoldDetectorState extends State<AgentVoiceHoldDetector> {
  static const _cancelDragSlop = 48.0;
  static const _longPressDelay = VoiceComposerMotion.longPressDelay;
  static const _longPressSlop = 18.0;

  bool _holdStarted = false;
  bool _cancelArmed = false;
  bool _startFailed = false;
  bool _finishing = false;
  // 松手后让语音态（转写/外框）短暂停留再收起，避免识别结果一闪而过。
  bool _keepVisual = false;
  Timer? _dismissTimer;
  // 取消判定改用全局坐标：按下点全局位置 + 最近一次 move 的全局 y。
  // 这样即使手指滑出组件边界（组件仅 ~44-64px 高），仍能可靠触发“上滑取消”。
  Offset? _downGlobal;
  double? _lastMoveDy;
  int? _trackedPointer;
  Future<bool>? _pendingStart;
  Timer? _longPressTimer;
  Offset? _pendingDownLocal;

  bool get _showVoiceUi => widget.listening || _holdStarted;

  bool get _canHoldStart {
    if (!widget.enabled) return false;
    final hasText = widget.textController.text.trim().isNotEmpty;
    return !hasText || widget.listening;
  }

  bool get _voiceHoldCapture =>
      widget.enabled && _canHoldStart && !widget.listening && !_holdStarted;

  bool get _voiceHoldTracking => _holdStarted || widget.listening;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant AgentVoiceHoldDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.listening && !_holdStarted) {
      _resetLocalHold(notify: false);
      _notifyVisual();
    } else if (oldWidget.listening != widget.listening ||
        oldWidget.enabled != widget.enabled) {
      _notifyVisual();
    }
  }

  @override
  void dispose() {
    _removeTrackingRoute();
    _longPressTimer?.cancel();
    _dismissTimer?.cancel();
    _dismissTimer = null;
    super.dispose();
  }

  void _deliverVisual() {
    final cb = widget.onVisualChanged;
    if (cb == null || !mounted) return;
    cb(
      active: _showVoiceUi || _keepVisual,
      cancelArmed: _cancelArmed,
      arming: _holdStarted && !widget.listening && !_startFailed,
      startFailed: _startFailed,
      waveActive: _showVoiceUi,
    );
  }

  void _notifyVisual({bool urgent = false}) {
    if (urgent) {
      _deliverVisual();
      return;
    }
    final cb = widget.onVisualChanged;
    if (cb == null) return;

    void deliver() => _deliverVisual();

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      deliver();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => deliver());
  }

  void _resetLocalHold({bool notify = true}) {
    _holdStarted = false;
    _cancelArmed = false;
    _startFailed = false;
    _keepVisual = false;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _downGlobal = null;
    _lastMoveDy = null;
    _pendingStart = null;
    if (notify) _notifyVisual(urgent: true);
  }

  void _updateCancelArmed() {
    if (_downGlobal == null || _lastMoveDy == null || !_voiceHoldTracking) {
      return;
    }
    // 全局坐标差值判定：手指相对按下点向上移动超过阈值即进入“上滑取消”。
    final nextCancel = (_lastMoveDy! - _downGlobal!.dy) < -_cancelDragSlop;

    if (nextCancel != _cancelArmed) {
      _cancelArmed = nextCancel;
      if (nextCancel) HapticFeedback.selectionClick();
      if (mounted) setState(() {});
      _notifyVisual(urgent: true);
    }
  }

  void _removeTrackingRoute() {
    if (_trackedPointer != null) {
      GestureBinding.instance.pointerRouter.removeRoute(
        _trackedPointer!,
        _handleTrackedPointer,
      );
      _trackedPointer = null;
    }
  }

  // 全局指针路由：从按下起接管该 pointer 的所有 move/up/cancel 事件，
  // 即使手指滑出组件边界也能持续上报，从而可靠触发“上滑取消”。
  void _handleTrackedPointer(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _lastMoveDy = event.position.dy;
      if (_voiceHoldTracking) {
        _updateCancelArmed();
      } else if (_downGlobal != null &&
          (event.position - _downGlobal!).distance > _longPressSlop) {
        _cancelPendingLongPress();
      }
    } else if (event is PointerUpEvent) {
      _removeTrackingRoute();
      if (_voiceHoldTracking) {
        unawaited(_finishHold(cancel: _cancelArmed));
      } else {
        _cancelPendingLongPress();
      }
    } else if (event is PointerCancelEvent) {
      _removeTrackingRoute();
      if (_voiceHoldTracking) {
        unawaited(_finishHold(cancel: true));
      } else {
        _cancelPendingLongPress();
      }
    }
  }

  void _cancelPendingLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _pendingDownLocal = null;
    _removeTrackingRoute();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_voiceHoldCapture) return;
    _downGlobal = event.position;
    _lastMoveDy = event.position.dy;
    _pendingDownLocal = event.localPosition;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDelay, () {
      _longPressTimer = null;
      if (!mounted || _pendingDownLocal == null) return;
      _onLongPressStart();
    });
    // 关键修复：按下即注册全局指针路由，使后续事件在手指滑出组件后仍可被处理。
    GestureBinding.instance.pointerRouter.addRoute(
      event.pointer,
      _handleTrackedPointer,
    );
    _trackedPointer = event.pointer;
  }

  void _onLongPressStart() {
    if (!widget.enabled || !_canHoldStart || widget.listening) return;

    // 若还在上一轮松手后的停留期内，立即清掉停留计时器，避免随后误触发收起。
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _keepVisual = false;
    _pendingDownLocal = null;
    unawaited(AgentVoiceService.instance.warmUp());
    _holdStarted = true;
    HapticFeedback.lightImpact();
    FocusManager.instance.primaryFocus?.unfocus();
    _notifyVisual(urgent: true);
    if (mounted) setState(() {});
    unawaited(_armHold());
  }

  Future<void> _armHold() async {
    if (!mounted || !_holdStarted || !_canHoldStart) return;

    final pending = widget.onHoldStart();
    _pendingStart = pending;
    final ok = await pending;
    if (!mounted || !_holdStarted) return;

    if (!ok) {
      if (_holdStarted) {
        _startFailed = true;
        if (mounted) setState(() {});
        _notifyVisual();
      } else {
        _resetLocalHold();
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _finishHold({required bool cancel}) async {
    // 防止全局路由与（边界内）Listener 同时触发 up 导致重复收尾。
    if (_finishing) return;
    _finishing = true;
    try {
      final wasStarted = _holdStarted || widget.listening;
      final pending = _pendingStart;
      final startFailed = _startFailed;

      // 先复位内部状态（允许立即发起新一轮长按），但让语音视觉停留一小段，
      // 使识别结果可读，随后再经 switchOut 柔和收起。
      _resetLocalHold(notify: false);
      _keepVisual = true;
      _dismissTimer?.cancel();
      _dismissTimer = Timer(const Duration(milliseconds: 320), () {
        _dismissTimer = null;
        _keepVisual = false;
        if (mounted) _notifyVisual(urgent: true);
      });
      if (mounted) setState(() {});

      if (!wasStarted) return;

      if (startFailed || cancel) {
        if (pending != null) await pending;
        await widget.onHoldCancel();
        return;
      }

      if (pending != null) await pending;
      await widget.onHoldEnd();
    } finally {
      _finishing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final effects = AppLifecycleGate.effectsEnabled;
    final switchDuration = effects
        ? VoiceComposerMotion.switchIn
        : Duration.zero;
    final switchReverseDuration = effects
        ? VoiceComposerMotion.switchOut
        : Duration.zero;

    final voiceInterior = SizedBox(
      key: const ValueKey('voice-interior'),
      height: widget.interiorHeight,
      child: VoiceInputWaveInterior(
        active: widget.listening || _holdStarted,
        cancelArmed: _cancelArmed,
        startFailed: _startFailed,
        colors: widget.colors,
      ),
    );

    final inputChild = KeyedSubtree(
      key: const ValueKey('composer-input'),
      child: widget.child,
    );

    final content = ClipRect(
      child: AnimatedSize(
        duration: switchDuration,
        reverseDuration: switchReverseDuration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        clipBehavior: Clip.hardEdge,
        child: AnimatedSwitcher(
          duration: switchDuration,
          reverseDuration: switchReverseDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.hardEdge,
              children: [...previousChildren, ?currentChild],
            );
          },
          transitionBuilder: (child, animation) {
            if (!effects) return child;
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
            );
            return FadeTransition(opacity: curved, child: child);
          },
          child: _showVoiceUi ? voiceInterior : inputChild,
        ),
      ),
    );

    // 空输入时长按：Listener 仅负责按下起手，后续 move/up/cancel 由全局指针路由接管，
    // 短按仍交给 TextField（Listener 不抢占手势竞技场）。
    final ignoreChild = _voiceHoldTracking;
    final listenForHold = _voiceHoldCapture || _voiceHoldTracking;

    return Listener(
      behavior: listenForHold
          ? HitTestBehavior.translucent
          : HitTestBehavior.deferToChild,
      onPointerDown: _onPointerDown,
      child: IgnorePointer(ignoring: ignoreChild, child: content),
    );
  }
}
