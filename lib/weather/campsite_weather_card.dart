/// 캠핑장 상세의 날씨 섹션.
///
/// 화면을 열면 그 캠핑장 좌표의 실제 날씨를 한 번 받아온다. 가벼운 GET 한 번이고,
/// 실패해도 다시 시도 버튼만 남을 뿐 상세 화면의 나머지는 그대로 뜬다.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme.dart';
import 'weather_service.dart';

IconData weatherIcon(WeatherCondition condition) => switch (condition) {
  WeatherCondition.clear => LucideIcons.sun,
  WeatherCondition.partlyCloudy => LucideIcons.cloudSun,
  WeatherCondition.cloudy => LucideIcons.cloudy,
  WeatherCondition.fog => LucideIcons.cloudFog,
  WeatherCondition.drizzle => LucideIcons.cloudDrizzle,
  WeatherCondition.rain => LucideIcons.cloudRain,
  WeatherCondition.snow => LucideIcons.cloudSnow,
  WeatherCondition.thunder => LucideIcons.cloudLightning,
};

class CampsiteWeatherCard extends StatefulWidget {
  const CampsiteWeatherCard({
    required this.lat,
    required this.lon,
    this.service,
    super.key,
  });

  final double lat;
  final double lon;
  final WeatherService? service;

  @override
  State<CampsiteWeatherCard> createState() => _CampsiteWeatherCardState();
}

class _CampsiteWeatherCardState extends State<CampsiteWeatherCard> {
  late final WeatherService _service = widget.service ?? WeatherService();

  bool _loading = true;
  CampsiteWeather? _weather;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final weather = await _service.load(lat: widget.lat, lon: widget.lon);
    if (!mounted) return;
    setState(() {
      _weather = weather;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _WeatherShell(
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              '날씨를 불러오는 중이에요.',
              style: CampText.caption.copyWith(color: CampColors.inkMuted80),
            ),
          ],
        ),
      );
    }

    final weather = _weather;
    if (weather == null) {
      return _WeatherShell(
        child: Row(
          children: [
            Expanded(
              child: Text(
                '지금은 날씨를 불러오지 못했어요.',
                style: CampText.caption.copyWith(color: CampColors.inkMuted80),
              ),
            ),
            TextButton(
              onPressed: _load,
              style: TextButton.styleFrom(
                foregroundColor: CampColors.primaryDark,
                padding: EdgeInsets.zero,
                textStyle: CampText.captionStrong,
              ),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    return _WeatherShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CurrentRow(weather: weather),
          if (weather.days.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: CampColors.hairline),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final day in weather.days)
                  Expanded(child: _DayColumn(day: day)),
              ],
            ),
          ],
          if (weather.caution != null) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.umbrella,
                  size: 15,
                  color: CampColors.primaryDark,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    weather.caution!,
                    style: CampText.caption.copyWith(
                      color: CampColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Open-Meteo 제공 · 방문 전 최신 예보를 다시 확인해주세요.',
            style: CampText.finePrint.copyWith(color: CampColors.inkMuted48),
          ),
        ],
      ),
    );
  }
}

/// 세 가지 상태(로딩·실패·성공)가 같은 테두리 안에서 바뀌도록 감싸는 껍데기.
class _WeatherShell extends StatelessWidget {
  const _WeatherShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CampColors.surface,
        border: Border.all(color: CampColors.hairline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _CurrentRow extends StatelessWidget {
  const _CurrentRow({required this.weather});

  final CampsiteWeather weather;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          weatherIcon(weather.condition),
          size: 40,
          color: CampColors.forestMid,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${weather.temperatureC}°',
                style: CampText.displaySmall.copyWith(fontSize: 30),
              ),
              const SizedBox(height: 2),
              Text(
                '${weather.condition.label} · 체감 ${weather.feelsLikeC}°',
                style: CampText.caption.copyWith(color: CampColors.inkMuted80),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _MetricRow(
              icon: LucideIcons.wind,
              label: '${weather.windMs.toStringAsFixed(1)}m/s',
            ),
            const SizedBox(height: 6),
            _MetricRow(
              icon: LucideIcons.droplets,
              label: '${weather.humidityPct}%',
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: CampColors.inkMuted48),
        const SizedBox(width: 5),
        Text(
          label,
          style: CampText.caption.copyWith(color: CampColors.inkMuted80),
        ),
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({required this.day});

  final DailyWeather day;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          dayLabel(day.date),
          style: CampText.finePrint.copyWith(color: CampColors.inkMuted48),
        ),
        const SizedBox(height: 6),
        Icon(weatherIcon(day.condition), size: 20, color: CampColors.forestMid),
        const SizedBox(height: 6),
        Text('${day.highC}° / ${day.lowC}°', style: CampText.captionStrong),
        const SizedBox(height: 3),
        Text(
          '비 ${day.precipPct}%',
          style: CampText.finePrint.copyWith(color: CampColors.inkMuted48),
        ),
      ],
    );
  }
}

/// 오늘부터 이틀 뒤까지는 말로, 그 밖은 날짜로 적는다.
String dayLabel(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final days = DateTime(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime(today.year, today.month, today.day)).inDays;
  return switch (days) {
    0 => '오늘',
    1 => '내일',
    2 => '모레',
    _ => '${date.month}/${date.day}',
  };
}
