// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Swamy Sharanam';

  @override
  String get iAmPresent => 'I am Present';

  @override
  String get countOpen => 'Count open — mark Present';

  @override
  String get readyToMarch => 'Ready to march';

  @override
  String get lostHelp => 'If you are lost';

  @override
  String get downloadTripPack => 'Download trip pack';

  @override
  String get offlinePending => 'No network — marked locally, will sync';
}
