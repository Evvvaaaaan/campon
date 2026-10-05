import 'dart:convert';
import 'dart:io';

typedef CampsiteImageFetcher = Future<String> Function(Uri url);

const _defaultBaseUrl = String.fromEnvironment('IMAGE_PROXY_URL');

Future<String> _httpFetch(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('이미지 검색 실패: HTTP ${response.statusCode}');
    }
    return response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

class CampsiteSearchImage {
  const CampsiteSearchImage({
    required this.title,
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.sourceUrl,
  });

  factory CampsiteSearchImage.fromJson(Map<String, dynamic> json) {
    return CampsiteSearchImage(
      title: _string(json['title']),
      imageUrl: _httpsUrl(json['imageUrl']),
      thumbnailUrl: _httpsUrl(json['thumbnailUrl']),
      sourceUrl: _httpsUrl(json['sourceUrl']),
    );
  }

  final String title;
  final String imageUrl;
  final String thumbnailUrl;
  final String sourceUrl;

  bool get isValid => imageUrl.isNotEmpty;
}

class CampsiteImageService {
  CampsiteImageService({CampsiteImageFetcher? fetcher, String? baseUrl})
    : _fetch = fetcher ?? _httpFetch,
      _baseUrl = baseUrl ?? _defaultBaseUrl;

  static final shared = CampsiteImageService();

  final CampsiteImageFetcher _fetch;
  final String _baseUrl;
  final Map<String, Future<List<CampsiteSearchImage>>> _cache = {};

  Future<List<CampsiteSearchImage>> search({
    required String name,
    String? region,
  }) {
    final key = '${name.trim()}|${region?.trim() ?? ''}';
    return _cache.putIfAbsent(key, () => _search(name: name, region: region));
  }

  Future<List<CampsiteSearchImage>> _search({
    required String name,
    String? region,
  }) async {
    if (_baseUrl.trim().isEmpty || name.trim().isEmpty) return const [];
    try {
      final base = Uri.parse(_baseUrl);
      final url = base.replace(
        path: '${base.path.replaceFirst(RegExp(r'/$'), '')}/api/campsite-image',
        queryParameters: <String, String>{
          'name': name.trim(),
          if (region != null && region.trim().isNotEmpty)
            'region': region.trim(),
        },
      );
      final decoded = jsonDecode(await _fetch(url));
      if (decoded is! Map<String, dynamic> || decoded['images'] is! List) {
        return const [];
      }
      return (decoded['images'] as List)
          .whereType<Map<String, dynamic>>()
          .map(CampsiteSearchImage.fromJson)
          .where((image) => image.isValid)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}

String _string(Object? value) => value is String ? value : '';

String _httpsUrl(Object? value) {
  final raw = _string(value);
  final uri = Uri.tryParse(raw);
  return uri != null && uri.isScheme('https') ? raw : '';
}
