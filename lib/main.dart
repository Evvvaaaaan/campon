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

import 'campsites/campsite_map_view.dart';
import 'campsites/campsite_pagination.dart';
import 'campsites/favorites_store.dart';
import 'location/location_service.dart';
import 'motion/motion.dart';
import 'planner/plan_models.dart';
import 'planner/planner_input_screen.dart';
import 'planner/planner_result_screen.dart';
import 'preview/night_preview_button.dart';
import 'preview/night_preview_screen.dart';
import 'preview/preview_models.dart';
import 'theme.dart';
import 'tonight/night_models.dart';
import 'tonight/night_visuals.dart';
import 'tonight/tonight_card.dart';
import 'tonight/tonight_service.dart';

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
  AuthRepository.initialize(appKey: AuthConfig.kakaoJavascriptKey);
}

class AuthConfig {
  static const kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
    defaultValue: '0ecef49f91608f40010f59053f36fa9a',
  );
  static const kakaoJavascriptKey = String.fromEnvironment(
    'KAKAO_JAVASCRIPT_KEY',
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

  static bool get hasLinks =>
      privacyPolicyUrl.isNotEmpty || termsOfServiceUrl.isNotEmpty;

  /// 링크를 열지 못하면 조용히 실패하지 않고 호출한 쪽이 안내할 수 있게 false를 준다.
  static Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
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
    final scope = context
        .dependOnInheritedWidgetOfExactType<CampThemeScope>();
    assert(scope != null, 'CampThemeScope가 트리에 없습니다');
    return scope!;
  }

  @override
  bool updateShouldNotify(CampThemeScope oldWidget) =>
      oldWidget.isDark != isDark;
}

class CampOnApp extends StatefulWidget {
  const CampOnApp({this.api, this.favoritesStore, super.key});

  final CampOnApi? api;
  final FavoritesStore? favoritesStore;

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
  onboardingBasics,
  onboardingExperience,
  onboardingPreferences,
  recommendations,
  settings,
  plannerInput,
  plannerResult,
}

enum DetailEntry { recommendations, browse }

class CampOnShell extends StatefulWidget {
  const CampOnShell({this.api, this.favoritesStore, super.key});

  final CampOnApi? api;
  final FavoritesStore? favoritesStore;

  @override
  State<CampOnShell> createState() => _CampOnShellState();
}

class _CampOnShellState extends State<CampOnShell> {
  late final CampOnApi _api;
  late final FavoritesStore _favoritesStore;

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

  CampPlan? _plan;
  List<Campsite> _planCandidates = <Campsite>[];
  List<String> _aiChecklistItems = const <String>[];

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? CampOnApi();
    _favoritesStore =
        widget.favoritesStore ?? const SharedPrefsFavoritesStore();
    _api.onSessionInvalidated = _returnToLogin;
    _restoreSession();
    _restoreFavorites();
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
  bool get _showTabs => const {
    AppStep.home,
    AppStep.browse,
    AppStep.recommendations,
    AppStep.checklist,
    AppStep.settings,
  }.contains(_step);

  void _goHome() {
    setState(() => _step = AppStep.home);
  }

  void _startOnboarding() {
    setState(() => _step = AppStep.onboardingBasics);
  }

  void _goBrowse() {
    setState(() {
      _browseFuture ??= _api.fetchAllNearby(region: _region);
      _step = AppStep.browse;
    });
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
      try {
        _planCandidates =
            await _api.fetchNearby(region: _region, page: 0, size: 10);
      } catch (_) {
        // Planner still works with region-based fallback when candidates fail.
      }
    }
    if (mounted) {
      setState(() => _step = AppStep.plannerInput);
    }
  }

  /// 오늘 밤 카드에 이름을 붙일 대표 캠핑장.
  ///
  /// 이미 받아둔 후보만 쓰고 새로 조회하지 않는다. 홈에서 인증 API를 부르면
  /// 토큰이 만료됐을 때 카드 문구 하나 때문에 로그인 화면으로 튕길 수 있다.
  /// 후보가 없으면 지역명으로 표시된다.
  Future<String?> _loadTonightDestination() async =>
      _planCandidates.isEmpty ? null : _planCandidates.first.name;

  void _openNightPreview(NightSky night, String place, int? myTempC) {
    openNightPreview(
      context,
      input: PreviewInput(
        place: place,
        date: night.date,
        moonIlluminationPct: night.moonIlluminationPct,
        moonInterferencePct: night.moonInterferencePct,
        score: night.score,
        grade: night.grade.name,
        people: _people,
        experience: _skillLevel ?? '초보',
        cloudPct: night.cloudPct,
        precipPct: night.precipPct,
        windMs: night.windMs,
        nightLowC: night.nightLowC,
        myTempC: myTempC,
      ),
      actionLabel: '이 밤에 갈 캠핑장 보기',
      onAction: _goBrowse,
    );
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
          .map((s) => PlanCandidate(
                name: s.name,
                facility: s.facility,
                equipmentRental: s.equipmentRental,
              ))
          .toList(),
    );
  }

  void _back() {
    setState(() {
      switch (_step) {
        case AppStep.onboardingExperience:
          _step = AppStep.onboardingBasics;
        case AppStep.onboardingPreferences:
          _step = AppStep.onboardingExperience;
        case AppStep.details:
          _step = _detailEntry == DetailEntry.browse
              ? AppStep.browse
              : AppStep.recommendations;
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
        case AppStep.settings:
        case AppStep.onboardingBasics:
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

  void _selectSite(Campsite site, DetailEntry entry) {
    setState(() {
      _selectedSite = site;
      _detailEntry = entry;
      _step = AppStep.details;
    });
  }

  void _startPreparation() {
    if (_selectedSite != null) {
      setState(_seedChecklistAndOpen);
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
      _hasRecommended = false;
      _equipment.clear();
      _preferences.clear();
      _checkedItems.clear();
      _checklistSeeded = false;
      _recommendationsFuture = null;
      _browseFuture = null;
      _detailEntry = DetailEntry.recommendations;
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
      _hasRecommended = false;
      _equipment.clear();
      _preferences.clear();
      _checkedItems.clear();
      _checklistSeeded = false;
      _recommendationsFuture = null;
      _browseFuture = null;
      _detailEntry = DetailEntry.recommendations;
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
      _hasRecommended = false;
      _equipment.clear();
      _preferences.clear();
      _checkedItems.clear();
      _checklistSeeded = false;
      _recommendationsFuture = null;
      _browseFuture = null;
      _detailEntry = DetailEntry.recommendations;
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
        _showTutorial &&
        _step != AppStep.login &&
        _step != AppStep.loading;
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
      bottomNavigationBar: _showTabs
          ? SafeArea(
              top: false,
              child: CampTabBar(
                currentStep: _step,
                hasRecommended: _hasRecommended,
                onHome: _goHome,
                onBrowse: _goBrowse,
                onRecommend: _goRecommendTab,
                onChecklist: _goChecklist,
                onSettings: _goSettings,
              ),
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
          onPlanner: _goPlanner,
          tonightCard: TonightCard(
            regionName: _region.name,
            lat: _region.lat,
            lon: _region.lon,
            service: TonightService(location: readLocationIfAlreadyGranted),
            destinationLoader: _loadTonightDestination,
            onExplore: _goBrowse,
            onPreview: _openNightPreview,
          ),
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
          onBack: _back,
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
          onBack: _back,
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
              _selectedSite != null && _favorites.containsKey(_selectedSite!.id),
          onToggleFavorite: () {
            if (_selectedSite != null) _toggleFavorite(_selectedSite!);
          },
        );
      case AppStep.checklist:
        return ChecklistScreen(
          selectedSite: _selectedSite,
          checkedItems: _checkedItems,
          aiItems: _aiChecklistItems,
          onToggle: (key) => _toggleSetValue(_checkedItems, key),
          onReset: _reset,
        );
      case AppStep.community:
        return CommunityScreen(
          api: _api,
          site: _selectedSite,
          onBack: _back,
        );
      case AppStep.plannerInput:
        return PlannerInputScreen(
          prefill: _buildPlanInput(),
          onBack: _goHome,
          onGenerated: (plan) => setState(() {
            _plan = plan;
            _step = AppStep.plannerResult;
          }),
        );
      case AppStep.plannerResult:
        return PlannerResultScreen(
          plan: _plan!,
          onBack: () => setState(() => _step = AppStep.plannerInput),
          onRegenerate: () => setState(() => _step = AppStep.plannerInput),
          onSendToChecklist: (items) => setState(() {
            _aiChecklistItems = items;
            _seedChecklistAndOpen();
          }),
        );
      case AppStep.settings:
        return SettingsScreen(
          region: _region,
          people: _people,
          hasCar: _hasCar,
          preTripAlerts: _preTripAlerts,
          equipmentCount: _equipment.length,
          onAlertChanged: (value) => setState(() => _preTripAlerts = value),
          onResetPreferences: _reset,
          onSignOut: _signOut,
          onDeleteAccount: _deleteAccount,
        );
      case AppStep.browse:
        return CampsiteBrowseScreen(
          title: '주변 캠핑장',
          subtitle: '${_region.name} 반경 20km 이내 캠핑장이에요.',
          future: _browseFuture,
          emptyText: '반경 20km 이내에서 캠핑장을 찾지 못했어요.',
          onRetry: () {
            setState(() {
              _browseFuture = _api.fetchAllNearby(region: _region);
            });
          },
          onSelect: (site) => _selectSite(site, DetailEntry.browse),
          mapViewBuilder: (sites, onSelect) => CampsiteMapView(
            region: _region,
            sites: sites,
            onSelect: onSelect,
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
        ClientErrorCause.notSupported =>
          '이 기기에서는 카카오 로그인을 사용할 수 없습니다.',
        ClientErrorCause.tokenNotFound =>
          '카카오 로그인 정보가 없습니다. 다시 로그인해주세요.',
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
      return _withDebugDetail(
        '카카오 로그인에 실패했습니다. 잠시 후 다시 시도해주세요.',
        '$error',
      );
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
                    minHeight: (constraints.maxHeight - verticalPadding)
                        .clamp(0.0, double.infinity),
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
                      if (LegalConfig.hasLinks) ...[
                        const SizedBox(height: 6),
                        LegalLinkRow(),
                      ],
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onStart,
    required this.onBrowse,
    required this.onPlanner,
    required this.tonightCard,
    super.key,
  });

  final VoidCallback onStart;
  final VoidCallback onBrowse;
  final VoidCallback onPlanner;

  /// 홈 최상단의 "오늘 밤 지수" 카드. 셸이 만들어 넣어준다.
  final Widget tonightCard;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                // 로고 배지는 디자인에서 테마와 무관하게 같은 색을 쓴다.
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
        const SizedBox(height: 18),
        tonightCard,
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 232,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 히어로는 사진 자리를 대신하는 고정 어두운 면이다. 테마를 따라
                // 밝아지면 위에 얹은 흰 글자가 읽히지 않으므로 라이트 값을 고정한다.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        CampPalette.light.forestMid,
                        CampPalette.light.forest,
                      ],
                    ),
                  ),
                ),
                // 디자인의 히어로 오버레이(160deg, rgba(20,40,29,0.55)→0.9).
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-0.35, -1),
                      end: Alignment(0.35, 1),
                      stops: [0.1, 0.9],
                      colors: [Color(0x8C14281D), Color(0xE614281D)],
                    ),
                  ),
                ),
                const Positioned(
                  top: 14,
                  right: 16,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: 130,
                      height: 46,
                      child: StarField(starCount: 10, seed: 3),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '오늘의 캠핑을\n정리해볼까요?',
                        style: CampText.display.copyWith(
                          fontSize: 26,
                          height: 1.25,
                          color: CampColors.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'AI에게 한 줄만 적으면 캠핑장·날씨·준비물·타임라인까지 한 번에 만들어 드려요.',
                        style: CampText.caption.copyWith(
                          fontSize: 13,
                          color: CampPalette.light.greenTint,
                        ),
                      ),
                      const SizedBox(height: 14),
                      CampButton(
                        label: 'AI로 캠핑 플랜 짜기',
                        icon: LucideIcons.sparkles,
                        onPressed: onPlanner,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        CampCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SettingsIcon(
                    icon: LucideIcons.sparkles,
                    background: CampColors.amberTint,
                    iconColor: CampColors.primaryDark,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '맞춤 추천',
                    style: CampText.sectionTitle.copyWith(fontSize: 19),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '날짜, 지역, 이동수단을 기준으로 캠핑장을 추천합니다.',
                style: CampText.caption.copyWith(color: CampColors.inkMuted80),
              ),
              const SizedBox(height: 16),
              CampButton(
                label: '추천 시작',
                icon: LucideIcons.sparkles,
                background: CampColors.forest,
                onPressed: onStart,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CampCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SettingsIcon(icon: LucideIcons.mountain, size: 40),
                  const SizedBox(width: 12),
                  Text(
                    '캠핑장 둘러보기',
                    style: CampText.sectionTitle.copyWith(fontSize: 19),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '현재 선택된 지역 근처의 캠핑장을 먼저 살펴봅니다.',
                style: CampText.caption.copyWith(color: CampColors.inkMuted80),
              ),
              const SizedBox(height: 16),
              CampButton.secondary(
                label: '목록 보기',
                foreground: CampColors.forest,
                borderColor: CampColors.forest,
                onPressed: onBrowse,
              ),
            ],
          ),
        ),
      ],
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
    required this.onBack,
    required this.onHasCarChanged,
    required this.onSkillChanged,
    required this.onNext,
    required this.nextEnabled,
    super.key,
  });

  final bool? hasCar;
  final String? skillLevel;
  final VoidCallback onBack;
  final ValueChanged<bool> onHasCarChanged;
  final ValueChanged<String> onSkillChanged;
  final VoidCallback onNext;
  final bool nextEnabled;

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      progressIndex: 1,
      onBack: onBack,
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
    required this.onBack,
    required this.onEquipmentToggle,
    required this.onPreferenceToggle,
    required this.onFamilyChanged,
    required this.onSubmit,
    super.key,
  });

  final Set<String> equipment;
  final Set<String> preferences;
  final bool? withFamily;
  final VoidCallback onBack;
  final ValueChanged<String> onEquipmentToggle;
  final ValueChanged<String> onPreferenceToggle;
  final ValueChanged<bool> onFamilyChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      progressIndex: 2,
      onBack: onBack,
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

typedef CampsiteMapBuilder = Widget Function(
  List<Campsite> sites,
  ValueChanged<Campsite> onSelect,
);

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
                return ErrorPanel(
                  message: snapshot.error.toString(),
                  onRetry: widget.onRetry,
                );
              }
              final sites = snapshot.data ?? <Campsite>[];
              if (sites.isEmpty) {
                return EmptyPanel(text: widget.emptyText, onRetry: widget.onRetry);
              }
              if (_showMap) {
                return widget.mapViewBuilder(sites, widget.onSelect);
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  Text(widget.subtitle, style: CampText.body.copyWith(color: CampColors.inkMuted80)),
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
    _exit = AnimationController(
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
              return EmptyPanel(text: widget.emptyText, onRetry: widget.onRetry);
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
              CampImagePlaceholder()
            else
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    CampImagePlaceholder(),
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
                    site.lineIntro.isEmpty
                        ? site.accessHint
                        : '${site.accessHint} · ${site.lineIntro}',
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

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Row(
                children: [
                  BackCircleButton(onPressed: onBack),
                  const Spacer(),
                  FavoriteHeartButton(
                    isFavorite: isFavorite,
                    onPressed: onToggleFavorite,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              CampsiteHeroImage(site: campsite),
              const SizedBox(height: 16),
              Text(campsite.name, style: CampText.tagline),
              const SizedBox(height: 2),
              Text(
                campsite.caption,
                style: CampText.caption.copyWith(color: CampColors.inkMuted48),
              ),
              const SizedBox(height: 10),
              Text(
                campsite.scoreLabel,
                style: CampText.bodyStrong.copyWith(color: CampColors.primary),
              ),
              if (campsite.description.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  campsite.description,
                  style: CampText.body.copyWith(color: CampColors.inkMuted80),
                ),
              ],
              const SizedBox(height: 22),
              FormLabel('시설 점수'),
              FacilityBars(site: campsite),
              const SizedBox(height: 22),
              FormLabel(hasCar ? '차량 이동' : '대중교통 · 도보 이동'),
              Text(
                campsite.accessDescription(hasCar: hasCar),
                style: CampText.body.copyWith(color: CampColors.inkMuted80),
              ),
              const SizedBox(height: 22),
              FormLabel('길찾기'),
              DirectionsCard(
                fetchDirections: api.fetchDirections,
                location: const GeolocatorLocationProvider(),
                site: campsite,
              ),
              const SizedBox(height: 22),
              FormLabel('그날 밤'),
              NightPreviewButton(
                placeName: campsite.name,
                lat: campsite.lat,
                lon: campsite.lon,
                actionLabel: '이 캠핑장으로 준비 시작',
                onAction: onPrepare,
              ),
              const SizedBox(height: 22),
              FormLabel('날씨 리스크 · 준비 중'),
              Text(
                '현재 API 명세에는 날씨 정보가 없어 캠핑장 시설과 거리 기준으로 먼저 안내해요.',
                style: CampText.body.copyWith(color: CampColors.inkMuted80),
              ),
              const SizedBox(height: 22),
              FormLabel('이용 후기'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(campsite.ratingLabel, style: CampText.bodyStrong),
                  const SizedBox(width: 8),
                  Text(
                    '· 커뮤니티 준비 중',
                    style: CampText.caption.copyWith(
                      color: CampColors.inkMuted48,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final review in campsite.previewReviews)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: CampColors.hairline)),
                  ),
                  child: Text(
                    '“$review”',
                    style: CampText.caption.copyWith(
                      color: CampColors.inkMuted80,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onCommunity,
                  style: TextButton.styleFrom(
                    foregroundColor: CampColors.primaryDark,
                    padding: EdgeInsets.zero,
                    textStyle: CampText.captionStrong,
                  ),
                  child: const Text('커뮤니티에서 더 보기'),
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

typedef DirectionsFetcher =
    Future<DirectionResult> Function({
      required double originX,
      required double originY,
      required double destX,
      required double destY,
    });

class DirectionsCard extends StatefulWidget {
  const DirectionsCard({
    required this.fetchDirections,
    required this.location,
    required this.site,
    super.key,
  });

  final DirectionsFetcher fetchDirections;
  final LocationProvider location;
  final Campsite site;

  @override
  State<DirectionsCard> createState() => _DirectionsCardState();
}

class _DirectionsCardState extends State<DirectionsCard> {
  bool _loading = false;
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
    return Row(
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
                    Icon(LucideIcons.sparkles,
                        size: 16, color: CampColors.forest),
                    const SizedBox(width: 6),
                    Text('AI 플래너가 이번 캠핑에 맞춰 추천했어요',
                        style: CampText.captionStrong
                            .copyWith(color: CampColors.forest)),
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
                            horizontal: 12, vertical: 7),
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
                    checked:
                        checkedItems.contains(checklistItems[index].apiValue),
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

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
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
        BackCircleButton(onPressed: widget.onBack),
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
              return ErrorPanel(
                message: '${snapshot.error}',
                onRetry: _reload,
              );
            }
            final posts = snapshot.data ?? const <CampPost>[];
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
                  _PostCard(post: post, onDelete: () => _deletePost(post)),
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
  const _PostCard({required this.post, required this.onDelete});

  final CampPost post;
  final VoidCallback onDelete;

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
              IconButton(
                tooltip: '삭제',
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: CampColors.inkMuted48,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(post.content, style: CampText.body),
          if (post.createdAtLabel.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              post.createdAtLabel,
              style: CampText.finePrint.copyWith(color: CampColors.inkMuted48),
            ),
          ],
        ],
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
      title: '앱 버전',
      value: _version,
    );
  }
}

/// 이용약관과 개인정보 처리방침을 여는 링크. URL이 설정된 문서만 보여준다.
class LegalLinkRow extends StatelessWidget {
  const LegalLinkRow({this.color, super.key});

  final Color? color;

  Future<void> _open(BuildContext context, String url) async {
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
      if (LegalConfig.termsOfServiceUrl.isNotEmpty)
        GestureDetector(
          onTap: () => _open(context, LegalConfig.termsOfServiceUrl),
          child: Text('이용약관', style: style),
        ),
      if (LegalConfig.privacyPolicyUrl.isNotEmpty)
        GestureDetector(
          onTap: () => _open(context, LegalConfig.privacyPolicyUrl),
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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.region,
    required this.people,
    required this.hasCar,
    required this.preTripAlerts,
    required this.equipmentCount,
    required this.onAlertChanged,
    required this.onResetPreferences,
    required this.onSignOut,
    required this.onDeleteAccount,
    super.key,
  });

  final CampRegion region;
  final int people;
  final bool? hasCar;
  final bool preTripAlerts;
  final int equipmentCount;
  final ValueChanged<bool> onAlertChanged;
  final VoidCallback onResetPreferences;
  final VoidCallback onSignOut;
  final Future<void> Function() onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final mobility = switch (hasCar) {
      true => '차량 이동',
      false => '대중교통 이동',
      null => '미설정',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Text('설정', style: CampText.displaySmall),
        const SizedBox(height: 6),
        Text(
          '계정과 추천 조건을 확인하고 앱 동작을 관리합니다.',
          style: CampText.caption.copyWith(color: CampColors.inkMuted80),
        ),
        const SizedBox(height: 20),
        CampCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('계정', style: CampText.sectionTitle),
              const SizedBox(height: 14),
              SettingsRow(
                icon: LucideIcons.shieldCheck,
                title: '로그인 상태',
                value: '활성',
                badge: true,
                valueColor: CampColors.forestMid,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: CampButton.secondary(
                  label: '로그아웃',
                  onPressed: onSignOut,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: DeleteAccountButton(onDelete: onDeleteAccount),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CampCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('추천 조건', style: CampText.sectionTitle),
              const SizedBox(height: 14),
              SettingsRow(
                icon: LucideIcons.mapPin,
                title: '기준 지역',
                value: region.name,
              ),
              const SizedBox(height: 14),
              SettingsRow(
                icon: LucideIcons.users,
                title: '인원',
                value: '$people명',
              ),
              const SizedBox(height: 14),
              SettingsRow(
                icon: LucideIcons.car,
                title: '이동수단',
                value: mobility,
              ),
              const SizedBox(height: 14),
              SettingsRow(
                icon: Icons.backpack_outlined,
                title: '보유 장비',
                value: '$equipmentCount개',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: CampButton.secondary(
                  label: '조건 초기화',
                  onPressed: onResetPreferences,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Builder(
          builder: (context) {
            final scope = CampThemeScope.of(context);
            return ToggleSettingCard(
              icon: LucideIcons.moon,
              title: '야간 캠핑 테마',
              subtitle: '어두운 곳에서도 편안하게',
              value: scope.isDark,
              onChanged: (_) => scope.toggle(),
            );
          },
        ),
        const SizedBox(height: 14),
        CampCard(
          child: Row(
            children: [
              Icon(
                LucideIcons.bell,
                size: 18,
                color: CampColors.forestMid,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('준비 알림', style: CampText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      '캠핑 준비 흐름 알림 유지',
                      style: CampText.caption.copyWith(
                        color: CampColors.inkMuted80,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: preTripAlerts,
                activeThumbColor: CampColors.onPrimary,
                activeTrackColor: CampColors.forestMid,
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
              // API 호스트는 사용자에게 의미가 없으므로 디버그 빌드에서만 보여준다.
              if (kDebugMode) ...[
                SettingsRow(
                  icon: Icons.dns_outlined,
                  title: 'API 서버',
                  value: CampOnApi.publicHost,
                ),
                const SizedBox(height: 14),
              ],
              AppVersionRow(),
              if (LegalConfig.hasLinks) ...[
                const SizedBox(height: 16),
                LegalLinkRow(color: CampColors.inkMuted80),
              ],
            ],
          ),
        ),
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
    return CampButton.secondary(
      label: _deleting ? '탈퇴 처리 중…' : '회원 탈퇴',
      foreground: _danger,
      borderColor: _danger,
      onPressed: _deleting ? null : _confirmAndDelete,
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
    (
      '추천에서 골라보세요',
      '조건을 정하면 추천 카드가 나와요. 하트를 누르면 저장하고, X를 누르면 다음 캠핑장으로 넘어가요.',
    ),
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
          BoxShadow(color: Color(0x590E1F17), blurRadius: 44, offset: Offset(0, 20)),
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
class ToggleSettingCard extends StatelessWidget {
  const ToggleSettingCard({
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
      borderRadius: BorderRadius.circular(18),
      child: CampCard(
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
    this.onBack,
    super.key,
  });

  final int progressIndex;
  final Widget body;
  final Widget bottom;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(onBack == null ? 20 : 14, 4, 20, 0),
          child: Row(
            children: [
              if (onBack != null) ...[
                BackCircleButton(onPressed: onBack!),
                const SizedBox(width: 12),
              ],
              Expanded(child: ProgressSegments(activeIndex: progressIndex)),
            ],
          ),
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
              child: CustomPaint(painter: _RegionTerrainPainter()),
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

/// 지역 지도의 라인아트 지형. 디자인 SVG(360×230 viewBox)의 좌표를 그대로 쓴다.
class _RegionTerrainPainter extends CustomPainter {
  const _RegionTerrainPainter();

  static const _ridges = <(List<(double, double)>, Color)>[
    ([(0, 230), (70, 110), (140, 230)], Color(0x222C4A38)),
    ([(90, 230), (180, 70), (260, 230)], Color(0x302C4A38)),
    ([(220, 230), (300, 100), (360, 230)], Color(0x222C4A38)),
  ];

  static const _dots = <(double, double, double)>[
    (40, 30, 2),
    (90, 18, 1.5),
    (300, 24, 2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 360;
    final scaleY = size.height / 230;
    Offset at(double x, double y) => Offset(x * scaleX, y * scaleY);

    for (final (points, color) in _ridges) {
      canvas.drawPath(
        Path()..addPolygon([for (final (x, y) in points) at(x, y)], true),
        Paint()..color = color,
      );
    }

    final dotPaint = Paint()
      ..color = CampColors.primaryDark.withValues(alpha: 0.5);
    for (final (x, y, radius) in _dots) {
      canvas.drawCircle(at(x, y), radius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RegionTerrainPainter oldDelegate) => false;
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
    super.key,
  });

  final Campsite site;
  final bool showScore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final topRight = showScore
        ? site.scoreLabel
        : (site.distance > 0 ? _formatDistance(site.distance) : null);

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
                    ? CampImagePlaceholder()
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
                  const SizedBox(height: 4),
                  Text(
                    site.caption,
                    style: CampText.caption.copyWith(
                      fontSize: 12.5,
                      color: CampColors.inkMuted80,
                    ),
                  ),
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

class CampsiteHeroImage extends StatelessWidget {
  const CampsiteHeroImage({required this.site, super.key});

  final Campsite site;

  @override
  Widget build(BuildContext context) {
    final url = site.validThumbnailUrl;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: url == null
            ? CampImagePlaceholder()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    CampImagePlaceholder(),
              ),
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
                  ? Icon(
                      Icons.check,
                      size: 14,
                      color: CampColors.onPrimary,
                    )
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
        child: Row(
          children: [
            TabItem(
              icon: LucideIcons.home,
              label: '홈',
              selected: currentStep == AppStep.home,
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
          SvgPicture.asset(
            'assets/illustrations/camp_empty.svg',
            height: 132,
          ),
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
  const BackCircleButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

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
        foregroundColor: CampColors.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: CampColors.hairline),
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
    super.key,
  });

  final bool isFavorite;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: isFavorite ? '저장 해제' : '저장하기',
      onPressed: onPressed,
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        size: 20,
      ),
      style: IconButton.styleFrom(
        fixedSize: const Size(36, 36),
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
        foregroundColor: isFavorite ? CampColors.primary : CampColors.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: CampColors.hairline),
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
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final DateTime expiresAt;
  final AuthProvider? provider;
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
  }

  @override
  Future<void> clear() async {
    await Future.wait(<Future<void>>[
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _tokenTypeKey),
      _storage.delete(key: _expiresAtKey),
      _storage.delete(key: _providerKey),
    ]);
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
  Future<void>? _googleInitializeFuture;
  Future<void>? _refreshFuture;
  VoidCallback? onSessionInvalidated;

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
    );
  }

  Future<void> clearSession({bool notify = false}) async {
    _accessToken = null;
    _refreshToken = null;
    _tokenType = 'Bearer';
    _accessTokenExpiresAt = null;
    _provider = null;
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
  }) async {
    await _setSessionFrom(
      _requestJwt(
        _buildUri(provider.path, <String, String>{}),
        method: 'POST',
        body: provider.authRequestBody(credential: credential, name: name),
      ),
      provider: provider,
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

    await signInWithOAuth(
      provider: AuthProvider.kakao,
      credential: token.accessToken,
      name: 'Kakao User',
    );
  }

  Future<List<Campsite>> fetchNearby({
    required CampRegion region,
    required int page,
    required int size,
  }) {
    final uri = _buildUri('/api/v1/campsites/nearby', <String, String>{
      'lat': region.lat.toString(),
      'lon': region.lon.toString(),
      'radius': '10000',
      'size': '$size',
      'page': '$page',
    });
    return _fetchCampsites(uri);
  }

  static const _regionAggregateRadius = 20000;
  static const _regionAggregatePageSize = 100;

  Future<List<Campsite>> fetchAllNearby({required CampRegion region}) {
    return aggregateAllPages<Campsite>((page) {
      final uri = _buildUri('/api/v1/campsites/nearby', <String, String>{
        'lat': region.lat.toString(),
        'lon': region.lon.toString(),
        'radius': '$_regionAggregateRadius',
        'size': '$_regionAggregatePageSize',
        'page': '$page',
      });
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
      trailerAccompanyAt: json['trailerAccompanyAt'] == true,
      caravanAccompanyAt: json['caravanAccompanyAt'] == true,
      toiletCount: _asInt(json['toiletCount']),
      showerRoomCount: _asInt(json['showerRoomCount']),
      sinkCount: _asInt(json['sinkCount']),
      equipmentRental: _asStringList(json['equipmentRental']),
    );
  }

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

  String get accessHint {
    if (distance <= 0) {
      return '위치 정보를 확인하고 있어요.';
    }
    return '${_formatDistance(distance)} 거리에 있어요.';
  }

  String? get validThumbnailUrl {
    final uri = Uri.tryParse(thumbnailUrl);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return null;
    }
    return thumbnailUrl;
  }

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

  List<String> get previewReviews {
    if (facility.isEmpty) {
      return <String>[
        '아직 시설 정보가 많지 않아요. 방문 전 예약처에서 최신 정보를 확인해보세요.',
        '거리와 기본 편의시설을 기준으로 먼저 비교해보세요.',
      ];
    }
    return <String>[
      '${tags.first} 조건을 중요하게 보는 캠퍼에게 맞는 곳이에요.',
      '시설 수와 위치 정보를 함께 확인하고 준비하면 좋아요.',
    ];
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
  });

  factory CampPost.fromJson(Map<String, dynamic> json) {
    return CampPost(
      id: _asInt(json['id']),
      campsiteId: _asInt(json['campsiteId']),
      title: _asString(json['title'], fallback: '제목 없음'),
      content: _asString(json['content']),
      createdAt: DateTime.tryParse(_asString(json['createdAt']))?.toLocal(),
    );
  }

  final int id;
  final int campsiteId;
  final String title;
  final String content;
  final DateTime? createdAt;

  String get createdAtLabel {
    final date = createdAt;
    if (date == null) {
      return '';
    }
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}.${two(date.month)}.${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
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
