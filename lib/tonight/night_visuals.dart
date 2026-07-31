/// 밤 화면에서 함께 쓰는 시각 요소. 별빛과 달 모양.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class NightPalette {
  static const deep = Color(0xFF0B1512); // 자정에 가까운 숲의 검정
  static const mid = Color(0xFF16241D);
  static const haze = Color(0xFF24382C);
  static const star = Color(0xFFFBF8F0);
  static const text = Color(0xFFEFE9DA);
  static const textMuted = Color(0xFF9FB0A2);
}

/// 천천히 반짝이는 별밭. 같은 [seed]면 별 배치가 항상 같다.
///
/// 반짝임은 [twinkleCycles]번만 돌고 멈춘다. 화면에 영구히 도는 애니메이션을
/// 남기지 않기 위해서다(배터리, 그리고 테스트에서 화면이 안정되도록).
/// 주기 수가 정수라 마지막 프레임 밝기가 첫 프레임과 같아 끊김이 없다.
class StarField extends StatefulWidget {
  const StarField({
    super.key,
    this.starCount = 46,
    this.seed = 7,
    this.twinkleCycles = 3,
  });

  final int starCount;
  final int seed;
  final int twinkleCycles;

  @override
  State<StarField> createState() => _StarFieldState();
}

class _StarFieldState extends State<StarField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(seconds: 3 * widget.twinkleCycles),
  )..forward();

  late final List<_Star> _stars = _buildStars(widget.starCount, widget.seed);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _StarFieldPainter(
          _stars,
          _controller.value * widget.twinkleCycles,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _Star {
  const _Star(this.dx, this.dy, this.radius, this.phase);

  final double dx;
  final double dy;
  final double radius;
  final double phase;
}

List<_Star> _buildStars(int count, int seed) {
  final random = math.Random(seed);
  return List.generate(
    count,
    (_) => _Star(
      random.nextDouble(),
      random.nextDouble(),
      0.6 + random.nextDouble() * 1.4,
      random.nextDouble(),
    ),
  );
}

class _StarFieldPainter extends CustomPainter {
  const _StarFieldPainter(this.stars, this.progress);

  final List<_Star> stars;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = NightPalette.star;
    for (final star in stars) {
      final twinkle =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin((progress + star.phase) * 2 * math.pi));
      paint.color = NightPalette.star.withValues(alpha: twinkle * 0.8);
      canvas.drawCircle(
        Offset(star.dx * size.width, star.dy * size.height),
        star.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarFieldPainter old) => old.progress != progress;
}

/// 실제 조도만큼 차오른 달. [illumination]은 0(삭)~1(보름).
class MoonGlyph extends StatelessWidget {
  const MoonGlyph({required this.illumination, this.size = 34, super.key});

  final double illumination;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MoonPainter(illumination.clamp(0.0, 1.0)),
    );
  }
}

class _MoonPainter extends CustomPainter {
  const _MoonPainter(this.illumination);

  final double illumination;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()..color = NightPalette.star.withValues(alpha: 0.14),
    );
    if (illumination <= 0.02) return;

    // 밝은 면은 원판에서 타원을 깎아 만든다. 조도가 0.5면 반원, 1이면 원판 전체.
    final lit = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi,
      )
      ..close();
    final terminatorWidth = radius * (1 - 2 * illumination).abs();
    final terminator = Path()
      ..addOval(
        Rect.fromCenter(
          center: center,
          width: terminatorWidth * 2,
          height: radius * 2,
        ),
      );
    final shape = illumination < 0.5
        ? Path.combine(PathOperation.difference, lit, terminator)
        : Path.combine(PathOperation.union, lit, terminator);

    canvas.drawPath(shape, Paint()..color = NightPalette.star);
  }

  @override
  bool shouldRepaint(_MoonPainter old) => old.illumination != illumination;
}
