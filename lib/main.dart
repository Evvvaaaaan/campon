import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeNativeSdks();
  runApp(const CampOnApp());
}

Future<void> _initializeNativeSdks() async {
  if (AuthConfig.kakaoNativeAppKey.isNotEmpty) {
    await KakaoSdk.init(nativeAppKey: AuthConfig.kakaoNativeAppKey);
  }
}

class AuthConfig {
  static const kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
    defaultValue: '0ecef49f91608f40010f59053f36fa9a',
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

class CampOnApp extends StatelessWidget {
  const CampOnApp({this.api, super.key});

  final CampOnApi? api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '캠프온',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: CampColors.canvas,
        textTheme: GoogleFonts.notoSansKrTextTheme(),
        colorScheme: ColorScheme.fromSeed(
          seedColor: CampColors.primary,
          brightness: Brightness.light,
          surface: CampColors.surface,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: CampColors.primary,
          selectionColor: Color(0x33C1702F),
          selectionHandleColor: CampColors.primary,
        ),
      ),
      home: CampOnShell(api: api),
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
}

enum DetailEntry { recommendations, browse }

class CampOnShell extends StatefulWidget {
  const CampOnShell({this.api, super.key});

  final CampOnApi? api;

  @override
  State<CampOnShell> createState() => _CampOnShellState();
}

class _CampOnShellState extends State<CampOnShell> {
  late final CampOnApi _api;

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

  Future<List<Campsite>>? _recommendationsFuture;
  Future<List<Campsite>>? _browseFuture;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? CampOnApi();
    _api.onSessionInvalidated = _returnToLogin;
    _restoreSession();
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
      _browseFuture ??= _api.fetchNearby(region: _region, page: 0, size: 20);
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
    setState(() => _step = AppStep.checklist);
  }

  void _goSettings() {
    setState(() => _step = AppStep.settings);
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
      setState(() => _step = AppStep.checklist);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
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
        return HomeScreen(onStart: _startOnboarding, onBrowse: _goBrowse);
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
        return CampsiteListScreen(
          title: '추천 캠핑장',
          subtitle: _date == null
              ? '${_region.name} 지역 캠핑장을 점수순으로 보여드려요.'
              : '${_formatKoreanDate(_date!)} · $_people명 · ${_region.name}',
          future: _recommendationsFuture,
          emptyText: '조건에 맞는 캠핑장을 찾지 못했어요.',
          onRetry: _loadRecommendations,
          onResetCondition: _startOnboarding,
          onSelect: (site) => _selectSite(site, DetailEntry.recommendations),
          entry: DetailEntry.recommendations,
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
        );
      case AppStep.checklist:
        return ChecklistScreen(
          selectedSite: _selectedSite,
          ownedEquipment: _equipment,
          checkedItems: _checkedItems,
          onToggle: (key) => _toggleSetValue(_checkedItems, key),
          onReset: _reset,
        );
      case AppStep.community:
        return CommunityScreen(
          api: _api,
          site: _selectedSite,
          onBack: _back,
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
        return CampsiteListScreen(
          title: '모든 캠핑장',
          subtitle: '${_region.name} 기준 가까운 캠핑장을 보여드려요.',
          future: _browseFuture,
          emptyText: '가까운 캠핑장을 찾지 못했어요.',
          onRetry: () {
            setState(() {
              _browseFuture = _api.fetchNearby(
                region: _region,
                page: 0,
                size: 20,
              );
            });
          },
          onResetCondition: null,
          onSelect: (site) => _selectSite(site, DetailEntry.browse),
          entry: DetailEntry.browse,
        );
    }
  }
}

enum AuthProvider {
  kakao('Kakao', '/api/v1/auth/oauth2/kakao'),
  google('Google', '/api/v1/auth/oauth2/google'),
  apple('Apple', '/api/v1/auth/oauth2/apple');

  const AuthProvider(this.label, this.path);

  final String label;
  final String path;

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
    if (error is KakaoException) {
      return '카카오 로그인에 실패했습니다. 잠시 후 다시 시도해주세요.';
    }
    return '로그인에 실패했습니다. 잠시 후 다시 시도해주세요.';
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
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF35543F), CampColors.forest],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.45, 1],
              colors: [Color(0x8C1E3A2B), Color(0xBF1E3A2B), CampColors.forest],
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 64,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: const _MountainRangePainter(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '캠핑을 시작할\n계정을 선택해주세요',
                        style: CampText.display.copyWith(
                          fontSize: 34,
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
                      Text(
                        '소셜 로그인',
                        style: CampText.captionStrong.copyWith(
                          color: CampColors.greenTint,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
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
    this.backgroundColor = CampColors.surface,
    this.foregroundColor = CampColors.ink,
    this.borderColor,
    super.key,
  }) : assert(icon != null || leading != null, 'icon or leading required');

  final String label;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
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
  const HomeScreen({required this.onStart, required this.onBrowse, super.key});

  final VoidCallback onStart;
  final VoidCallback onBrowse;

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
                color: CampColors.forest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                LucideIcons.tent,
                color: CampColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'CampOn',
              style: CampText.sectionTitle.copyWith(
                fontSize: 21,
                color: CampColors.forest,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 232,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [CampColors.forest, CampColors.forestMid],
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  right: 16,
                  child: Row(
                    children: List.generate(
                      4,
                      (index) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.circle,
                          size: index.isEven ? 4 : 3,
                          color: CampColors.amberTint.withValues(alpha: 0.7),
                        ),
                      ),
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
                        '조건에 맞는 캠핑장 추천부터 준비물 확인까지 한 흐름으로 이어집니다.',
                        style: CampText.caption.copyWith(
                          fontSize: 13,
                          color: CampColors.greenTint,
                        ),
                      ),
                      const SizedBox(height: 14),
                      CampButton(
                        label: '추천부터 준비까지 한 흐름',
                        icon: LucideIcons.shuffle,
                        onPressed: onStart,
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
                  const SettingsIcon(
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
                  const SettingsIcon(icon: LucideIcons.mountain, size: 40),
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
          Text('언제, 어디로\n떠나시나요?', style: CampText.displaySmall),
          const SizedBox(height: 6),
          Text(
            '기본 조건만 알려주시면 시작할 수 있어요.',
            style: CampText.body.copyWith(color: CampColors.inkMuted80),
          ),
          const SizedBox(height: 26),
          const FormLabel('캠핑 날짜', color: CampColors.primaryDark),
          DatePickerField(date: date, onChanged: onDateChanged),
          const SizedBox(height: 22),
          const FormLabel('지역 · 지도에서 핀을 찍어주세요', color: CampColors.primaryDark),
          RegionPicker(selected: region, onChanged: onRegionChanged),
          const SizedBox(height: 22),
          const FormLabel('인원 수', color: CampColors.primaryDark),
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
          const FormLabel('차량 보유 여부'),
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
          const FormLabel('캠핑 숙련도'),
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
          const FormLabel('보유 장비'),
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
          const FormLabel('가족 동반 여부'),
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
          const FormLabel('선호 조건'),
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
              return const LoadingPanel();
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
                for (final site in sites) ...[
                  CampsiteCard(
                    site: site,
                    showScore: entry == DetailEntry.recommendations,
                    onTap: () => onSelect(site),
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

class CampsiteDetailScreen extends StatelessWidget {
  const CampsiteDetailScreen({
    required this.api,
    required this.site,
    required this.region,
    required this.hasCar,
    required this.onBack,
    required this.onCommunity,
    required this.onPrepare,
    super.key,
  });

  final CampOnApi api;
  final Campsite? site;
  final CampRegion region;
  final bool hasCar;
  final VoidCallback onBack;
  final VoidCallback onCommunity;
  final VoidCallback onPrepare;

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
              BackCircleButton(onPressed: onBack),
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
              const FormLabel('시설 점수'),
              FacilityBars(site: campsite),
              const SizedBox(height: 22),
              FormLabel(hasCar ? '차량 이동' : '대중교통 · 도보 이동'),
              Text(
                campsite.accessDescription(hasCar: hasCar),
                style: CampText.body.copyWith(color: CampColors.inkMuted80),
              ),
              const SizedBox(height: 22),
              const FormLabel('길찾기'),
              DirectionsCard(api: api, origin: region, site: campsite),
              const SizedBox(height: 22),
              const FormLabel('날씨 리스크 · 준비 중'),
              Text(
                '현재 API 명세에는 날씨 정보가 없어 캠핑장 시설과 거리 기준으로 먼저 안내해요.',
                style: CampText.body.copyWith(color: CampColors.inkMuted80),
              ),
              const SizedBox(height: 22),
              const FormLabel('이용 후기'),
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
                  decoration: const BoxDecoration(
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

class DirectionsCard extends StatefulWidget {
  const DirectionsCard({
    required this.api,
    required this.origin,
    required this.site,
    super.key,
  });

  final CampOnApi api;
  final CampRegion origin;
  final Campsite site;

  @override
  State<DirectionsCard> createState() => _DirectionsCardState();
}

class _DirectionsCardState extends State<DirectionsCard> {
  Future<DirectionResult>? _future;

  void _load() {
    setState(() {
      _future = widget.api.fetchDirections(
        originX: widget.origin.lon,
        originY: widget.origin.lat,
        destX: widget.site.lon,
        destY: widget.site.lat,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    return CampCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.origin.name} 지역 기준 출발지에서 ${widget.site.name}까지 경로를 확인해요.',
            style: CampText.caption.copyWith(color: CampColors.inkMuted80),
          ),
          const SizedBox(height: 12),
          if (future == null)
            CampButton.secondary(
              label: '경로 확인',
              icon: Icons.directions_outlined,
              onPressed: _load,
            )
          else
            FutureBuilder<DirectionResult>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingPanel();
                }
                if (snapshot.hasError) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('경로를 불러오지 못했어요.', style: CampText.bodyStrong),
                      const SizedBox(height: 4),
                      Text(
                        '${snapshot.error}',
                        style: CampText.caption.copyWith(
                          color: CampColors.inkMuted80,
                        ),
                      ),
                      const SizedBox(height: 12),
                      CampButton.secondary(label: '다시 시도', onPressed: _load),
                    ],
                  );
                }
                final result = snapshot.data!;
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
              },
            ),
        ],
      ),
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
    required this.ownedEquipment,
    required this.checkedItems,
    required this.onToggle,
    required this.onReset,
    super.key,
  });

  final Campsite? selectedSite;
  final Set<String> ownedEquipment;
  final Set<String> checkedItems;
  final ValueChanged<String> onToggle;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final checklistItems = [
      ...CampData.equipmentOptions,
      ...CampData.fixedChecklist,
    ];
    final doneCount = checklistItems
        .where(
          (item) =>
              ownedEquipment.contains(item.apiValue) ||
              checkedItems.contains(item.apiValue),
        )
        .length;
    final missingGear = CampData.equipmentOptions
        .where((item) => !ownedEquipment.contains(item.apiValue))
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
                  valueColor: const AlwaysStoppedAnimation(CampColors.primary),
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
        if (missingGear.isNotEmpty) ...[
          const SizedBox(height: 22),
          const FormLabel('부족한 장비', color: CampColors.primaryDark),
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
        const FormLabel('체크리스트', color: CampColors.forestMid),
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
                        ownedEquipment.contains(
                          checklistItems[index].apiValue,
                        ) ||
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
              return const LoadingPanel();
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
          const FormLabel('새 글'),
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
                icon: const Icon(
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
              const SettingsRow(
                icon: LucideIcons.shieldCheck,
                title: '로그인 상태',
                value: '활성',
                badge: true,
                valueColor: CampColors.forestMid,
              ),
              const SizedBox(height: 16),
              CampButton.secondary(label: '로그아웃', onPressed: onSignOut),
              const SizedBox(height: 10),
              DeleteAccountButton(onDelete: onDeleteAccount),
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
              CampButton.secondary(
                label: '조건 초기화',
                onPressed: onResetPreferences,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CampCard(
          child: Row(
            children: [
              const Icon(
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
            children: const [
              SettingsRow(
                icon: Icons.dns_outlined,
                title: 'API 서버',
                value: CampOnApi.publicHost,
              ),
              SizedBox(height: 14),
              SettingsRow(
                icon: Icons.info_outline_rounded,
                title: '앱 버전',
                value: '1.0.0',
              ),
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
    this.valueColor = CampColors.inkMuted80,
    super.key,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool badge;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
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

class SettingsIcon extends StatelessWidget {
  const SettingsIcon({
    required this.icon,
    this.background = CampColors.greenTint,
    this.iconColor = CampColors.forestMid,
    this.size = 36,
    super.key,
  });

  final IconData icon;
  final Color background;
  final Color iconColor;
  final double size;

  @override
  Widget build(BuildContext context) {
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
            const Icon(
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
        gradient: const LinearGradient(
          begin: Alignment(-1, -1),
          end: Alignment(1, 1),
          colors: [CampColors.greenTint, CampColors.amberTint],
        ),
      ),
      child: Stack(
        children: [
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
          side: const BorderSide(color: CampColors.outline, width: 1.5),
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
                    ? const CampImagePlaceholder()
                    : Image.network(
                        site.validThumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const CampImagePlaceholder(),
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
            ? const CampImagePlaceholder()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const CampImagePlaceholder(),
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
              valueColor: const AlwaysStoppedAnimation(CampColors.primary),
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
                ? const BorderSide(color: CampColors.hairline)
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
                  ? const Icon(
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
      decoration: const BoxDecoration(
        color: CampColors.canvas,
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
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: CampColors.primary,
          ),
        ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: CampText.bodyStrong),
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
                borderRadius: BorderRadius.circular(2),
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
          side: const BorderSide(color: CampColors.hairline),
        ),
      ),
    );
  }
}

class CampCard extends StatelessWidget {
  const CampCard({
    required this.child,
    this.backgroundColor = CampColors.surface,
    this.padding = const EdgeInsets.all(22),
    super.key,
  });

  final Widget child;
  final Color backgroundColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: CampColors.hairline),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
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
  const FormLabel(this.text, {this.color = CampColors.inkMuted48, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: CampText.captionStrong.copyWith(
          color: color,
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
      decoration: const BoxDecoration(
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
    required String code,
    required String name,
  }) async {
    await _setSessionFrom(
      _requestJwt(
        _buildUri(provider.path, <String, String>{}),
        method: 'POST',
        body: <String, String>{'code': code, 'name': name},
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
      code: code,
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
      code: credential.authorizationCode,
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

    final token = await UserApi.instance.loginWithKakao(context);

    await signInWithOAuth(
      provider: AuthProvider.kakao,
      code: token.accessToken,
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
        'radius': '70000',
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

  Future<List<Campsite>> _fetchCampsites(Uri uri) async {
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
      final items = decoded['items'];
      if (items is! List) {
        return <Campsite>[];
      }
      return items
          .whereType<Map<String, dynamic>>()
          .map(Campsite.fromJson)
          .toList();
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

class CampColors {
  static const primary = Color(0xFFC1702F); // Wood Amber
  static const primaryDark = Color(0xFF9C5620); // Amber Dark
  static const forest = Color(0xFF1E3A2B); // Deep Forest Green
  static const forestMid = Color(0xFF2C4A38); // Mid Green
  static const onPrimary = Color(0xFFFBF8F0);
  static const canvas = Color(0xFFF5EFE1); // Cream background
  static const surface = Color(0xFFFBF8F0); // Card surface
  static const amberTint = Color(0xFFF0D9BE); // Accent-tinted card/chip bg
  static const greenTint = Color(0xFFDCE6DA); // Neutral chip/icon badge bg
  static const ink = Color(0xFF2A2318);
  static const inkMuted80 = Color(0xFF8A8168); // Muted text
  static const inkMuted48 = Color(0xFFB5A98A); // Faint text / inactive nav
  static const hairline = Color(0xFFE4DCC8); // Border/line
  static const outline = Color(0xFFC9BB98); // Disabled/unchecked outline
  static const shadow = Color(0x141E3A2B);
}

class CampText {
  static final TextStyle display = GoogleFonts.blackHanSans(
    fontSize: 28,
    height: 1.2,
    color: CampColors.ink,
  );

  static final TextStyle displaySmall = GoogleFonts.blackHanSans(
    fontSize: 27,
    height: 1.25,
    color: CampColors.ink,
  );

  static final TextStyle tagline = GoogleFonts.blackHanSans(
    fontSize: 19,
    height: 1.2,
    color: CampColors.ink,
  );

  static final TextStyle body = GoogleFonts.notoSansKr(
    fontSize: 14.5,
    height: 1.55,
    fontWeight: FontWeight.w400,
    color: CampColors.ink,
  );

  static final TextStyle bodyStrong = GoogleFonts.notoSansKr(
    fontSize: 14.5,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: CampColors.ink,
  );

  static final TextStyle sectionTitle = GoogleFonts.blackHanSans(
    fontSize: 17,
    height: 1.25,
    color: CampColors.ink,
  );

  static final TextStyle caption = GoogleFonts.notoSansKr(
    fontSize: 13.5,
    height: 1.55,
    fontWeight: FontWeight.w400,
    color: CampColors.ink,
  );

  static final TextStyle captionStrong = GoogleFonts.notoSansKr(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: CampColors.ink,
  );

  static final TextStyle button = GoogleFonts.notoSansKr(
    fontSize: 14.5,
    height: 1.27,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
  );

  static final TextStyle finePrint = GoogleFonts.notoSansKr(
    fontSize: 12,
    height: 1,
    fontWeight: FontWeight.w400,
  );
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
