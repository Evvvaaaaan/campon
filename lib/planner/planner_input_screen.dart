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
    this.service,
    super.key,
  });

  final PlanInput prefill;
  final void Function(CampPlan plan) onGenerated;
  final VoidCallback onBack;
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
                    child: const Icon(LucideIcons.chevronLeft,
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
                ? const _GeneratingView()
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: revealColumn(
                      children: [
                        _IntroCard(),
                        _ContextChips(input: p),
                        _QueryField(controller: _controller, hint: _defaultQuery()),
                      ],
                    ),
                  ),
          ),
          if (!_loading)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: const BoxDecoration(
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
                        const Icon(LucideIcons.sparkles,
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
  const _ContextChips({required this.input});
  final PlanInput input;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(LucideIcons.mapPin, input.region),
        _chip(LucideIcons.calendar, input.date),
        _chip(LucideIcons.users, '${input.people}명'),
        _chip(LucideIcons.car, input.hasCar ? '차량 있음' : '차량 없음'),
        _chip(LucideIcons.sparkles, input.experience),
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

class _GeneratingView extends StatelessWidget {
  const _GeneratingView();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.sparkles, size: 18, color: CampColors.primary),
              const SizedBox(width: 8),
              Text('플랜을 만드는 중...', style: CampText.sectionTitle),
            ],
          ),
          const SizedBox(height: 20),
          const Shimmer(height: 120),
          const SizedBox(height: 16),
          const Shimmer(height: 96),
          const SizedBox(height: 16),
          const Shimmer(height: 140),
        ],
      ),
    );
  }
}
