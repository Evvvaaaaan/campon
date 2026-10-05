import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../motion/motion.dart';
import '../theme.dart';
import 'plan_models.dart';
import 'plan_service.dart';

class PlannerInputScreen extends StatefulWidget {
  const PlannerInputScreen({
    required this.prefill,
    required this.onGenerated,
    required this.onBack,
    this.onEditConditions,
    this.service,
    super.key,
  });

  final PlanInput prefill;
  final void Function(CampPlan plan) onGenerated;
  final VoidCallback onBack;

  /// 지역·날짜·인원 같은 조건을 고칠 수 있게 한다. 조건은 셸이 들고 있으므로
  /// 고치는 화면도 셸이 띄우고, 여기서는 새 [prefill]로 다시 그려질 뿐이다.
  final VoidCallback? onEditConditions;
  final PlanService? service;

  @override
  State<PlannerInputScreen> createState() => _PlannerInputScreenState();
}

class _PlannerInputScreenState extends State<PlannerInputScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.prefill.query);
  late final PlanService _service = widget.service ?? PlanService();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _defaultQuery() {
    final p = widget.prefill;
    final car = p.hasCar ? '오토캠핑' : '캠핑';
    return '${p.region} ${p.people}명 ${p.experience} $car';
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    final text = _controller.text.trim();
    final input = PlanInput(
      query: text.isEmpty ? _defaultQuery() : text,
      date: widget.prefill.date,
      people: widget.prefill.people,
      hasCar: widget.prefill.hasCar,
      experience: widget.prefill.experience,
      region: widget.prefill.region,
      lat: widget.prefill.lat,
      lon: widget.prefill.lon,
      preferences: widget.prefill.preferences,
      equipment: widget.prefill.equipment,
      candidates: widget.prefill.candidates,
    );
    final plan = await _service.generate(input);
    if (mounted) widget.onGenerated(plan);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.prefill;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 16, 8),
            child: Row(
              children: [
                Pressable(
                  onTap: widget.onBack,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: CampColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: CampColors.hairline),
                    ),
                    child: Icon(LucideIcons.chevronLeft,
                        size: 20, color: CampColors.ink),
                  ),
                ),
                const SizedBox(width: 12),
                Text('AI 플래너', style: CampText.tagline),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? _GeneratingView()
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: revealColumn(
                      children: [
                        _IntroCard(),
                        _ContextChips(
                          input: p,
                          onEdit: widget.onEditConditions,
                        ),
                        _QueryField(controller: _controller, hint: _defaultQuery()),
                      ],
                    ),
                  ),
          ),
          if (!_loading)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: CampColors.canvas,
                border: Border(top: BorderSide(color: CampColors.hairline)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: Pressable(
                  onTap: _generate,
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
                        Icon(LucideIcons.sparkles,
                            size: 18, color: CampColors.onPrimary),
                        const SizedBox(width: 8),
                        Text('플랜 생성',
                            style: CampText.button.copyWith(color: CampColors.onPrimary)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: CampColors.forest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('한 줄이면 충분해요',
                    style: CampText.display
                        .copyWith(color: CampColors.onPrimary, fontSize: 24)),
                const SizedBox(height: 10),
                Text('원하는 캠핑을 자유롭게 적어주세요.\n캠핑장·날씨·준비물·타임라인을 한 번에 만들어 드릴게요.',
                    style: CampText.body.copyWith(
                        color: CampColors.onPrimary.withValues(alpha: 0.86))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SvgPicture.asset('assets/illustrations/planner_hero.svg', height: 92),
        ],
      ),
    );
  }
}

class _ContextChips extends StatelessWidget {
  const _ContextChips({required this.input, this.onEdit});
  final PlanInput input;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final edit = onEdit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (edit != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '이 조건으로 플랜을 만들어요',
                  style: CampText.caption.copyWith(color: CampColors.inkMuted80),
                ),
              ),
              const SizedBox(width: 8),
              _EditButton(onTap: edit),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(LucideIcons.mapPin, input.region),
            _chip(LucideIcons.calendar, input.date),
            _chip(LucideIcons.users, '${input.people}명'),
            _chip(LucideIcons.car, input.hasCar ? '차량 있음' : '차량 없음'),
            _chip(LucideIcons.sparkles, input.experience),
          ],
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CampColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: CampColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: CampColors.primaryDark),
          const SizedBox(width: 6),
          Text(label, style: CampText.caption),
        ],
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: CampColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: CampColors.primary),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.pencil, size: 13, color: CampColors.primaryDark),
            const SizedBox(width: 6),
            Text(
              '조건 수정',
              style: CampText.captionStrong.copyWith(
                color: CampColors.primaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueryField extends StatelessWidget {
  const _QueryField({required this.controller, required this.hint});
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: CampColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CampColors.hairline),
      ),
      child: TextField(
        controller: controller,
        minLines: 3,
        maxLines: 5,
        style: CampText.body,
        decoration: InputDecoration(
          hintText: '예) $hint',
          hintStyle: CampText.body.copyWith(color: CampColors.inkMuted48),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
    );
  }
}

/// 플랜을 기다리는 동안 보여주는 화면.
///
/// 서버는 진행률을 알려주지 않으므로, 예상 소요 시간에 맞춰 단계 문구와 진행 바를
/// 앞으로 밀어 두고 마지막 단계에서 속도를 늦춰 응답을 기다린다.
class _GeneratingView extends StatefulWidget {
  const _GeneratingView();

  @override
  State<_GeneratingView> createState() => _GeneratingViewState();
}

class _GeneratingViewState extends State<_GeneratingView>
    with SingleTickerProviderStateMixin {
  static const _steps = <String>[
    '입력한 조건을 정리하고 있어요',
    '조건에 맞는 캠핑장을 고르고 있어요',
    '그날 날씨를 확인하고 있어요',
    '준비물과 타임라인을 짜고 있어요',
  ];

  /// 프록시 연결 타임아웃이 30초라 그보다 짧게 잡는다.
  static const _expected = Duration(seconds: 20);

  /// 응답이 오기 전에 100%를 보여주지 않으려고 남겨 두는 여유.
  static const _ceiling = 0.94;

  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: _expected,
  )..forward();

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 18, color: CampColors.primary),
              const SizedBox(width: 8),
              Text('플랜을 만드는 중...', style: CampText.sectionTitle),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _fill,
            builder: (context, _) => _ProgressRow(
              progress: Curves.easeOut.transform(_fill.value),
              steps: _steps,
              ceiling: _ceiling,
            ),
          ),
          const SizedBox(height: 20),
          Shimmer(height: 120),
          const SizedBox(height: 16),
          Shimmer(height: 96),
          const SizedBox(height: 16),
          Shimmer(height: 140),
        ],
      ),
    );
  }
}

/// 진행 바와 그 아래 단계 문구 한 줄.
class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.progress,
    required this.steps,
    required this.ceiling,
  });

  final double progress;
  final List<String> steps;
  final double ceiling;

  @override
  Widget build(BuildContext context) {
    final index = (progress * steps.length).floor();
    final step = index < steps.length ? index : steps.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress * ceiling,
            minHeight: 8,
            backgroundColor: CampColors.greenTint,
            valueColor: AlwaysStoppedAnimation<Color>(CampColors.primary),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: Text(
                  steps[step],
                  key: ValueKey<int>(step),
                  style:
                      CampText.caption.copyWith(color: CampColors.inkMuted80),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${step + 1}/${steps.length}',
              style: CampText.captionStrong
                  .copyWith(color: CampColors.primaryDark),
            ),
          ],
        ),
      ],
    );
  }
}
