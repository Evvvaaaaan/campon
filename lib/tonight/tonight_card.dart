/// 홈 최상단의 "오늘 밤 지수" 카드.
///
/// 왜 하필 지금 캠핑을 가야 하는지를 숫자로 보여준다. 계산에 실패해도
/// 달 정보만으로 카드를 채우고, 절대 에러 상자를 띄우지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../motion/motion.dart';
import '../theme.dart';
import 'night_models.dart';
import 'night_visuals.dart';
import 'tonight_service.dart';

typedef NightPreviewRequested =
    void Function(NightSky night, String place, int? myTempC);

class TonightCard extends StatefulWidget {
  const TonightCard({
    required this.regionName,
    required this.lat,
    required this.lon,
    required this.onExplore,
    required this.onPreview,
    this.service,
    this.destinationLoader,
    super.key,
  });

  final String regionName;
  final double lat;
  final double lon;
  final VoidCallback onExplore;
  final NightPreviewRequested onPreview;
  final TonightService? service;

  /// 그 지역의 대표 캠핑장 이름을 가져온다. 실패하면 지역명을 쓴다.
  final Future<String?> Function()? destinationLoader;

  @override
  State<TonightCard> createState() => _TonightCardState();
}

class _TonightCardState extends State<TonightCard> {
  late final TonightService _service = widget.service ?? TonightService();
  TonightForecast? _forecast;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TonightCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lat != widget.lat || oldWidget.lon != widget.lon) {
      setState(() => _forecast = null);
      _load();
    }
  }

  Future<void> _load() async {
    final forecast = await _service.load(lat: widget.lat, lon: widget.lon);
    if (!mounted) return;
    setState(() => _forecast = forecast);

    // 캠핑장 이름과 현재 위치 기온은 곁들이는 정보다. 카드가 먼저 뜬 뒤에 채운다.
    await Future.wait([_fillDestination(), _fillMyTemperature()]);
  }

  Future<void> _fillDestination() async {
    final loader = widget.destinationLoader;
    if (loader == null) return;
    final name = await loader();
    if (!mounted || name == null || name.isEmpty) return;
    setState(() => _forecast = _forecast?.copyWith(destinationName: name));
  }

  Future<void> _fillMyTemperature() async {
    final temperature = await _service.myTemperature();
    if (!mounted || temperature == null) return;
    setState(() => _forecast = _forecast?.copyWith(myTempC: temperature));
  }

  String get _place =>
      _forecast?.destinationName ?? '${widget.regionName} 밤하늘';

  @override
  Widget build(BuildContext context) {
    final forecast = _forecast;
    if (forecast == null) {
      return const Shimmer(height: 268);
    }
    return _NightCardBody(
      forecast: forecast,
      place: _place,
      onExplore: widget.onExplore,
      onPreview: () =>
          widget.onPreview(forecast.best, _place, forecast.myTempC),
    ).animate().fadeIn(duration: 420.ms).slideY(
      begin: 0.06,
      end: 0,
      duration: 420.ms,
      curve: Curves.easeOutCubic,
    );
  }
}

class _NightCardBody extends StatelessWidget {
  const _NightCardBody({
    required this.forecast,
    required this.place,
    required this.onExplore,
    required this.onPreview,
  });

  final TonightForecast forecast;
  final String place;
  final VoidCallback onExplore;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final night = forecast.best;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [NightPalette.deep, NightPalette.haze],
                ),
              ),
            ),
          ),
          const Positioned.fill(child: StarField()),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _ScoreBadge(night: night)),
                    MoonGlyph(illumination: night.moonIlluminationPct / 100),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  night.grade.headline,
                  style: CampText.display.copyWith(
                    fontSize: 25,
                    height: 1.2,
                    color: NightPalette.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_formatNight(night.date)} · $place',
                  style: CampText.captionStrong.copyWith(
                    color: NightPalette.textMuted,
                  ),
                ),
                const SizedBox(height: 14),
                _MetricRow(night: night),
                if (forecast.myTempC != null && night.nightLowC != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '지금 계신 곳 ${forecast.myTempC}℃ · '
                    '그날 밤 거기 ${night.nightLowC}℃',
                    style: CampText.caption.copyWith(
                      fontSize: 12.5,
                      color: NightPalette.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _RarityLine(count: forecast.darkSaturdayNightsLeft),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _NightButton(
                        label: '이 밤 미리 보기',
                        icon: LucideIcons.moonStar,
                        onPressed: onPreview,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _NightTextButton(label: '캠핑장 보기', onPressed: onExplore),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.night});

  final NightSky night;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: CampColors.primary.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            night.grade.badge,
            style: CampText.finePrint.copyWith(
              fontWeight: FontWeight.w700,
              color: CampColors.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${night.score}',
          style: CampText.display.copyWith(
            fontSize: 30,
            color: NightPalette.text,
          ),
        ),
        Text(
          ' / 100',
          style: CampText.finePrint.copyWith(color: NightPalette.textMuted),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.night});

  final NightSky night;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      if (night.cloudPct != null) '구름 ${night.cloudPct}%',
      night.moonlessEnough ? '달 없음' : '달빛 ${night.moonInterferencePct}%',
      if (night.windMs != null) '바람 ${night.windMs}m/s',
      if (night.nightLowC != null) '밤 ${night.nightLowC}℃',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final chip in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: NightPalette.mid.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: NightPalette.textMuted.withValues(alpha: 0.28),
              ),
            ),
            child: Text(
              chip,
              style: CampText.finePrint.copyWith(
                fontWeight: FontWeight.w600,
                color: NightPalette.text,
              ),
            ),
          ),
      ],
    );
  }
}

class _RarityLine extends StatelessWidget {
  const _RarityLine({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(LucideIcons.sparkles, size: 14, color: CampColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '올해 남은 달 없는 토요일 밤 — $count번',
            style: CampText.captionStrong.copyWith(
              fontSize: 12.5,
              color: CampColors.amberTint,
            ),
          ),
        ),
      ],
    );
  }
}

class _NightButton extends StatelessWidget {
  const _NightButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: CampColors.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: CampColors.onPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: CampText.button.copyWith(color: CampColors.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _NightTextButton extends StatelessWidget {
  const _NightTextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: NightPalette.textMuted.withValues(alpha: 0.45),
          ),
        ),
        child: Text(
          label,
          style: CampText.button.copyWith(
            fontSize: 13.5,
            color: NightPalette.text,
          ),
        ),
      ),
    );
  }
}

const _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];

String _formatNight(DateTime date) =>
    '${date.month}월 ${date.day}일 ${_weekdayNames[date.weekday - 1]}요일 밤';
