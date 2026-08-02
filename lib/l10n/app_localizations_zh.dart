// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '浮念';

  @override
  String get manageBubbles => '管理泡泡';

  @override
  String get todaySubtitle => '今天，让几颗想法重新浮现。';

  @override
  String get settings => '设置';

  @override
  String get launchAtStartup => '登录后自动运行';

  @override
  String get newBubble => '新建概念';

  @override
  String get editBubble => '编辑概念';

  @override
  String get delete => '删除';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get frequency => '出现频率';

  @override
  String get frequency1 => '很少';

  @override
  String get frequency2 => '较少';

  @override
  String get frequency3 => '适中';

  @override
  String get frequency4 => '较多';

  @override
  String get frequency5 => '频繁';
}
