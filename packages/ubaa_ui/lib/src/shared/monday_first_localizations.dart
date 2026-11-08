import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

/// 中文 Material 本地化，但一周从周一开始。
///
/// Flutter 的中文日期选择器默认周日在前；课表、日程和月历都以周一开头，
/// 这里只改 [firstDayOfWeekIndex]，其余文案沿用官方中文翻译。
class UiMondayFirstLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const UiMondayFirstLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'zh';

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    const name = 'zh';
    // 官方委托返回 SynchronousFuture；用 then 串接保持同步，首帧不会空白。
    // 先由它完成中文日期数据的初始化，再构造周一开头的本地化。
    return GlobalMaterialLocalizations.delegate
        .load(locale)
        .then<MaterialLocalizations>(
          (_) => _MondayFirstZh(
            fullYearFormat: intl.DateFormat.y(name),
            compactDateFormat: intl.DateFormat.yMd(name),
            shortDateFormat: intl.DateFormat.yMMMd(name),
            mediumDateFormat: intl.DateFormat.MMMEd(name),
            longDateFormat: intl.DateFormat.yMMMMEEEEd(name),
            yearMonthFormat: intl.DateFormat.yMMMM(name),
            shortMonthDayFormat: intl.DateFormat.MMMd(name),
            decimalFormat: intl.NumberFormat.decimalPattern(name),
            twoDigitZeroPaddedFormat: intl.NumberFormat('00', name),
          ),
        );
  }

  @override
  bool shouldReload(UiMondayFirstLocalizationsDelegate old) => false;
}

class _MondayFirstZh extends MaterialLocalizationZh {
  const _MondayFirstZh({
    required super.fullYearFormat,
    required super.compactDateFormat,
    required super.shortDateFormat,
    required super.mediumDateFormat,
    required super.longDateFormat,
    required super.yearMonthFormat,
    required super.shortMonthDayFormat,
    required super.decimalFormat,
    required super.twoDigitZeroPaddedFormat,
  });

  @override
  int get firstDayOfWeekIndex => 1;
}
