import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_fonts.dart';
import '../utils/agent_kaomoji_mood.dart';

/// AI 助手颜文字形象：随语境换表情，工作时逐字抖动。
class AgentKaomoji extends StatefulWidget {
  final AgentKaomojiMood mood;
  final double size;
  final bool shaking;
  final bool wiggling;
  final Color? color;

  const AgentKaomoji({
    super.key,
    required this.mood,
    this.size = 28,
    this.shaking = false,
    this.wiggling = false,
    this.color,
  });

  @override
  State<AgentKaomoji> createState() => _AgentKaomojiState();
}

class _AgentKaomojiState extends State<AgentKaomoji>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _syncShake();
  }

  @override
  void didUpdateWidget(covariant AgentKaomoji oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shaking != widget.shaking ||
        oldWidget.wiggling != widget.wiggling) {
      _syncShake();
    }
  }

  void _syncShake() {
    if (widget.shaking || widget.wiggling) {
      _shakeCtrl.repeat();
    } else {
      _shakeCtrl.stop();
      _shakeCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  TextStyle _faceStyle(Color color) {
    return AppFonts.body(color: color).copyWith(
      fontSize: widget.size,
      height: 1.1,
      letterSpacing: 0,
      fontFamily: null,
    );
  }

  List<String> _splitGlyphs(String face) {
    return face.runes.map((r) => String.fromCharCode(r)).toList();
  }

  Widget _buildFace(String face, Color color) {
    final style = _faceStyle(color);

    if (widget.wiggling) {
      return AnimatedBuilder(
        animation: _shakeCtrl,
        builder: (context, _) {
          final t = _shakeCtrl.value * math.pi * 2;
          final dx = math.sin(t * 2.8) * widget.size * 0.42;
          return Transform.translate(
            offset: Offset(dx, 0),
            child: Text(
              face,
              style: style,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
          );
        },
      );
    }

    final glyphs = _splitGlyphs(face);

    if (!widget.shaking) {
      return Text(
        face,
        style: style,
        textAlign: TextAlign.center,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
      );
    }

    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (context, _) {
        final t = _shakeCtrl.value * math.pi * 2;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(glyphs.length, (i) {
            final glyph = glyphs[i];
            final seed = i * 2.399 + glyph.codeUnitAt(0) * 0.013;
            final dx =
                math.sin(t * (2.6 + i * 0.29) + seed) * widget.size * 0.10;
            final dy =
                math.sin(t * (3.3 + i * 0.23) + seed * 1.4) *
                widget.size *
                0.08;
            final rot = math.sin(t * (2.1 + i * 0.37) + seed * 0.9) * 0.13;
            final scale =
                1.0 + math.sin(t * (1.7 + i * 0.19) + seed * 0.6) * 0.05;

            return Transform.translate(
              offset: Offset(dx, dy),
              child: Transform.rotate(
                angle: rot,
                child: Transform.scale(
                  scale: scale,
                  child: Text(glyph, style: style),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.onSurface;
    final face = widget.mood.face;

    Widget faceWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey(face), child: _buildFace(face, color)),
    );

    return faceWidget;
  }
}
