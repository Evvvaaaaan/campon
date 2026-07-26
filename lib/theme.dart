import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
