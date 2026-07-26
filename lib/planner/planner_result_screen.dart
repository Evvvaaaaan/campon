import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../motion/motion.dart';
import '../theme.dart';
import 'plan_models.dart';

class PlannerResultScreen extends StatelessWidget {
  const PlannerResultScreen({
    required this.plan,
    required this.onSendToChecklist,
    required this.onBack,
    this.onRegenerate,
    super.key,
  });

  final CampPlan plan;
  final void Function(List<String> items) onSendToChecklist;
  final VoidCallback onBack;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _Header(onBack: onBack, onRegenerate: onRegenerate),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: revealColumn(
                children: [
                  _SummaryCard(summary: plan.summary),
                  _WeatherCard(weather: plan.weather),
                  _CampsitesCard(campsites: plan.campsites),
                  _ChecklistCard(checklist: plan.checklist),
                  _TimelineCard(timeline: plan.timeline),
                ],
              ),
            ),
          ),
          _BottomBar(
            onSend: () =>
                onSendToChecklist(plan.checklist.expand((c) => c.items).toList()),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack, this.onRegenerate});
  final VoidCallback onBack;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 16, 8),
      child: Row(
        children: [
          _circleButton(icon: LucideIcons.chevronLeft, onTap: onBack, tooltip: '뒤로'),
          const SizedBox(width: 12),
          Text('AI 캠핑 플랜', style: CampText.tagline),
          const Spacer(),
          if (onRegenerate != null)
            _circleButton(
                icon: LucideIcons.refreshCw, onTap: onRegenerate!, tooltip: '다시 만들기'),
        ],
      ),
    );
  }
}

Widget _circleButton({
  required IconData icon,
  required VoidCallback onTap,
  required String tooltip,
}) {
  return Pressable(
    onTap: onTap,
    child: Tooltip(
      message: tooltip,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: CampColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: CampColors.hairline),
        ),
        child: Icon(icon, size: 20, color: CampColors.ink),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.background = CampColors.surface});
  final Widget child;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: CampColors.hairline),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: CampColors.shadow, blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: child,
    );
  }
}

class _CardLabel extends StatelessWidget {
  const _CardLabel({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: CampColors.greenTint,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 18, color: CampColors.forest),
        ),
        const SizedBox(width: 10),
        Text(text, style: CampText.sectionTitle),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final PlanSummary summary;

  @override
  Widget build(BuildContext context) {
    return _Card(
      background: CampColors.forest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: CampColors.onPrimary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.sparkles, size: 14, color: CampColors.onPrimary),
                const SizedBox(width: 6),
                Text(summary.mood,
                    style: CampText.captionStrong.copyWith(color: CampColors.onPrimary)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(summary.title,
              style: CampText.display.copyWith(color: CampColors.onPrimary, fontSize: 26)),
          const SizedBox(height: 10),
          Text(summary.oneLiner,
              style: CampText.body.copyWith(
                  color: CampColors.onPrimary.withValues(alpha: 0.86))),
        ],
      ),
    );
  }
}

Color _gradeColor(WeatherGrade g) => switch (g) {
      WeatherGrade.good => CampColors.forest,
      WeatherGrade.caution => CampColors.primary,
      WeatherGrade.risk => const Color(0xFFB23A2E),
    };

String _gradeLabel(WeatherGrade g) => switch (g) {
      WeatherGrade.good => '캠핑 좋음',
      WeatherGrade.caution => '주의',
      WeatherGrade.risk => '위험',
    };

IconData _gradeIcon(WeatherGrade g) => switch (g) {
      WeatherGrade.good => LucideIcons.sun,
      WeatherGrade.caution => LucideIcons.cloudSun,
      WeatherGrade.risk => LucideIcons.cloudLightning,
    };

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.weather});
  final PlanWeather weather;

  @override
  Widget build(BuildContext context) {
    final color = _gradeColor(weather.grade);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _CardLabel(icon: LucideIcons.thermometer, text: '캠핑 날씨'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_gradeIcon(weather.grade), size: 14, color: color),
                    const SizedBox(width: 6),
                    Text(_gradeLabel(weather.grade),
                        style: CampText.captionStrong.copyWith(color: color)),
                  ],
                ),
              )
                  .animate()
                  .scaleXY(begin: 0.8, end: 1, duration: 320.ms, curve: Curves.easeOutBack)
                  .fadeIn(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _metric('야간최저', '${weather.nightLowC}°'),
              _metric('강수확률', '${weather.precipPct}%'),
              _metric('바람', '${weather.windMs}㎧'),
              _metric('일교차', '${weather.diurnalRangeC}°'),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CampColors.canvas,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(weather.advice, style: CampText.caption)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: CampText.tagline),
          const SizedBox(height: 4),
          Text(label, style: CampText.finePrint.copyWith(color: CampColors.inkMuted80)),
        ],
      ),
    );
  }
}

class _CampsitesCard extends StatelessWidget {
  const _CampsitesCard({required this.campsites});
  final List<PlanCampsite> campsites;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel(icon: LucideIcons.tent, text: '추천 캠핑장'),
          const SizedBox(height: 14),
          for (var i = 0; i < campsites.length; i++) ...[
            if (i != 0) const Divider(height: 24, color: CampColors.hairline),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CampColors.amberTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${i + 1}',
                      style: CampText.captionStrong.copyWith(color: CampColors.primaryDark)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(campsites[i].name, style: CampText.bodyStrong),
                      const SizedBox(height: 4),
                      Text(campsites[i].reason,
                          style: CampText.caption.copyWith(color: CampColors.inkMuted80)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.checklist});
  final List<PlanChecklistCategory> checklist;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel(icon: LucideIcons.listChecks, text: '스마트 준비물'),
          const SizedBox(height: 14),
          for (var i = 0; i < checklist.length; i++) ...[
            if (i != 0) const SizedBox(height: 14),
            Text(checklist[i].category, style: CampText.captionStrong),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in checklist[i].items)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: CampColors.greenTint,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(item, style: CampText.caption),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.timeline});
  final List<PlanTimelineItem> timeline;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel(icon: LucideIcons.clock, text: '하루 타임라인'),
          const SizedBox(height: 16),
          for (var i = 0; i < timeline.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(timeline[i].time,
                        style: CampText.captionStrong.copyWith(color: CampColors.primaryDark)),
                  ),
                  Column(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: CampColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: CampColors.surface, width: 2),
                        ),
                      ),
                      if (i != timeline.length - 1)
                        Expanded(child: Container(width: 2, color: CampColors.hairline)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: i == timeline.length - 1 ? 0 : 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(timeline[i].title, style: CampText.bodyStrong),
                          const SizedBox(height: 2),
                          Text(timeline[i].detail,
                              style: CampText.caption.copyWith(color: CampColors.inkMuted80)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onSend});
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: CampColors.canvas,
        border: Border(top: BorderSide(color: CampColors.hairline)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Pressable(
          onTap: onSend,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CampColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.listChecks, size: 18, color: CampColors.onPrimary),
                const SizedBox(width: 8),
                Text('체크리스트로 보내기',
                    style: CampText.button.copyWith(color: CampColors.onPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
