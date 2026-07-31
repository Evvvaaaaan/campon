/// "그날 밤 미리보기" 화면.
///
/// 화면이 밤으로 바뀌고, 그 캠핑장의 그날 밤 장면이 한 줄씩 흘러나온다.
/// 정보를 더 주는 화면이 아니라, 가 있는 자신을 먼저 보게 하는 화면이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../motion/motion.dart';
import '../theme.dart';
import '../tonight/night_visuals.dart';
import 'preview_models.dart';
import 'preview_service.dart';

/// 밤 미리보기를 연다. 앱의 다른 화면 전환과 달리 어둠으로 덮으며 들어간다.
Future<void> openNightPreview(
  BuildContext context, {
  required PreviewInput input,
  required String actionLabel,
  required VoidCallback onAction,
  PreviewService? service,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, _, _) => NightPreviewScreen(
        input: input,
        actionLabel: actionLabel,
        onAction: onAction,
        service: service,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class NightPreviewScreen extends StatefulWidget {
  const NightPreviewScreen({
    required this.input,
    required this.actionLabel,
    required this.onAction,
    this.service,
    super.key,
  });

  final PreviewInput input;
  final String actionLabel;
  final VoidCallback onAction;
  final PreviewService? service;

  @override
  State<NightPreviewScreen> createState() => _NightPreviewScreenState();
}

class _NightPreviewScreenState extends State<NightPreviewScreen> {
  late final PreviewService _service = widget.service ?? PreviewService();
  NightPreview? _preview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preview = await _service.generate(widget.input);
    if (!mounted) return;
    setState(() => _preview = preview);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      backgroundColor: NightPalette.deep,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [NightPalette.deep, NightPalette.mid],
                ),
              ),
            ),
          ),
          const Positioned.fill(child: StarField(starCount: 96, seed: 21)),
          Positioned(
            top: 74,
            right: 26,
            child:
                MoonGlyph(
                  illumination: widget.input.moonIlluminationPct / 100,
                  size: 62,
                ).animate().fadeIn(
                  duration: 1400.ms,
                  delay: 200.ms,
                ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: _CloseButton(
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
                Expanded(
                  child: preview == null
                      ? const _DrawingNight()
                      : _PreviewBody(
                          preview: preview,
                          actionLabel: widget.actionLabel,
                          onAction: () {
                            Navigator.of(context).pop();
                            widget.onAction();
                          },
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

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({
    required this.preview,
    required this.actionLabel,
    required this.onAction,
  });

  final NightPreview preview;
  final String actionLabel;
  final VoidCallback onAction;

  /// 한 줄이 나타나고 다음 줄이 나오기까지의 간격. 읽는 속도에 맞췄다.
  static const _lineGap = Duration(milliseconds: 1100);

  @override
  Widget build(BuildContext context) {
    final afterLines = _lineGap * (preview.lines.length + 1);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preview.title,
            style: CampText.display.copyWith(
              fontSize: 23,
              height: 1.3,
              color: NightPalette.text,
            ),
          ).animate().fadeIn(duration: 700.ms, delay: 200.ms),
          const SizedBox(height: 26),
          for (var i = 0; i < preview.lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child:
                  Text(
                    preview.lines[i],
                    style: CampText.body.copyWith(
                      fontSize: 16.5,
                      height: 1.85,
                      color: NightPalette.text,
                    ),
                  ).animate().fadeIn(
                    duration: 900.ms,
                    delay: _lineGap * (i + 1),
                  ).slideY(
                    begin: 0.25,
                    end: 0,
                    duration: 900.ms,
                    delay: _lineGap * (i + 1),
                    curve: Curves.easeOutCubic,
                  ),
            ),
          const SizedBox(height: 4),
          Text(
            preview.closing,
            style: CampText.bodyStrong.copyWith(
              fontSize: 16,
              height: 1.6,
              color: CampColors.amberTint,
            ),
          ).animate().fadeIn(duration: 1000.ms, delay: afterLines),
          const SizedBox(height: 30),
          _NightAction(
            label: actionLabel,
            onPressed: onAction,
          ).animate().fadeIn(duration: 700.ms, delay: afterLines + 500.ms),
        ],
      ),
    );
  }
}

class _DrawingNight extends StatelessWidget {
  const _DrawingNight();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '그날 밤을 그리는 중',
            style: CampText.tagline.copyWith(color: NightPalette.textMuted),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child:
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: NightPalette.star,
                          shape: BoxShape.circle,
                        ),
                      ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(
                        duration: 620.ms,
                        delay: Duration(milliseconds: 180 * i),
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: NightPalette.mid.withValues(alpha: 0.7),
          shape: BoxShape.circle,
          border: Border.all(
            color: NightPalette.textMuted.withValues(alpha: 0.3),
          ),
        ),
        child: const Icon(LucideIcons.x, size: 18, color: NightPalette.text),
      ),
    );
  }
}

class _NightAction extends StatelessWidget {
  const _NightAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: CampColors.primary,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          label,
          style: CampText.button.copyWith(color: CampColors.onPrimary),
        ),
      ),
    );
  }
}
