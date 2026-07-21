import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 应用前后台状态：暂停滚动/重任务，并在切走时关闭昂贵渲染（模糊、Ticker）。
class AppLifecycleGate extends ChangeNotifier {
  AppLifecycleGate._();

  static final AppLifecycleGate instance = AppLifecycleGate._();

  bool _isActive = true;

  static bool get isActive => instance._isActive;

  /// 应用处于前台且可渲染昂贵特效（毛玻璃等）时为 true。
  /// 仅在 paused / hidden / detached 时置 false；inactive 过渡态保持，避免回前台特效丢失。
  static bool get effectsEnabled => instance._isActive;

  static void setActive(bool active) {
    instance._setActive(active);
  }

  void _setActive(bool active) {
    if (_isActive == active) return;
    _isActive = active;
    if (active) {
      notifyListeners();
      return;
    }
    // 退后台时延后通知，避免和系统退出动画抢主线程。
    SchedulerBinding.instance.scheduleTask(() {
      if (!_isActive) notifyListeners();
    }, Priority.idle);
  }
}

/// 在 App 退到后台时暂停其子树内所有 Ticker（动画 / 逐帧重绘），
/// 回到前台自动恢复。仅后台生效，对用户完全不可见。
///
/// 用法：包裹需要被门控的动画子树，例如常驻陪伴层、语音面板。
class LifecycleTickerGate extends StatefulWidget {
  final Widget child;

  const LifecycleTickerGate({super.key, required this.child});

  @override
  State<LifecycleTickerGate> createState() => _LifecycleTickerGateState();
}

class _LifecycleTickerGateState extends State<LifecycleTickerGate> {
  @override
  void initState() {
    super.initState();
    AppLifecycleGate.instance.addListener(_onLifecycleChanged);
  }

  @override
  void dispose() {
    AppLifecycleGate.instance.removeListener(_onLifecycleChanged);
    super.dispose();
  }

  void _onLifecycleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return TickerMode(enabled: AppLifecycleGate.isActive, child: widget.child);
  }
}
