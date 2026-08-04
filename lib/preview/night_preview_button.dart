/// 캠핑장 상세에서 그 캠핑장의 밤을 여는 버튼.
///
/// 탭한 순간에만 좌표 기준 밤 예보를 계산한다. 상세 화면을 열 때마다
/// 네트워크를 쓰지 않기 위해서다.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../motion/motion.dart';
import '../theme.dart';
import '../tonight/night_models.dart';
import '../tonight/tonight_service.dart';
import 'night_preview_screen.dart';
import 'preview_models.dart';
import 'preview_service.dart';

class NightPreviewButton extends StatefulWidget {
  const NightPreviewButton({
    required this.placeName,
    required this.lat,
    required this.lon,
    required this.actionLabel,
    required this.onAction,
    this.people = 2,
    this.experience = '초보',
    this.tonightService,
    this.previewService,
    super.key,
  });

  final String placeName;
  final double lat;
  final double lon;
  final String actionLabel;
  final VoidCallback onAction;
  final int people;
  final String experience;
  final TonightService? tonightService;
  final PreviewService? previewService;

  @override
  State<NightPreviewButton> createState() => _NightPreviewButtonState();
}

class _NightPreviewButtonState extends State<NightPreviewButton> {
  late final TonightService _tonight = widget.tonightService ?? TonightService();
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    final forecast = await _tonight.load(lat: widget.lat, lon: widget.lon);
    if (!mounted) return;
    setState(() => _opening = false);
    await openNightPreview(
      context,
      input: _inputFor(forecast.best),
      actionLabel: widget.actionLabel,
      onAction: widget.onAction,
      service: widget.previewService,
    );
  }

  PreviewInput _inputFor(NightSky night) => PreviewInput(
    place: widget.placeName,
    date: night.date,
    moonIlluminationPct: night.moonIlluminationPct,
    moonInterferencePct: night.moonInterferencePct,
    score: night.score,
    grade: night.grade.name,
    people: widget.people,
    experience: widget.experience,
    cloudPct: night.cloudPct,
    precipPct: night.precipPct,
    windMs: night.windMs,
    nightLowC: night.nightLowC,
  );

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: _open,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF0B1512), Color(0xFF24382C)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.moonStar,
              size: 22,
              color: CampPalette.light.amberTint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '그날 밤 미리 보기',
                    style: CampText.bodyStrong.copyWith(
                      color: const Color(0xFFEFE9DA),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '실제 날씨와 달을 기준으로 그 밤의 장면을 보여드려요.',
                    style: CampText.finePrint.copyWith(
                      height: 1.4,
                      color: const Color(0xFF9FB0A2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (_opening)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CampPalette.light.amberTint,
                ),
              )
            else
              const Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: Color(0xFF9FB0A2),
              ),
          ],
        ),
      ),
    );
  }
}
