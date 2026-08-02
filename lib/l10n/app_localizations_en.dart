// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Mind Bubble';

  @override
  String get manageBubbles => 'Manage bubbles';

  @override
  String get todaySubtitle => 'Let a few ideas resurface today.';

  @override
  String get settings => 'Settings';

  @override
  String get launchAtStartup => 'Launch at login';

  @override
  String get newBubble => 'New concept';

  @override
  String get editBubble => 'Edit concept';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get frequency => 'Appearance frequency';

  @override
  String get frequency1 => 'Very rare';

  @override
  String get frequency2 => 'Rare';

  @override
  String get frequency3 => 'Balanced';

  @override
  String get frequency4 => 'Often';

  @override
  String get frequency5 => 'Frequent';
}
