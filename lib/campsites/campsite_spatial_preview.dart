import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 일반 사진에 제한된 시점 이동을 더해 공간의 분위기를 살펴보게 하는 진입 카드.
class CampsiteSpatialPreviewCard extends StatelessWidget {
  const CampsiteSpatialPreviewCard({
    required this.campsiteName,
    required this.imageUrls,
    super.key,
  });

  final String campsiteName;
  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Semantics(
      button: true,
      label: '$campsiteName 입체 미리보기 열기',
      child: Material(
        color: CampColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CampsiteSpatialPreviewScreen(
                campsiteName: campsiteName,
                imageUrls: imageUrls,
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: CampColors.hairline),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: CampColors.greenTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.view_in_ar_outlined,
                    color: CampColors.forestMid,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '입체로 둘러보기',
                        style: CampText.sectionTitle.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '사진 ${imageUrls.length}장 · 드래그해서 시점 이동',
                        style: CampText.caption.copyWith(
                          color: CampColors.inkMuted80,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: CampColors.inkMuted48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CampsiteSpatialPreviewScreen extends StatefulWidget {
  const CampsiteSpatialPreviewScreen({
    required this.campsiteName,
    required this.imageUrls,
    super.key,
  });

  final String campsiteName;
  final List<String> imageUrls;

  @override
  State<CampsiteSpatialPreviewScreen> createState() =>
      _CampsiteSpatialPreviewScreenState();
}

class _CampsiteSpatialPreviewScreenState
    extends State<CampsiteSpatialPreviewScreen> {
  int _scene = 0;
  Offset _look = Offset.zero;

  void _selectScene(int scene) {
    setState(() {
      _scene = scene;
      _look = Offset.zero;
    });
  }

  void _moveView(DragUpdateDetails details, Size size) {
    setState(() {
      _look = Offset(
        (_look.dx + details.delta.dx / size.width * 2)
            .clamp(-1.0, 1.0)
            .toDouble(),
        (_look.dy + details.delta.dy / size.height * 2)
            .clamp(-1.0, 1.0)
            .toDouble(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.imageUrls;
    if (images.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('미리보기 사진이 없습니다.', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final imageUrl = images[_scene];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                return GestureDetector(
                  key: const Key('spatial-preview-gesture'),
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) => _moveView(details, size),
                  child: ClipRect(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Transform(
                        key: ValueKey('spatial-scene-$imageUrl'),
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(_look.dx * math.pi / 45)
                          ..rotateX(-_look.dy * math.pi / 55),
                        child: Transform.translate(
                          offset: Offset(_look.dx * 18, _look.dy * 12),
                          child: Transform.scale(
                            scale: 1.14,
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (context, error, stackTrace) =>
                                  const _SpatialImageError(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Positioned.fill(child: IgnorePointer(child: _ViewerShade())),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    _ViewerButton(
                      tooltip: '미리보기 닫기',
                      icon: Icons.close,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.campsiteName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CampText.bodyStrong.copyWith(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '사진 기반 입체 미리보기',
                            style: CampText.finePrint.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _ViewerButton(
                      tooltip: '시점 초기화',
                      icon: Icons.center_focus_strong,
                      onPressed: () => setState(() => _look = Offset.zero),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: MediaQuery.paddingOf(context).top + 84,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 7,
                  ),
                  child: Text(
                    '화면을 드래그해 주변을 살펴보세요',
                    style: CampText.finePrint.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          if (images.length > 1)
            Positioned(
              right: 18,
              top: MediaQuery.sizeOf(context).height * 0.43,
              child: _SceneHotspot(
                onPressed: () => _selectScene((_scene + 1) % images.length),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '일반 사진에 제한된 시점 효과를 적용했습니다. 실제 공간 구조와 차이가 있을 수 있어요.',
                    textAlign: TextAlign.center,
                    style: CampText.finePrint.copyWith(
                      color: Colors.white70,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.58),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '장면 ${_scene + 1}/${images.length}',
                          style: CampText.captionStrong.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        if (images.length > 1) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (var i = 0; i < images.length; i++)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        right: i == images.length - 1 ? 0 : 7,
                                      ),
                                      child: _SceneChip(
                                        index: i,
                                        selected: i == _scene,
                                        onPressed: () => _selectScene(i),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerShade extends StatelessWidget {
  const _ViewerShade();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.58),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.7),
          ],
          stops: const [0, 0.36, 1],
        ),
      ),
    );
  }
}

class _ViewerButton extends StatelessWidget {
  const _ViewerButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.48),
        foregroundColor: Colors.white,
      ),
      icon: Icon(icon),
    );
  }
}

class _SceneHotspot extends StatelessWidget {
  const _SceneHotspot({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('spatial-preview-next'),
      tooltip: '다음 장면으로 이동',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(58, 58),
        backgroundColor: CampColors.primary,
        foregroundColor: Colors.white,
        elevation: 6,
        shadowColor: Colors.black54,
      ),
      icon: const Icon(Icons.arrow_forward),
    );
  }
}

class _SceneChip extends StatelessWidget {
  const _SceneChip({
    required this.index,
    required this.selected,
    required this.onPressed,
  });

  final int index;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('spatial-scene-chip-$index'),
      borderRadius: BorderRadius.circular(999),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? CampColors.primary : Colors.white12,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Colors.white70 : Colors.white24),
        ),
        child: Text(
          '${index + 1}',
          style: CampText.captionStrong.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

class _SpatialImageError extends StatelessWidget {
  const _SpatialImageError();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF16281E),
      child: Center(
        child: Text('사진을 불러오지 못했습니다.', style: TextStyle(color: Colors.white70)),
      ),
    );
  }
}
