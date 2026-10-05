import 'dart:convert';
import 'dart:io';

typedef CampsiteReservationFetcher = Future<String> Function(Uri url);

const _defaultBaseUrl = String.fromEnvironment(
  'RESERVATION_PROXY_URL',
  defaultValue: String.fromEnvironment('IMAGE_PROXY_URL'),
);

Future<String> _httpFetch(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('예약 정보 검색 실패: HTTP ${response.statusCode}');
    }
    return response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

class CampsiteReservationService {
  CampsiteReservationService({
    CampsiteReservationFetcher? fetcher,
    String? baseUrl,
  }) : _fetch = fetcher ?? _httpFetch,
       _baseUrl = baseUrl ?? _defaultBaseUrl;

  static final shared = CampsiteReservationService();

  final CampsiteReservationFetcher _fetch;
  final String _baseUrl;
  final Map<String, Future<Uri?>> _cache = {};

  Future<Uri?> lookup({required String name}) {
    final key = name.trim();
    return _cache.putIfAbsent(key, () => _lookup(name: key));
  }

  Future<Uri?> _lookup({required String name}) async {
    if (_baseUrl.trim().isEmpty || name.isEmpty) return null;
    try {
      final base = Uri.parse(_baseUrl);
      final url = base.replace(
        path:
            '${base.path.replaceFirst(RegExp(r'/$'), '')}/api/campsite-reservation',
        queryParameters: <String, String>{'name': name},
      );
      final decoded = jsonDecode(await _fetch(url));
      if (decoded is! Map<String, dynamic>) return null;
      final reservation = decoded['reservation'];
      if (reservation is! Map<String, dynamic>) return null;
      return _webUri(reservation['url']);
    } catch (_) {
      return null;
    }
  }
}

Uri naverReservationSearchUri(String campsiteName) => Uri.https(
  'search.naver.com',
  '/search.naver',
  <String, String>{'query': '${campsiteName.trim()} 예약'},
);

Uri? _webUri(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    return null;
  }
  return uri;
}
