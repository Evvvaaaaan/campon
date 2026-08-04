import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 한 벌의 색 토큰. 라이트/다크(야간 캠핑 테마)가 같은 이름을 공유하고
/// 값만 갈아끼우므로, 화면 코드는 밝기를 신경 쓰지 않고 토큰 이름만 쓴다.
class CampPalette {
  const CampPalette({
    required this.primary,
    required this.primaryDark,
    required this.forest,
    required this.forestMid,
    required this.onPrimary,
    required this.canvas,
    required this.surface,
    required this.amberTint,
    required this.greenTint,
    required this.ink,
    required this.inkMuted80,
    required this.inkMuted48,
    required this.hairline,
    required this.outline,
    required this.shadow,
  });

  final Color primary; // Wood Amber / 강조 버튼
  final Color primaryDark; // Amber Dark / 강조 텍스트
  final Color forest; // Deep Forest Green / 주 버튼
  final Color forestMid; // Mid Green / 칩 텍스트·활성 탭
  final Color onPrimary; // 색 버튼 위 텍스트
  final Color canvas; // 페이지 배경
  final Color surface; // 카드 표면
  final Color amberTint; // 앰버 톤 칩/뱃지 배경
  final Color greenTint; // 그린 톤 칩/뱃지 배경
  final Color ink; // 제목 텍스트
  final Color inkMuted80; // 본문 텍스트
  final Color inkMuted48; // 흐린 텍스트 / 비활성 탭
  final Color hairline; // 경계선
  final Color outline; // 미선택 체크박스 / 토글 트랙
  final Color shadow;

  static const light = CampPalette(
    primary: Color(0xFFC1702F),
    primaryDark: Color(0xFF9C5620),
    forest: Color(0xFF1E3A2B),
    forestMid: Color(0xFF2C4A38),
    onPrimary: Color(0xFFFBF8F0),
    canvas: Color(0xFFF5EFE1),
    surface: Color(0xFFFBF8F0),
    amberTint: Color(0xFFF0D9BE),
    greenTint: Color(0xFFDCE6DA),
    ink: Color(0xFF2A2318),
    inkMuted80: Color(0xFF8A8168),
    inkMuted48: Color(0xFFB5A98A),
    hairline: Color(0xFFE4DCC8),
    outline: Color(0xFFC9BB98),
    shadow: Color(0x141E3A2B),
  );

  /// 야간 캠핑 테마. 값은 디자인의 다크 토큰 세트를 그대로 옮긴 것이다.
  static const dark = CampPalette(
    primary: Color(0xFFE8944A),
    primaryDark: Color(0xFFE8944A),
    forest: Color(0xFF2FA36B),
    forestMid: Color(0xFF8FD9AE),
    onPrimary: Color(0xFFFBF8F0),
    canvas: Color(0xFF0E1F17),
    surface: Color(0xFF16281E),
    amberTint: Color(0xFF3A2A18),
    greenTint: Color(0xFF1F3A2A),
    ink: Color(0xFFF5EFE1),
    inkMuted80: Color(0xFF9FB0A2),
    inkMuted48: Color(0xFF4A5F52),
    hairline: Color(0xFF28402F),
    outline: Color(0xFF3A4F42),
    shadow: Color(0x3D000000),
  );
}

/// 앱 전역에서 활성화된 팔레트를 읽는 창구.
///
/// 토글은 [CampThemeScope]가 하고, 여기 담긴 값은 그 결과를 반영할 뿐이다.
/// 화면 코드가 `CampColors.canvas`처럼 이름만 쓰도록 두려고 정적 게터로 노출한다.
class CampColors {
  static CampPalette _active = CampPalette.light;

  static CampPalette get palette => _active;
  static bool get isDark => identical(_active, CampPalette.dark);

  /// 팔레트를 갈아끼운다. 트리 리빌드는 호출한 쪽이 책임진다.
  static void apply(CampPalette palette) => _active = palette;

  static Color get primary => _active.primary;
  static Color get primaryDark => _active.primaryDark;
  static Color get forest => _active.forest;
  static Color get forestMid => _active.forestMid;
  static Color get onPrimary => _active.onPrimary;
  static Color get canvas => _active.canvas;
  static Color get surface => _active.surface;
  static Color get amberTint => _active.amberTint;
  static Color get greenTint => _active.greenTint;
  static Color get ink => _active.ink;
  static Color get inkMuted80 => _active.inkMuted80;
  static Color get inkMuted48 => _active.inkMuted48;
  static Color get hairline => _active.hairline;
  static Color get outline => _active.outline;
  static Color get shadow => _active.shadow;
}

/// 한 팔레트에 대한 텍스트 스타일 묶음.
/// 밝기마다 한 번씩만 만들어 두고 [CampText]가 골라 쓴다.
class CampTextSet {
  CampTextSet(Color ink)
    : display = GoogleFonts.blackHanSans(fontSize: 28, height: 1.2, color: ink),
      displaySmall = GoogleFonts.blackHanSans(
        fontSize: 27,
        height: 1.25,
        color: ink,
      ),
      tagline = GoogleFonts.blackHanSans(
        fontSize: 19,
        height: 1.2,
        color: ink,
      ),
      body = GoogleFonts.notoSansKr(
        fontSize: 14.5,
        height: 1.55,
        fontWeight: FontWeight.w400,
        color: ink,
      ),
      bodyStrong = GoogleFonts.notoSansKr(
        fontSize: 14.5,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      sectionTitle = GoogleFonts.blackHanSans(
        fontSize: 17,
        height: 1.25,
        color: ink,
      ),
      caption = GoogleFonts.notoSansKr(
        fontSize: 13.5,
        height: 1.55,
        fontWeight: FontWeight.w400,
        color: ink,
      ),
      captionStrong = GoogleFonts.notoSansKr(
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: ink,
      );

  final TextStyle display;
  final TextStyle displaySmall;
  final TextStyle tagline;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle sectionTitle;
  final TextStyle caption;
  final TextStyle captionStrong;
}

class CampText {
  static final CampTextSet _light = CampTextSet(CampPalette.light.ink);
  static final CampTextSet _dark = CampTextSet(CampPalette.dark.ink);

  static CampTextSet get _set => CampColors.isDark ? _dark : _light;

  static TextStyle get display => _set.display;
  static TextStyle get displaySmall => _set.displaySmall;
  static TextStyle get tagline => _set.tagline;
  static TextStyle get body => _set.body;
  static TextStyle get bodyStrong => _set.bodyStrong;
  static TextStyle get sectionTitle => _set.sectionTitle;
  static TextStyle get caption => _set.caption;
  static TextStyle get captionStrong => _set.captionStrong;

  // 색을 싣지 않는 스타일은 밝기와 무관하므로 한 번만 만든다.
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

  /// 디자인의 손글씨 액센트(Gaegu). 문구를 살짝 기울여 쓰는 자리에만 쓴다.
  static TextStyle handwritten({required Color color, double fontSize = 19}) =>
      GoogleFonts.gaegu(
        fontSize: fontSize,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: color,
      );
}
