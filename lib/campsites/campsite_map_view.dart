import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../main.dart' show AuthConfig, Campsite, CampRegion;
import '../theme.dart';
import 'map_area_loader.dart';
import 'nearby_campsite_cache.dart';

/// CampOn 로고에서 배경을 제거한 주황색 삼각 텐트 선만 사용한다.
/// 데이터 URI라 지도 WebView에서 별도 에셋 경로를 해석할 필요가 없다.
const _kCampsiteMarkerWidth = 38;
const _kCampsiteMarkerHeight = 42;
final _kCampsiteMarkerIconSrc =
    'data:image/svg+xml;base64,${base64Encode(utf8.encode('''
<svg xmlns="http://www.w3.org/2000/svg" width="$_kCampsiteMarkerWidth" height="$_kCampsiteMarkerHeight" viewBox="0 0 $_kCampsiteMarkerWidth $_kCampsiteMarkerHeight">
  <path d="M7 36 L19 12 L31 36 M12.5 5 L33.5 36 M25.5 5 L4.5 36 M3 36 H35" fill="none" stroke="#F09A45" stroke-width="3.4" stroke-linecap="square" stroke-linejoin="round"/>
  <path d="M14 36 L19 27 L24 36" fill="none" stroke="#F09A45" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
'''))}';

final _kCampsiteClusterStyles = <ClustererStyle>[
  ClustererStyle(
    width: 42,
    height: 42,
    background: CampPalette.light.forest,
    borderRadius: 21,
    color: CampPalette.light.onPrimary,
    textAlign: 'center',
    lineHeight: 42,
  ),
];

class MapPreviewController extends ValueNotifier<Campsite?> {
  MapPreviewController() : super(null);

  void select(Campsite site) => value = site;
  void clear() => value = null;
}

class CampsiteMapView extends StatefulWidget {
  const CampsiteMapView({
    required this.region,
    required this.sites,
    required this.onSelect,
    required this.cache,
    required this.onFetchArea,
    super.key,
  });

  final CampRegion region;
  final List<Campsite> sites;
  final ValueChanged<Campsite> onSelect;

  /// 지도를 움직이며 모은 캠핑장. 리스트 탭을 오갈 때도 남아야 해서 바깥에서 소유한다.
  final NearbyCampsiteCache cache;
  final FetchArea onFetchArea;

  @override
  State<CampsiteMapView> createState() => _CampsiteMapViewState();
}

class _CampsiteMapViewState extends State<CampsiteMapView> {
  final _preview = MapPreviewController();
  KakaoMapController? _controller;
  late final MapAreaLoader _loader;
  MarkerIcon? _markerIcon;

  @override
  void initState() {
    super.initState();
    // 지역 조회 결과를 캐시에 심어, 마커의 출처를 캐시 하나로 통일한다.
    widget.cache.seed(
      sites: widget.sites,
      lat: widget.region.lat,
      lon: widget.region.lon,
    );
    widget.cache.addListener(_onCacheChanged);
    _loader = MapAreaLoader(cache: widget.cache, fetchArea: widget.onFetchArea);
    MarkerIcon.fromNetwork(_kCampsiteMarkerIconSrc).then((icon) {
      if (!mounted) return;
      setState(() => _markerIcon = icon);
    });
  }

  void _onCacheChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(CampsiteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.sites, oldWidget.sites)) {
      widget.cache.seed(
        sites: widget.sites,
        lat: widget.region.lat,
        lon: widget.region.lon,
      );
      _preview.clear();
    }
  }

  @override
  void dispose() {
    _loader.dispose();
    // 캐시는 바깥 소유라 리스너만 떼고 dispose하지 않는다.
    widget.cache.removeListener(_onCacheChanged);
    _preview.dispose();
    super.dispose();
  }

  Campsite? _siteForMarkerId(String markerId) {
    final prefix = 'campsite-';
    if (!markerId.startsWith(prefix)) return null;
    final id = int.tryParse(markerId.substring(prefix.length));
    if (id == null) return null;
    for (final site in widget.cache.sites) {
      if (site.id == id) return site;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (AuthConfig.kakaoJavascriptKey.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '지도 키가 설정되지 않았어요.',
            style: CampText.bodyStrong,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final markers = widget.cache.sites
        .map(
          (site) => Marker(
            markerId: 'campsite-${site.id}',
            latLng: LatLng(site.lat, site.lon),
            width: _kCampsiteMarkerWidth,
            height: _kCampsiteMarkerHeight,
            icon: _markerIcon,
          ),
        )
        .toList();

    return Stack(
      children: [
        KakaoMap(
          center: LatLng(widget.region.lat, widget.region.lon),
          currentLevel: 11,
          clusterer: Clusterer(
            markers: markers,
            minLevel: 10,
            styles: _kCampsiteClusterStyles,
          ),
          onMapCreated: (controller) {
            if (!mounted) return;
            _controller = controller;
            setState(() {});
          },
          onMapTap: (_) {
            if (!mounted) return;
            _preview.clear();
          },
          onCameraIdle: (latLng, zoomLevel) {
            _loader.onCameraIdle(latLng.latitude, latLng.longitude);
          },
          onMarkerTap: (markerId, latLng, zoomLevel) {
            if (!mounted) return;
            final site = _siteForMarkerId(markerId);
            if (site != null) {
              _preview.select(site);
            }
          },
          onMarkerClustererTap: (latLng, zoomLevel, clusterMarkers) {
            if (!mounted) return;
            final controller = _controller;
            if (controller == null) return;
            controller.setCenter(latLng);
            final nextLevel = zoomLevel - 2;
            controller.setLevel(nextLevel < 1 ? 1 : nextLevel);
          },
        ),
        ValueListenableBuilder<Campsite?>(
          valueListenable: _preview,
          builder: (context, site, _) {
            if (site == null) return const SizedBox.shrink();
            return Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: CampsiteMapPreviewCard(
                site: site,
                onTap: () => widget.onSelect(site),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 지도 마커 선택 시 상세 화면으로 들어가기 전에 보여주는 핵심 정보 카드.
class CampsiteMapPreviewCard extends StatelessWidget {
  const CampsiteMapPreviewCard({
    required this.site,
    required this.onTap,
    super.key,
  });

  final Campsite site;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = site.validThumbnailUrl;
    final tags = site.tags.take(2).toList();

    return Material(
      color: CampColors.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 7,
      shadowColor: CampColors.shadow,
      child: InkWell(
        key: const Key('campsite-map-preview-card'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: CampColors.hairline),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  key: const Key('campsite-map-preview-thumbnail'),
                  width: 82,
                  height: 82,
                  child: thumbnailUrl == null
                      ? const _MapThumbnailPlaceholder()
                      : Image.network(
                          thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const _MapThumbnailPlaceholder(),
                        ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CampText.sectionTitle.copyWith(fontSize: 18),
                    ),
                    if (site.distance > 0 || site.score != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (site.distance > 0) ...[
                            Icon(
                              Icons.near_me_outlined,
                              size: 14,
                              color: CampColors.inkMuted80,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _formatMapDistance(site.distance),
                              style: CampText.caption.copyWith(
                                fontSize: 12.5,
                                color: CampColors.inkMuted80,
                              ),
                            ),
                          ],
                          if (site.distance > 0 && site.score != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                              ),
                              child: Text(
                                '·',
                                style: CampText.caption.copyWith(
                                  color: CampColors.inkMuted48,
                                ),
                              ),
                            ),
                          if (site.score != null)
                            Text(
                              '추천 ${site.score}점',
                              style: CampText.captionStrong.copyWith(
                                fontSize: 12.5,
                                color: CampColors.primaryDark,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final tag in tags) _MapPreviewTag(label: tag),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: CampColors.inkMuted48),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapThumbnailPlaceholder extends StatelessWidget {
  const _MapThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CampColors.greenTint,
      child: Icon(
        Icons.landscape_outlined,
        color: CampColors.forestMid,
        size: 28,
      ),
    );
  }
}

class _MapPreviewTag extends StatelessWidget {
  const _MapPreviewTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CampColors.greenTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: CampText.finePrint.copyWith(
            color: CampColors.forestMid,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String _formatMapDistance(int distanceMeters) {
  if (distanceMeters >= 1000) {
    final km = distanceMeters / 1000;
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1)}km';
  }
  return '${distanceMeters}m';
}
