import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../main.dart' show AuthConfig, Campsite, CampRegion;
import '../theme.dart';

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
    super.key,
  });

  final CampRegion region;
  final List<Campsite> sites;
  final ValueChanged<Campsite> onSelect;

  @override
  State<CampsiteMapView> createState() => _CampsiteMapViewState();
}

class _CampsiteMapViewState extends State<CampsiteMapView> {
  final _preview = MapPreviewController();
  KakaoMapController? _controller;

  @override
  void didUpdateWidget(CampsiteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.sites, oldWidget.sites)) {
      _preview.clear();
    }
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Campsite? _siteForMarkerId(String markerId) {
    final prefix = 'campsite-';
    if (!markerId.startsWith(prefix)) return null;
    final id = int.tryParse(markerId.substring(prefix.length));
    if (id == null) return null;
    for (final site in widget.sites) {
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

    final markers = widget.sites
        .map(
          (site) => Marker(
            markerId: 'campsite-${site.id}',
            latLng: LatLng(site.lat, site.lon),
          ),
        )
        .toList();

    return Stack(
      children: [
        KakaoMap(
          center: LatLng(widget.region.lat, widget.region.lon),
          currentLevel: 11,
          clusterer: Clusterer(markers: markers, minLevel: 10),
          onMapCreated: (controller) {
            if (!mounted) return;
            _controller = controller;
            setState(() {});
          },
          onMapTap: (_) {
            if (!mounted) return;
            _preview.clear();
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
              child: GestureDetector(
                onTap: () => widget.onSelect(site),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CampColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CampColors.hairline),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(site.name, style: CampText.bodyStrong),
                            Text(site.accessHint, style: CampText.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
