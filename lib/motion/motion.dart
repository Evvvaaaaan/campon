import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme.dart';

/// Column whose children fade+slide in one after another (staggered reveal).
Widget revealColumn({
  required List<Widget> children,
  Duration stagger = const Duration(milliseconds: 90),
  double spacing = 16,
}) {
  final items = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    items.add(
      children[i]
          .animate()
          .fadeIn(duration: 360.ms, delay: stagger * i)
          .slideY(
            begin: 0.12,
            end: 0,
            duration: 360.ms,
            delay: stagger * i,
            curve: Curves.easeOutCubic,
          ),
    );
    if (i != children.length - 1) items.add(SizedBox(height: spacing));
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items);
}

/// Loading skeleton block with a sweeping shimmer.
class Shimmer extends StatelessWidget {
  const Shimmer({super.key, required this.height, this.width});
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: CampColors.greenTint,
        borderRadius: BorderRadius.circular(12),
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(
          duration: 1200.ms,
          color: CampColors.surface.withValues(alpha: 0.6),
        );
  }
}

/// Wraps a tappable widget with a subtle scale-down press feedback.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.behavior,
  });
  final Widget child;
  final VoidCallback onTap;

  /// 배경색 없는 자식을 감쌀 때 [HitTestBehavior.opaque]를 준다.
  /// 기본값(deferToChild)에서는 글자만 있는 줄이 탭을 받지 못한다.
  final HitTestBehavior? behavior;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  double _scale = 1;

  void _set(double v) {
    if (mounted) setState(() => _scale = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _set(0.96),
      onTapUp: (_) => _set(1),
      onTapCancel: () => _set(1),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 110),
        child: widget.child,
      ),
    );
  }
}
