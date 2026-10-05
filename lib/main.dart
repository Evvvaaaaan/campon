import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

import 'campsites/campsite_image_service.dart';
import 'campsites/campsite_map_view.dart';
import 'campsites/campsite_pagination.dart';
import 'campsites/campsite_reservation_service.dart';
import 'campsites/campsite_spatial_preview.dart';
import 'campsites/favorites_store.dart';
import 'campsites/nearby_campsite_cache.dart';
import 'location/location_service.dart';
import 'motion/motion.dart';
import 'planner/plan_models.dart';
import 'planner/planner_input_screen.dart';
import 'planner/planner_result_screen.dart';
import 'preview/night_preview_button.dart';
import 'theme.dart';
import 'tonight/night_visuals.dart';
import 'weather/campsite_weather_card.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeNativeSdks();
  runApp(CampOnApp());
}

Future<void> _initializeNativeSdks() async {
  if (AuthConfig.kakaoNativeAppKey.isEmpty) {
    debugPrint('[KakaoSdk] KAKAO_NATIVE_APP_KEY가 비어 있어 초기화를 건너뜁니다.');
    return;
  }
  try {
    // 디버그 빌드에서는 카카오 SDK 내부 로그를 콘솔에 남겨 실패 지점을 추적한다.
    await KakaoSdk.init(
      nativeAppKey: AuthConfig.kakaoNativeAppKey,
      loggingEnabled: kDebugMode,
    );
    debugPrint(
      '[KakaoSdk] init 완료 | nativeAppKey=${AuthConfig.kakaoNativeAppKey} '
      'customScheme=${KakaoSdk.customScheme} redirectUri=${KakaoSdk.redirectUri}',
    );
  } catch (error, stackTrace) {
    debugPrint('[KakaoSdk] init 실패: $error');
    debugPrint('[KakaoSdk] Stack trace:\n$stackTrace');
  }

  if (AuthConfig.kakaoJavascriptKey.isEmpty) {
    debugPrint('[KakaoMap] KAKAO_JAVASCRIPT_KEY가 비어 있어 지도 초기화를 건너뜁니다.');
    return;
  }
  // baseUrl은 반드시 https여야 한다. 카카오맵 sdk.js는 로더 스텁일 뿐이고, 실제 지도 엔진
  // (t1.daumcdn.net/mapjsapi/.../kakao.js)과 타일을 받을 주소를
  // `"https:" == location.protocol ? "https:" : "http:"`로 정한다. baseUrl이 http면 엔진을
  // 평문 HTTP로 받으려 하는데 iOS ATS(및 안드로이드 cleartext 정책)가 이를 막아
  // kakao.maps.load 콜백이 영영 호출되지 않고 지도가 빈 화면으로 남는다.
  // 이 도메인은 카카오 디벨로퍼스 콘솔의 해당 JS 키 "플랫폼 > Web"에도 등록되어 있어야 한다.
  AuthRepository.initialize(
    appKey: AuthConfig.kakaoJavascriptKey,
    baseUrl: AuthConfig.kakaoMapBaseUrl,
  );
}

class AuthConfig {
  static const kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
    defaultValue: '0ecef49f91608f40010f59053f36fa9a',
  );
  static const kakaoJavascriptKey = String.fromEnvironment(
    'KAKAO_JAVASCRIPT_KEY',
    defaultValue: 'da305f3d0050858669209af771943ff8',
  );

  /// 카카오맵 WebView가 등록된 도메인처럼 보이도록 쓰는 고정 origin.
  /// 카카오 디벨로퍼스 콘솔 > 해당 JS 키 > 플랫폼 > Web에 이 값과 정확히 같은 도메인을
  /// 등록해야 지도가 뜬다 (미등록 시 401 domain mismatched로 빈 화면).
  /// 반드시 https로 둔다. http면 SDK가 지도 엔진을 평문 HTTP로 받으려다 ATS에 막힌다.
  static const kakaoMapBaseUrl = String.fromEnvironment(
    'KAKAO_MAP_BASE_URL',
    defaultValue: 'https://localhost',
  );
  static const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '651935780618-ncfo4v0ej4c3ti8c9b5r5i3kdv5ssi15.apps.googleusercontent.com',
  );
  static const appleServiceId = String.fromEnvironment(
    'APPLE_SERVICE_ID',
    defaultValue: 'com.seohamin.camping',
  );
  static const appleRedirectUri = String.fromEnvironment('APPLE_REDIRECT_URI');
  static const showDevLogin = bool.fromEnvironment(
    'SHOW_DEV_LOGIN',
    defaultValue: false,
  );

  /// 디버그 빌드에서는 항상 개발 계정 로그인을 노출한다.
  static bool get devLoginVisible => showDevLogin || kDebugMode;
}

/// 약관 문서의 위치. 로그인 화면이 동의를 전제하므로 사용자가 실제로 읽을 수 있어야 한다.
///
/// App Store는 계정을 만드는 앱에 개인정보 처리방침을 요구한다. 값이 비어 있으면 링크를
/// 감추므로, 제출 빌드에서는 반드시 `--dart-define`으로 두 URL을 넣어야 한다.
class LegalConfig {
  static const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');
  static const termsOfServiceUrl = String.fromEnvironment(
    'TERMS_OF_SERVICE_URL',
  );
  static const contactEmail = String.fromEnvironment(
    'LEGAL_CONTACT_EMAIL',
    defaultValue: 'shm040806@gmail.com',
  );

  /// 링크를 열지 못하면 조용히 실패하지 않고 호출한 쪽이 안내할 수 있게 false를 준다.
  static Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 약관/방침 URL이 설정되어 있으면 외부로 열고, 없으면 앱 내 문서 화면을 보여준다.
  static Future<void> openDocument(
    BuildContext context,
    String url,
    LegalDocument document,
  ) async {
    if (url.isEmpty) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => LegalDocumentScreen(document: document),
        ),
      );
      return;
    }

    final opened = await open(url);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('링크를 열지 못했습니다.')));
    }
  }
}

/// 야간 캠핑 테마의 현재 상태와 토글을 하위 트리에 내려보낸다.
class CampThemeScope extends InheritedWidget {
  const CampThemeScope({
    required this.isDark,
    required this.toggle,
    required super.child,
    super.key,
  });

  final bool isDark;
  final VoidCallback toggle;

  static CampThemeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CampThemeScope>();
    assert(scope != null, 'CampThemeScope가 트리에 없습니다');
    return scope!;
  }

  @override
  bool updateShouldNotify(CampThemeScope oldWidget) =>
      oldWidget.isDark != isDark;
}

class CampOnApp extends StatefulWidget {
  const CampOnApp({this.api, this.favoritesStore, this.location, super.key});

  final CampOnApi? api;
  final FavoritesStore? favoritesStore;
  final LocationProvider? location;

  @override
  State<CampOnApp> createState() => _CampOnAppState();
}

class _CampOnAppState extends State<CampOnApp> {
  bool _dark = false;

  void _toggleTheme() {
    setState(() {
      _dark = !_dark;
      CampColors.apply(_dark ? CampPalette.dark : CampPalette.light);
    });
  }

  @override
  void initState() {
    super.initState();
    // 테스트가 다크로 끝난 뒤 다음 실행에 새어 나가지 않도록 시작 시 맞춰 둔다.
    CampColors.apply(_dark ? CampPalette.dark : CampPalette.light);
  }

  @override
  Widget build(BuildContext context) {
    return CampThemeScope(
      isDark: _dark,
      toggle: _toggleTheme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '캠프온',
        theme: ThemeData(
          useMaterial3: true,
          brightness: _dark ? Brightness.dark : Brightness.light,
          scaffoldBackgroundColor: CampColors.canvas,
          textTheme: GoogleFonts.notoSansKrTextTheme(
            _dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: CampColors.primary,
            brightness: _dark ? Brightness.dark : Brightness.light,
            surface: CampColors.surface,
          ),
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: CampColors.primary,
            selectionColor: CampColors.primary.withValues(alpha: 0.2),
            selectionHandleColor: CampColors.primary,
          ),
        ),
        home: CampOnShell(
          api: widget.api,
          favoritesStore: widget.favoritesStore,
          location: widget.location,
        ),
      ),
    );
  }
}

enum AppStep {
  loading,
  login,
  home,
  details,
  checklist,
  community,
  browse,
  favorites,
  onboardingBasics,
  onboardingExperience,
  onboardingPreferences,
  recommendations,
  settings,
  plannerInput,
  plannerResult,
}

enum DetailEntry { home, recommendations, browse, favorites, planner }

class CampOnShell extends StatefulWidget {
  const CampOnShell({this.api, this.favoritesStore, this.location, super.key});

  final CampOnApi? api;
  final FavoritesStore? favoritesStore;
  final LocationProvider? location;

  @override
  State<CampOnShell> createState() => _CampOnShellState();
}

class _CampOnShellState extends State<CampOnShell> {
  late final CampOnApi _api;
  late final FavoritesStore _favoritesStore;
  late final LocationProvider _location;

  /// 지도를 움직이며 모은 캠핑장. 리스트↔지도 탭을 오갈 때 지도 위젯이 새로 만들어지므로
  /// 누적분이 살아남으려면 셸이 들고 있어야 한다.
  final _nearbyCache = NearbyCampsiteCache();

  AppStep _step = AppStep.loading;
  DetailEntry _detailEntry = DetailEntry.recommendations;
  DateTime? _date;
  CampRegion _region = CampData.regions[1];
  int _people = 2;
  bool? _hasCar;
  String? _skillLevel;
  bool? _withFamily;
  bool _preTripAlerts = true;
  Campsite? _selectedSite;
  // 상세를 열어본 캠핑장과 실제 준비를 시작한 캠핑장을 구분한다.
  // 홈의 일정 카드는 사용자가 준비 시작을 누른 캠핑장만 보여준다.
  Campsite? _tripSite;
  bool _hasRecommended = false;

  final Set<String> _equipment = <String>{};
  final Set<String> _preferences = <String>{};
  final Set<String> _checkedItems = <String>{};
  // 하트를 누른 캠핑장. 추천 덱과 상세 화면이 같은 값을 본다.
  // 단건 조회 API가 없어 목록 복원을 위해 캠핑장 정보를 통째로 들고 있는다.
  final Map<int, Campsite> _favorites = <int, Campsite>{};

  // 첫 진입 코치마크. 이 앱은 아직 어떤 설정도 저장하지 않으므로 이 값도
  // 메모리에만 둔다(앱을 새로 켜면 다시 나온다).
  bool _showTutorial = true;
  int _tutorialStep = 0;
  // 보유 장비를 체크리스트에 한 번만 옮겨 담아, 이후 체크/해제는 _checkedItems만 따른다.
  bool _checklistSeeded = false;

  Future<List<Campsite>>? _recommendationsFuture;
  Future<List<Campsite>>? _browseFuture;
  Future<List<Campsite>>? _weeklyRecommendationsFuture;
  // 주변 캠핑장 지도의 초기 중심점. 추천 지역이 아니라 실제 현재 위치를 써야 해서
  // 조회가 끝나는 시점에 함께 채운다.
  LocationPoint? _browseOrigin;

  CampPlan? _plan;
  List<Campsite> _planCandidates = <Campsite>[];
  List<String> _aiChecklistItems = const <String>[];

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? CampOnApi();
    _favoritesStore =
        widget.favoritesStore ?? const SharedPrefsFavoritesStore();
    _location = widget.location ?? const GeolocatorLocationProvider();
    _api.onSessionInvalidated = _returnToLogin;
    _restoreSession();
    _restoreFavorites();
  }

  @override
  void dispose() {
    _nearbyCache.dispose();
    super.dispose();
  }

  Future<void> _restoreFavorites() async {
    final stored = await _favoritesStore.read();
    if (!mounted || stored.isEmpty) {
      return;
    }
    setState(() {
      for (final site in stored) {
        _favorites[site.id] = site;
      }
    });
  }

  Future<void> _restoreSession() async {
    final restored = await _api.restoreSession();
    if (!mounted) {
      return;
    }
    setState(() => _step = restored ? AppStep.home : AppStep.login);
  }

  void _returnToLogin() {
    if (!mounted || _step == AppStep.login) {
      return;
    }
    setState(() => _step = AppStep.login);
  }

  bool get _canGoBasicsNext => _date != null;
  bool get _canGoExperienceNext => _hasCar != null && _skillLevel != null;
  // 온보딩 3단계에는 뒤로가기 버튼이 없다. 탭바가 이 단계에서 유일한 탈출구이므로
  // 반드시 함께 켜져 있어야 한다.
  bool get _showTabs => const {
    AppStep.home,
    AppStep.browse,
    AppStep.favorites,
    AppStep.onboardingBasics,
    AppStep.onboardingExperience,
    AppStep.onboardingPreferences,
    AppStep.recommendations,
    AppStep.checklist,
    AppStep.settings,
  }.contains(_step);

  void _goHome() {
    setState(() => _step = AppStep.home);
  }

  void _goFavorites() {
    setState(() => _step = AppStep.favorites);
  }

  void _startOnboarding() {
    setState(() => _step = AppStep.onboardingBasics);
  }

  void _goBrowse() {
    setState(() {
      // FutureBuilder가 구독하기 전에 실패하면 처리되지 않은 예외로 새어나갈
      // 수 있어, 별도로 미리 구독해 무시해 둔다. FutureBuilder는 여전히
      // 자신의 구독으로 성공/실패를 그대로 받는다.
      _browseFuture ??= _fetchNearbyByCurrentLocation()..ignore();
      _step = AppStep.browse;
    });
  }

  /// 주변 캠핑장은 추천에 쓰인 지역이 아니라 실제 현재 위치를 기준으로 찾는다.
  /// 위치를 얻지 못하면(권한 거부 등) 목록 자체를 보여줄 수 없으므로 예외를
  /// 그대로 던져, 화면이 위치 권한 안내를 보여주게 한다.
  Future<List<Campsite>> _fetchNearbyByCurrentLocation() async {
    final origin = await _location.current();
    _browseOrigin = origin;
    final sites = await _api.fetchAllNearbyAt(lat: origin.lat, lon: origin.lon);
    return [
      for (final site in sites)
        site.copyWithDistance(
          distanceBetweenMeters(
            origin,
            LocationPoint(lat: site.lat, lon: site.lon),
          ).round(),
        ),
    ];
  }

  void _goRecommendTab() {
    setState(() {
      _step = _hasRecommended
          ? AppStep.recommendations
          : AppStep.onboardingBasics;
    });
  }

  void _goChecklist() {
    setState(_seedChecklistAndOpen);
  }

  void _seedChecklistAndOpen() {
    if (!_checklistSeeded) {
      _checkedItems.addAll(_equipment);
      _checklistSeeded = true;
    }
    _step = AppStep.checklist;
  }

  void _goSettings() {
    setState(() => _step = AppStep.settings);
  }

  Future<void> _goPlanner() async {
    if (_planCandidates.isEmpty) {
      await _loadPlanCandidates();
    }
    if (mounted) {
      setState(() => _step = AppStep.plannerInput);
    }
  }

  /// 플래너가 AI에게 넘길 실제 캠핑장 후보. 지역이 바뀌면 다시 받아야
  /// 이전 지역의 캠핑장이 플랜에 남지 않는다.
  Future<void> _loadPlanCandidates() async {
    try {
      final candidates = await _api.fetchNearby(
        region: _region,
        page: 0,
        size: 10,
      );
      if (!mounted) {
        return;
      }
      setState(() => _planCandidates = candidates);
    } catch (_) {
      // Planner still works with region-based fallback when candidates fail.
    }
  }

  /// 홈의 "이번 주 추천" 데이터 진입점.
  ///
  /// 현재는 주변 캠핑장 API가 반환한 순서를 그대로 쓴다. 추후 광고 상품이
  /// 서버 응답에 추가되면 이 메서드의 데이터 소스만 교체하면 된다.
  Future<List<Campsite>> _loadWeeklyRecommendations() async {
    final requestedRegion = _region;
    final sites = await _api.fetchWeeklyRecommendations(
      region: requestedRegion,
      size: 10,
    );
    if (mounted &&
        requestedRegion.name == _region.name &&
        _planCandidates.isEmpty) {
      setState(() => _planCandidates = sites);
    }
    return sites;
  }

  Future<List<Campsite>> _ensureWeeklyRecommendations() {
    final cached = _weeklyRecommendationsFuture;
    if (cached != null) return cached;
    final future = _loadWeeklyRecommendations();
    future.ignore();
    _weeklyRecommendationsFuture = future;
    return future;
  }

  void _retryWeeklyRecommendations() {
    final future = _loadWeeklyRecommendations();
    future.ignore();
    setState(() => _weeklyRecommendationsFuture = future);
  }

  /// 플래너 화면에서 조건을 고친다. 저장을 눌렀을 때만 반영되고,
  /// 지역이 바뀌면 후보를 비운 뒤 새 지역으로 다시 받는다.
  Future<void> _editPlanConditions() async {
    final edited = await showModalBottomSheet<PlanConditions>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CampColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => PlanConditionSheet(
        initial: PlanConditions(
          // 칩에 이미 오늘 날짜가 떠 있으므로 시트도 같은 값에서 시작한다.
          date: _date ?? DateTime.now(),
          region: _region,
          people: _people,
          hasCar: _hasCar ?? true,
          skillLevel: _skillLevel ?? CampData.skillLevels.first,
          equipment: _equipment,
          preferences: _preferences,
        ),
      ),
    );
    if (edited == null || !mounted) {
      return;
    }

    final regionChanged = edited.region.name != _region.name;
    setState(() {
      _date = edited.date;
      _region = edited.region;
      _people = edited.people;
      _hasCar = edited.hasCar;
      _skillLevel = edited.skillLevel;
      _equipment
        ..clear()
        ..addAll(edited.equipment);
      _preferences
        ..clear()
        ..addAll(edited.preferences);
      if (regionChanged) {
        _planCandidates = <Campsite>[];
        _browseFuture = null;
        _weeklyRecommendationsFuture = null;
        // 지역을 옮기면 이전 지역에서 쌓은 마커가 남지 않게 비운다.
        _nearbyCache.clear();
      }
    });
    if (regionChanged) {
      await _loadPlanCandidates();
    }
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  PlanInput _buildPlanInput() {
    final date = _date ?? DateTime.now();
    return PlanInput(
      query: '',
      date: _isoDate(date),
      people: _people,
      hasCar: _hasCar ?? true,
      experience: _skillLevel ?? '초보',
      region: _region.name,
      lat: _region.lat,
      lon: _region.lon,
      preferences: _preferences.toList(),
      equipment: _equipment.toList(),
      candidates: _planCandidates
          .map(
            (s) => PlanCandidate(
              name: s.name,
              facility: s.facility,
              equipmentRental: s.equipmentRental,
            ),
          )
          .toList(),
    );
  }

  void _back() {
    setState(() {
      switch (_step) {
        case AppStep.details:
          _step = switch (_detailEntry) {
            DetailEntry.home => AppStep.home,
            DetailEntry.browse => AppStep.browse,
            DetailEntry.favorites => AppStep.favorites,
            DetailEntry.recommendations => AppStep.recommendations,
            DetailEntry.planner => AppStep.plannerResult,
          };
        case AppStep.community:
          _step = AppStep.details;
        case AppStep.plannerResult:
          _step = AppStep.plannerInput;
        case AppStep.plannerInput:
          _step = AppStep.home;
        case AppStep.loading:
        case AppStep.home:
        case AppStep.login:
        case AppStep.checklist:
        case AppStep.browse:
        case AppStep.favorites:
        case AppStep.settings:
        case AppStep.onboardingBasics:
        case AppStep.onboardingExperience:
        case AppStep.onboardingPreferences:
        case AppStep.recommendations:
          _step = AppStep.home;
      }
    });
  }

  void _continueFromBasics() {
    if (!_canGoBasicsNext) {
      return;
    }
    setState(() => _step = AppStep.onboardingExperience);
  }

  void _continueFromExperience() {
    if (!_canGoExperienceNext) {
      return;
    }
    setState(() => _step = AppStep.onboardingPreferences);
  }

  void _loadRecommendations() {
    if (_date == null || _hasCar == null) {
      return;
    }

    setState(() {
      _hasRecommended = true;
      _selectedSite = null;
      _checkedItems.clear();
      _checklistSeeded = false;
      _recommendationsFuture = _api.fetchRecommendations(
        region: _region,
        date: _date!,
        people: _people,
        hasCar: _hasCar!,
        equipment: _equipment.toList(),
        preferences: _preferences.toList(),
        page: 0,
        size: 20,
      );
      _step = AppStep.recommendations;
    });
  }

  /// 플랜에 적힌 이름으로 그 캠핑장의 상세 화면을 연다.
  ///
  /// 플랜에는 이름만 담겨 오므로 AI에 넘겼던 후보 목록에서 이름으로 되찾는다.
  /// 프롬프트가 후보 목록에서만 고르게 하지만, 어긋난 이름이면 아무 일도 없다.
  void _openPlanCampsite(String name) {
    for (final site in _planCandidates) {
      if (site.name == name) {
        _selectSite(site, DetailEntry.planner);
        return;
      }
    }
  }

  void _selectSite(Campsite site, DetailEntry entry) {
    setState(() {
      _selectedSite = site;
      _detailEntry = entry;
      _step = AppStep.details;
    });
  }

  void _startPreparation() {
    if (_selectedSite != null) {
      setState(() {
        _tripSite = _selectedSite;
        _seedChecklistAndOpen();
      });
    }
  }

  void _openCommunity() {
    setState(() => _step = AppStep.community);
  }

  void _reset() {
    setState(() {
      _step = AppStep.home;
      _date = null;
      _region = CampData.regions[1];
      _people = 2;
      _hasCar = null;
      _skillLevel = null;
      _withFamily = null;
      _selectedSite = null;
      _tripSite = null;
      _hasRecommended = false;
      _equipment.clear();
      _preferences.clear();
      _checkedItems.clear();
      _checklistSeeded = false;
      _recommendationsFuture = null;
      _browseFuture = null;
      _weeklyRecommendationsFuture = null;
      _detailEntry = DetailEntry.recommendations;
      _planCandidates = <Campsite>[];
      _nearbyCache.clear();
    });
  }

  Future<void> _signOut() async {
    await _api.signOut();
    if (!mounted) {
      return;
    }
    setState(() {
      _step = AppStep.login;
      _date = null;
      _region = CampData.regions[1];
      _people = 2;
      _hasCar = null;
      _skillLevel = null;
      _withFamily = null;
      _selectedSite = null;
      _tripSite = null;
      _hasRecommended = false;
      _equipment.clear();
      _preferences.clear();
      _checkedItems.clear();
      _checklistSeeded = false;
      _recommendationsFuture = null;
      _browseFuture = null;
      _weeklyRecommendationsFuture = null;
      _detailEntry = DetailEntry.recommendations;
      _planCandidates = <Campsite>[];
      _nearbyCache.clear();
    });
  }

  Future<void> _deleteAccount() async {
    await _api.deleteAccount();
    if (!mounted) {
      return;
    }
    setState(() {
      _step = AppStep.login;
      _date = null;
      _region = CampData.regions[1];
      _people = 2;
      _hasCar = null;
      _skillLevel = null;
      _withFamily = null;
      _selectedSite = null;
      _tripSite = null;
      _hasRecommended = false;
      _equipment.clear();
      _preferences.clear();
      _checkedItems.clear();
      _checklistSeeded = false;
      _recommendationsFuture = null;
      _browseFuture = null;
      _weeklyRecommendationsFuture = null;
      _detailEntry = DetailEntry.recommendations;
      _planCandidates = <Campsite>[];
      _nearbyCache.clear();
    });
  }

  Future<void> _signInWithDevUser() async {
    await _api.signInWithDevUser();
    if (!mounted) {
      return;
    }
    setState(() => _step = AppStep.home);
  }

  Future<void> _signInWithNativeProvider(
    AuthProvider provider,
    BuildContext context,
  ) async {
    await _api.signInWithNativeProvider(provider: provider, context: context);
    if (!mounted) {
      return;
    }
    setState(() => _step = AppStep.home);
  }

  void _toggleSetValue(Set<String> values, String value) {
    setState(() {
      if (values.contains(value)) {
        values.remove(value);
      } else {
        values.add(value);
      }
    });
  }

  void _nextTutorial() {
    final next = _tutorialStep + 1;
    if (next >= TutorialOverlay.steps.length) {
      setState(() => _showTutorial = false);
      return;
    }
    setState(() => _tutorialStep = next);
    // 탭 전환은 탭바와 같은 경로를 탄다. 안내 문구와 실제로 열리는 화면이
    // 어긋나지 않게 하기 위해서다.
    switch (next) {
      case 1:
        _goBrowse();
      case 2:
        _goRecommendTab();
      case 3:
        _goChecklist();
      case 4:
        _goSettings();
    }
  }

  void _addFavorite(Campsite site) {
    if (_favorites.containsKey(site.id)) {
      return;
    }
    setState(() => _favorites[site.id] = site);
    _persistFavorites();
  }

  void _toggleFavorite(Campsite site) {
    setState(() {
      if (_favorites.remove(site.id) == null) {
        _favorites[site.id] = site;
      }
    });
    _persistFavorites();
  }

  /// 저장 실패가 화면을 막지는 않는다. 다음 토글에서 다시 기록된다.
  void _persistFavorites() {
    unawaited(_favoritesStore.write(_favorites.values));
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = _buildScaffold();
    // 추천 단계는 아직 조건을 안 정한 사용자를 온보딩으로 보낸다. 그때도 안내가
    // 이어져야 하므로 탭바 유무가 아니라 로그인/로딩만 제외한다.
    final tutorialVisible =
        _showTutorial && _step != AppStep.login && _step != AppStep.loading;
    if (!tutorialVisible) return scaffold;
    return Stack(
      children: [
        scaffold,
        TutorialOverlay(
          stepIndex: _tutorialStep,
          showTabHint: _showTabs,
          onNext: _nextTutorial,
          onSkip: () => setState(() => _showTutorial = false),
        ),
      ],
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      body: SafeArea(
        // 로그인은 배경이 노치까지 꽉 차는 풀블리드 화면이다.
        // 내부 콘텐츠는 LoginScreen이 자체 SafeArea로 띄운다.
        top: _step != AppStep.login,
        bottom: _step != AppStep.login,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.015),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<AppStep>(_step),
            child: _buildStep(),
          ),
        ),
      ),
      // 하단 여백은 CampTabBar가 배경색 안쪽에서 직접 처리한다.
      bottomNavigationBar: _showTabs
          ? CampTabBar(
              currentStep: _step,
              hasRecommended: _hasRecommended,
              onHome: _goHome,
              onBrowse: _goBrowse,
              onRecommend: _goRecommendTab,
              onChecklist: _goChecklist,
              onSettings: _goSettings,
            )
          : null,
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case AppStep.loading:
        return const Center(child: CircularProgressIndicator());
      case AppStep.login:
        return LoginScreen(
          onDevLogin: _signInWithDevUser,
          onNativeLogin: _signInWithNativeProvider,
          showDevLogin: AuthConfig.devLoginVisible,
        );
      case AppStep.home:
        return HomeScreen(
          onStart: _startOnboarding,
          onBrowse: _goBrowse,
          onRecommendations: _goRecommendTab,
          onPlanner: _goPlanner,
          onChecklist: _goChecklist,
          onFavorites: _goFavorites,
          favoriteCount: _favorites.length,
          weeklyRecommendations: _ensureWeeklyRecommendations(),
          onRetryWeeklyRecommendations: _retryWeeklyRecommendations,
          onOpenWeeklyRecommendation: (site) =>
              _selectSite(site, DetailEntry.home),
          tripDate: _date,
          region: _region,
          people: _people,
          tripSite: _tripSite,
          checklistDone: [
            ...CampData.equipmentOptions,
            ...CampData.fixedChecklist,
          ].where((item) => _checkedItems.contains(item.apiValue)).length,
          checklistTotal:
              CampData.equipmentOptions.length + CampData.fixedChecklist.length,
          hasRecommended: _hasRecommended,
        );
      case AppStep.onboardingBasics:
        return BasicsScreen(
          date: _date,
          region: _region,
          people: _people,
          onDateChanged: (date) => setState(() => _date = date),
          onRegionChanged: (region) {
            setState(() {
              _region = region;
              _browseFuture = null;
              _weeklyRecommendationsFuture = null;
              _planCandidates = <Campsite>[];
              // 지역을 옮기면 이전 지역에서 쌓은 마커가 남지 않게 비운다.
              _nearbyCache.clear();
            });
          },
          onPeopleChanged: (people) => setState(() => _people = people),
          onNext: _continueFromBasics,
          nextEnabled: _canGoBasicsNext,
        );
      case AppStep.onboardingExperience:
        return ExperienceScreen(
          hasCar: _hasCar,
          skillLevel: _skillLevel,
          onHasCarChanged: (hasCar) => setState(() => _hasCar = hasCar),
          onSkillChanged: (skill) => setState(() => _skillLevel = skill),
          onNext: _continueFromExperience,
          nextEnabled: _canGoExperienceNext,
        );
      case AppStep.onboardingPreferences:
        return PreferencesScreen(
          equipment: _equipment,
          preferences: _preferences,
          withFamily: _withFamily,
          onEquipmentToggle: (value) => _toggleSetValue(_equipment, value),
          onPreferenceToggle: (value) => _toggleSetValue(_preferences, value),
          onFamilyChanged: (value) => setState(() => _withFamily = value),
          onSubmit: _loadRecommendations,
        );
      case AppStep.recommendations:
        return RecommendationSwipeScreen(
          title: '오늘의 추천',
          subtitle: _date == null
              ? '마음에 들면 하트, 아니면 X를 눌러 다음 캠핑장을 확인하세요.'
              : '${_formatKoreanDate(_date!)} · $_people명 · ${_region.name}',
          future: _recommendationsFuture,
          emptyText: '조건에 맞는 캠핑장을 찾지 못했어요.',
          onRetry: _loadRecommendations,
          onResetCondition: _startOnboarding,
          onSelect: (site) => _selectSite(site, DetailEntry.recommendations),
          onFavorite: _addFavorite,
          isFavorite: (site) => _favorites.containsKey(site.id),
        );
      case AppStep.details:
        return CampsiteDetailScreen(
          api: _api,
          site: _selectedSite,
          region: _region,
          hasCar: _hasCar ?? true,
          onBack: _back,
          onCommunity: _openCommunity,
          onPrepare: _startPreparation,
          isFavorite:
              _selectedSite != null &&
              _favorites.containsKey(_selectedSite!.id),
          onToggleFavorite: () {
            if (_selectedSite != null) _toggleFavorite(_selectedSite!);
          },
        );
      case AppStep.checklist:
        return ChecklistScreen(
          selectedSite: _tripSite,
          checkedItems: _checkedItems,
          aiItems: _aiChecklistItems,
          onToggle: (key) => _toggleSetValue(_checkedItems, key),
          onReset: _reset,
        );
      case AppStep.community:
        return CommunityScreen(api: _api, site: _selectedSite, onBack: _back);
      case AppStep.plannerInput:
        return PlannerInputScreen(
          prefill: _buildPlanInput(),
          onBack: _goHome,
          onEditConditions: _editPlanConditions,
          onGenerated: (plan) => setState(() {
            _plan = plan;
            _step = AppStep.plannerResult;
          }),
        );
      case AppStep.plannerResult:
        return PlannerResultScreen(
          plan: _plan!,
          openableCampsites: {for (final site in _planCandidates) site.name},
          onOpenCampsite: _openPlanCampsite,
          onBack: () => setState(() => _step = AppStep.plannerInput),
          onRegenerate: () => setState(() => _step = AppStep.plannerInput),
          onSendToChecklist: (items) => setState(() {
            _aiChecklistItems = items;
            _seedChecklistAndOpen();
          }),
        );
      case AppStep.settings:
        return SettingsScreen(
          api: _api,
          preTripAlerts: _preTripAlerts,
          onAlertChanged: (value) => setState(() => _preTripAlerts = value),
          onSignOut: _signOut,
          onDeleteAccount: _deleteAccount,
        );
      case AppStep.favorites:
        return FavoritesScreen(
          sites: _favorites.values.toList(growable: false),
          onSelect: (site) => _selectSite(site, DetailEntry.favorites),
          onStartRecommend: _startOnboarding,
        );
      case AppStep.browse:
        return CampsiteBrowseScreen(
          title: '주변 캠핑장',
          subtitle: '현재 위치 반경 20km 이내 캠핑장이에요.',
          future: _browseFuture,
          emptyText: '반경 20km 이내에서 캠핑장을 찾지 못했어요.',
          onRetry: () {
            setState(() {
              _browseFuture = _fetchNearbyByCurrentLocation()..ignore();
            });
          },
          onSelect: (site) => _selectSite(site, DetailEntry.browse),
          mapViewBuilder: (sites, onSelect) => CampsiteMapView(
            region: CampRegion(
              name: '현재 위치',
              lat: _browseOrigin?.lat ?? _region.lat,
              lon: _browseOrigin?.lon ?? _region.lon,
              mapX: 0,
              mapY: 0,
            ),
            sites: sites,
            onSelect: onSelect,
            cache: _nearbyCache,
            onFetchArea: (lat, lon) =>
                _api.fetchAllNearbyAt(lat: lat, lon: lon),
          ),
        );
    }
  }
}

enum AuthProvider {
  kakao('Kakao', '/api/v1/auth/oauth2/kakao', 'accessToken'),
  google('Google', '/api/v1/auth/oauth2/google', 'code'),
  apple('Apple', '/api/v1/auth/oauth2/apple', 'code');

  const AuthProvider(this.label, this.path, this.credentialField);

  final String label;
  final String path;

  /// 서버 `OauthRequestDto`는 provider마다 다른 필드를 요구한다.
  /// Kakao는 네이티브 SDK가 내려준 access token(`accessToken`)을,
  /// Google/Apple은 authorization code(`code`)를 받는다.
  final String credentialField;

  Map<String, String> authRequestBody({
    required String credential,
    required String name,
  }) => <String, String>{credentialField: credential, 'name': name};

  String get storageValue => name;

  static AuthProvider? fromStorageValue(String? value) {
    for (final provider in AuthProvider.values) {
      if (provider.storageValue == value) {
        return provider;
      }
    }
    return null;
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.onDevLogin,
    required this.onNativeLogin,
    required this.showDevLogin,
    super.key,
  });

  final Future<void> Function() onDevLogin;
  final Future<void> Function(AuthProvider provider, BuildContext context)
  onNativeLogin;
  final bool showDevLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _runLogin(Future<void> Function() action) async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } catch (error, stackTrace) {
      debugPrint('[Login] 오류 발생: $error');
      debugPrint('[Login] 오류 타입: ${error.runtimeType}');
      debugPrint('[Login] Stack trace:\n$stackTrace');
      if (!mounted) {
        return;
      }
      if (_isUserCancelled(error)) {
        return;
      }
      setState(() => _error = _describeLoginError(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 사용자가 로그인 창을 스스로 닫은 경우는 오류로 표시하지 않는다.
  bool _isUserCancelled(Object error) {
    if (error is GoogleSignInException) {
      return error.code == GoogleSignInExceptionCode.canceled;
    }
    if (error is SignInWithAppleAuthorizationException) {
      return error.code == AuthorizationErrorCode.canceled;
    }
    if (error is KakaoAuthException) {
      return error.error == AuthErrorCause.accessDenied;
    }
    // 카카오 SDK는 로그인 방법 선택 창을 닫으면 ClientErrorCause.cancelled를 던진다.
    if (error is KakaoClientException) {
      return error.reason == ClientErrorCause.cancelled;
    }
    if (error is PlatformException) {
      return error.code == 'CANCELED' || error.code == 'CANCELLED';
    }
    return false;
  }

  String _describeLoginError(Object error) {
    if (error is CampOnApiException) {
      return error.message;
    }
    if (error is GoogleSignInException) {
      return switch (error.code) {
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          'Google 로그인 설정이 아직 완료되지 않았습니다. 관리자에게 문의해주세요.',
        _ => 'Google 로그인에 실패했습니다. 잠시 후 다시 시도해주세요.',
      };
    }
    if (error is SignInWithAppleAuthorizationException) {
      return switch (error.code) {
        AuthorizationErrorCode.failed ||
        AuthorizationErrorCode.invalidResponse ||
        AuthorizationErrorCode.notHandled =>
          'Apple 로그인 설정을 확인해주세요. Apple Developer의 App ID와 '
              'Sign in with Apple capability가 현재 bundle ID와 일치해야 합니다.',
        AuthorizationErrorCode.notInteractive =>
          'Apple 로그인은 버튼을 눌러 시작해야 합니다. 다시 시도해주세요.',
        _ => 'Apple 로그인에 실패했습니다. 잠시 후 다시 시도해주세요.',
      };
    }
    if (error is KakaoClientException) {
      final base = switch (error.reason) {
        ClientErrorCause.notSupported => '이 기기에서는 카카오 로그인을 사용할 수 없습니다.',
        ClientErrorCause.tokenNotFound => '카카오 로그인 정보가 없습니다. 다시 로그인해주세요.',
        _ => '카카오 로그인에 실패했습니다. 잠시 후 다시 시도해주세요.',
      };
      return _withDebugDetail(base, '${error.reason.name}: ${error.msg}');
    }
    if (error is KakaoAuthException) {
      final base = switch (error.error) {
        AuthErrorCause.misconfigured =>
          '카카오 로그인 설정이 완료되지 않았습니다. Kakao Developers의 '
              '플랫폼(bundle ID / 패키지명·키 해시)과 앱 키 등록을 확인해주세요.',
        AuthErrorCause.unauthorized =>
          '카카오 앱 권한 설정을 확인해주세요. 카카오 로그인 활성화와 동의항목이 필요합니다.',
        _ => '카카오 로그인에 실패했습니다. 잠시 후 다시 시도해주세요.',
      };
      return _withDebugDetail(
        base,
        '${error.error.name}: ${error.errorDescription ?? ''}',
      );
    }
    if (error is KakaoException) {
      return _withDebugDetail('카카오 로그인에 실패했습니다. 잠시 후 다시 시도해주세요.', '$error');
    }
    return '로그인에 실패했습니다. 잠시 후 다시 시도해주세요.';
  }

  /// 디버그 빌드에서만 원인 문자열을 덧붙인다. 릴리즈에서는 원문 오류를 노출하지 않는다.
  String _withDebugDetail(String message, String detail) {
    if (!kDebugMode || detail.trim().isEmpty) {
      return message;
    }
    return '$message\n(디버그: $detail)';
  }

  void _submitDevLogin() {
    _runLogin(widget.onDevLogin);
  }

  void _submitNativeLogin(AuthProvider provider) {
    _runLogin(() => widget.onNativeLogin(provider, context));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF35543F), CampColors.forest],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.45, 1],
              colors: [Color(0x8C1E3A2B), Color(0xBF1E3A2B), CampColors.forest],
            ),
          ),
        ),
        // 하늘 풍경(별·산맥·안개·모닥불). 화면 높이에 비례해 배치해야
        // 아래에서 올라오는 버튼 스택에 가리지 않는다.
        Positioned.fill(
          child: IgnorePointer(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const bandHeight = 90.0;
                // 로그인 문구 묶음이 화면 아래 3분의 2를 차지하므로, 능선 밑동이
                // 그 위에서 끝나도록 잡는다.
                final ridgeTop = constraints.maxHeight * 0.17;
                final ridgeBase = ridgeTop + bandHeight;
                return Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: ridgeTop,
                      child: const StarField(starCount: 34, seed: 11),
                    ),
                    // 라인아트 산맥. 디자인의 추가 opacity 0.5는 뺐다. 배경 사진이
                    // 없는 지금은 그대로 두면 단색 위에서 형체가 보이지 않는다.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: ridgeTop,
                      height: bandHeight,
                      child: const CustomPaint(
                        painter: _MountainRangePainter(),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: ridgeBase - 52,
                      height: 74,
                      child: const DriftingFog(),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: ridgeBase - 66,
                      child: const Center(child: Campfire()),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 세로 패딩(24+24)을 빼야 최소 높이가 뷰포트를 넘지 않는다.
              // 빼지 않으면 내용이 짧아도 항상 48px만큼 잘린다.
              const verticalPadding = 48.0;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - verticalPadding).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Transform.rotate(
                        angle: -1.5 * math.pi / 180,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '모닥불 앞, 딱 한 걸음이면 돼요',
                          style: CampText.handwritten(
                            color: CampPalette.light.amberTint,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '캠핑을 시작할\n계정을 선택해주세요',
                        style: CampText.display.copyWith(
                          fontSize: 38,
                          height: 1.18,
                          color: CampColors.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '추천, 체크리스트, 캠핑장 보관을 위해 로그인이 필요합니다.',
                        style: CampText.caption.copyWith(
                          color: CampColors.greenTint,
                        ),
                      ),
                      const SizedBox(height: 22),
                      SocialLoginButton(
                        label: '카카오로 계속하기',
                        leading: SvgPicture.string(_kakaoLogoSvg),
                        backgroundColor: const Color(0xFFFEE500),
                        foregroundColor: const Color(0xFF3A2E0F),
                        onPressed: _loading
                            ? null
                            : () => _submitNativeLogin(AuthProvider.kakao),
                      ),
                      const SizedBox(height: 10),
                      SocialLoginButton(
                        label: 'Google로 계속하기',
                        leading: SvgPicture.string(_googleLogoSvg),
                        backgroundColor: CampColors.surface,
                        foregroundColor: CampColors.ink,
                        borderColor: CampColors.hairline,
                        onPressed: _loading
                            ? null
                            : () => _submitNativeLogin(AuthProvider.google),
                      ),
                      const SizedBox(height: 10),
                      SocialLoginButton(
                        label: 'Apple로 계속하기',
                        icon: Icons.apple,
                        backgroundColor: const Color(0xFF12241A),
                        foregroundColor: CampColors.onPrimary,
                        onPressed: _loading
                            ? null
                            : () => _submitNativeLogin(AuthProvider.apple),
                      ),
                      if (widget.showDevLogin) ...[
                        const SizedBox(height: 10),
                        Center(
                          child: TextButton(
                            onPressed: _loading ? null : _submitDevLogin,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF9FB0A2),
                              padding: EdgeInsets.zero,
                            ),
                            child: Text(
                              _loading ? '로그인 중' : '개발 계정으로 시작',
                              style: CampText.finePrint.copyWith(
                                fontSize: 12.5,
                                color: const Color(0xFF9FB0A2),
                                decoration: TextDecoration.underline,
                                decorationColor: const Color(0xFF9FB0A2),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF0EA),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Color(0xFFC2410C),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: CampText.caption.copyWith(
                                    color: const Color(0xFF7C2D12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        '로그인하면 CampOn 이용약관과 개인정보 처리방침에\n동의하는 것으로 간주됩니다.',
                        textAlign: TextAlign.center,
                        style: CampText.finePrint.copyWith(
                          color: CampColors.greenTint.withValues(alpha: 0.75),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const LegalLinkRow(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MountainRangePainter extends CustomPainter {
  const _MountainRangePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 402;
    final scaleY = size.height / 90;
    Offset p(double x, double y) => Offset(x * scaleX, y * scaleY);

    void polygon(List<Offset> points, Color color) {
      canvas.drawPath(Path()..addPolygon(points, true), Paint()..color = color);
    }

    polygon([p(0, 90), p(60, 30), p(110, 90)], const Color(0x58163022));
    polygon([p(80, 90), p(150, 10), p(220, 90)], const Color(0x70163022));
    polygon([p(190, 90), p(260, 40), p(330, 90)], const Color(0x58163022));
    polygon([p(290, 90), p(350, 20), p(402, 90)], const Color(0x70163022));
  }

  @override
  bool shouldRepaint(covariant _MountainRangePainter oldDelegate) => false;
}

const _kakaoLogoSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
<path d="M12 3.5C6.48 3.5 2 6.98 2 11.3c0 2.77 1.85 5.2 4.63 6.58-.2.75-1.13 4.1-1.17 4.38 0 0-.02.2.11.28.13.08.28.02.28.02.37-.05 4.28-2.83 4.96-3.3.38.04.79.06 1.19.06 5.52 0 10-3.48 10-7.8s-4.48-8.02-10-8.02z" fill="#3A2E0F"/>
</svg>
''';

const _googleLogoSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.3 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.9 1.2 8 3.1l5.7-5.7C34.6 6.5 29.6 4.5 24 4.5 13.2 4.5 4.5 13.2 4.5 24S13.2 43.5 24 43.5 43.5 34.8 43.5 24c0-1.2-.1-2.4-.4-3.5z"/>
<path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.6 16 18.9 13 24 13c3.1 0 5.9 1.2 8 3.1l5.7-5.7C34.6 6.5 29.6 4.5 24 4.5c-7.7 0-14.4 4.4-17.7 10.2z"/>
<path fill="#4CAF50" d="M24 43.5c5.5 0 10.4-1.9 14.2-5.1l-6.6-5.4C29.6 34.6 26.9 35.5 24 35.5c-5.3 0-9.7-3.3-11.3-8l-6.6 5.1C9.5 39 16.2 43.5 24 43.5z"/>
<path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.1-4.1 5.5l6.6 5.4C39.9 37.6 43.5 31.5 43.5 24c0-1.2-.1-2.4-.4-3.5z"/>
</svg>
''';

class SocialLoginButton extends StatelessWidget {
  const SocialLoginButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    super.key,
  }) : assert(icon != null || leading != null, 'icon or leading required');

  final String label;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final backgroundColor = this.backgroundColor ?? CampColors.surface;
    final foregroundColor = this.foregroundColor ?? CampColors.ink;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: disabled
              ? backgroundColor.withValues(alpha: 0.45)
              : backgroundColor,
          foregroundColor: foregroundColor,
          disabledForegroundColor: CampColors.inkMuted48,
          side: BorderSide(
            color: borderColor ?? Colors.transparent,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: CampText.button.copyWith(fontSize: 16),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 19,
              height: 19,
              child: leading ?? Icon(icon, size: 19),
            ),
            const SizedBox(width: 10),
            Text(label),
          ],
        ),
      ),
    );
  }
}

enum _HomeStage { noPlan, choosing, preTrip, tripDay, pastTrip }

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onStart,
    required this.onBrowse,
    required this.onRecommendations,
    required this.onPlanner,
    required this.onChecklist,
    required this.onFavorites,
    required this.favoriteCount,
    required this.weeklyRecommendations,
    required this.onRetryWeeklyRecommendations,
    required this.onOpenWeeklyRecommendation,
    required this.tripDate,
    required this.region,
    required this.people,
    required this.tripSite,
    required this.checklistDone,
    required this.checklistTotal,
    required this.hasRecommended,
    this.now,
    super.key,
  });

  final VoidCallback onStart;
  final VoidCallback onBrowse;
  final VoidCallback onRecommendations;
  final VoidCallback onPlanner;
  final VoidCallback onChecklist;
  final VoidCallback onFavorites;
  final int favoriteCount;
  final Future<List<Campsite>> weeklyRecommendations;
  final VoidCallback onRetryWeeklyRecommendations;
  final ValueChanged<Campsite> onOpenWeeklyRecommendation;
  final DateTime? tripDate;
  final CampRegion region;
  final int people;
  final Campsite? tripSite;
  final int checklistDone;
  final int checklistTotal;
  final bool hasRecommended;
  final DateTime? now;

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  int? get _daysUntilTrip {
    if (tripDate == null) return null;
    return _day(tripDate!).difference(_day(now ?? DateTime.now())).inDays;
  }

  _HomeStage get _stage {
    if (tripDate == null && tripSite == null) return _HomeStage.noPlan;
    if (tripDate == null || tripSite == null) return _HomeStage.choosing;
    final days = _daysUntilTrip!;
    if (days > 0) return _HomeStage.preTrip;
    if (days == 0) return _HomeStage.tripDay;
    return _HomeStage.pastTrip;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _FreshHomeColors.canvas,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          // 기존 로고와 야간 테마 버튼은 그대로 유지한다.
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: CampPalette.light.forest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  LucideIcons.tent,
                  color: CampPalette.dark.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'CampOn',
                style: CampText.sectionTitle.copyWith(
                  fontSize: 21,
                  color: CampColors.ink,
                ),
              ),
              const Spacer(),
              const NightThemeToggle(),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'YOUR WEEKEND, YOUR WAY',
            style: CampText.finePrint.copyWith(
              color: CampColors.inkMuted80,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          _HomeLead(
            stage: _stage,
            tripDate: tripDate,
            region: region,
            people: people,
            tripSite: tripSite,
            daysUntilTrip: _daysUntilTrip,
            checklistDone: checklistDone,
            checklistTotal: checklistTotal,
            onStart: onStart,
            onPlanner: onPlanner,
            onRecommendations: hasRecommended ? onRecommendations : onStart,
            onChecklist: onChecklist,
          ),
          const SizedBox(height: 30),
          _HomeSectionHeader(
            title: '이번 주 추천',
            subtitle: '${region.name} 주변 캠핑장',
            actionLabel: '모두 보기',
            onAction: onBrowse,
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Campsite>>(
            future: weeklyRecommendations,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _WeeklyRecommendationLoading();
              }
              if (snapshot.hasError) {
                return _WeeklyRecommendationMessage(
                  icon: LucideIcons.wifiOff,
                  title: '추천을 불러오지 못했어요',
                  body: '연결을 확인한 뒤 다시 시도해주세요.',
                  actionLabel: '다시 시도',
                  onAction: onRetryWeeklyRecommendations,
                );
              }
              final sites = snapshot.data ?? const <Campsite>[];
              if (sites.isEmpty) {
                return _WeeklyRecommendationMessage(
                  icon: LucideIcons.mapPin,
                  title: '이번 주 추천을 준비하고 있어요',
                  body: '다른 지역의 캠핑장을 먼저 둘러보세요.',
                  actionLabel: '캠핑장 둘러보기',
                  onAction: onBrowse,
                );
              }
              return _WeeklyRecommendationPager(
                sites: sites,
                onOpen: onOpenWeeklyRecommendation,
              );
            },
          ),
          const SizedBox(height: 14),
          _FavoritesStrip(favoriteCount: favoriteCount, onPressed: onFavorites),
          const SizedBox(height: 30),
          const _HomeSectionHeader(title: 'AI 플래너'),
          const SizedBox(height: 12),
          _AiPlannerCard(onPressed: onPlanner),
        ],
      ),
    );
  }
}

class _FreshHomeColors {
  static Color get canvas =>
      CampColors.isDark ? CampColors.canvas : const Color(0xFFE4EBDD);
  static Color get paper =>
      CampColors.isDark ? CampColors.surface : const Color(0xFFFFFCF3);
  static const deepGreen = Color(0xFF18382B);
  static const lime = Color(0xFFDDF24C);
}

class _HomeLead extends StatelessWidget {
  const _HomeLead({
    required this.stage,
    required this.tripDate,
    required this.region,
    required this.people,
    required this.tripSite,
    required this.daysUntilTrip,
    required this.checklistDone,
    required this.checklistTotal,
    required this.onStart,
    required this.onPlanner,
    required this.onRecommendations,
    required this.onChecklist,
  });

  final _HomeStage stage;
  final DateTime? tripDate;
  final CampRegion region;
  final int people;
  final Campsite? tripSite;
  final int? daysUntilTrip;
  final int checklistDone;
  final int checklistTotal;
  final VoidCallback onStart;
  final VoidCallback onPlanner;
  final VoidCallback onRecommendations;
  final VoidCallback onChecklist;

  @override
  Widget build(BuildContext context) {
    return switch (stage) {
      _HomeStage.noPlan => _NoPlanLead(onPlanner: onPlanner, onStart: onStart),
      _HomeStage.choosing => _ChoosingLead(
        tripDate: tripDate,
        region: region,
        people: people,
        tripSite: tripSite,
        onStart: onStart,
        onRecommendations: onRecommendations,
      ),
      _HomeStage.preTrip => _TripLead(
        eyebrow: 'D-${daysUntilTrip!}',
        title: tripSite!.name,
        message: '${_formatKoreanDate(tripDate!)} · $people명',
        checklistDone: checklistDone,
        checklistTotal: checklistTotal,
        actionLabel: '준비 이어가기',
        onAction: onChecklist,
      ),
      _HomeStage.tripDay => _TripLead(
        eyebrow: '오늘의 캠핑',
        title: tripSite!.name,
        message: '오늘은 ${region.name}에서 머무는 날이에요.',
        checklistDone: checklistDone,
        checklistTotal: checklistTotal,
        actionLabel: '체크리스트 확인',
        onAction: onChecklist,
      ),
      _HomeStage.pastTrip => _TripLead(
        eyebrow: '다녀온 캠핑',
        title: tripSite!.name,
        message: '${_formatKoreanDate(tripDate!)}의 캠핑 기록이에요.',
        checklistDone: checklistDone,
        checklistTotal: checklistTotal,
        actionLabel: '다음 캠핑 계획하기',
        onAction: onPlanner,
      ),
    };
  }
}

class _NoPlanLead extends StatelessWidget {
  const _NoPlanLead({required this.onPlanner, required this.onStart});

  final VoidCallback onPlanner;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '어디로\n떠나볼까요?',
          style: CampText.display.copyWith(fontSize: 40, height: 1.05),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _FreshHomeColors.deepGreen,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -26,
                top: -38,
                child: Container(
                  width: 122,
                  height: 122,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 24,
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.sparkles,
                    color: _FreshHomeColors.lime,
                    size: 22,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    '한 줄로 만드는\n나만의 캠핑 계획',
                    style: CampText.sectionTitle.copyWith(
                      fontSize: 24,
                      height: 1.25,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '날씨와 준비물까지 한 번에 정리해드려요.',
                    style: CampText.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _FreshActionButton(
                    label: '캠핑 계획 만들기',
                    icon: LucideIcons.arrowUpRight,
                    onPressed: onPlanner,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: onStart,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.only(top: 12),
                      ),
                      child: const Text('조건부터 추천받기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChoosingLead extends StatelessWidget {
  const _ChoosingLead({
    required this.tripDate,
    required this.region,
    required this.people,
    required this.tripSite,
    required this.onStart,
    required this.onRecommendations,
  });

  final DateTime? tripDate;
  final CampRegion region;
  final int people;
  final Campsite? tripSite;
  final VoidCallback onStart;
  final VoidCallback onRecommendations;

  @override
  Widget build(BuildContext context) {
    final needsDate = tripDate == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          needsDate ? '날짜만 정하면\n준비가 시작돼요' : '캠핑장은\n정하셨나요?',
          style: CampText.display.copyWith(fontSize: 38, height: 1.08),
        ),
        const SizedBox(height: 18),
        _FreshPaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                needsDate ? tripSite!.name : _formatKoreanDate(tripDate!),
                style: CampText.sectionTitle.copyWith(fontSize: 21),
              ),
              const SizedBox(height: 5),
              Text(
                needsDate ? '방문 날짜를 선택해주세요.' : '${region.name} · $people명',
                style: CampText.caption.copyWith(color: CampColors.inkMuted80),
              ),
              const SizedBox(height: 16),
              _FreshActionButton(
                label: needsDate ? '날짜 선택하기' : '추천 캠핑장 보기',
                icon: needsDate ? LucideIcons.calendar : LucideIcons.mapPin,
                onPressed: needsDate ? onStart : onRecommendations,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TripLead extends StatelessWidget {
  const _TripLead({
    required this.eyebrow,
    required this.title,
    required this.message,
    required this.checklistDone,
    required this.checklistTotal,
    required this.actionLabel,
    required this.onAction,
  });

  final String eyebrow;
  final String title;
  final String message;
  final int checklistDone;
  final int checklistTotal;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final progress = checklistTotal == 0 ? 0.0 : checklistDone / checklistTotal;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _FreshHomeColors.deepGreen,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: _FreshHomeColors.lime,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              eyebrow,
              style: CampText.captionStrong.copyWith(
                color: _FreshHomeColors.deepGreen,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            style: CampText.displaySmall.copyWith(
              fontSize: 29,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            style: CampText.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: progress,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation(
                      _FreshHomeColors.lime,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$checklistDone / $checklistTotal',
                style: CampText.captionStrong.copyWith(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _FreshActionButton(
            label: actionLabel,
            icon: LucideIcons.arrowRight,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}

class _FreshPaperCard extends StatelessWidget {
  const _FreshPaperCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _FreshHomeColors.paper,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CampColors.hairline),
      ),
      child: child,
    );
  }
}

class _AiPlannerCard extends StatelessWidget {
  const _AiPlannerCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _FreshHomeColors.deepGreen,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.sparkles, color: _FreshHomeColors.lime, size: 22),
          const SizedBox(height: 18),
          Text(
            '원하는 캠핑을\nAI와 함께 계획해보세요',
            style: CampText.sectionTitle.copyWith(
              fontSize: 22,
              height: 1.25,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '일정과 취향에 맞는 캠핑장부터 준비물까지 추천해드려요.',
            style: CampText.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 18),
          _FreshActionButton(
            label: 'AI 플래너 시작하기',
            icon: LucideIcons.arrowUpRight,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

class _FreshActionButton extends StatelessWidget {
  const _FreshActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          foregroundColor: _FreshHomeColors.deepGreen,
          backgroundColor: _FreshHomeColors.lime,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: CampText.button,
        ),
        iconAlignment: IconAlignment.end,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: CampText.sectionTitle.copyWith(fontSize: 21)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: CampText.caption.copyWith(
                    color: CampColors.inkMuted80,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: CampColors.ink,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _WeeklyRecommendationPager extends StatefulWidget {
  const _WeeklyRecommendationPager({required this.sites, required this.onOpen});

  final List<Campsite> sites;
  final ValueChanged<Campsite> onOpen;

  @override
  State<_WeeklyRecommendationPager> createState() =>
      _WeeklyRecommendationPagerState();
}

class _WeeklyRecommendationPagerState
    extends State<_WeeklyRecommendationPager> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void didUpdateWidget(_WeeklyRecommendationPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sites != widget.sites) {
      _page = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 270,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.sites.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) {
              final site = widget.sites[index];
              return Semantics(
                label: '추천 ${index + 1}, ${site.name}',
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => widget.onOpen(site),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: _FreshHomeColors.paper,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: CampColors.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 174,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              site.validThumbnailUrl == null
                                  ? CampsiteCoverImage(site: site)
                                  : Image.network(
                                      site.validThumbnailUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          CampImagePlaceholder(),
                                    ),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Color(0xA6000000),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 18,
                                right: 18,
                                bottom: 14,
                                child: Text(
                                  site.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: CampText.sectionTitle.copyWith(
                                    fontSize: 22,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    site.lineIntro.isNotEmpty
                                        ? site.lineIntro
                                        : site.tags.take(2).join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: CampText.caption.copyWith(
                                      color: CampColors.inkMuted80,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: _FreshHomeColors.deepGreen,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    LucideIcons.arrowUpRight,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < widget.sites.length; index++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: index == _page ? 20 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: index == _page
                      ? _FreshHomeColors.deepGreen
                      : CampColors.inkMuted48,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            const SizedBox(width: 7),
            Text(
              '${_page + 1} / ${widget.sites.length}',
              style: CampText.finePrint.copyWith(color: CampColors.inkMuted80),
            ),
          ],
        ),
      ],
    );
  }
}

class _WeeklyRecommendationLoading extends StatelessWidget {
  const _WeeklyRecommendationLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 270,
      decoration: BoxDecoration(
        color: _FreshHomeColors.paper,
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: Alignment.center,
      child: CircularProgressIndicator(color: CampColors.forestMid),
    );
  }
}

class _WeeklyRecommendationMessage extends StatelessWidget {
  const _WeeklyRecommendationMessage({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return _FreshPaperCard(
      child: Column(
        children: [
          Icon(icon, color: CampColors.forestMid),
          const SizedBox(height: 10),
          Text(title, style: CampText.bodyStrong),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: CampText.caption.copyWith(color: CampColors.inkMuted80),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _FavoritesStrip extends StatelessWidget {
  const _FavoritesStrip({required this.favoriteCount, required this.onPressed});

  final int favoriteCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _FreshPaperCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: CampColors.amberTint,
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.heart, color: CampColors.primaryDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('찜한 캠핑장', style: CampText.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  favoriteCount == 0
                      ? '마음에 드는 캠핑장에 하트를 눌러보세요.'
                      : '$favoriteCount곳을 이 기기에 저장해 두었어요.',
                  style: CampText.caption.copyWith(
                    color: CampColors.inkMuted80,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onPressed, child: const Text('찜 목록 보기')),
        ],
      ),
    );
  }
}

class BasicsScreen extends StatelessWidget {
  const BasicsScreen({
    required this.date,
    required this.region,
    required this.people,
    required this.onDateChanged,
    required this.onRegionChanged,
    required this.onPeopleChanged,
    required this.onNext,
    required this.nextEnabled,
    super.key,
  });

  final DateTime? date;
  final CampRegion region;
  final int people;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<CampRegion> onRegionChanged;
  final ValueChanged<int> onPeopleChanged;
  final VoidCallback onNext;
  final bool nextEnabled;

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      progressIndex: 0,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Transform.rotate(
            angle: -1.5 * math.pi / 180,
            alignment: Alignment.centerLeft,
            child: Text(
              '떠날 준비, 지금 시작할까요?',
              style: CampText.handwritten(color: CampColors.primaryDark),
            ),
          ),
          const SizedBox(height: 2),
          Text('언제, 어디로\n떠나시나요?', style: CampText.displaySmall),
          const SizedBox(height: 6),
          Text(
            '기본 조건만 알려주시면 시작할 수 있어요.',
            style: CampText.body.copyWith(color: CampColors.inkMuted80),
          ),
          const SizedBox(height: 26),
          FormLabel('캠핑 날짜', color: CampColors.primaryDark),
          DatePickerField(date: date, onChanged: onDateChanged),
          const SizedBox(height: 22),
          FormLabel('지역 · 지도에서 핀을 찍어주세요', color: CampColors.primaryDark),
          RegionPicker(selected: region, onChanged: onRegionChanged),
          const SizedBox(height: 22),
          FormLabel('인원 수', color: CampColors.primaryDark),
          PeopleStepper(value: people, onChanged: onPeopleChanged),
        ],
      ),
      bottom: CampButton(label: '다음', onPressed: nextEnabled ? onNext : null),
    );
  }
}

class ExperienceScreen extends StatelessWidget {
  const ExperienceScreen({
    required this.hasCar,
    required this.skillLevel,
    required this.onHasCarChanged,
    required this.onSkillChanged,
    required this.onNext,
    required this.nextEnabled,
    super.key,
  });

  final bool? hasCar;
  final String? skillLevel;
  final ValueChanged<bool> onHasCarChanged;
  final ValueChanged<String> onSkillChanged;
  final VoidCallback onNext;
  final bool nextEnabled;

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      progressIndex: 1,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Text('이동수단과\n경험을 알려주세요', style: CampText.displaySmall),
          const SizedBox(height: 6),
          Text(
            '갈 수 있는 곳과 준비물이 달라져요.',
            style: CampText.body.copyWith(color: CampColors.inkMuted80),
          ),
          const SizedBox(height: 26),
          FormLabel('차량 보유 여부'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CampChoiceChip(
                label: '차량 있음',
                selected: hasCar == true,
                onTap: () => onHasCarChanged(true),
              ),
              CampChoiceChip(
                label: '차량 없음',
                selected: hasCar == false,
                onTap: () => onHasCarChanged(false),
              ),
            ],
          ),
          const SizedBox(height: 22),
          FormLabel('캠핑 숙련도'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CampData.skillLevels
                .map(
                  (skill) => CampChoiceChip(
                    label: skill,
                    selected: skillLevel == skill,
                    onTap: () => onSkillChanged(skill),
                  ),
                )
                .toList(),
          ),
        ],
      ),
      bottom: CampButton(label: '다음', onPressed: nextEnabled ? onNext : null),
    );
  }
}

class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({
    required this.equipment,
    required this.preferences,
    required this.withFamily,
    required this.onEquipmentToggle,
    required this.onPreferenceToggle,
    required this.onFamilyChanged,
    required this.onSubmit,
    super.key,
  });

  final Set<String> equipment;
  final Set<String> preferences;
  final bool? withFamily;
  final ValueChanged<String> onEquipmentToggle;
  final ValueChanged<String> onPreferenceToggle;
  final ValueChanged<bool> onFamilyChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      progressIndex: 2,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Text('보유 장비와\n선호를 알려주세요', style: CampText.displaySmall),
          const SizedBox(height: 6),
          Text(
            '있는 것만 체크해주세요. 없어도 괜찮아요.',
            style: CampText.body.copyWith(color: CampColors.inkMuted80),
          ),
          const SizedBox(height: 22),
          FormLabel('보유 장비'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CampData.equipmentOptions
                .map(
                  (item) => CampChoiceChip(
                    label: item.label,
                    selected: equipment.contains(item.apiValue),
                    onTap: () => onEquipmentToggle(item.apiValue),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 22),
          FormLabel('가족 동반 여부'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CampChoiceChip(
                label: '예',
                selected: withFamily == true,
                onTap: () => onFamilyChanged(true),
              ),
              CampChoiceChip(
                label: '아니요',
                selected: withFamily == false,
                onTap: () => onFamilyChanged(false),
              ),
            ],
          ),
          const SizedBox(height: 22),
          FormLabel('선호 조건'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CampData.preferenceOptions
                .map(
                  (item) => CampChoiceChip(
                    label: item.label,
                    selected: preferences.contains(item.apiValue),
                    onTap: () => onPreferenceToggle(item.apiValue),
                  ),
                )
                .toList(),
          ),
        ],
      ),
      bottom: CampButton(label: '캠핑장 추천받기', onPressed: onSubmit),
    );
  }
}

/// AI 플래너가 넘길 조건 묶음. 시트를 저장하면 이 값으로 돌아온다.
class PlanConditions {
  const PlanConditions({
    required this.date,
    required this.region,
    required this.people,
    required this.hasCar,
    required this.skillLevel,
    required this.equipment,
    required this.preferences,
  });

  final DateTime date;
  final CampRegion region;
  final int people;
  final bool hasCar;
  final String skillLevel;
  final Set<String> equipment;
  final Set<String> preferences;
}

/// 플래너에서 조건을 고치는 시트.
///
/// 온보딩과 같은 입력 위젯을 쓰되 단계를 밟지 않고 한 화면에서 고친다.
/// 저장을 눌러야 반영되므로, 중간에 닫으면 원래 조건이 그대로 남는다.
class PlanConditionSheet extends StatefulWidget {
  const PlanConditionSheet({required this.initial, super.key});

  final PlanConditions initial;

  @override
  State<PlanConditionSheet> createState() => _PlanConditionSheetState();
}

class _PlanConditionSheetState extends State<PlanConditionSheet> {
  late DateTime _date = widget.initial.date;
  late CampRegion _region = widget.initial.region;
  late int _people = widget.initial.people;
  late bool _hasCar = widget.initial.hasCar;
  late String _skillLevel = widget.initial.skillLevel;
  // 셸이 들고 있는 집합을 그대로 고치면 취소해도 되돌릴 수 없다. 복사해 둔다.
  late final Set<String> _equipment = {...widget.initial.equipment};
  late final Set<String> _preferences = {...widget.initial.preferences};

  void _toggle(Set<String> values, String value) {
    setState(() {
      if (!values.remove(value)) {
        values.add(value);
      }
    });
  }

  void _save() {
    Navigator.of(context).pop(
      PlanConditions(
        date: _date,
        region: _region,
        people: _people,
        hasCar: _hasCar,
        skillLevel: _skillLevel,
        equipment: _equipment,
        preferences: _preferences,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 4),
              child: Row(
                children: [
                  Expanded(child: Text('조건 수정', style: CampText.sectionTitle)),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: CampColors.inkMuted80),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  FormLabel('캠핑 날짜', color: CampColors.primaryDark),
                  DatePickerField(
                    date: _date,
                    onChanged: (date) => setState(() => _date = date),
                  ),
                  const SizedBox(height: 22),
                  FormLabel('지역', color: CampColors.primaryDark),
                  RegionPicker(
                    selected: _region,
                    onChanged: (region) => setState(() => _region = region),
                  ),
                  const SizedBox(height: 22),
                  FormLabel('인원 수', color: CampColors.primaryDark),
                  PeopleStepper(
                    value: _people,
                    onChanged: (people) => setState(() => _people = people),
                  ),
                  const SizedBox(height: 22),
                  FormLabel('차량 보유 여부'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      CampChoiceChip(
                        label: '차량 있음',
                        selected: _hasCar,
                        onTap: () => setState(() => _hasCar = true),
                      ),
                      CampChoiceChip(
                        label: '차량 없음',
                        selected: !_hasCar,
                        onTap: () => setState(() => _hasCar = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  FormLabel('캠핑 숙련도'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: CampData.skillLevels
                        .map(
                          (skill) => CampChoiceChip(
                            label: skill,
                            selected: _skillLevel == skill,
                            onTap: () => setState(() => _skillLevel = skill),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 22),
                  FormLabel('보유 장비'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: CampData.equipmentOptions
                        .map(
                          (item) => CampChoiceChip(
                            label: item.label,
                            selected: _equipment.contains(item.apiValue),
                            onTap: () => _toggle(_equipment, item.apiValue),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 22),
                  FormLabel('선호 조건'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: CampData.preferenceOptions
                        .map(
                          (item) => CampChoiceChip(
                            label: item.label,
                            selected: _preferences.contains(item.apiValue),
                            onTap: () => _toggle(_preferences, item.apiValue),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            BottomActionBar(
              child: CampButton(label: '이 조건으로 저장', onPressed: _save),
            ),
          ],
        ),
      ),
    );
  }
}

typedef CampsiteMapBuilder =
    Widget Function(List<Campsite> sites, ValueChanged<Campsite> onSelect);

class CampsiteBrowseScreen extends StatefulWidget {
  const CampsiteBrowseScreen({
    required this.title,
    required this.subtitle,
    required this.future,
    required this.emptyText,
    required this.onRetry,
    required this.onSelect,
    required this.mapViewBuilder,
    super.key,
  });

  final String title;
  final String subtitle;
  final Future<List<Campsite>>? future;
  final String emptyText;
  final VoidCallback onRetry;
  final ValueChanged<Campsite> onSelect;
  final CampsiteMapBuilder mapViewBuilder;

  @override
  State<CampsiteBrowseScreen> createState() => _CampsiteBrowseScreenState();
}

class _CampsiteBrowseScreenState extends State<CampsiteBrowseScreen> {
  bool _showMap = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: CampText.displaySmall),
              const SizedBox(height: 12),
              Row(
                children: [
                  CampChoiceChip(
                    label: '리스트',
                    selected: !_showMap,
                    onTap: () => setState(() => _showMap = false),
                  ),
                  const SizedBox(width: 8),
                  CampChoiceChip(
                    label: '지도',
                    selected: _showMap,
                    onTap: () => setState(() => _showMap = true),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Campsite>>(
            future: widget.future,
            builder: (context, snapshot) {
              if (widget.future == null ||
                  snapshot.connectionState == ConnectionState.waiting) {
                return LoadingPanel();
              }
              if (snapshot.hasError) {
                final error = snapshot.error;
                if (error is LocationBlockedException) {
                  return _LocationBlockedPanel(
                    error: error,
                    onRetry: widget.onRetry,
                    onOpenSettings: () => const GeolocatorLocationProvider()
                        .openSettings(error.reason),
                  );
                }
                return ErrorPanel(
                  message: error.toString(),
                  onRetry: widget.onRetry,
                );
              }
              final sites = snapshot.data ?? <Campsite>[];
              if (sites.isEmpty) {
                return EmptyPanel(
                  text: widget.emptyText,
                  onRetry: widget.onRetry,
                );
              }
              if (_showMap) {
                return widget.mapViewBuilder(sites, widget.onSelect);
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  Text(
                    widget.subtitle,
                    style: CampText.body.copyWith(color: CampColors.inkMuted80),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < sites.length; i++) ...[
                    CampsiteCard(
                      site: sites[i],
                      showScore: false,
                      onTap: () => widget.onSelect(sites[i]),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class CampsiteListScreen extends StatelessWidget {
  const CampsiteListScreen({
    required this.title,
    required this.subtitle,
    required this.future,
    required this.emptyText,
    required this.onRetry,
    required this.onResetCondition,
    required this.onSelect,
    required this.entry,
    super.key,
  });

  final String title;
  final String subtitle;
  final Future<List<Campsite>>? future;
  final String emptyText;
  final VoidCallback onRetry;
  final VoidCallback? onResetCondition;
  final ValueChanged<Campsite> onSelect;
  final DetailEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(title, style: CampText.displaySmall),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: CampText.body.copyWith(color: CampColors.inkMuted80),
        ),
        if (onResetCondition != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onResetCondition,
              style: TextButton.styleFrom(
                foregroundColor: CampColors.primaryDark,
                padding: EdgeInsets.zero,
                textStyle: CampText.captionStrong,
              ),
              child: const Text('조건 다시 설정하기'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        FutureBuilder<List<Campsite>>(
          future: future,
          builder: (context, snapshot) {
            if (future == null ||
                snapshot.connectionState == ConnectionState.waiting) {
              return LoadingPanel();
            }
            if (snapshot.hasError) {
              return ErrorPanel(
                message: snapshot.error.toString(),
                onRetry: onRetry,
              );
            }
            final sites = snapshot.data ?? <Campsite>[];
            if (sites.isEmpty) {
              return EmptyPanel(text: emptyText, onRetry: onRetry);
            }
            return Column(
              children: [
                for (var i = 0; i < sites.length; i++) ...[
                  CampsiteCard(
                        site: sites[i],
                        showScore: entry == DetailEntry.recommendations,
                        onTap: () => onSelect(sites[i]),
                      )
                      .animate()
                      .fadeIn(duration: 320.ms, delay: (60 * i).ms)
                      .slideY(
                        begin: 0.1,
                        end: 0,
                        duration: 320.ms,
                        delay: (60 * i).ms,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 하트를 눌러 저장해 둔 캠핑장 목록. 저장된 값을 그대로 그리므로
/// 네트워크 없이도 보인다.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({
    required this.sites,
    required this.onSelect,
    required this.onStartRecommend,
    super.key,
  });

  final List<Campsite> sites;
  final ValueChanged<Campsite> onSelect;
  final VoidCallback onStartRecommend;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text('찜한 캠핑장', style: CampText.displaySmall),
        const SizedBox(height: 4),
        Text(
          '하트를 누른 캠핑장은 이 기기에 저장됩니다.',
          style: CampText.body.copyWith(color: CampColors.inkMuted80),
        ),
        const SizedBox(height: 12),
        if (sites.isEmpty)
          CampCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '아직 찜한 캠핑장이 없어요',
                  style: CampText.sectionTitle.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 8),
                Text(
                  '추천 카드나 상세 화면에서 하트를 누르면 여기에 모입니다.',
                  style: CampText.caption.copyWith(
                    color: CampColors.inkMuted80,
                  ),
                ),
                const SizedBox(height: 16),
                CampButton(
                  label: '추천 시작',
                  icon: LucideIcons.sparkles,
                  background: CampColors.forest,
                  onPressed: onStartRecommend,
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < sites.length; i++) ...[
            CampsiteCard(
                  site: sites[i],
                  // 추천에서 온 캠핑장만 점수가 있어 목록 안에서 들쭉날쭉해진다.
                  showScore: false,
                  // 찜 당시 검색 지역 기준 거리라 갱신되지 않으므로 보여주지 않는다.
                  showDistance: false,
                  onTap: () => onSelect(sites[i]),
                )
                .animate()
                .fadeIn(duration: 320.ms, delay: (60 * i).ms)
                .slideY(
                  begin: 0.1,
                  end: 0,
                  duration: 320.ms,
                  delay: (60 * i).ms,
                  curve: Curves.easeOutCubic,
                ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

/// 디자인의 "오늘의 추천" 화면. 카드를 좌우로 넘기며 한 곳씩 고른다.
class RecommendationSwipeScreen extends StatefulWidget {
  const RecommendationSwipeScreen({
    required this.title,
    required this.subtitle,
    required this.future,
    required this.emptyText,
    required this.onRetry,
    required this.onResetCondition,
    required this.onSelect,
    required this.onFavorite,
    required this.isFavorite,
    super.key,
  });

  final String title;
  final String subtitle;
  final Future<List<Campsite>>? future;
  final String emptyText;
  final VoidCallback onRetry;
  final VoidCallback? onResetCondition;
  final ValueChanged<Campsite> onSelect;
  final ValueChanged<Campsite> onFavorite;
  final bool Function(Campsite) isFavorite;

  @override
  State<RecommendationSwipeScreen> createState() =>
      _RecommendationSwipeScreenState();
}

class _RecommendationSwipeScreenState extends State<RecommendationSwipeScreen>
    with SingleTickerProviderStateMixin {
  static const _exitRotation = 16 * math.pi / 180;

  late final AnimationController _exit;
  int _index = 0;
  double _dragX = 0;
  int _exitSign = 0;

  @override
  void initState() {
    super.initState();
    _exit =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 280),
        )..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          setState(() {
            _index++;
            _dragX = 0;
            _exitSign = 0;
          });
          _exit.reset();
        });
  }

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  void _swipe(int sign, Campsite site) {
    if (_exit.isAnimating) return;
    if (sign > 0) widget.onFavorite(site);
    setState(() => _exitSign = sign);
    _exit.forward(from: 0);
  }

  void _reset() {
    _exit.reset();
    setState(() {
      _index = 0;
      _dragX = 0;
      _exitSign = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        FutureBuilder<List<Campsite>>(
          future: widget.future,
          builder: (context, snapshot) {
            if (widget.future == null ||
                snapshot.connectionState == ConnectionState.waiting) {
              return LoadingPanel();
            }
            if (snapshot.hasError) {
              return ErrorPanel(
                message: snapshot.error.toString(),
                onRetry: widget.onRetry,
              );
            }
            final sites = snapshot.data ?? <Campsite>[];
            if (sites.isEmpty) {
              return EmptyPanel(
                text: widget.emptyText,
                onRetry: widget.onRetry,
              );
            }
            return _buildDeck(sites);
          },
        ),
      ],
    );
  }

  Widget _buildDeck(List<Campsite> sites) {
    final done = _index >= sites.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(widget.title, style: CampText.displaySmall)),
            Text(
              '${done ? sites.length : _index + 1} / ${sites.length}',
              style: CampText.captionStrong.copyWith(
                color: CampColors.inkMuted80,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          widget.subtitle,
          style: CampText.caption.copyWith(color: CampColors.inkMuted80),
        ),
        if (widget.onResetCondition != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.onResetCondition,
              style: TextButton.styleFrom(
                foregroundColor: CampColors.primaryDark,
                padding: EdgeInsets.zero,
                textStyle: CampText.captionStrong,
              ),
              child: const Text('조건 다시 설정하기'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (done) _buildDoneCard() else ..._buildActiveDeck(sites),
      ],
    );
  }

  List<Widget> _buildActiveDeck(List<Campsite> sites) {
    final current = sites[_index];
    final next = _index + 1 < sites.length ? sites[_index + 1] : null;
    return [
      SizedBox(
        height: 420,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              children: [
                // 뒤에 깔린 다음 카드. 넘길 대상이 더 있다는 걸 보여준다.
                if (next != null)
                  Positioned.fill(
                    child: Transform.translate(
                      offset: const Offset(0, 10),
                      child: Transform.scale(
                        scale: 0.95,
                        child: Opacity(
                          opacity: 0.6,
                          child: _RecommendationCard(site: next),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _exit,
                    builder: (context, child) {
                      final flying = _exitSign != 0;
                      final target = _exitSign * width * 1.4;
                      final dx = flying
                          ? _dragX + (target - _dragX) * _exit.value
                          : _dragX;
                      final rotation = flying
                          ? _exitRotation * _exitSign * _exit.value
                          : _exitRotation * (dx / width).clamp(-1.0, 1.0);
                      return Transform.translate(
                        offset: Offset(dx, 0),
                        child: Transform.rotate(
                          angle: rotation,
                          child: Opacity(
                            opacity: flying ? 1 - _exit.value : 1,
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: GestureDetector(
                      onTap: () => widget.onSelect(current),
                      onHorizontalDragUpdate: (details) {
                        if (_exit.isAnimating) return;
                        setState(() => _dragX += details.delta.dx);
                      },
                      onHorizontalDragEnd: (_) {
                        if (_exit.isAnimating) return;
                        if (_dragX.abs() > width * 0.28) {
                          _swipe(_dragX.isNegative ? -1 : 1, current);
                        } else {
                          setState(() => _dragX = 0);
                        }
                      },
                      child: _RecommendationCard(site: current),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      const SizedBox(height: 22),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _SwipeActionButton(
            icon: LucideIcons.x,
            iconColor: const Color(0xFFB5665A),
            background: CampColors.surface,
            borderColor: CampColors.hairline,
            semanticLabel: '이 캠핑장 넘기기',
            onPressed: () => _swipe(-1, current),
          ),
          const SizedBox(width: 24),
          _SwipeActionButton(
            icon: widget.isFavorite(current)
                ? Icons.favorite
                : Icons.favorite_border,
            iconColor: CampColors.onPrimary,
            background: CampColors.primary,
            filled: true,
            semanticLabel: '이 캠핑장 저장하기',
            onPressed: () => _swipe(1, current),
          ),
        ],
      ),
    ];
  }

  Widget _buildDoneCard() {
    return CampCard(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      child: Column(
        children: [
          Text(
            '모든 추천을 확인했어요!',
            style: CampText.sectionTitle.copyWith(fontSize: 21),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '이제 체크리스트를 준비해볼까요?',
            style: CampText.caption.copyWith(color: CampColors.inkMuted80),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          CampButton.secondary(
            label: '다시 보기',
            foreground: CampColors.forest,
            borderColor: CampColors.forest,
            onPressed: _reset,
          ),
        ],
      ),
    );
  }
}

/// 추천 덱의 카드 한 장. 사진 위에 이름·평점·거리·태그를 얹는다.
class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.site});

  final Campsite site;

  @override
  Widget build(BuildContext context) {
    final url = site.validThumbnailUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CampColors.surface,
          boxShadow: [
            BoxShadow(
              color: CampColors.shadow,
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url == null)
              CampsiteCoverImage(site: site)
            else
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    CampsiteCoverImage(site: site),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.4, 1],
                  colors: [Color(0x0D0E1F17), Color(0xE60E1F17)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          site.name,
                          style: CampText.display.copyWith(
                            fontSize: 26,
                            color: CampPalette.light.surface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        LucideIcons.star,
                        size: 15,
                        color: CampPalette.dark.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        site.ratingLabel,
                        style: CampText.captionStrong.copyWith(
                          fontSize: 14,
                          color: CampPalette.light.amberTint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    site.lineIntro,
                    style: CampText.caption.copyWith(
                      fontSize: 13,
                      color: CampPalette.light.greenTint,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in site.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: CampPalette.light.canvas.withValues(
                              alpha: 0.18,
                            ),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            tag,
                            style: CampText.finePrint.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: CampPalette.light.surface,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeActionButton extends StatelessWidget {
  const _SwipeActionButton({
    required this.icon,
    required this.iconColor,
    required this.background,
    required this.semanticLabel,
    required this.onPressed,
    this.borderColor,
    this.filled = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color background;
  final Color? borderColor;
  final bool filled;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: borderColor == null
                ? null
                : Border.all(color: borderColor!, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: CampColors.shadow,
                blurRadius: filled ? 22 : 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, size: 24, color: iconColor),
        ),
      ),
    );
  }
}

class CampsiteDetailScreen extends StatelessWidget {
  const CampsiteDetailScreen({
    required this.api,
    required this.site,
    required this.region,
    required this.hasCar,
    required this.onBack,
    required this.onCommunity,
    required this.onPrepare,
    required this.isFavorite,
    required this.onToggleFavorite,
    this.reservationService,
    this.openUrl,
    super.key,
  });

  final CampOnApi api;
  final Campsite? site;
  final CampRegion region;
  final bool hasCar;
  final VoidCallback onBack;
  final VoidCallback onCommunity;
  final VoidCallback onPrepare;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final CampsiteReservationService? reservationService;
  final Future<bool> Function(Uri)? openUrl;

  @override
  Widget build(BuildContext context) {
    final campsite = site;
    if (campsite == null) {
      return MissingState(
        title: '캠핑장을 먼저 선택해주세요.',
        actionLabel: '홈으로 돌아가기',
        onPressed: onBack,
      );
    }

    final imageUrls = campsite.validImageUrls.isNotEmpty
        ? campsite.validImageUrls
        : <String>[?campsite.validThumbnailUrl];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              _CampsiteDetailHero(
                site: campsite,
                regionName: region.name,
                onBack: onBack,
                isFavorite: isFavorite,
                onToggleFavorite: onToggleFavorite,
              ),
              _CampsiteDetailSummary(
                site: campsite,
                reservationService:
                    reservationService ?? CampsiteReservationService.shared,
                openUrl: openUrl,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (campsite.lineIntro.isNotEmpty ||
                        campsite.description.isNotEmpty) ...[
                      _DetailSection(
                        title: '소개',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (campsite.lineIntro.isNotEmpty) ...[
                              Text(
                                campsite.lineIntro,
                                style: CampText.bodyStrong.copyWith(
                                  fontSize: 16,
                                  color: CampColors.ink,
                                ),
                              ),
                              if (campsite.description.isNotEmpty)
                                const SizedBox(height: 8),
                            ],
                            if (campsite.description.isNotEmpty)
                              Text(
                                campsite.description,
                                style: CampText.body.copyWith(
                                  color: CampColors.inkMuted80,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const _DetailDivider(),
                    ],
                    _DetailSection(
                      key: const Key('campsite-detail-facilities'),
                      title: '편의시설',
                      child: _FacilityOverview(site: campsite),
                    ),
                    if (campsite.equipmentRental.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        '대여 가능',
                        style: CampText.captionStrong.copyWith(
                          color: CampColors.inkMuted48,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in campsite.equipmentRental)
                            TipTag(label: item),
                        ],
                      ),
                    ],
                    const _DetailDivider(),
                    _DetailSection(
                      title: '날씨',
                      child: CampsiteWeatherCard(
                        lat: campsite.lat,
                        lon: campsite.lon,
                      ),
                    ),
                    const _DetailDivider(),
                    _DetailSection(
                      title: hasCar ? '차량 이동' : '대중교통 · 도보 이동',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            campsite.accessDescription(hasCar: hasCar),
                            style: CampText.body.copyWith(
                              color: CampColors.inkMuted80,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DirectionsCard(
                            fetchDirections: api.fetchDirections,
                            location: const GeolocatorLocationProvider(),
                            site: campsite,
                            hasCar: hasCar,
                          ),
                        ],
                      ),
                    ),
                    if (imageUrls.isNotEmpty) ...[
                      const _DetailDivider(),
                      _DetailSection(
                        title: '사진으로 둘러보기',
                        child: CampsiteSpatialPreviewCard(
                          campsiteName: campsite.name,
                          imageUrls: imageUrls,
                        ),
                      ),
                    ],
                    const _DetailDivider(),
                    _DetailSection(
                      title: '캠퍼들의 이야기',
                      child: _DetailLinkCard(
                        icon: LucideIcons.messagesSquare,
                        text: '후기를 확인하고 내 이야기도 남겨보세요.',
                        actionLabel: '커뮤니티 열기',
                        onTap: onCommunity,
                      ),
                    ),
                    const _DetailDivider(),
                    _DetailSection(
                      title: '그날 밤',
                      child: NightPreviewButton(
                        placeName: campsite.name,
                        lat: campsite.lat,
                        lon: campsite.lon,
                        actionLabel: '이 캠핑장으로 준비 시작',
                        onAction: onPrepare,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        BottomActionBar(
          child: CampButton(label: '이 캠핑장으로 준비 시작', onPressed: onPrepare),
        ),
      ],
    );
  }
}

class _CampsiteDetailHero extends StatelessWidget {
  const _CampsiteDetailHero({
    required this.site,
    required this.regionName,
    required this.onBack,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  final Campsite site;
  final String regionName;
  final VoidCallback onBack;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('campsite-detail-hero'),
      height: 356,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CampsiteHeroImage(
            site: site,
            region: regionName,
            aspectRatio: 1,
            borderRadius: BorderRadius.zero,
            attributionBottom: 108,
          ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.42, 1],
                  colors: [
                    Color(0x59000000),
                    Colors.transparent,
                    Color(0xD9000000),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            top: 4,
            child: BackCircleButton(onPressed: onBack, onImage: true),
          ),
          Positioned(
            right: 20,
            top: 4,
            child: FavoriteHeartButton(
              isFavorite: isFavorite,
              onPressed: onToggleFavorite,
              onImage: true,
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 34,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  site.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CampText.displaySmall.copyWith(
                    fontSize: 25,
                    height: 1.2,
                    color: Colors.white,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 10),
                    ],
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

class _CampsiteDetailSummary extends StatelessWidget {
  const _CampsiteDetailSummary({
    required this.site,
    required this.reservationService,
    this.openUrl,
  });

  final Campsite site;
  final CampsiteReservationService reservationService;
  final Future<bool> Function(Uri)? openUrl;

  Future<void> _openReservation(BuildContext context) async {
    final uri =
        site.validReservationUri ??
        await reservationService.lookup(name: site.name) ??
        naverReservationSearchUri(site.name);
    final opener =
        openUrl ??
        (Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);
    final opened = await opener(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('링크를 열지 못했습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('campsite-detail-summary'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: CampColors.surface,
        border: Border(bottom: BorderSide(color: CampColors.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryMetric(
              label: '예약 정보',
              value: site.validReservationUri == null ? '네이버 찾기' : '예약하기',
              onTap: () => _openReservation(context),
            ),
          ),
          const _SummaryDivider(),
          Expanded(
            child: _SummaryMetric(
              label: '거리',
              value: site.distance > 0 ? _formatDistance(site.distance) : '—',
            ),
          ),
          const _SummaryDivider(),
          Expanded(
            child: _SummaryMetric(
              label: '시설 점수',
              value: '${site.ratingLabel} / 5',
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: CampText.finePrint.copyWith(color: CampColors.inkMuted48),
        ),
        const SizedBox(height: 7),
        Text(
          value,
          style: CampText.bodyStrong.copyWith(
            fontSize: 17,
            color: CampColors.ink,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: VerticalDivider(width: 1, color: CampColors.hairline),
  );
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: CampText.sectionTitle.copyWith(fontSize: 20)),
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}

class _DetailDivider extends StatelessWidget {
  const _DetailDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 26),
    child: Divider(height: 1, color: CampColors.hairline),
  );
}

class _FacilityOverview extends StatelessWidget {
  const _FacilityOverview({required this.site});

  final Campsite site;

  @override
  Widget build(BuildContext context) {
    final facilities = <(IconData, String, int)>[
      (Icons.wc_outlined, '화장실', site.facilityScore('TOILET')),
      (Icons.shower_outlined, '샤워실', site.facilityScore('SHOWER')),
      (Icons.water_drop_outlined, '개수대', site.facilityScore('SINK')),
      (Icons.electric_bolt_outlined, '전기', site.facilityScore('ELECTRICITY')),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final facility in facilities)
              SizedBox(
                width: width,
                child: _FacilityTile(
                  icon: facility.$1,
                  label: facility.$2,
                  value: '${facility.$3} / 5',
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FacilityTile extends StatelessWidget {
  const _FacilityTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CampColors.surface,
        border: Border.all(color: CampColors.hairline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: CampColors.forestMid),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: CampText.captionStrong),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: CampText.finePrint.copyWith(
                    color: CampColors.inkMuted48,
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

class _DetailLinkCard extends StatelessWidget {
  const _DetailLinkCard({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CampColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: CampColors.hairline),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: CampColors.forestMid),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      style: CampText.caption.copyWith(
                        color: CampColors.inkMuted80,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      actionLabel,
                      style: CampText.captionStrong.copyWith(
                        color: CampColors.primaryDark,
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
    );
  }
}

typedef DirectionsFetcher =
    Future<DirectionResult> Function({
      required double originX,
      required double originY,
      required double destX,
      required double destY,
    });

typedef UrlOpener = Future<bool> Function(Uri uri);

class DirectionsCard extends StatefulWidget {
  const DirectionsCard({
    required this.fetchDirections,
    required this.location,
    required this.site,
    required this.hasCar,
    this.openUrl,
    super.key,
  });

  final DirectionsFetcher fetchDirections;
  final LocationProvider location;
  final Campsite site;
  final bool hasCar;
  final UrlOpener? openUrl;

  @override
  State<DirectionsCard> createState() => _DirectionsCardState();
}

class _DirectionsCardState extends State<DirectionsCard> {
  bool _loading = false;
  LocationPoint? _origin;
  DirectionResult? _result;
  Object? _error;

  /// 현재 위치를 먼저 확보한 뒤 그 좌표를 출발지로 길찾기를 요청한다.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final origin = await widget.location.current();
      final result = await widget.fetchDirections(
        originX: origin.lon,
        originY: origin.lat,
        destX: widget.site.lon,
        destY: widget.site.lat,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _origin = origin;
        _result = result;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  /// 이미 확보한 출발지·도착지 좌표로 카카오맵 길찾기를 연다. 모바일웹 스킴을 쓰면
  /// 앱이 설치돼 있을 때는 카카오맵 앱으로, 없을 때는 스토어로 카카오 쪽에서 알아서
  /// 보내주므로 iOS/Android 앱스킴 등록 없이도 동작한다.
  Future<void> _openKakaoMap() async {
    final origin = _origin;
    if (origin == null) {
      return;
    }
    final by = widget.hasCar ? 'car' : 'publictransit';
    final uri = Uri.parse(
      'http://m.map.kakao.com/scheme/route'
      '?sp=${origin.lat},${origin.lon}'
      '&ep=${widget.site.lat},${widget.site.lon}'
      '&by=$by',
    );
    final opener =
        widget.openUrl ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    final opened = await opener(uri);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('링크를 열지 못했습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return CampCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '현재 위치에서 ${widget.site.name}까지 경로를 확인해요.',
            style: CampText.caption.copyWith(color: CampColors.inkMuted80),
          ),
          const SizedBox(height: 12),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return LoadingPanel();
    }

    final error = _error;
    if (error is LocationBlockedException) {
      return _LocationBlockedPanel(
        error: error,
        onRetry: _load,
        onOpenSettings: () => widget.location.openSettings(error.reason),
      );
    }
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('경로를 불러오지 못했어요.', style: CampText.bodyStrong),
          const SizedBox(height: 4),
          Text(
            '$error',
            style: CampText.caption.copyWith(color: CampColors.inkMuted80),
          ),
          const SizedBox(height: 12),
          CampButton.secondary(label: '다시 시도', onPressed: _load),
        ],
      );
    }

    final result = _result;
    if (result == null) {
      return CampButton.secondary(
        label: '경로 확인',
        icon: Icons.directions_outlined,
        onPressed: _load,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _DirectionMetric(
                label: '거리',
                value: _formatDistance(result.distanceMeters),
              ),
            ),
            Expanded(
              child: _DirectionMetric(
                label: '예상 시간',
                value: _formatDuration(result.durationSeconds),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CampButton.secondary(
          label: '카카오맵으로 이동',
          icon: Icons.map_outlined,
          onPressed: _openKakaoMap,
        ),
      ],
    );
  }
}

/// 위치를 얻지 못한 이유별로 안내 문구와 다음 행동을 하나씩 보여준다.
class _LocationBlockedPanel extends StatelessWidget {
  const _LocationBlockedPanel({
    required this.error,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final LocationBlockedException error;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final needsSettings =
        error.reason == LocationBlockReason.serviceDisabled ||
        error.reason == LocationBlockReason.deniedForever;
    final label = switch (error.reason) {
      LocationBlockReason.serviceDisabled => '위치 설정 열기',
      LocationBlockReason.deniedForever => '설정 열기',
      LocationBlockReason.denied => '권한 다시 요청',
      LocationBlockReason.failed => '다시 시도',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('현재 위치를 사용할 수 없어요.', style: CampText.bodyStrong),
        const SizedBox(height: 4),
        Text(
          error.message,
          style: CampText.caption.copyWith(color: CampColors.inkMuted80),
        ),
        const SizedBox(height: 12),
        CampButton.secondary(
          label: label,
          onPressed: needsSettings ? onOpenSettings : onRetry,
        ),
        // 설정을 다녀온 뒤 화면을 다시 열지 않고 바로 재시도할 수 있게 한다.
        if (needsSettings)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: CampColors.primaryDark,
                padding: EdgeInsets.zero,
                textStyle: CampText.captionStrong,
              ),
              child: const Text('다시 시도'),
            ),
          ),
      ],
    );
  }
}

class _DirectionMetric extends StatelessWidget {
  const _DirectionMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: CampText.caption.copyWith(color: CampColors.inkMuted48),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: CampText.sectionTitle.copyWith(color: CampColors.primaryDark),
        ),
      ],
    );
  }
}

class ChecklistScreen extends StatelessWidget {
  const ChecklistScreen({
    required this.selectedSite,
    required this.checkedItems,
    required this.onToggle,
    required this.onReset,
    this.aiItems = const <String>[],
    super.key,
  });

  final Campsite? selectedSite;
  final Set<String> checkedItems;
  final List<String> aiItems;
  final ValueChanged<String> onToggle;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final checklistItems = [
      ...CampData.equipmentOptions,
      ...CampData.fixedChecklist,
    ];
    final doneCount = checklistItems
        .where((item) => checkedItems.contains(item.apiValue))
        .length;
    final missingGear = CampData.equipmentOptions
        .where((item) => !checkedItems.contains(item.apiValue))
        .toList();

    final progress = checklistItems.isEmpty
        ? 0.0
        : doneCount / checklistItems.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text('준비 체크리스트', style: CampText.displaySmall),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: progress,
                  backgroundColor: CampColors.hairline,
                  valueColor: AlwaysStoppedAnimation(CampColors.primary),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$doneCount / ${checklistItems.length}',
              style: CampText.captionStrong.copyWith(
                color: CampColors.inkMuted80,
              ),
            ),
          ],
        ),
        if (selectedSite != null) ...[
          const SizedBox(height: 8),
          Text(
            '${selectedSite!.name} 기준으로 준비하고 있어요.',
            style: CampText.caption.copyWith(color: CampColors.inkMuted48),
          ),
        ],
        if (aiItems.isNotEmpty) ...[
          const SizedBox(height: 22),
          FormLabel('AI 추천 준비물', color: CampColors.primaryDark),
          CampCard(
            padding: const EdgeInsets.all(16),
            backgroundColor: CampColors.greenTint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.sparkles,
                      size: 16,
                      color: CampColors.forest,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'AI 플래너가 이번 캠핑에 맞춰 추천했어요',
                      style: CampText.captionStrong.copyWith(
                        color: CampColors.forest,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in aiItems)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: CampColors.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: CampColors.hairline),
                        ),
                        child: Text(item, style: CampText.caption),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (missingGear.isNotEmpty) ...[
          const SizedBox(height: 22),
          FormLabel('부족한 장비', color: CampColors.primaryDark),
          Column(
            children: [
              for (final item in missingGear) ...[
                CampCard(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: CampColors.amberTint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: CampText.sectionTitle.copyWith(fontSize: 17),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.note,
                        style: CampText.caption.copyWith(
                          color: CampColors.inkMuted80,
                        ),
                      ),
                      if (selectedSite?.equipmentRental.contains(
                            item.apiValue,
                          ) ??
                          false) ...[
                        const SizedBox(height: 8),
                        Text(
                          '이 캠핑장에서 대여 가능해요.',
                          style: CampText.captionStrong.copyWith(
                            color: CampColors.primaryDark,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ],
        const SizedBox(height: 14),
        FormLabel('체크리스트', color: CampColors.forestMid),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: CampColors.hairline),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                for (var index = 0; index < checklistItems.length; index++)
                  ChecklistRow(
                    item: checklistItems[index],
                    checked: checkedItems.contains(
                      checklistItems[index].apiValue,
                    ),
                    showDivider: index != checklistItems.length - 1,
                    onTap: () => onToggle(checklistItems[index].apiValue),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onReset,
            style: TextButton.styleFrom(
              foregroundColor: CampColors.primaryDark,
              padding: EdgeInsets.zero,
              textStyle: CampText.captionStrong,
            ),
            child: const Text('처음부터 다시 시작하기'),
          ),
        ),
      ],
    );
  }
}

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    required this.api,
    required this.site,
    required this.onBack,
    super.key,
  });

  final CampOnApi api;
  final Campsite? site;
  final VoidCallback onBack;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  Future<List<CampPost>>? _postsFuture;
  bool _composing = false;
  bool _submitting = false;

  /// 차단한 유저 ID 집합 (글 필터링에 사용)
  Set<int> _blockedUserIds = const {};

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
    _reload();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  /// 차단 목록 로드 (글 목록 필터링용)
  Future<void> _loadBlockedUsers() async {
    try {
      final blocked = await widget.api.getBlockedUsers();
      if (mounted) {
        setState(() {
          _blockedUserIds = blocked.map((b) => b.blockedUserId).toSet();
        });
      }
    } catch (_) {
      // 차단 목록 조회 실패 시 필터링 없이 진행
    }
  }

  void _reload() {
    final site = widget.site;
    if (site == null) {
      return;
    }
    setState(() {
      _postsFuture = widget.api.fetchPosts(campsiteId: site.id);
    });
  }

  /// 특정 유저를 차단하고 목록에서 즉시 제거
  Future<void> _blockUser(int userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이 유저를 차단할까요?'),
        content: const Text('차단한 유저의 글은 더 이상 표시되지 않아요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('차단', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.blockUser(userId);
      if (mounted) {
        setState(() {
          _blockedUserIds = {..._blockedUserIds, userId};
        });
        _showMessage('해당 유저를 차단했어요. 이 유저의 글이 숨겨집니다.');
      }
    } catch (e) {
      if (mounted) _showMessage('차단에 실패했어요: $e');
    }
  }

  Future<void> _submitPost() async {
    final site = widget.site;
    if (site == null || _submitting) {
      return;
    }
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      _showMessage('제목과 내용을 모두 입력해주세요.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.api.createPost(
        campsiteId: site.id,
        title: title,
        content: content,
      );
      if (!mounted) {
        return;
      }
      _titleController.clear();
      _contentController.clear();
      setState(() => _composing = false);
      _showMessage('글을 등록했어요.');
      _reload();
    } catch (error) {
      if (mounted) {
        _showMessage('$error');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _deletePost(CampPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('글을 삭제할까요?'),
        content: const Text('삭제한 글은 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.api.deletePost(post.id);
      if (!mounted) {
        return;
      }
      _showMessage('글을 삭제했어요.');
      _reload();
    } catch (error) {
      if (mounted) {
        _showMessage('$error');
      }
    }
  }

  /// 게시글 신고 POST /api/v1/posts/{postId}/reports
  Future<void> _reportPost(CampPost post) async {
    final reasons = <String>['스팸/광고', '욕설/혐오 표현', '허위 정보', '기타'];
    String? selectedReason = reasons.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('신고하기'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('신고 사유를 선택해주세요.'),
              const SizedBox(height: 8),
              ...reasons.map(
                (r) => InkWell(
                  onTap: () => setDlgState(() => selectedReason = r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          selectedReason == r
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 20,
                          color: selectedReason == r
                              ? CampColors.forestMid
                              : CampColors.inkMuted48,
                        ),
                        const SizedBox(width: 8),
                        Text(r, style: CampText.body),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('신고'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selectedReason == null) return;
    try {
      await widget.api.reportPost(postId: post.id, reason: selectedReason!);
      if (mounted) _showMessage('신고가 접수되었어요.');
    } catch (e) {
      if (mounted) _showMessage('신고에 실패했어요: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    if (site == null) {
      return MissingState(
        title: '캠핑장을 먼저 선택해주세요.',
        actionLabel: '돌아가기',
        onPressed: widget.onBack,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        // 상세 화면과 같은 크기·위치로 두려면 가로로 늘어나지 않게 Row로 감싼다.
        Row(children: [BackCircleButton(onPressed: widget.onBack)]),
        const SizedBox(height: 14),
        Text(
          '${site.name} 커뮤니티',
          style: CampText.displaySmall.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 4),
        Text(
          '이 캠핑장을 다녀온 캠퍼들의 글이에요.',
          style: CampText.body.copyWith(color: CampColors.inkMuted80),
        ),
        const SizedBox(height: 14),
        if (_composing)
          _buildComposer()
        else
          CampButton(
            label: '글쓰기',
            icon: Icons.edit_outlined,
            onPressed: () => setState(() => _composing = true),
          ),
        const SizedBox(height: 18),
        FutureBuilder<List<CampPost>>(
          future: _postsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return LoadingPanel();
            }
            if (snapshot.hasError) {
              return ErrorPanel(message: '${snapshot.error}', onRetry: _reload);
            }
            final allPosts = snapshot.data ?? const <CampPost>[];
            // 차단한 유저의 글 필터링
            final posts = allPosts
                .where(
                  (p) =>
                      p.authorId == null ||
                      !_blockedUserIds.contains(p.authorId),
                )
                .toList();
            if (posts.isEmpty) {
              return CampCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('아직 등록된 글이 없어요.', style: CampText.bodyStrong),
                    const SizedBox(height: 6),
                    Text(
                      '첫 번째 후기를 남겨보세요.',
                      style: CampText.caption.copyWith(
                        color: CampColors.inkMuted80,
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (final post in posts) ...[
                  _PostCard(
                    post: post,
                    actions: postMenuActions(
                      post: post,
                      currentUserId: widget.api.currentUserId,
                    ),
                    onDelete: () => _deletePost(post),
                    onBlock: () => _blockUser(post.authorId!),
                    onReport: () => _reportPost(post),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildComposer() {
    return CampCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FormLabel('새 글'),
          TextField(
            controller: _titleController,
            style: CampText.bodyStrong,
            decoration: const InputDecoration(
              hintText: '제목',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _contentController,
            style: CampText.body,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: '내용을 입력해주세요.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CampButton.secondary(
                  label: '취소',
                  onPressed: _submitting
                      ? null
                      : () => setState(() => _composing = false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CampButton(
                  label: _submitting ? '등록 중…' : '등록',
                  onPressed: _submitting ? null : _submitPost,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.actions,
    required this.onDelete,
    required this.onBlock,
    required this.onReport,
  });

  final CampPost post;

  /// 더보기 메뉴에 노출할 동작. [postMenuActions]가 정한다.
  final List<PostAction> actions;
  final VoidCallback onDelete;
  final VoidCallback onBlock;
  final VoidCallback onReport;

  static PopupMenuItem<PostAction> _menuItem(PostAction action) {
    final (IconData icon, String label, Color? color) = switch (action) {
      PostAction.delete => (Icons.delete_outline, '삭제', null),
      PostAction.block => (Icons.block, '이 유저 차단', Colors.red),
      PostAction.report => (Icons.flag_outlined, '신고', Colors.orange),
    };
    return PopupMenuItem<PostAction>(
      value: action,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CampCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(post.title, style: CampText.bodyStrong)),
              // 더보기 메뉴 (삭제 / 차단 / 신고)
              PopupMenuButton<PostAction>(
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: Icon(
                  Icons.more_horiz,
                  size: 20,
                  color: CampColors.inkMuted48,
                ),
                onSelected: (action) {
                  switch (action) {
                    case PostAction.delete:
                      onDelete();
                    case PostAction.block:
                      onBlock();
                    case PostAction.report:
                      onReport();
                  }
                },
                itemBuilder: (context) => [
                  for (final action in actions) _menuItem(action),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(post.content, style: CampText.body),
          if (post.metaLabel.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              post.metaLabel,
              style: CampText.finePrint.copyWith(color: CampColors.inkMuted48),
            ),
          ],
        ],
      ),
    );
  }
}

enum PostAction { delete, block, report }

/// 게시글 더보기 메뉴에 노출할 동작을 정한다.
///
/// 서버가 작성자를 안 내려주는 동안에는 내 글인지 가릴 수 없어서, 차단만 숨기고
/// 기존 삭제 동작은 그대로 둔다.
List<PostAction> postMenuActions({
  required CampPost post,
  required int? currentUserId,
}) {
  final authorId = post.authorId;
  if (authorId == null) {
    return const <PostAction>[PostAction.delete, PostAction.report];
  }
  if (currentUserId != null && authorId == currentUserId) {
    return const <PostAction>[PostAction.delete];
  }
  return const <PostAction>[PostAction.block, PostAction.report];
}

/// 차단한 유저 목록을 보여주고 차단을 해제할 수 있는 화면
class BlockManagementScreen extends StatefulWidget {
  const BlockManagementScreen({required this.api, super.key});

  final CampOnApi api;

  @override
  State<BlockManagementScreen> createState() => _BlockManagementScreenState();
}

class _BlockManagementScreenState extends State<BlockManagementScreen> {
  late Future<List<BlockedUser>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = widget.api.getBlockedUsers();
    });
  }

  Future<void> _unblock(BlockedUser user) async {
    try {
      await widget.api.unblockUser(user.blockedUserId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('차단을 해제했어요.')));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('차단 해제에 실패했어요: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('차단 관리'), centerTitle: true),
      body: FutureBuilder<List<BlockedUser>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('목록을 불러오지 못했어요.\n${snapshot.error}'),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _load, child: const Text('다시 시도')),
                ],
              ),
            );
          }
          final list = snapshot.data ?? <BlockedUser>[];
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 48,
                    color: CampColors.inkMuted48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '차단한 유저가 없어요.',
                    style: CampText.body.copyWith(color: CampColors.inkMuted80),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = list[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: CampColors.inkMuted48,
                  child: Icon(Icons.person, color: CampColors.onPrimary),
                ),
                title: Text(user.displayName, style: CampText.bodyStrong),
                subtitle: user.createdAt != null
                    ? Text(
                        '차단일: ${user.createdAt!.year}.${user.createdAt!.month.toString().padLeft(2, '0')}.${user.createdAt!.day.toString().padLeft(2, '0')}',
                        style: CampText.finePrint.copyWith(
                          color: CampColors.inkMuted48,
                        ),
                      )
                    : null,
                trailing: TextButton(
                  onPressed: () => _unblock(user),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('차단 해제'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 앱 버전을 번들에서 읽어 보여준다. 문자열을 직접 적으면 pubspec 버전과 어긋난다.
class AppVersionRow extends StatefulWidget {
  const AppVersionRow({super.key});

  @override
  State<AppVersionRow> createState() => _AppVersionRowState();
}

class _AppVersionRowState extends State<AppVersionRow> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      // 플러그인을 쓸 수 없는 환경(위젯 테스트 등)에서는 비워 둔다.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: Icons.info_outline_rounded,
      title: '버전 정보',
      value: _version,
    );
  }
}

/// 이용약관과 개인정보 처리방침을 여는 링크. URL이 설정된 문서만 보여준다.
class LegalLinkRow extends StatelessWidget {
  const LegalLinkRow({this.color, super.key});

  final Color? color;

  Future<void> _open(
    BuildContext context,
    String url,
    LegalDocument document,
  ) async {
    if (url.isEmpty) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => LegalDocumentScreen(document: document),
        ),
      );
      return;
    }

    final opened = await LegalConfig.open(url);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('링크를 열지 못했습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = CampText.finePrint.copyWith(
      color: color ?? CampColors.greenTint,
      decoration: TextDecoration.underline,
      decorationColor: color ?? CampColors.greenTint,
    );
    final links = <Widget>[
      GestureDetector(
        onTap: () =>
            _open(context, LegalConfig.termsOfServiceUrl, LegalDocument.terms),
        child: Text('이용약관', style: style),
      ),
      GestureDetector(
        onTap: () =>
            _open(context, LegalConfig.privacyPolicyUrl, LegalDocument.privacy),
        child: Text('개인정보 처리방침', style: style),
      ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (index, link) in links.indexed) ...[
          if (index > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('·', style: style.copyWith(decoration: null)),
            ),
          link,
        ],
      ],
    );
  }
}

enum LegalDocument { terms, privacy }

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({required this.document, super.key});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final isTerms = document == LegalDocument.terms;
    final title = isTerms ? '이용약관' : '개인정보 처리방침';
    final effectiveDate = isTerms ? '2026년 8월 3일' : '2026년 9월 1일';
    final body = isTerms
        ? LegalDocuments.terms(contactEmail: LegalConfig.contactEmail)
        : LegalDocuments.privacy();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Text(title, style: CampText.displaySmall),
              const SizedBox(height: 8),
              Text(
                '시행일: $effectiveDate',
                style: CampText.caption.copyWith(color: CampColors.inkMuted80),
              ),
              const SizedBox(height: 20),
              Text(body, style: CampText.body.copyWith(height: 1.65)),
            ],
          ),
        ),
      ),
    );
  }
}

class LegalDocuments {
  const LegalDocuments._();

  static String terms({required String contactEmail}) =>
      '''
제1조 (목적)
이 약관은 CampOn(이하 “서비스”)의 이용 조건, 이용자와 운영자의 권리·의무 및 책임 사항을 정합니다.

제2조 (서비스)
서비스는 캠핑장 정보, 추천, 길찾기, 날씨·AI 기반 플랜, 체크리스트 및 커뮤니티 게시글 기능을 제공합니다. 날씨, 길찾기, AI 생성 결과와 캠핑장 정보는 참고용이며, 실제 기상·시설·교통·안전 상황을 보장하지 않습니다. 캠핑 전에는 캠핑장과 관계 기관의 최신 안내를 확인해야 합니다.

제3조 (계정과 이용)
이용자는 Apple, Google 또는 Kakao 계정으로 로그인할 수 있습니다. 이용자는 자신의 계정 접근 정보를 안전하게 관리해야 하며, 타인의 계정을 사용하거나 서비스 운영을 방해해서는 안 됩니다.

제4조 (이용자 콘텐츠)
커뮤니티에 작성하는 제목, 본문 등 콘텐츠의 책임은 작성자에게 있습니다. 이용자는 타인의 권리·개인정보를 침해하거나, 불법·혐오·음란·위협·광고성 내용을 게시해서는 안 됩니다. 운영자는 법령 또는 이 약관에 위반되는 콘텐츠를 삭제하거나 이용을 제한할 수 있습니다. 자신의 게시글은 앱에서 삭제할 수 있으며, 권리 침해 신고는 아래 문의처로 알려주시기 바랍니다.

제5조 (지식재산권)
서비스의 화면, 상표, 소프트웨어 및 운영자가 제공하는 콘텐츠에 관한 권리는 운영자 또는 정당한 권리자에게 있습니다. 이용자가 작성한 콘텐츠의 권리는 작성자에게 남지만, 서비스 제공·표시·운영에 필요한 범위에서 운영자에게 비독점적으로 이용을 허락합니다.

제6조 (서비스 변경 및 중단)
운영자는 운영·보안·법령상 필요한 경우 서비스의 전부 또는 일부를 변경하거나 중단할 수 있습니다. 중요한 변경은 앱 또는 공개된 처리방침 페이지를 통해 안내합니다.

제7조 (책임의 제한)
운영자는 고의 또는 중대한 과실이 없는 한, 통신 장애·외부 서비스 장애·이용자 입력 오류·천재지변 등 통제할 수 없는 사유로 발생한 손해에 책임을 지지 않습니다. 이용자는 안전 수칙과 현장 규정을 준수하고, 위험한 기상 또는 현장 상황에서는 캠핑을 취소하거나 관계 기관의 지침을 따라야 합니다.

제8조 (문의 및 약관 변경)
문의, 신고 및 권리 침해 통지는 $contactEmail 로 보내실 수 있습니다. 이 약관은 법령이나 서비스 변경에 따라 개정될 수 있으며, 중요한 변경은 시행 전에 앱 또는 공개 페이지로 안내합니다.
''';

  static String privacy() => '''
제1조 (개인정보의 처리 목적)
CAMPON은 다음 목적을 위해 개인정보를 처리합니다.
1. 캠핑장 추천 및 이동 가능성·시설 적합도 계산
2. 장비 부족 분석 및 준비 체크리스트 생성
3. 날씨 기반 리스크 안내
4. 회원 가입 및 관리
5. 위치 기반 길찾기 및 주변 캠핑장 안내

제2조 (처리하는 개인정보 항목)
회원가입(OAuth): OAuth 제공자(Apple, Google, Kakao)로부터 전달받는 이메일, 고유식별자(OAuth ID) 및 제공자가 제공에 동의한 최소한의 프로필 정보. 비밀번호는 자체적으로 수집·저장하지 않습니다(OAuth 제공자가 인증을 담당).

서비스 이용(필수): 캠핑 날짜, 희망 지역, 인원 수, 차량 보유 여부, 캠핑 숙련도, 보유 장비, 가족 동반 여부, 선호 조건(전기 사용, 샤워실, 화장실 청결도, 아이 동반 등) — 개인 맞춤형 추천 기능 제공을 위한 필수 입력값입니다.

위치정보(선택): 이용자가 길찾기 또는 주변 정보 기능을 직접 요청하고 위치 권한을 허용한 경우에만 수집합니다. 거리·이동 경로·주변 캠핑장 및 날씨 정보 제공에 사용하며, 백그라운드 위치는 수집하지 않습니다.

커뮤니티 게시글(선택): 게시글 작성 시 입력하는 제목과 본문.

참고: OAuth 제공자가 자체적으로 수집하는 정보는 각 제공자의 개인정보처리방침이 적용되며, 본 서비스는 인증 과정에서 제공자로부터 전달받는 최소한의 정보만 처리합니다. AI 플랜 요청에는 이메일과 이름을 포함하지 않으며, 이용자가 질문이나 게시글에 개인정보를 직접 입력하지 않도록 유의해야 합니다.

제3조 (기기에 저장하는 정보)
로그인 토큰은 iOS Keychain 또는 Android 보안 저장소에 저장합니다. 즐겨찾기 캠핑장과 일부 앱 설정은 기기에 저장되며 다른 이용자에게 공개되지 않습니다. 앱을 삭제하면 기기에 저장된 정보도 함께 삭제됩니다.

제4조 (개인정보의 처리 및 보유 기간)
서비스 이용 목적 달성 시 또는 회원 탈퇴 시까지 보유하며, 이후 지체 없이 파기합니다.

제5조 (개인정보 처리업무의 위탁)
CAMPON은 서비스 제공을 위해 다음과 같이 처리업무를 위탁하고 있습니다.

· 수탁자: Google LLC (Gemini API) / 위탁 업무 내용: 사용자 입력값 정규화, 캠핑 준비 가이드 텍스트 생성 / 보유·이용 기간: 위탁 업무 수행 목적 달성 시까지(수탁자 정책에 따름)
· 수탁자: Microsoft Azure / 위탁 업무 내용: AI 프록시 서버 운영 / 보유·이용 기간: 위탁 업무 수행 목적 달성 시까지(수탁자 정책에 따름)
· 수탁자: Kakao(카카오맵) / 위탁 업무 내용: 캠핑장 위치 정보 지도 표시 / 보유·이용 기간: 위탁 업무 수행 목적 달성 시까지(수탁자 정책에 따름)
· 수탁자: Open-Meteo / 위탁 업무 내용: 캠핑장 좌표 기반 날씨 조회 / 보유·이용 기간: 위탁 업무 수행 목적 달성 시까지(수탁자 정책에 따름)

제6조 (개인정보의 국외 이전)
CAMPON은 Gemini API(Google LLC) 및 Azure(Microsoft) 이용을 위해 다음과 같이 개인정보를 국외로 이전합니다.

· 이전받는 자: Google LLC, Microsoft Corporation
· 이전되는 국가: 미국 등 각 사 또는 그 대리인이 시설을 운영하는 국가(각 사가 특정 국가를 보장하지 않음)
· 이전 일시 및 방법: 서비스 이용 시 네트워크를 통한 실시간 API 전송
· 이전 항목: 캠핑 날짜, 지역, 인원 수, 차량 보유 여부, 숙련도, 보유 장비, 선호 조건 등 추천에 필요한 입력값(OAuth 이메일 등 식별정보는 전송하지 않음)
· 이전받는 자의 이용 목적 및 보유·이용 기간: AI 응답 생성 및 서버 운영 목적으로만 처리하며, 유료 서비스 기준 각 사는 정책 위반 감지 등 제한된 목적으로 일정 기간만 기록한 후 파기합니다.

제7조 (개인정보의 제3자 제공)
원칙적으로 개인정보를 제3자에게 제공하지 않으며, 제공이 필요한 경우 별도 동의를 받습니다. 제5조·제6조의 위탁·국외이전은 제3자 제공이 아닌 처리위탁에 해당합니다.

제8조 (개인정보의 파기절차 및 방법)
보유기간 경과 또는 처리목적 달성 후 별도의 DB로 옮겨 내부 방침에 따라 일정 기간 저장한 후 파기하거나 즉시 파기합니다. 전자적 파일 형태로 저장된 개인정보는 기록을 재생할 수 없는 기술적 방법으로 삭제합니다.

제9조 (자동수집장치의 설치·운영 및 거부)
CAMPON은 서비스 이용 과정에서 접속 IP, 접속 일시, 서비스 이용 기록 등을 자동으로 수집할 수 있습니다.

제10조 (정보주체의 권리·의무 및 행사방법)
이용자는 언제든지 개인정보의 열람·정정·삭제·처리정지를 요구할 수 있습니다. 요청은 제13조의 개인정보 보호책임자 연락처로 전화 또는 이메일을 통해 하실 수 있으며, 접수 후 지체 없이(10일 이내) 처리합니다. 회원 탈퇴는 앱 설정의 "회원 탈퇴"에서 할 수 있고, 위치 권한은 기기 설정에서 철회할 수 있습니다.

제11조 (개인정보의 안전성 확보조치)
CAMPON은 개인정보 보호를 위해 다음과 같은 조치를 취하고 있습니다.

· 관리적 조치: 개인정보 처리 담당자 최소화 및 책임자 지정
· 기술적 조치: 접근권한 관리, 서버 방화벽 설정, 앱-서버 간 HTTPS 암호화 통신
· 물리적 조치: 개인정보가 저장된 서버(자체 운영 서버)에 대한 접근 통제

제12조 (아동의 개인정보)
서비스는 만 14세 미만 아동을 대상으로 하지 않으며, 해당 아동의 개인정보를 의도적으로 수집하지 않습니다. 수집 사실을 알게 되면 관련 정보를 삭제하기 위해 조치합니다.

제13조 (개인정보 보호책임자)
성명: 서하민
연락처: 010-4864-1548
이메일: shm040806@gmail.com

제14조 (개인정보처리방침의 변경)
이 개인정보처리방침은 2026년 09월 01일부터 적용됩니다. 내용의 추가·삭제 및 변경이 있는 경우 시행 최소 7일 전에 공지합니다.
''';
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.api,
    required this.preTripAlerts,
    required this.onAlertChanged,
    required this.onSignOut,
    required this.onDeleteAccount,
    super.key,
  });

  final CampOnApi api;
  final bool preTripAlerts;
  final ValueChanged<bool> onAlertChanged;
  final VoidCallback onSignOut;
  final Future<void> Function() onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Text('설정', style: CampText.displaySmall),
        const SizedBox(height: 6),
        Text(
          '계정을 확인하고 앱 동작을 관리합니다.',
          style: CampText.caption.copyWith(color: CampColors.inkMuted80),
        ),
        const SizedBox(height: 20),
        CampCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('계정', style: CampText.sectionTitle),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          api.displayName?.isNotEmpty ?? false
                              ? api.displayName!
                              : '캠퍼님',
                          style: CampText.bodyStrong,
                        ),
                        if (api.email?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 2),
                          Text(
                            api.email!,
                            style: CampText.caption.copyWith(
                              color: CampColors.inkMuted80,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SettingsIcon(icon: LucideIcons.shieldCheck, size: 34),
                ],
              ),
              const SizedBox(height: 16),
              SettingsLinkRow(
                title: '로그아웃',
                showChevron: false,
                onTap: onSignOut,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // ── 차단 관리 ──────────────────────────────────
        CampCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('커뮤니티', style: CampText.sectionTitle),
              const SizedBox(height: 14),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BlockManagementScreen(api: api),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.block, size: 18, color: CampColors.inkMuted80),
                      const SizedBox(width: 10),
                      Expanded(child: Text('차단 관리', style: CampText.body)),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: CampColors.inkMuted48,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CampCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('앱 환경', style: CampText.sectionTitle),
              const SizedBox(height: 14),
              Builder(
                builder: (context) {
                  final scope = CampThemeScope.of(context);
                  return ToggleSettingRow(
                    icon: LucideIcons.moon,
                    title: '야간 캠핑 테마',
                    subtitle: '어두운 곳에서도 편안하게',
                    value: scope.isDark,
                    onChanged: (_) => scope.toggle(),
                  );
                },
              ),
              const SizedBox(height: 14),
              ToggleSettingRow(
                icon: LucideIcons.bell,
                title: '준비 알림',
                subtitle: '캠핑 준비 흐름 알림 유지',
                value: preTripAlerts,
                onChanged: onAlertChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CampCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('지원', style: CampText.sectionTitle),
              const SizedBox(height: 10),
              SettingsLinkRow(
                title: '문의하기',
                onTap: () async {
                  final opened = await LegalConfig.open(
                    'mailto:${LegalConfig.contactEmail}',
                  );
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(content: Text('메일 앱을 열지 못했습니다.')),
                      );
                  }
                },
              ),
              const SizedBox(height: 14),
              SettingsLinkRow(
                title: '이용약관',
                onTap: () => LegalConfig.openDocument(
                  context,
                  LegalConfig.termsOfServiceUrl,
                  LegalDocument.terms,
                ),
              ),
              const SizedBox(height: 14),
              SettingsLinkRow(
                title: '개인정보처리방침',
                onTap: () => LegalConfig.openDocument(
                  context,
                  LegalConfig.privacyPolicyUrl,
                  LegalDocument.privacy,
                ),
              ),
              const SizedBox(height: 16),
              AppVersionRow(),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Center(child: DeleteAccountButton(onDelete: onDeleteAccount)),
      ],
    );
  }
}

class DeleteAccountButton extends StatefulWidget {
  const DeleteAccountButton({required this.onDelete, super.key});

  final Future<void> Function() onDelete;

  @override
  State<DeleteAccountButton> createState() => _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends State<DeleteAccountButton> {
  static const Color _danger = Color(0xFFB3261E);

  bool _deleting = false;

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text('탈퇴하면 계정과 저장된 추천 조건이 삭제되며 되돌릴 수 없어요. 계속할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('탈퇴'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() => _deleting = true);
    try {
      await widget.onDelete();
      // 성공하면 상위에서 로그인 화면으로 전환되며 이 위젯은 사라진다.
    } catch (error) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsLinkRow(
      title: _deleting ? '탈퇴 처리 중…' : '회원 탈퇴',
      color: _danger,
      showChevron: false,
      onTap: _deleting ? null : _confirmAndDelete,
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.title,
    required this.value,
    this.badge = false,
    this.valueColor,
    super.key,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool badge;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final valueColor = this.valueColor ?? CampColors.inkMuted80;
    return Row(
      children: [
        if (badge)
          SettingsIcon(icon: icon, size: 34)
        else
          Icon(icon, size: 17, color: CampColors.inkMuted80),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: CampText.body.copyWith(fontSize: 14.5)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: CampText.captionStrong.copyWith(color: valueColor),
          ),
        ),
      ],
    );
  }
}

/// 지원 섹션의 탭 가능한 링크 행.
class SettingsLinkRow extends StatelessWidget {
  const SettingsLinkRow({
    required this.title,
    required this.onTap,
    this.color,
    this.showChevron = true,
    super.key,
  });

  final String title;
  final VoidCallback? onTap;
  final Color? color;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: CampText.body.copyWith(fontSize: 14.5, color: color),
              ),
            ),
            if (showChevron)
              Icon(Icons.chevron_right, size: 18, color: CampColors.inkMuted48),
          ],
        ),
      ),
    );
  }
}

/// 첫 진입 코치마크. 탭을 하나씩 짚어가며 앱 흐름을 설명한다.
///
/// 카드와 건너뛰기만 탭을 받고 나머지는 그대로 통과시킨다. 안내 중에도
/// 사용자가 하단 탭을 직접 눌러볼 수 있어야 하기 때문이다.
class TutorialOverlay extends StatelessWidget {
  const TutorialOverlay({
    required this.stepIndex,
    required this.onNext,
    required this.onSkip,
    this.showTabHint = true,
    super.key,
  });

  static const steps = <(String, String)>[
    ('환영해요, 캠퍼님 👋', '홈에서 오늘의 캠핑 추천과 준비 흐름을 한눈에 확인해요.'),
    ('캠핑장을 둘러보세요', '현재 위치 근처 캠핑장 목록이에요. 카드를 누르면 상세정보로 들어가요.'),
    ('추천에서 골라보세요', '조건을 정하면 추천 카드가 나와요. 하트를 누르면 저장하고, X를 누르면 다음 캠핑장으로 넘어가요.'),
    ('체크리스트로 준비해요', '항목을 눌러 체크하면 진행률과 부족한 장비가 실시간으로 업데이트돼요.'),
    ('나만의 환경으로', '설정에서 야간 캠핑 테마 등 앱 동작을 자유롭게 바꿀 수 있어요.'),
  ];

  final int stepIndex;
  final bool showTabHint;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final (title, description) = steps[stepIndex];
    final isLast = stepIndex == steps.length - 1;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 190,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB30E1F17), Color(0x000E1F17)],
                  ),
                ),
              ),
            ),
          ),
          if (showTabHint)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 110,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0x8C0E1F17), Color(0x000E1F17)],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 38),
                      child: Text(
                        '👇 지금 이 탭이 활성화돼 있어요',
                        style: CampText.handwritten(
                          color: CampPalette.light.surface,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  right: 20,
                  child: TextButton(
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: CampPalette.light.canvas,
                      textStyle: CampText.captionStrong,
                    ),
                    child: const Text('건너뛰기'),
                  ),
                ),
                Positioned(
                  top: 52,
                  left: 16,
                  right: 16,
                  child: _TutorialCard(
                    title: title,
                    description: description,
                    stepIndex: stepIndex,
                    stepCount: steps.length,
                    buttonLabel: isLast ? '시작하기' : '다음',
                    onNext: onNext,
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

class _TutorialCard extends StatelessWidget {
  const _TutorialCard({
    required this.title,
    required this.description,
    required this.stepIndex,
    required this.stepCount,
    required this.buttonLabel,
    required this.onNext,
  });

  final String title;
  final String description;
  final int stepIndex;
  final int stepCount;
  final String buttonLabel;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    // 코치마크 카드는 어두운 딤 위에 뜨므로 테마와 무관하게 밝은 면을 유지한다.
    final light = CampPalette.light;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: light.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x590E1F17),
            blurRadius: 44,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (var i = 0; i < stepCount; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i == stepIndex ? light.primary : light.hairline,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: CampText.sectionTitle.copyWith(
              fontSize: 19,
              color: light.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: CampText.caption.copyWith(color: light.inkMuted80),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '${stepIndex + 1} / $stepCount',
                style: CampText.finePrint.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: light.inkMuted48,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: light.primary,
                  foregroundColor: light.onPrimary,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  textStyle: CampText.button,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(buttonLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 설정의 토글 카드. 카드 전체를 눌러도 값이 바뀐다.
class ToggleSettingRow extends StatelessWidget {
  const ToggleSettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: CampColors.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CampText.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: CampText.caption.copyWith(
                    color: CampColors.inkMuted80,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: CampColors.onPrimary,
            activeTrackColor: CampColors.forestMid,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 홈 헤더 우측의 야간 캠핑 테마 토글. 라이트에서는 달, 다크에서는 해를 보여준다.
class NightThemeToggle extends StatelessWidget {
  const NightThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = CampThemeScope.of(context);
    return Semantics(
      button: true,
      label: scope.isDark ? '야간 캠핑 테마 끄기' : '야간 캠핑 테마 켜기',
      child: InkWell(
        onTap: scope.toggle,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: CampColors.surface,
            border: Border.all(color: CampColors.hairline, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            scope.isDark ? LucideIcons.sun : LucideIcons.moon,
            size: 17,
            // 각 아이콘은 한쪽 테마에서만 보이므로 디자인의 고정색을 그대로 쓴다.
            color: scope.isDark
                ? CampPalette.light.amberTint
                : CampPalette.light.forestMid,
          ),
        ),
      ),
    );
  }
}

class SettingsIcon extends StatelessWidget {
  const SettingsIcon({
    required this.icon,
    this.background,
    this.iconColor,
    this.size = 36,
    super.key,
  });

  final IconData icon;
  final Color? background;
  final Color? iconColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final background = this.background ?? CampColors.greenTint;
    final iconColor = this.iconColor ?? CampColors.forestMid;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: size * 0.5, color: iconColor),
      ),
    );
  }
}

class StepScaffold extends StatelessWidget {
  const StepScaffold({
    required this.progressIndex,
    required this.body,
    required this.bottom,
    super.key,
  });

  final int progressIndex;
  final Widget body;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: ProgressSegments(activeIndex: progressIndex),
        ),
        const SizedBox(height: 18),
        Expanded(child: body),
        BottomActionBar(child: bottom),
      ],
    );
  }
}

class DatePickerField extends StatelessWidget {
  const DatePickerField({
    required this.date,
    required this.onChanged,
    super.key,
  });

  final DateTime? date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? now,
          firstDate: DateTime(now.year, now.month, now.day),
          lastDate: DateTime(now.year + 2),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: CampColors.primary,
                  onPrimary: CampColors.onPrimary,
                  surface: CampColors.canvas,
                  onSurface: CampColors.ink,
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          onChanged(picked);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: CampColors.surface,
          border: Border.all(color: CampColors.hairline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date == null ? '날짜를 선택해주세요' : _formatKoreanDate(date!),
                style: CampText.body.copyWith(
                  color: date == null ? CampColors.inkMuted48 : CampColors.ink,
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: CampColors.inkMuted48,
            ),
          ],
        ),
      ),
    );
  }
}

class RegionPicker extends StatelessWidget {
  const RegionPicker({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final CampRegion selected;
  final ValueChanged<CampRegion> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        border: Border.all(color: CampColors.hairline),
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment(-1, -1),
          end: Alignment(1, 1),
          colors: [CampColors.greenTint, CampColors.amberTint],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              child: Image(
                key: Key('recommendation-region-map-image'),
                image: AssetImage('assets/images/recommendation_map.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          for (final region in CampData.regions)
            Positioned(
              left: region.mapX * 0.01 * MediaQuery.sizeOf(context).width - 28,
              top: region.mapY * 2.18,
              child: RegionPin(
                region: region,
                selected: selected.name == region.name,
                onTap: () => onChanged(region),
              ),
            ),
        ],
      ),
    );
  }
}

class RegionPin extends StatelessWidget {
  const RegionPin({
    required this.region,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final CampRegion region;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on,
            color: selected ? CampColors.forest : CampColors.inkMuted80,
            size: 32,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: selected ? CampColors.forest : CampColors.surface,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              region.name,
              style: CampText.captionStrong.copyWith(
                color: selected ? CampColors.onPrimary : CampColors.inkMuted80,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PeopleStepper extends StatelessWidget {
  const PeopleStepper({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        StepperButton(
          icon: Icons.remove,
          label: '인원 줄이기',
          onTap: value > 1 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 56,
          child: Text(
            '$value명',
            textAlign: TextAlign.center,
            style: CampText.sectionTitle.copyWith(fontSize: 22),
          ),
        ),
        StepperButton(
          icon: Icons.add,
          label: '인원 늘리기',
          onTap: value < 10 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class StepperButton extends StatelessWidget {
  const StepperButton({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onTap,
      style: IconButton.styleFrom(
        fixedSize: const Size(38, 38),
        minimumSize: const Size(38, 38),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: CampColors.outline, width: 1.5),
        ),
        foregroundColor: CampColors.inkMuted80,
        disabledForegroundColor: CampColors.inkMuted48,
      ),
      icon: Icon(icon, size: 18),
    );
  }
}

class CampsiteCard extends StatelessWidget {
  const CampsiteCard({
    required this.site,
    required this.showScore,
    required this.onTap,
    this.showDistance = true,
    super.key,
  });

  final Campsite site;
  final bool showScore;
  final VoidCallback onTap;
  // 찜 목록의 거리는 저장 당시 검색 지역 기준이라 갱신되지 않으므로,
  // 화면에서 감출 수 있게 한다.
  final bool showDistance;

  @override
  Widget build(BuildContext context) {
    final topRight = showScore
        ? site.scoreLabel
        : (showDistance && site.distance > 0
              ? _formatDistance(site.distance)
              : null);
    // 거리는 위 배지 하나로만 보여준다. 캡션에 우편번호·거리를 또 넣으면
    // 같은 정보가 두 번 반복되므로, showDistance일 때는 캡션을 비운다.
    final captionText = showDistance
        ? null
        : (site.zipcode.isNotEmpty ? '우편번호 ${site.zipcode}' : '캠핑장');

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: CampCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 84,
                height: 84,
                child: site.validThumbnailUrl == null
                    ? CampsiteCoverImage(site: site)
                    : Image.network(
                        site.validThumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            CampImagePlaceholder(),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          site.name,
                          style: CampText.sectionTitle.copyWith(fontSize: 18),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (topRight != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          topRight,
                          style: CampText.captionStrong.copyWith(
                            fontSize: 12.5,
                            color: CampColors.primaryDark,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (captionText != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      captionText,
                      style: CampText.caption.copyWith(
                        fontSize: 12.5,
                        color: CampColors.inkMuted80,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: site.tags
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: CampColors.greenTint,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              tag,
                              style: CampText.captionStrong.copyWith(
                                fontSize: 11.5,
                                color: CampColors.forestMid,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CampsiteHeroImage extends StatefulWidget {
  const CampsiteHeroImage({
    required this.site,
    this.region,
    this.imageService,
    this.aspectRatio = 16 / 9,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.attributionBottom = 8,
    super.key,
  });

  final Campsite site;
  final String? region;
  final CampsiteImageService? imageService;
  final double aspectRatio;
  final BorderRadiusGeometry borderRadius;
  final double attributionBottom;

  @override
  State<CampsiteHeroImage> createState() => _CampsiteHeroImageState();
}

class _CampsiteHeroImageState extends State<CampsiteHeroImage> {
  final _controller = PageController();
  int _page = 0;
  Future<List<CampsiteSearchImage>>? _fallbackImages;

  @override
  void initState() {
    super.initState();
    _loadFallbackIfNeeded();
  }

  @override
  void didUpdateWidget(CampsiteHeroImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site.id != widget.site.id ||
        oldWidget.region != widget.region ||
        oldWidget.imageService != widget.imageService) {
      _page = 0;
      _loadFallbackIfNeeded();
    }
  }

  void _loadFallbackIfNeeded() {
    _fallbackImages =
        widget.site.validImageUrls.isEmpty &&
            widget.site.validThumbnailUrl == null
        ? (widget.imageService ?? CampsiteImageService.shared).search(
            name: widget.site.name,
            region: widget.region,
          )
        : null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final originalImages = widget.site.validImageUrls.isNotEmpty
        ? widget.site.validImageUrls
        : [
            if (widget.site.validThumbnailUrl != null)
              widget.site.validThumbnailUrl!,
          ];

    if (originalImages.isNotEmpty) {
      return _buildImagePager(originalImages, const []);
    }
    return FutureBuilder<List<CampsiteSearchImage>>(
      future: _fallbackImages,
      builder: (context, snapshot) {
        final fallback = snapshot.data ?? const <CampsiteSearchImage>[];
        return _buildImagePager(
          fallback.map((image) => image.imageUrl).toList(growable: false),
          fallback,
        );
      },
    );
  }

  Widget _buildImagePager(
    List<String> images,
    List<CampsiteSearchImage> fallback,
  ) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: images.isEmpty
            ? CampImagePlaceholder()
            : Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: images.length,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemBuilder: (context, index) => Image.network(
                      images[index],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          CampImagePlaceholder(),
                    ),
                  ),
                  if (images.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < images.length; i++)
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(
                                  alpha: i == _page ? 1 : 0.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (fallback.isNotEmpty)
                    Positioned(
                      left: 10,
                      bottom: widget.attributionBottom,
                      child: TextButton(
                        onPressed: () => LegalConfig.open(
                          fallback[_page.clamp(0, fallback.length - 1)]
                              .sourceUrl,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0x99000000),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('NAVER 검색 이미지 · 원본'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class CampsiteCoverImage extends StatefulWidget {
  const CampsiteCoverImage({required this.site, this.imageService, super.key});

  final Campsite site;
  final CampsiteImageService? imageService;

  @override
  State<CampsiteCoverImage> createState() => _CampsiteCoverImageState();
}

class _CampsiteCoverImageState extends State<CampsiteCoverImage> {
  Future<List<CampsiteSearchImage>>? _images;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CampsiteCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site.id != widget.site.id ||
        oldWidget.imageService != widget.imageService) {
      _load();
    }
  }

  void _load() {
    _images = (widget.imageService ?? CampsiteImageService.shared).search(
      name: widget.site.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CampsiteSearchImage>>(
      future: _images,
      builder: (context, snapshot) {
        final images = snapshot.data;
        final image = images == null || images.isEmpty ? null : images.first;
        if (image == null) return CampImagePlaceholder();
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              image.thumbnailUrl.isNotEmpty
                  ? image.thumbnailUrl
                  : image.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  CampImagePlaceholder(),
            ),
            Positioned(
              left: 5,
              bottom: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  child: Text(
                    'NAVER',
                    style: TextStyle(color: Colors.white, fontSize: 9),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 캠핑장 상세 상단의 점수 뱃지.
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: CampColors.amberTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: CampText.captionStrong.copyWith(color: CampColors.primaryDark),
      ),
    );
  }
}

/// 이용 팁의 대여 장비 태그.
class TipTag extends StatelessWidget {
  const TipTag({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CampColors.greenTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: CampText.captionStrong.copyWith(color: CampColors.forestMid),
      ),
    );
  }
}

class CampImagePlaceholder extends StatelessWidget {
  const CampImagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFECE2D2), Color(0xFFCDBCA0)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '캠핑장 사진 자리',
        style: CampText.caption.copyWith(color: CampColors.inkMuted48),
      ),
    );
  }
}

class FacilityBars extends StatelessWidget {
  const FacilityBars({required this.site, super.key});

  final Campsite site;

  @override
  Widget build(BuildContext context) {
    final bars = [
      FacilityBarData('화장실', site.facilityScore('TOILET')),
      FacilityBarData('샤워실', site.facilityScore('SHOWER')),
      FacilityBarData('개수대', site.facilityScore('SINK')),
      FacilityBarData('전기', site.facilityScore('ELECTRICITY')),
    ];

    return Column(
      children: [
        for (final bar in bars) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  bar.label,
                  style: CampText.caption.copyWith(
                    color: CampColors.inkMuted80,
                  ),
                ),
              ),
              Text(
                '${bar.value}/5',
                style: CampText.caption.copyWith(color: CampColors.inkMuted48),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: bar.value / 5,
              backgroundColor: CampColors.hairline,
              valueColor: AlwaysStoppedAnimation(CampColors.primary),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class ChecklistRow extends StatelessWidget {
  const ChecklistRow({
    required this.item,
    required this.checked,
    required this.showDivider,
    required this.onTap,
    super.key,
  });

  final CampOption item;
  final bool checked;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: CampColors.canvas,
          border: Border(
            bottom: showDivider
                ? BorderSide(color: CampColors.hairline)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: checked ? CampColors.forestMid : Colors.transparent,
                border: Border.all(
                  color: checked ? CampColors.forestMid : CampColors.outline,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              child: checked
                  ? Icon(Icons.check, size: 14, color: CampColors.onPrimary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: CampText.body.copyWith(
                  fontSize: 15,
                  color: checked ? CampColors.inkMuted80 : CampColors.ink,
                  decoration: checked ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CampTabBar extends StatelessWidget {
  const CampTabBar({
    required this.currentStep,
    required this.hasRecommended,
    required this.onHome,
    required this.onBrowse,
    required this.onRecommend,
    required this.onChecklist,
    required this.onSettings,
    super.key,
  });

  final AppStep currentStep;
  final bool hasRecommended;
  final VoidCallback onHome;
  final VoidCallback onBrowse;
  final VoidCallback onRecommend;
  final VoidCallback onChecklist;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CampColors.surface,
        border: Border(top: BorderSide(color: CampColors.hairline)),
      ),
      // 홈 인디케이터 여백을 색이 칠해진 안쪽에서 확보해야
      // 화면 맨 아래까지 같은 색으로 이어지고 바가 떠 보이지 않는다.
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
          child: Row(
            children: [
              TabItem(
                icon: LucideIcons.home,
                label: '홈',
                selected:
                    currentStep == AppStep.home ||
                    currentStep == AppStep.favorites,
                onTap: onHome,
              ),
              TabItem(
                icon: LucideIcons.mapPin,
                label: '캠핑장',
                selected: currentStep == AppStep.browse,
                onTap: onBrowse,
              ),
              TabItem(
                icon: LucideIcons.star,
                label: '추천',
                selected:
                    currentStep == AppStep.recommendations ||
                    currentStep == AppStep.onboardingBasics ||
                    currentStep == AppStep.onboardingExperience ||
                    currentStep == AppStep.onboardingPreferences,
                onTap: onRecommend,
              ),
              TabItem(
                icon: LucideIcons.checkSquare,
                label: '체크리스트',
                selected: currentStep == AppStep.checklist,
                onTap: onChecklist,
              ),
              TabItem(
                icon: LucideIcons.settings,
                label: '설정',
                selected: currentStep == AppStep.settings,
                onTap: onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TabItem extends StatelessWidget {
  const TabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? CampColors.forestMid : CampColors.inkMuted48;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(height: 3),
              Text(
                label,
                style: CampText.finePrint.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Shimmer(height: 132),
          SizedBox(height: 12),
          Shimmer(height: 132),
          SizedBox(height: 12),
          Shimmer(height: 132),
        ],
      ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return CampCard(
      backgroundColor: CampColors.amberTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('캠핑장 정보를 불러오지 못했어요.', style: CampText.bodyStrong),
          const SizedBox(height: 6),
          Text(
            message,
            style: CampText.caption.copyWith(color: CampColors.inkMuted80),
          ),
          const SizedBox(height: 14),
          CampButton.secondary(label: '다시 시도', onPressed: onRetry),
        ],
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({required this.text, required this.onRetry, super.key});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return CampCard(
      child: Column(
        children: [
          SvgPicture.asset('assets/illustrations/camp_empty.svg', height: 132),
          const SizedBox(height: 12),
          Text(text, style: CampText.bodyStrong, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          CampButton.secondary(label: '다시 시도', onPressed: onRetry),
        ],
      ),
    );
  }
}

class MissingState extends StatelessWidget {
  const MissingState({
    required this.title,
    required this.actionLabel,
    required this.onPressed,
    super.key,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: CampText.bodyStrong,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            CampButton.secondary(label: actionLabel, onPressed: onPressed),
          ],
        ),
      ),
    );
  }
}

class ProgressSegments extends StatelessWidget {
  const ProgressSegments({required this.activeIndex, super.key});

  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < 3; index++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: activeIndex >= index
                    ? CampColors.primary
                    : CampColors.hairline,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (index != 2) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class BackCircleButton extends StatelessWidget {
  const BackCircleButton({
    required this.onPressed,
    this.onImage = false,
    super.key,
  });

  final VoidCallback onPressed;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '뒤로',
      onPressed: onPressed,
      icon: const Icon(Icons.chevron_left),
      style: IconButton.styleFrom(
        fixedSize: const Size(36, 36),
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
        foregroundColor: onImage ? Colors.white : CampColors.ink,
        backgroundColor: onImage
            ? Colors.black.withValues(alpha: 0.28)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: onImage
                ? Colors.white.withValues(alpha: 0.65)
                : CampColors.hairline,
          ),
        ),
      ),
    );
  }
}

/// 상세 화면의 즐겨찾기 하트. 켜지면 앰버로 채워진다.
class FavoriteHeartButton extends StatelessWidget {
  const FavoriteHeartButton({
    required this.isFavorite,
    required this.onPressed,
    this.onImage = false,
    super.key,
  });

  final bool isFavorite;
  final VoidCallback onPressed;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: isFavorite ? '저장 해제' : '저장하기',
      onPressed: onPressed,
      icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, size: 20),
      style: IconButton.styleFrom(
        fixedSize: const Size(36, 36),
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
        foregroundColor: isFavorite
            ? CampColors.primary
            : (onImage ? Colors.white : CampColors.ink),
        backgroundColor: onImage
            ? Colors.black.withValues(alpha: 0.28)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: onImage
                ? Colors.white.withValues(alpha: 0.65)
                : CampColors.hairline,
          ),
        ),
      ),
    );
  }
}

class CampCard extends StatelessWidget {
  const CampCard({
    required this.child,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final Widget child;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = this.backgroundColor ?? CampColors.surface;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: CampColors.hairline),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: CampColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class CampButton extends StatelessWidget {
  const CampButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.background,
    this.foreground,
    this.borderColor,
    super.key,
  });

  const CampButton.secondary({
    required this.label,
    required this.onPressed,
    this.icon,
    this.foreground,
    this.borderColor,
    super.key,
  }) : secondary = true,
       background = null;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary;
  final Color? background;
  final Color? foreground;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
        Text(label, overflow: TextOverflow.ellipsis),
      ],
    );

    if (secondary) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground ?? CampColors.primaryDark,
          disabledForegroundColor: CampColors.inkMuted48,
          side: BorderSide(
            color: borderColor ?? CampColors.hairline,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: CampText.button,
        ),
        child: content,
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background ?? CampColors.primary,
        foregroundColor: foreground ?? CampColors.onPrimary,
        disabledBackgroundColor: CampColors.hairline,
        disabledForegroundColor: CampColors.inkMuted48,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: CampText.button,
      ),
      child: content,
    );
  }
}

class CampChoiceChip extends StatelessWidget {
  const CampChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? CampColors.primary : CampColors.canvas,
          border: Border.all(
            color: selected ? CampColors.primary : CampColors.hairline,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: CampText.captionStrong.copyWith(
            color: selected ? CampColors.onPrimary : CampColors.inkMuted80,
          ),
        ),
      ),
    );
  }
}

class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: CampText.captionStrong.copyWith(
          color: color ?? CampColors.inkMuted48,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class BottomActionBar extends StatelessWidget {
  const BottomActionBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CampColors.canvas,
        border: Border(top: BorderSide(color: CampColors.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresAt,
    this.provider,
    this.displayName,
    this.email,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final DateTime expiresAt;
  final AuthProvider? provider;
  final String? displayName;
  final String? email;
}

abstract interface class AuthSessionStore {
  Future<AuthSession?> read();
  Future<void> write(AuthSession session);
  Future<void> clear();
}

class SecureAuthSessionStore implements AuthSessionStore {
  SecureAuthSessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _accessTokenKey = 'campon.auth.accessToken';
  static const _refreshTokenKey = 'campon.auth.refreshToken';
  static const _tokenTypeKey = 'campon.auth.tokenType';
  static const _expiresAtKey = 'campon.auth.expiresAt';
  static const _providerKey = 'campon.auth.provider';
  static const _displayNameKey = 'campon.auth.displayName';
  static const _emailKey = 'campon.auth.email';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    final values = await _storage.readAll();
    final accessToken = values[_accessTokenKey];
    final expiresAtMilliseconds = int.tryParse(values[_expiresAtKey] ?? '');
    if (accessToken == null ||
        accessToken.isEmpty ||
        expiresAtMilliseconds == null) {
      return null;
    }

    return AuthSession(
      accessToken: accessToken,
      refreshToken: values[_refreshTokenKey] ?? '',
      tokenType: values[_tokenTypeKey] ?? 'Bearer',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMilliseconds),
      provider: AuthProvider.fromStorageValue(values[_providerKey]),
      displayName: values[_displayNameKey],
      email: values[_emailKey],
    );
  }

  @override
  Future<void> write(AuthSession session) async {
    await _storage.write(key: _accessTokenKey, value: session.accessToken);
    await _storage.write(key: _refreshTokenKey, value: session.refreshToken);
    await _storage.write(key: _tokenTypeKey, value: session.tokenType);
    await _storage.write(
      key: _expiresAtKey,
      value: session.expiresAt.millisecondsSinceEpoch.toString(),
    );
    if (session.provider == null) {
      await _storage.delete(key: _providerKey);
    } else {
      await _storage.write(
        key: _providerKey,
        value: session.provider!.storageValue,
      );
    }
    if (session.displayName == null || session.displayName!.isEmpty) {
      await _storage.delete(key: _displayNameKey);
    } else {
      await _storage.write(key: _displayNameKey, value: session.displayName);
    }
    if (session.email == null || session.email!.isEmpty) {
      await _storage.delete(key: _emailKey);
    } else {
      await _storage.write(key: _emailKey, value: session.email);
    }
  }

  @override
  Future<void> clear() async {
    await Future.wait(<Future<void>>[
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _tokenTypeKey),
      _storage.delete(key: _expiresAtKey),
      _storage.delete(key: _providerKey),
      _storage.delete(key: _displayNameKey),
      _storage.delete(key: _emailKey),
    ]);
  }
}

/// 액세스 토큰 payload의 `sub`에서 내 유저 ID를 읽는다.
///
/// 서버가 유저 ID를 따로 내려주는 API가 없어서 토큰에서 꺼낸다. 서명은 검증하지
/// 않으므로 화면 표시 용도로만 쓰고, 권한 판단은 서버에 맡긴다.
int? userIdFromAccessToken(String? accessToken) {
  if (accessToken == null || accessToken.isEmpty) {
    return null;
  }
  final segments = accessToken.split('.');
  if (segments.length != 3) {
    return null;
  }
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
    );
    if (payload is! Map<String, dynamic>) {
      return null;
    }
    final sub = payload['sub'];
    if (sub is int) {
      return sub;
    }
    if (sub is String) {
      return int.tryParse(sub);
    }
    return null;
  } catch (_) {
    return null;
  }
}

class CampOnApi {
  static const String publicHost = 'campon.seohamin.com';
  static const String _host = 'campon.seohamin.com';
  static const Duration _timeout = Duration(seconds: 12);
  static const int _devUserId = 1;

  CampOnApi({AuthSessionStore? sessionStore})
    : _sessionStore = sessionStore ?? SecureAuthSessionStore();

  final AuthSessionStore _sessionStore;
  String? _accessToken;
  String? _refreshToken;
  String _tokenType = 'Bearer';
  DateTime? _accessTokenExpiresAt;
  AuthProvider? _provider;
  String? _displayName;
  String? _email;
  Future<void>? _googleInitializeFuture;
  Future<void>? _refreshFuture;
  VoidCallback? onSessionInvalidated;

  /// 로그인한 유저의 ID. 서버가 따로 알려주지 않아서 액세스 토큰에서 읽는다.
  int? get currentUserId => userIdFromAccessToken(_accessToken);

  /// 로그인 시점에 제공자로부터 받아 기기에 캐시해 둔 표시 이름. 서버는 별도의
  /// 내 프로필 조회 API가 없어 로그인 응답 대신 이 값을 화면에 사용한다.
  String? get displayName => _displayName;
  String? get email => _email;

  Future<bool> restoreSession() async {
    try {
      final session = await _sessionStore.read();
      if (session == null) {
        return false;
      }
      _applySession(session);

      if (_hasUsableAccessToken()) {
        return true;
      }
      await _refreshSession();
      return true;
    } on CampOnSessionExpiredException {
      await clearSession(notify: false);
      return false;
    } on MissingPluginException {
      // 위젯 테스트처럼 보안 저장소 플러그인이 없는 실행 환경에서는 로그인 화면을 보인다.
      return false;
    } on CampOnApiException {
      // 네트워크가 없거나 서버가 일시적으로 실패한 경우에도 만료 세션으로 진입하지 않는다.
      return false;
    } catch (_) {
      // Keychain/Keystore 접근이 불가능한 환경에서는 앱을 로그인 화면으로 안전하게 시작한다.
      return false;
    }
  }

  Future<void> signInWithDevUser() async {
    await _sendEmptyPost(_buildUri('/api/v1/auth/dev/user', const {}));
    await _setSessionFrom(
      _requestJwt(
        _buildUri('/api/v1/auth/dev/token', <String, String>{
          'userId': '$_devUserId',
        }),
      ),
      provider: null,
      displayName: '개발 계정',
    );
  }

  Future<void> clearSession({bool notify = false}) async {
    _accessToken = null;
    _refreshToken = null;
    _tokenType = 'Bearer';
    _accessTokenExpiresAt = null;
    _provider = null;
    _displayName = null;
    _email = null;
    await _sessionStore.clear();
    if (notify) {
      onSessionInvalidated?.call();
    }
  }

  Future<void> signOut() async {
    final provider = _provider;
    try {
      switch (provider) {
        case AuthProvider.google:
          await GoogleSignIn.instance.signOut();
        case AuthProvider.kakao:
          await UserApi.instance.logout();
        case AuthProvider.apple:
        case null:
          break;
      }
    } catch (_) {
      // 제공자 로그아웃이 실패하더라도 이 기기의 CampOn 세션은 반드시 제거한다.
    } finally {
      await clearSession();
    }
  }

  Future<void> signInWithOAuth({
    required AuthProvider provider,
    required String credential,
    required String name,
    String? email,
  }) async {
    await _setSessionFrom(
      _requestJwt(
        _buildUri(provider.path, <String, String>{}),
        method: 'POST',
        body: provider.authRequestBody(credential: credential, name: name),
      ),
      provider: provider,
      displayName: name,
      email: email,
    );
  }

  Future<void> signInWithNativeProvider({
    required AuthProvider provider,
    required BuildContext context,
  }) async {
    switch (provider) {
      case AuthProvider.google:
        await _signInWithGoogle();
      case AuthProvider.apple:
        await _signInWithApple();
      case AuthProvider.kakao:
        await _signInWithKakao(context);
    }
  }

  Future<void> _signInWithGoogle() async {
    await _ensureGoogleInitialized();
    final signIn = GoogleSignIn.instance;
    if (!signIn.supportsAuthenticate()) {
      throw const CampOnApiException('현재 플랫폼에서 Google 네이티브 로그인을 사용할 수 없습니다.');
    }

    debugPrint('[GoogleSignIn] authenticate 시작...');
    final account = await signIn.authenticate(
      scopeHint: const <String>['email', 'profile'],
    );
    debugPrint('[GoogleSignIn] authenticate 성공: ${account.email}');
    debugPrint(
      '[GoogleSignIn] authorizeServer 호출 (기본 프로필 교환을 위해 빈 scope 전달)...',
    );

    // 기본 프로필(email, profile)에 대한 serverAuthCode를 획득할 때는
    // scopes를 빈 리스트([])로 전달해야 사용자에게 로그인/동의 창이 두 번 뜨지 않습니다.
    final serverAuth = await account.authorizationClient.authorizeServer(
      const <String>[],
    );
    debugPrint('[GoogleSignIn] serverAuth: $serverAuth');
    debugPrint('[GoogleSignIn] serverAuthCode: ${serverAuth?.serverAuthCode}');

    final code = serverAuth?.serverAuthCode;
    if (code == null || code.isEmpty) {
      throw const CampOnApiException(
        'Google 서버 인증 코드를 받지 못했습니다. Google Cloud Console의 '
        '웹 OAuth client ID를 GOOGLE_SERVER_CLIENT_ID로 설정한 뒤, '
        '기기에서 Google 계정을 로그아웃하고 다시 시도해주세요.',
      );
    }

    await signInWithOAuth(
      provider: AuthProvider.google,
      credential: code,
      name: account.displayName ?? account.email,
      email: account.email,
    );
  }

  Future<void> _ensureGoogleInitialized() {
    debugPrint('[GoogleSignIn] clientId: "${AuthConfig.googleClientId}"');
    debugPrint(
      '[GoogleSignIn] serverClientId: "${AuthConfig.googleServerClientId}"',
    );
    return _googleInitializeFuture ??= GoogleSignIn.instance.initialize(
      clientId: AuthConfig.googleClientId.isEmpty
          ? null
          : AuthConfig.googleClientId,
      serverClientId: AuthConfig.googleServerClientId.isEmpty
          ? null
          : AuthConfig.googleServerClientId,
    );
  }

  Future<void> _signInWithApple() async {
    final webOptions = _appleWebAuthenticationOptions;
    if (!Platform.isIOS && !Platform.isMacOS && webOptions == null) {
      throw const CampOnApiException(
        'Android Apple 로그인에는 APPLE_SERVICE_ID와 APPLE_REDIRECT_URI가 필요합니다.',
      );
    }

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const <AppleIDAuthorizationScopes>[
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      webAuthenticationOptions: webOptions,
    );
    final name = [
      credential.givenName,
      credential.familyName,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' ');

    await signInWithOAuth(
      provider: AuthProvider.apple,
      credential: credential.authorizationCode,
      name: name.isNotEmpty ? name : credential.email ?? 'Apple User',
      email: credential.email,
    );
  }

  WebAuthenticationOptions? get _appleWebAuthenticationOptions {
    if (AuthConfig.appleServiceId.isEmpty ||
        AuthConfig.appleRedirectUri.isEmpty) {
      return null;
    }
    final redirectUri = Uri.tryParse(AuthConfig.appleRedirectUri);
    if (redirectUri == null) {
      throw const CampOnApiException('APPLE_REDIRECT_URI 값이 올바른 URI가 아닙니다.');
    }
    return WebAuthenticationOptions(
      clientId: AuthConfig.appleServiceId,
      redirectUri: redirectUri,
    );
  }

  Future<void> _signInWithKakao(BuildContext context) async {
    if (AuthConfig.kakaoNativeAppKey.isEmpty) {
      throw const CampOnApiException('KAKAO_NATIVE_APP_KEY가 설정되지 않았습니다.');
    }

    debugPrint(
      '[Kakao] 로그인 시작 | platform=${Platform.operatingSystem} '
      'nativeAppKey=${AuthConfig.kakaoNativeAppKey} '
      'customScheme=${KakaoSdk.customScheme}',
    );

    final OAuthToken token;
    try {
      token = await UserApi.instance.loginWithKakao(context);
    } catch (error, stackTrace) {
      debugPrint('[Kakao] SDK 로그인 실패 (${error.runtimeType}): $error');
      debugPrint('[Kakao] kakaoTalkInstalled=${await isKakaoTalkInstalled()}');
      debugPrint('[Kakao] Stack trace:\n$stackTrace');
      rethrow;
    }

    // 토큰 값 자체는 남기지 않고 서버 교환에 필요한 형태 정보만 기록한다.
    debugPrint(
      '[Kakao] SDK 로그인 성공 | accessTokenLength=${token.accessToken.length} '
      'hasRefreshToken=${token.refreshToken != null} '
      'hasIdToken=${token.idToken != null} scopes=${token.scopes} '
      'expiresAt=${token.expiresAt}',
    );
    debugPrint(
      '[Kakao] 서버 교환 요청 | ${AuthProvider.kakao.path} '
      '${AuthProvider.kakao.credentialField}=카카오 access token',
    );

    // 카카오 로그인 토큰만으로는 닉네임/이메일을 알 수 없어 프로필을 한 번 더
    // 조회한다. 사용자가 관련 동의를 하지 않았다면 조용히 기본값으로 넘어간다.
    var kakaoName = 'Kakao User';
    String? kakaoEmail;
    try {
      final profile = await UserApi.instance.me();
      final nickname = profile.kakaoAccount?.profile?.nickname;
      if (nickname != null && nickname.isNotEmpty) {
        kakaoName = nickname;
      }
      kakaoEmail = profile.kakaoAccount?.email;
    } catch (error) {
      debugPrint('[Kakao] 프로필 조회 실패, 기본값으로 진행: $error');
    }

    await signInWithOAuth(
      provider: AuthProvider.kakao,
      credential: token.accessToken,
      name: kakaoName,
      email: kakaoEmail,
    );
  }

  /// `/api/v1/campsites/nearby`의 쿼리 파라미터. 네트워크 없이 검증할 수 있게 분리해 둔다.
  static Map<String, String> nearbyQuery({
    required double lat,
    required double lon,
    required int radius,
    required int page,
    required int size,
  }) => <String, String>{
    'lat': lat.toString(),
    'lon': lon.toString(),
    'radius': '$radius',
    'size': '$size',
    'page': '$page',
  };

  Future<List<Campsite>> fetchNearby({
    required CampRegion region,
    required int page,
    required int size,
  }) {
    final uri = _buildUri(
      '/api/v1/campsites/nearby',
      nearbyQuery(
        lat: region.lat,
        lon: region.lon,
        radius: 10000,
        page: page,
        size: size,
      ),
    );
    return _fetchCampsites(uri);
  }

  /// 홈 추천의 단일 데이터 진입점. 현재는 주변 캠핑장 API의 첫 페이지를 쓴다.
  Future<List<Campsite>> fetchWeeklyRecommendations({
    required CampRegion region,
    required int size,
  }) => fetchNearby(region: region, page: 0, size: size);

  static const _regionAggregateRadius = 20000;
  static const _regionAggregatePageSize = 100;

  Future<List<Campsite>> fetchAllNearby({required CampRegion region}) {
    return fetchAllNearbyAt(lat: region.lat, lon: region.lon);
  }

  /// 지도를 움직인 임의의 지점에서도 같은 방식으로 전량 조회한다.
  Future<List<Campsite>> fetchAllNearbyAt({
    required double lat,
    required double lon,
  }) {
    return aggregateAllPages<Campsite>((page) {
      final uri = _buildUri(
        '/api/v1/campsites/nearby',
        nearbyQuery(
          lat: lat,
          lon: lon,
          radius: _regionAggregateRadius,
          page: page,
          size: _regionAggregatePageSize,
        ),
      );
      return _fetchCampsitesPage(uri);
    });
  }

  Future<List<Campsite>> fetchRecommendations({
    required CampRegion region,
    required DateTime date,
    required int people,
    required bool hasCar,
    required List<String> equipment,
    required List<String> preferences,
    required int page,
    required int size,
  }) {
    final uri = _buildUri(
      '/api/v1/campsites/recommend',
      <String, String>{
        'lat': region.lat.toString(),
        'lon': region.lon.toString(),
        'radius': '20000',
        'date': DateTime(date.year, date.month, date.day).toIso8601String(),
        'groupSize': '$people',
        'withCar': '$hasCar',
        'size': '$size',
        'page': '$page',
      },
      arrays: <String, List<String>>{
        'preferredConditions': preferences,
        'equipments': equipment,
      },
    );
    return _fetchCampsites(uri);
  }

  Future<PageResult<Campsite>> _fetchCampsitesPage(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        await _authorizationHeader(),
      );
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          await clearSession(notify: true);
          throw const CampOnSessionExpiredException(
            '로그인 정보가 만료되었습니다. 다시 로그인해주세요.',
          );
        }
        throw CampOnApiException('HTTP ${response.statusCode}: $body');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const CampOnApiException('Unexpected response shape.');
      }
      return parseCampsitePage(decoded);
    } on SocketException catch (error) {
      throw CampOnApiException('Network error: ${error.message}');
    } on TimeoutException {
      throw const CampOnApiException('Request timed out.');
    } on FormatException catch (error) {
      throw CampOnApiException('Invalid JSON: ${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Campsite>> _fetchCampsites(Uri uri) async {
    final page = await _fetchCampsitesPage(uri);
    return page.items;
  }

  Future<List<CampPost>> fetchPosts({
    required int campsiteId,
    int page = 0,
    int size = 20,
  }) async {
    final uri = _buildUri('/api/v1/posts', <String, String>{
      'campsiteId': '$campsiteId',
      'size': '$size',
      'page': '$page',
    });
    final body = await _authorizedRequest(uri);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return <CampPost>[];
    }
    final items = decoded['items'];
    if (items is! List) {
      return <CampPost>[];
    }
    return items
        .whereType<Map<String, dynamic>>()
        .map(CampPost.fromJson)
        .toList();
  }

  Future<CampPost> createPost({
    required int campsiteId,
    required String title,
    required String content,
  }) async {
    final body = await _authorizedRequest(
      _buildUri('/api/v1/posts', const <String, String>{}),
      method: 'POST',
      body: <String, dynamic>{
        'campsiteId': campsiteId,
        'title': title,
        'content': content,
      },
    );
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const CampOnApiException('서버 응답 형식이 올바르지 않습니다.');
    }
    return CampPost.fromJson(decoded);
  }

  Future<void> deletePost(int postId) async {
    await _authorizedRequest(
      _buildUri('/api/v1/posts/$postId', const <String, String>{}),
      method: 'DELETE',
    );
  }

  // ──────────────────────────────────────────────
  // 차단(Block) API
  // ──────────────────────────────────────────────

  /// 차단한 유저 목록 조회 GET /api/v1/blocks
  Future<List<BlockedUser>> getBlockedUsers() async {
    final body = await _authorizedRequest(
      _buildUri('/api/v1/blocks', const <String, String>{}),
    );
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      return <BlockedUser>[];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(BlockedUser.fromJson)
        .toList();
  }

  /// 유저 차단 POST /api/v1/blocks
  Future<BlockedUser> blockUser(int blockedUserId) async {
    final body = await _authorizedRequest(
      _buildUri('/api/v1/blocks', const <String, String>{}),
      method: 'POST',
      body: <String, dynamic>{'blockedUserId': blockedUserId},
    );
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const CampOnApiException('서버 응답 형식이 올바르지 않습니다.');
    }
    return BlockedUser.fromJson(decoded);
  }

  /// 차단 해제 DELETE /api/v1/blocks/{blockedUserId}
  Future<void> unblockUser(int blockedUserId) async {
    await _authorizedRequest(
      _buildUri('/api/v1/blocks/$blockedUserId', const <String, String>{}),
      method: 'DELETE',
    );
  }

  // ──────────────────────────────────────────────
  // 신고(Report) API
  // ──────────────────────────────────────────────

  /// 게시글 신고 POST /api/v1/posts/{postId}/reports
  Future<void> reportPost({required int postId, required String reason}) async {
    await _authorizedRequest(
      _buildUri('/api/v1/posts/$postId/reports', const <String, String>{}),
      method: 'POST',
      body: <String, dynamic>{'reason': reason},
    );
  }

  Future<void> deleteAccount() async {
    await _authorizedRequest(
      _buildUri('/api/v1/users', const <String, String>{}),
      method: 'DELETE',
    );
    // 서버 탈퇴가 끝나면 제공자 로그아웃과 로컬 세션을 함께 정리한다.
    await signOut();
  }

  Future<DirectionResult> fetchDirections({
    required double originX,
    required double originY,
    required double destX,
    required double destY,
  }) async {
    final uri = _buildUri('/api/v1/directions', <String, String>{
      'originX': '$originX',
      'originY': '$originY',
      'destX': '$destX',
      'destY': '$destY',
    });
    final body = await _authorizedRequest(uri);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const CampOnApiException('경로 응답 형식이 올바르지 않습니다.');
    }
    return DirectionResult.fromJson(decoded);
  }

  /// 로그인 토큰을 붙여 요청하고 JSON 응답 본문을 문자열로 돌려준다.
  Future<String> _authorizedRequest(
    Uri uri, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();
    try {
      final authorization = await _authorizationHeader();
      final HttpClientRequest request;
      switch (method) {
        case 'POST':
          request = await client.postUrl(uri).timeout(_timeout);
        case 'DELETE':
          request = await client.deleteUrl(uri).timeout(_timeout);
        case 'PATCH':
          request = await client.patchUrl(uri).timeout(_timeout);
        default:
          request = await client.getUrl(uri).timeout(_timeout);
      }
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, authorization);
      if (body != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.add(utf8.encode(jsonEncode(body)));
      }

      final response = await request.close().timeout(_timeout);
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          await clearSession(notify: true);
          throw const CampOnSessionExpiredException(
            '로그인 정보가 만료되었습니다. 다시 로그인해주세요.',
          );
        }
        throw CampOnApiException(
          _authFailureMessage(response.statusCode, responseBody),
        );
      }
      return responseBody;
    } on SocketException catch (error) {
      throw CampOnApiException('네트워크 연결을 확인한 뒤 다시 시도해주세요. (${error.message})');
    } on TimeoutException {
      throw const CampOnApiException('요청 시간이 초과되었습니다. 다시 시도해주세요.');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _authorizationHeader() async {
    if (_hasUsableAccessToken()) {
      return '$_tokenType $_accessToken';
    }

    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await clearSession(notify: true);
      throw const CampOnSessionExpiredException('로그인이 필요합니다.');
    }

    await _refreshSession();
    final refreshedToken = _accessToken;
    if (refreshedToken == null || refreshedToken.isEmpty) {
      throw const CampOnApiException('토큰 갱신에 실패했습니다.');
    }
    return '$_tokenType $refreshedToken';
  }

  Future<void> _sendEmptyPost(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CampOnApiException('HTTP ${response.statusCode}: $body');
      }
    } on SocketException catch (error) {
      throw CampOnApiException('Network error: ${error.message}');
    } on TimeoutException {
      throw const CampOnApiException('Request timed out.');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _requestJwt(
    Uri uri, {
    String method = 'GET',
    Map<String, String>? body,
    bool sessionRefresh = false,
  }) async {
    final client = HttpClient();
    try {
      final request = method == 'POST'
          ? await client.postUrl(uri).timeout(_timeout)
          : await client.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.add(utf8.encode(jsonEncode(body)));
      }

      final response = await request.close().timeout(_timeout);
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        // 화면에는 요약 메시지만 노출되므로 원본 응답은 콘솔에만 남긴다.
        debugPrint(
          '[Auth] ${uri.path} 실패 | HTTP ${response.statusCode} | body=$responseBody',
        );
        if (sessionRefresh &&
            (response.statusCode == 401 || response.statusCode == 403)) {
          throw CampOnSessionExpiredException(
            _authFailureMessage(response.statusCode, responseBody),
          );
        }
        throw CampOnApiException(
          _authFailureMessage(response.statusCode, responseBody),
        );
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw const CampOnApiException('서버 응답 형식이 올바르지 않습니다.');
      }
      return decoded;
    } on SocketException {
      throw const CampOnApiException('네트워크 연결을 확인한 뒤 다시 시도해주세요.');
    } on TimeoutException {
      throw const CampOnApiException('로그인 요청 시간이 초과되었습니다. 다시 시도해주세요.');
    } on FormatException {
      throw const CampOnApiException('서버 응답을 해석하지 못했습니다.');
    } finally {
      client.close(force: true);
    }
  }

  /// 서버가 내려주는 한국어 message 필드를 우선 사용한다.
  static String _authFailureMessage(int statusCode, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = _asString(decoded['message']);
        if (message.isNotEmpty) {
          return message;
        }
      }
    } on FormatException {
      // 본문이 JSON이 아니면 상태 코드 기반 메시지로 대체한다.
    }
    return '로그인 요청이 실패했습니다. (HTTP $statusCode)';
  }

  bool _hasUsableAccessToken() {
    final token = _accessToken;
    final expiresAt = _accessTokenExpiresAt;
    return token != null &&
        token.isNotEmpty &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 1)));
  }

  Future<void> _refreshSession() {
    final activeRefresh = _refreshFuture;
    if (activeRefresh != null) {
      return activeRefresh;
    }

    final refresh = _performRefresh();
    _refreshFuture = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshFuture, refresh)) {
        _refreshFuture = null;
      }
    });
  }

  Future<void> _performRefresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const CampOnSessionExpiredException('로그인이 필요합니다.');
    }
    try {
      await _setSessionFrom(
        _requestJwt(
          _buildUri('/api/v1/auth/token/refresh', <String, String>{}),
          method: 'POST',
          body: <String, String>{'refreshToken': refreshToken},
          sessionRefresh: true,
        ),
        provider: _provider,
      );
    } on CampOnSessionExpiredException {
      await clearSession(notify: true);
      rethrow;
    }
  }

  Future<void> _setSessionFrom(
    Future<Map<String, dynamic>> jwtFuture, {
    required AuthProvider? provider,
    String? displayName,
    String? email,
  }) async {
    final jwt = await jwtFuture;
    final accessToken = _asString(jwt['accessToken']);
    if (accessToken.isEmpty) {
      throw const CampOnApiException('인증 토큰이 비어 있습니다.');
    }
    final session = AuthSession(
      accessToken: accessToken,
      refreshToken: _asString(jwt['refreshToken']),
      tokenType: _asString(jwt['tokenType'], fallback: 'Bearer'),
      expiresAt: DateTime.now().add(Duration(seconds: _asInt(jwt['exprTime']))),
      provider: provider,
      // 토큰 갱신처럼 새 값이 없는 호출에서는 이미 캐시된 이름/이메일을 유지한다.
      displayName: displayName ?? _displayName,
      email: email ?? _email,
    );
    await _sessionStore.write(session);
    _applySession(session);
  }

  void _applySession(AuthSession session) {
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
    _tokenType = session.tokenType;
    _accessTokenExpiresAt = session.expiresAt;
    _provider = session.provider;
    _displayName = session.displayName;
    _email = session.email;
  }

  Uri _buildUri(
    String path,
    Map<String, String> query, {
    Map<String, List<String>> arrays = const <String, List<String>>{},
  }) {
    final pairs = <String>[];
    query.forEach((key, value) {
      pairs.add(
        '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
      );
    });
    arrays.forEach((key, values) {
      if (values.isEmpty) {
        pairs.add('${Uri.encodeQueryComponent(key)}=');
      } else {
        for (final value in values) {
          pairs.add(
            '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
          );
        }
      }
    });

    return Uri(
      scheme: 'https',
      host: _host,
      path: path,
      query: pairs.join('&'),
    );
  }
}

/// 캠핑장 목록 응답(JSON) 한 페이지를 파싱한다.
/// items가 리스트가 아니면 빈 페이지로 간주하고, hasNext는 true일 때만 true다.
PageResult<Campsite> parseCampsitePage(Map<String, dynamic> decoded) {
  final items = decoded['items'];
  if (items is! List) {
    return (items: <Campsite>[], hasNext: false);
  }
  return (
    items: items
        .whereType<Map<String, dynamic>>()
        .map(Campsite.fromJson)
        .toList(),
    hasNext: decoded['hasNext'] == true,
  );
}

class CampOnApiException implements Exception {
  const CampOnApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CampOnSessionExpiredException extends CampOnApiException {
  const CampOnSessionExpiredException(super.message);
}

class Campsite {
  Campsite({
    required this.id,
    required this.name,
    required this.lineIntro,
    required this.description,
    required this.lat,
    required this.lon,
    required this.distance,
    required this.zipcode,
    required this.tel,
    required this.reservationUrl,
    required this.facility,
    required this.thumbnailUrl,
    required this.imageUrls,
    required this.trailerAccompanyAt,
    required this.caravanAccompanyAt,
    required this.toiletCount,
    required this.showerRoomCount,
    required this.sinkCount,
    required this.equipmentRental,
    this.score,
  });

  factory Campsite.fromJson(Map<String, dynamic> json) {
    return Campsite(
      id: _asInt(json['campsiteId']),
      score: json.containsKey('score') ? _asInt(json['score']) : null,
      name: _asString(json['name'], fallback: '이름 없는 캠핑장'),
      lineIntro: _asString(json['lineIntro']),
      description: _asString(json['description']),
      lat: _asDouble(json['lat']),
      lon: _asDouble(json['lon']),
      distance: _asInt(json['distance']),
      zipcode: _asString(json['zipcode']),
      tel: _asString(json['tel']),
      reservationUrl: _asString(json['resveUrl']),
      facility: _asStringList(json['facility']),
      thumbnailUrl: _asString(json['thumbnailUrl']),
      imageUrls: _asStringList(json['imageUrls']),
      trailerAccompanyAt: json['trailerAccompanyAt'] == true,
      caravanAccompanyAt: json['caravanAccompanyAt'] == true,
      toiletCount: _asInt(json['toiletCount']),
      showerRoomCount: _asInt(json['showerRoomCount']),
      sinkCount: _asInt(json['sinkCount']),
      equipmentRental: _asStringList(json['equipmentRental']),
    );
  }

  /// 서버가 준 거리(검색 지역 중심 기준)를 실제 사용자 위치 기준 거리로 바꿔치기한다.
  Campsite copyWithDistance(int distance) => Campsite(
    id: id,
    score: score,
    name: name,
    lineIntro: lineIntro,
    description: description,
    lat: lat,
    lon: lon,
    distance: distance,
    zipcode: zipcode,
    tel: tel,
    reservationUrl: reservationUrl,
    facility: facility,
    thumbnailUrl: thumbnailUrl,
    imageUrls: imageUrls,
    trailerAccompanyAt: trailerAccompanyAt,
    caravanAccompanyAt: caravanAccompanyAt,
    toiletCount: toiletCount,
    showerRoomCount: showerRoomCount,
    sinkCount: sinkCount,
    equipmentRental: equipmentRental,
  );

  /// 로컬 즐겨찾기 저장용. `fromJson`이 읽는 키와 이름을 정확히 맞춰
  /// 저장한 값을 그대로 되돌릴 수 있게 한다.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'campsiteId': id,
    // fromJson이 containsKey로 판정하므로, 점수가 없으면 키 자체를 넣지 않는다.
    if (score != null) 'score': score,
    'name': name,
    'lineIntro': lineIntro,
    'description': description,
    'lat': lat,
    'lon': lon,
    'distance': distance,
    'zipcode': zipcode,
    'tel': tel,
    'resveUrl': reservationUrl,
    'facility': facility,
    'thumbnailUrl': thumbnailUrl,
    'imageUrls': imageUrls,
    'trailerAccompanyAt': trailerAccompanyAt,
    'caravanAccompanyAt': caravanAccompanyAt,
    'toiletCount': toiletCount,
    'showerRoomCount': showerRoomCount,
    'sinkCount': sinkCount,
    'equipmentRental': equipmentRental,
  };

  final int id;
  final int? score;
  final String name;
  final String lineIntro;
  final String description;
  final double lat;
  final double lon;
  final int distance;
  final String zipcode;
  final String tel;
  final String reservationUrl;
  final List<String> facility;
  final String thumbnailUrl;
  final List<String> imageUrls;
  final bool trailerAccompanyAt;
  final bool caravanAccompanyAt;
  final int toiletCount;
  final int showerRoomCount;
  final int sinkCount;
  final List<String> equipmentRental;

  String get caption {
    final parts = <String>[];
    if (zipcode.isNotEmpty) {
      parts.add('우편번호 $zipcode');
    }
    if (distance > 0) {
      parts.add(_formatDistance(distance));
    }
    return parts.isEmpty ? '캠핑장' : parts.join(' · ');
  }

  String get scoreLabel => score == null ? '정보' : '$score점';

  Uri? get validReservationUri {
    final uri = Uri.tryParse(reservationUrl);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return null;
    }
    return uri;
  }

  String? get validThumbnailUrl {
    final uri = Uri.tryParse(thumbnailUrl);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return validImageUrls.isEmpty ? null : validImageUrls.first;
    }
    return thumbnailUrl;
  }

  List<String> get validImageUrls => imageUrls.where((url) {
    final uri = Uri.tryParse(url);
    return uri != null && (uri.isScheme('https') || uri.isScheme('http'));
  }).toList();

  List<String> get tags {
    final labels = facility
        .take(3)
        .map((value) => CampData.facilityLabels[value] ?? value)
        .toList();
    if (labels.isEmpty) {
      if (trailerAccompanyAt) {
        labels.add('트레일러 동반');
      }
      if (caravanAccompanyAt) {
        labels.add('카라반 동반');
      }
    }
    return labels.isEmpty ? <String>['기본 정보'] : labels;
  }

  String get ratingLabel {
    final values = [
      facilityScore('TOILET'),
      facilityScore('SHOWER'),
      facilityScore('SINK'),
      facilityScore('ELECTRICITY'),
    ];
    final rating = values.reduce((a, b) => a + b) / values.length;
    return rating.toStringAsFixed(1);
  }

  int facilityScore(String code) {
    if (facility.contains(code)) {
      return 5;
    }
    return switch (code) {
      'TOILET' => _countScore(toiletCount),
      'SHOWER' => _countScore(showerRoomCount),
      'SINK' => _countScore(sinkCount),
      'ELECTRICITY' => facility.contains('ELECTRICITY') ? 5 : 1,
      _ => 1,
    };
  }

  String accessDescription({required bool hasCar}) {
    final distanceText = distance > 0 ? _formatDistance(distance) : '거리 정보 없음';
    if (hasCar) {
      final options = <String>[
        distanceText,
        if (trailerAccompanyAt) '트레일러 동반 가능',
        if (caravanAccompanyAt) '카라반 동반 가능',
      ];
      return '${options.join(' · ')}. 차량 이동 기준으로 예약처의 진입로와 주차 정보를 확인해주세요.';
    }
    return '$distanceText. 대중교통 세부 정보는 API에 없어 출발 전 지도 앱으로 마지막 이동 구간을 확인해주세요.';
  }
}

class CampRegion {
  const CampRegion({
    required this.name,
    required this.lat,
    required this.lon,
    required this.mapX,
    required this.mapY,
  });

  final String name;
  final double lat;
  final double lon;
  final double mapX;
  final double mapY;
}

class CampOption {
  const CampOption({
    required this.label,
    required this.apiValue,
    required this.note,
  });

  final String label;
  final String apiValue;
  final String note;
}

class CampPost {
  const CampPost({
    required this.id,
    required this.campsiteId,
    required this.title,
    required this.content,
    required this.createdAt,
    this.authorId,
    this.authorNickname,
  });

  factory CampPost.fromJson(Map<String, dynamic> json) {
    final nickname = _asString(json['authorNickname']);
    return CampPost(
      id: _asInt(json['id']),
      campsiteId: _asInt(json['campsiteId']),
      title: _asString(json['title'], fallback: '제목 없음'),
      content: _asString(json['content']),
      createdAt: DateTime.tryParse(_asString(json['createdAt']))?.toLocal(),
      authorId: json['authorId'] != null ? _asInt(json['authorId']) : null,
      authorNickname: nickname.isEmpty ? null : nickname,
    );
  }

  final int id;
  final int campsiteId;
  final String title;
  final String content;
  final DateTime? createdAt;

  /// 게시글 작성자 ID (서버가 내려줄 때만 사용)
  final int? authorId;

  /// 게시글 작성자 닉네임 (서버가 내려줄 때만 사용)
  final String? authorNickname;

  String get createdAtLabel {
    final date = createdAt;
    if (date == null) {
      return '';
    }
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}.${two(date.month)}.${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  /// 카드 아래에 붙일 작성자·작성일 한 줄. 서버가 안 주는 값은 자연스럽게 빠진다.
  String get metaLabel => [
    ?authorNickname,
    if (createdAtLabel.isNotEmpty) createdAtLabel,
  ].join(' · ');
}

/// 차단된 유저 응답 DTO
class BlockedUser {
  const BlockedUser({
    required this.id,
    required this.blockedUserId,
    required this.createdAt,
    this.nickname,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    final nickname = _asString(json['nickname']);
    return BlockedUser(
      id: _asInt(json['id']),
      blockedUserId: _asInt(json['blockedUserId']),
      createdAt: DateTime.tryParse(_asString(json['createdAt']))?.toLocal(),
      nickname: nickname.isEmpty ? null : nickname,
    );
  }

  final int id;
  final int blockedUserId;
  final DateTime? createdAt;

  /// 차단한 유저 닉네임 (서버가 내려줄 때만 사용)
  final String? nickname;

  /// 목록에 보여줄 이름. 닉네임이 없으면 유저 번호로 대신한다.
  String get displayName => nickname ?? '유저 #$blockedUserId';
}

class DirectionResult {
  const DirectionResult({
    required this.distanceMeters,
    required this.durationSeconds,
  });

  factory DirectionResult.fromJson(Map<String, dynamic> json) {
    return DirectionResult(
      distanceMeters: _asInt(json['distance']),
      durationSeconds: _asInt(json['duration']),
    );
  }

  final int distanceMeters;
  final int durationSeconds;
}

class FacilityBarData {
  const FacilityBarData(this.label, this.value);

  final String label;
  final int value;
}

class CampData {
  static const regions = <CampRegion>[
    CampRegion(name: '경기', lat: 37.4138, lon: 127.5183, mapX: 34, mapY: 16),
    CampRegion(name: '강원', lat: 37.8228, lon: 128.1555, mapX: 70, mapY: 14),
    CampRegion(name: '충청', lat: 36.8, lon: 127.7, mapX: 40, mapY: 42),
    CampRegion(name: '전라', lat: 35.3, lon: 126.9, mapX: 28, mapY: 68),
    CampRegion(name: '경상', lat: 35.8, lon: 128.7, mapX: 66, mapY: 60),
    CampRegion(name: '제주', lat: 33.4996, lon: 126.5312, mapX: 34, mapY: 90),
  ];

  static const skillLevels = <String>['초보', '중급', '고급'];

  static const equipmentOptions = <CampOption>[
    CampOption(
      label: '텐트',
      apiValue: 'TENT',
      note: '텐트가 없으면 글램핑이나 대여 가능 여부를 먼저 확인하세요.',
    ),
    CampOption(
      label: '침낭',
      apiValue: 'SLEEPING_BAG',
      note: '침낭이 없으면 밤 기온에 대비하기 어렵습니다.',
    ),
    CampOption(
      label: '매트',
      apiValue: 'SLEEPING_PAD',
      note: '매트가 없으면 바닥 냉기가 그대로 전해질 수 있어요.',
    ),
    CampOption(
      label: '랜턴',
      apiValue: 'LANTERN',
      note: '랜턴이 없으면 야간 이동과 취사가 불편해요.',
    ),
    CampOption(
      label: '보조배터리',
      apiValue: 'POWER_BANK',
      note: '전기 사용이 제한된 곳에서는 방전 위험이 있어요.',
    ),
    CampOption(
      label: '버너',
      apiValue: 'PORTABLE_STOVE',
      note: '버너가 없으면 따뜻한 식사 준비가 어려워요.',
    ),
  ];

  static const preferenceOptions = <CampOption>[
    CampOption(label: '전기 사용 가능', apiValue: 'ELECTRICITY', note: ''),
    CampOption(label: '샤워실 필수', apiValue: 'SHOWER', note: ''),
    CampOption(label: '화장실 청결 중요', apiValue: 'TOILET', note: ''),
    CampOption(label: '아이 동반 가능', apiValue: 'PLAYGROUND', note: ''),
  ];

  static const fixedChecklist = <CampOption>[
    CampOption(label: '식수', apiValue: 'WATER', note: ''),
    CampOption(label: '여벌 옷', apiValue: 'SPARE_CLOTHES', note: ''),
    CampOption(label: '쓰레기봉투', apiValue: 'TRASH_BAG', note: ''),
    CampOption(label: '구급약', apiValue: 'FIRST_AID_KIT', note: ''),
  ];

  static const facilityLabels = <String, String>{
    'SHOWER': '샤워실',
    'TOILET': '화장실',
    'SINK': '개수대',
    'ELECTRICITY': '전기 사용 가능',
    'WIFI': '와이파이',
    'HOT_WATER': '온수',
    'FIREWOOD_SALE': '장작 판매',
    'WATER_PLAY': '물놀이',
    'PLAYGROUND': '놀이터',
    'EXERCISE_FACILITY': '운동시설',
    'PET_FRIENDLY': '반려동물',
    'BONFIRE_PIT': '화로대',
  };
}

String _formatKoreanDate(DateTime date) {
  return '${date.year}년 ${date.month}월 ${date.day}일';
}

String _formatDistance(int distanceMeters) {
  if (distanceMeters >= 1000) {
    final km = distanceMeters / 1000;
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1)}km';
  }
  return '${distanceMeters}m';
}

String _formatDuration(int seconds) {
  if (seconds <= 0) {
    return '정보 없음';
  }
  final totalMinutes = (seconds / 60).round();
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0) {
    return minutes > 0 ? '$hours시간 $minutes분' : '$hours시간';
  }
  return '$minutes분';
}

int _countScore(int count) {
  if (count >= 5) {
    return 5;
  }
  if (count >= 3) {
    return 4;
  }
  if (count >= 2) {
    return 3;
  }
  if (count >= 1) {
    return 2;
  }
  return 1;
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse('$value') ?? 0;
}

double _asDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse('$value') ?? 0;
}

String _asString(Object? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = '$value';
  return text.isEmpty ? fallback : text;
}

List<String> _asStringList(Object? value) {
  if (value is! List) {
    return <String>[];
  }
  return value.map((item) => '$item').toList();
}
