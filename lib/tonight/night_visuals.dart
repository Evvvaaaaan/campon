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

/// 옆으로 천천히 흘러가는 안개 띠.
///
/// [StarField]와 같은 이유로 [driftCycles]번만 돌고 멈춘다. 주기가 정수라
/// 마지막 프레임이 첫 프레임과 같아 멈출 때 튀지 않는다.
class DriftingFog extends StatefulWidget {
  const DriftingFog({
    super.key,
    this.color = NightPalette.star,
    this.driftCycles = 2,
  });

  final Color color;
  final int driftCycles;

  @override
  State<DriftingFog> createState() => _DriftingFogState();
}

class _DriftingFogState extends State<DriftingFog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(seconds: 8 * widget.driftCycles),
  )..forward();

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
        painter: _FogPainter(
          _controller.value * widget.driftCycles,
          widget.color,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _FogPainter extends CustomPainter {
  const _FogPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 두 겹이 서로 다른 속도로 흘러야 납작한 띠가 아니라 안개처럼 보인다.
    void band(double centerY, double rx, double ry, double speed, double alpha) {
      final shift = math.sin((progress + speed) * 2 * math.pi) * size.width * 0.12;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.5 + shift, centerY),
          width: rx * 2,
          height: ry * 2,
        ),
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }

    band(size.height * 0.45, size.width * 0.34, size.height * 0.30, 0, 0.20);
    band(size.height * 0.66, size.width * 0.42, size.height * 0.24, 0.4, 0.12);
  }

  @override
  bool shouldRepaint(_FogPainter old) => old.progress != progress;
}

/// 흔들리는 모닥불과 그 아래 번지는 잔광.
class Campfire extends StatefulWidget {
  const Campfire({
    super.key,
    this.size = 30,
    this.flickerCycles = 6,
    this.flameColor = const Color(0xFFE8944A),
  });

  final double size;
  final int flickerCycles;
  final Color flameColor;

  @override
  State<Campfire> createState() => _CampfireState();
}

class _CampfireState extends State<Campfire>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 1600 * widget.flickerCycles),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final phase = _controller.value * widget.flickerCycles * 2 * math.pi;
        final flicker = 0.85 + 0.15 * math.sin(phase);
        final glow = 0.55 + 0.45 * math.sin(phase * 0.75);
        return SizedBox(
          width: widget.size * 4,
          height: widget.size * 2.2,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 0,
                child: Container(
                  width: widget.size * 4,
                  height: widget.size * 1.2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.flameColor.withValues(alpha: 0.55 * glow),
                        widget.flameColor.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.7],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: widget.size * 0.35,
                child: Transform.scale(
                  scaleY: flicker,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
      child: CustomPaint(
        size: Size(widget.size * 0.88, widget.size),
        painter: _FlamePainter(widget.flameColor),
      ),
    );
  }
}

class _FlamePainter extends CustomPainter {
  const _FlamePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 디자인 SVG(24×24 viewBox)의 불꽃 경로를 옮긴 것.
    final s = size.width / 24;
    final path = Path()
      ..moveTo(12 * s, 2 * s)
      ..cubicTo(12 * s, 2 * s, 6 * s, 9 * s, 6 * s, 14 * s)
      ..arcToPoint(
        Offset(18 * s, 14 * s),
        radius: Radius.circular(6 * s),
        clockwise: false,
      )
      ..cubicTo(18 * s, 11 * s, 16 * s, 9 * s, 15 * s, 7 * s)
      ..cubicTo(15 * s, 9 * s, 14 * s, 10 * s, 13 * s, 10 * s)
      ..cubicTo(12 * s, 10 * s, 12 * s, 8 * s, 12 * s, 6 * s)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.color != color;
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
