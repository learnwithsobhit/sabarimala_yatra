// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'स्वामी शरणम्';

  @override
  String get iAmPresent => 'मैं उपस्थित हूँ';

  @override
  String get countOpen => 'गणना खुली — उपस्थित चिह्नित करें';

  @override
  String get readyToMarch => 'चलने के लिए तैयार';

  @override
  String get lostHelp => 'यदि आप खो गए हैं';

  @override
  String get downloadTripPack => 'यात्रा पैक डाउनलोड करें';

  @override
  String get offlinePending =>
      'नेटवर्क नहीं — स्थानीय रूप से चिह्नित, बाद में सिंक होगा';
}
