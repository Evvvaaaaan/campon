import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../main.dart' show Campsite, CampRegion;
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
          markers: markers,
          clusterer: Clusterer(markers: markers, minLevel: 10),
          onMarkerTap: (markerId, latLng, zoomLevel) {
            final site = _siteForMarkerId(markerId);
            if (site != null) {
              _preview.select(site);
            }
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
