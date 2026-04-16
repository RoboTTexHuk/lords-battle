import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as lordsbattleMath;
import 'dart:ui';

import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as lordsbattleTimezoneData;
import 'package:timezone/timezone.dart' as lordsbattleTimezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Если эти классы есть в main.dart – оставь импорт.
import 'main.dart' show MafiaHarbor, CaptainHarbor, BillHarbor;

// ============================================================================
// NCUP инфраструктура (бывшая Dress Retro инфраструктура)
// ============================================================================

class LordsbattleLogger {
  const LordsbattleLogger();

  void lordsbattleLogInfo(Object lordsbattleMessage) =>
      debugPrint('[DressRetroLogger] $lordsbattleMessage');

  void lordsbattleLogWarn(Object lordsbattleMessage) =>
      debugPrint('[DressRetroLogger/WARN] $lordsbattleMessage');

  void lordsbattleLogError(Object lordsbattleMessage) =>
      debugPrint('[DressRetroLogger/ERR] $lordsbattleMessage');
}

class LordsbattleVault {
  static final LordsbattleVault lordsbattleSharedInstance =
  LordsbattleVault._lordsbattleInternalConstructor();
  LordsbattleVault._lordsbattleInternalConstructor();
  factory LordsbattleVault() => lordsbattleSharedInstance;

  final LordsbattleLogger lordsbattleLoggerInstance =
  const LordsbattleLogger();
}

// ============================================================================
// Константы (статистика/кеш) — строки в кавычках не меняем
// ============================================================================

const String lordsbattleMetrLoadedOnceKey = 'wheel_loaded_once';
const String lordsbattleMetrStatEndpoint =
    'https://getgame.portalroullete.bar/stat';
const String lordsbattleMetrCachedFcmKey = 'wheel_cached_fcm';

// ============================================================================
// Утилиты: LordsbattleKit (бывший NcupKit / DressRetroKit)
// ============================================================================

class LordsbattleKit {
  static bool lordsbattleLooksLikeBareMail(Uri lordsbattleUri) {
    final String lordsbattleScheme = lordsbattleUri.scheme;
    if (lordsbattleScheme.isNotEmpty) return false;
    final String lordsbattleRaw = lordsbattleUri.toString();
    return lordsbattleRaw.contains('@') && !lordsbattleRaw.contains(' ');
  }

  static Uri lordsbattleToMailto(Uri lordsbattleUri) {
    final String lordsbattleFull = lordsbattleUri.toString();
    final List<String> lordsbattleBits = lordsbattleFull.split('?');
    final String lordsbattleWho = lordsbattleBits.first;
    final Map<String, String> lordsbattleQuery = lordsbattleBits.length > 1
        ? Uri.splitQueryString(lordsbattleBits[1])
        : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: lordsbattleWho,
      queryParameters:
      lordsbattleQuery.isEmpty ? null : lordsbattleQuery,
    );
  }

  static Uri lordsbattleGmailize(Uri lordsbattleMailUri) {
    final Map<String, String> lordsbattleQp =
        lordsbattleMailUri.queryParameters;
    final Map<String, String> lordsbattleParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (lordsbattleMailUri.path.isNotEmpty) 'to': lordsbattleMailUri.path,
      if ((lordsbattleQp['subject'] ?? '').isNotEmpty)
        'su': lordsbattleQp['subject']!,
      if ((lordsbattleQp['body'] ?? '').isNotEmpty)
        'body': lordsbattleQp['body']!,
      if ((lordsbattleQp['cc'] ?? '').isNotEmpty)
        'cc': lordsbattleQp['cc']!,
      if ((lordsbattleQp['bcc'] ?? '').isNotEmpty)
        'bcc': lordsbattleQp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', lordsbattleParams);
  }

  static String lordsbattleDigitsOnly(String lordsbattleSource) =>
      lordsbattleSource.replaceAll(RegExp(r'[^0-9+]'), '');
}

// ============================================================================
// Сервис открытия ссылок: LordsbattleLinker (бывший NcupLinker / DressRetroLinker)
// ============================================================================

class LordsbattleLinker {
  static Future<bool> lordsbattleOpen(Uri lordsbattleUri) async {
    try {
      if (await launchUrl(
        lordsbattleUri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }
      return await launchUrl(
        lordsbattleUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (lordsbattleError) {
      debugPrint('DressRetroLinker error: $lordsbattleError; url=$lordsbattleUri');
      try {
        return await launchUrl(
          lordsbattleUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// FCM Background Handler
// ============================================================================

@pragma('vm:entry-point')
Future<void> lordsbattleFcmBackgroundHandler(
    RemoteMessage lordsbattleMessage) async {
  debugPrint("Spin ID: ${lordsbattleMessage.messageId}");
  debugPrint("Spin Data: ${lordsbattleMessage.data}");
}

// ============================================================================
// LordsbattleDeviceProfile (бывший NcupDeviceProfile / DressRetroDeviceProfile)
// ============================================================================

class LordsbattleDeviceProfile {
  String? lordsbattleDeviceId;
  String? lordsbattleSessionId = 'wheel-one-off';
  String? lordsbattlePlatformKind;
  String? lordsbattleOsBuild;
  String? lordsbattleAppVersion;
  String? lordsbattleLocaleCode;
  String? lordsbattleTimezoneName;
  bool lordsbattlePushEnabled = true;

  Future<void> lordsbattleInitialize() async {
    final DeviceInfoPlugin lordsbattleInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo lordsbattleAndroidInfo =
      await lordsbattleInfoPlugin.androidInfo;
      lordsbattleDeviceId = lordsbattleAndroidInfo.id;
      lordsbattlePlatformKind = 'android';
      lordsbattleOsBuild = lordsbattleAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo lordsbattleIosInfo =
      await lordsbattleInfoPlugin.iosInfo;
      lordsbattleDeviceId = lordsbattleIosInfo.identifierForVendor;
      lordsbattlePlatformKind = 'ios';
      lordsbattleOsBuild = lordsbattleIosInfo.systemVersion;
    }

    final PackageInfo lordsbattlePackageInfo =
    await PackageInfo.fromPlatform();
    lordsbattleAppVersion = lordsbattlePackageInfo.version;
    lordsbattleLocaleCode = Platform.localeName.split('_').first;
    lordsbattleTimezoneName = lordsbattleTimezone.local.name;
    lordsbattleSessionId =
    'wheel-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> lordsbattleAsMap({String? lordsbattleFcmToken}) =>
      <String, dynamic>{
        'fcm_token': lordsbattleFcmToken ?? 'missing_token',
        'device_id': lordsbattleDeviceId ?? 'missing_id',
        'app_name': 'joiler',
        'instance_id': lordsbattleSessionId ?? 'missing_session',
        'platform': lordsbattlePlatformKind ?? 'missing_system',
        'os_version': lordsbattleOsBuild ?? 'missing_build',
        'app_version': lordsbattleAppVersion ?? 'missing_app',
        'language': lordsbattleLocaleCode ?? 'en',
        'timezone': lordsbattleTimezoneName ?? 'UTC',
        'push_enabled': lordsbattlePushEnabled,
        "fthcashier": "true"
      };
}

// ============================================================================
// (AppsFlyer шпион мог бы быть здесь — опущен, как и в исходном коде)
// ============================================================================

// ============================================================================
// Мост для FCM токена: LordsbattleFcmBridge (бывший NcupFcmBridge / DressRetroFcmBridge)
// ============================================================================

class LordsbattleFcmBridge {
  final LordsbattleLogger lordsbattleLog = const LordsbattleLogger();
  String? lordsbattleToken;
  final List<void Function(String)> lordsbattleWaiters =
  <void Function(String)>[];

  String? get lordsbattleCurrentToken => lordsbattleToken;

  LordsbattleFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall lordsbattleCall) async {
      if (lordsbattleCall.method == 'setToken') {
        final String lordsbattleTokenString =
        lordsbattleCall.arguments as String;
        if (lordsbattleTokenString.isNotEmpty) {
          lordsbattleSetToken(lordsbattleTokenString);
        }
      }
    });

    lordsbattleRestoreToken();
  }

  Future<void> lordsbattleRestoreToken() async {
    try {
      final SharedPreferences lordsbattlePrefs =
      await SharedPreferences.getInstance();
      final String? lordsbattleCached =
      lordsbattlePrefs.getString(lordsbattleMetrCachedFcmKey);
      if (lordsbattleCached != null && lordsbattleCached.isNotEmpty) {
        lordsbattleSetToken(lordsbattleCached, lordsbattleNotify: false);
      }
    } catch (_) {}
  }

  Future<void> lordsbattlePersistToken(String lordsbattleNewToken) async {
    try {
      final SharedPreferences lordsbattlePrefs =
      await SharedPreferences.getInstance();
      await lordsbattlePrefs.setString(
          lordsbattleMetrCachedFcmKey, lordsbattleNewToken);
    } catch (_) {}
  }

  void lordsbattleSetToken(
      String lordsbattleNewToken, {
        bool lordsbattleNotify = true,
      }) {
    lordsbattleToken = lordsbattleNewToken;
    lordsbattlePersistToken(lordsbattleNewToken);
    if (lordsbattleNotify) {
      for (final void Function(String) lordsbattleCallback
      in List<void Function(String)>.from(lordsbattleWaiters)) {
        try {
          lordsbattleCallback(lordsbattleNewToken);
        } catch (lordsbattleErr) {
          lordsbattleLog.lordsbattleLogWarn(
              'fcm waiter error: $lordsbattleErr');
        }
      }
      lordsbattleWaiters.clear();
    }
  }

  Future<void> lordsbattleWaitForToken(
      Function(String lordsbattleTokenValue) lordsbattleOnToken,
      ) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((lordsbattleToken ?? '').isNotEmpty) {
        lordsbattleOnToken(lordsbattleToken!);
        return;
      }

      lordsbattleWaiters.add(lordsbattleOnToken);
    } catch (lordsbattleErr) {
      lordsbattleLog.lordsbattleLogError(
          'wheelWaitToken error: $lordsbattleErr');
    }
  }
}

// ============================================================================
// Лоадер с двумя оранжевыми мечами (контуры), сталкивающимися в центре
// ============================================================================

class LordsbattleSwordsLoader extends StatefulWidget {
  const LordsbattleSwordsLoader({Key? key}) : super(key: key);

  @override
  State<LordsbattleSwordsLoader> createState() =>
      _LordsbattleSwordsLoaderState();
}

class _LordsbattleSwordsLoaderState extends State<LordsbattleSwordsLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController lordsbattleController;
  late Animation<double> lordsbattleAngleAnimation;

  static const Color lordsbattleBackgroundColor = Color(0xFF05071B);

  @override
  void initState() {
    super.initState();

    lordsbattleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    lordsbattleAngleAnimation =
        Tween<double>(begin: -0.35, end: 0.35).animate(
          CurvedAnimation(
            parent: lordsbattleController,
            curve: Curves.easeInOut,
          ),
        );
  }

  @override
  void dispose() {
    lordsbattleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: lordsbattleBackgroundColor,
      child: Center(
        child: SizedBox(
          width: 140,
          height: 140,
          child: AnimatedBuilder(
            animation: lordsbattleAngleAnimation,
            builder: (BuildContext context, Widget? child) {
              return CustomPaint(
                painter: _LordsbattleSwordsPainter(
                  lordsbattleAngle: lordsbattleAngleAnimation.value,
                  lordsbattleColor: const Color(0xFFFF9800),
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LordsbattleSwordsPainter extends CustomPainter {
  final double lordsbattleAngle;
  final Color lordsbattleColor;

  _LordsbattleSwordsPainter({
    required this.lordsbattleAngle,
    required this.lordsbattleColor,
  });

  @override
  void paint(Canvas lordsbattleCanvas, Size lordsbattleSize) {
    final Offset lordsbattleCenter =
    Offset(lordsbattleSize.width / 2, lordsbattleSize.height / 2);

    final Paint lordsbattlePaint = Paint()
      ..color = lordsbattleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final double lordsbattleSwordLen = lordsbattleSize.height * 0.42;
    final double lordsbattleHandleLen = lordsbattleSize.height * 0.14;

    void lordsbattleDrawSword(double lordsbattleBaseAngle) {
      final double lordsbattleRad = lordsbattleBaseAngle;

      final Offset lordsbattleTip = Offset(
        lordsbattleCenter.dx +
            lordsbattleSwordLen * -lordsbattleMath.sin(lordsbattleRad),
        lordsbattleCenter.dy +
            lordsbattleSwordLen * -lordsbattleMath.cos(lordsbattleRad),
      );

      final Offset lordsbattleHandleEnd = Offset(
        lordsbattleCenter.dx +
            (lordsbattleSwordLen - lordsbattleHandleLen) *
                -lordsbattleMath.sin(lordsbattleRad),
        lordsbattleCenter.dy +
            (lordsbattleSwordLen - lordsbattleHandleLen) *
                -lordsbattleMath.cos(lordsbattleRad),
      );

      final Path lordsbattleBladePath = Path()
        ..moveTo(lordsbattleCenter.dx, lordsbattleCenter.dy)
        ..lineTo(lordsbattleTip.dx, lordsbattleTip.dy);
      lordsbattleCanvas.drawPath(lordsbattleBladePath, lordsbattlePaint);

      final Path lordsbattleHandlePath = Path()
        ..moveTo(lordsbattleCenter.dx, lordsbattleCenter.dy)
        ..lineTo(lordsbattleHandleEnd.dx, lordsbattleHandleEnd.dy);
      lordsbattleCanvas.drawPath(lordsbattleHandlePath, lordsbattlePaint);

      final double lordsbattleCrossSize = 8;
      final Offset lordsbattleCrossOffset1 = Offset(
        lordsbattleHandleEnd.dx +
            lordsbattleCrossSize * lordsbattleMath.cos(lordsbattleRad),
        lordsbattleHandleEnd.dy -
            lordsbattleCrossSize * lordsbattleMath.sin(lordsbattleRad),
      );
      final Offset lordsbattleCrossOffset2 = Offset(
        lordsbattleHandleEnd.dx -
            lordsbattleCrossSize * lordsbattleMath.cos(lordsbattleRad),
        lordsbattleHandleEnd.dy +
            lordsbattleCrossSize * lordsbattleMath.sin(lordsbattleRad),
      );

      lordsbattleCanvas.drawLine(
        lordsbattleCrossOffset1,
        lordsbattleCrossOffset2,
        lordsbattlePaint,
      );
    }

    // Два меча, симметрично относительно вертикали, кончики сходятся в центре.
    lordsbattleDrawSword(lordsbattleAngle);
    lordsbattleDrawSword(-lordsbattleAngle);
  }

  @override
  bool shouldRepaint(covariant _LordsbattleSwordsPainter oldDelegate) {
    return oldDelegate.lordsbattleAngle != lordsbattleAngle ||
        oldDelegate.lordsbattleColor != lordsbattleColor;
  }
}

// ============================================================================
// Статистика (lordsbattleFinalUrl / lordsbattlePostStat) — строки не меняем
// ============================================================================

Future<String> lordsbattleFinalUrl(
    String lordsbattleStartUrl, {
      int lordsbattleMaxHops = 10,
    }) async {
  final HttpClient lordsbattleClient = HttpClient();

  try {
    Uri lordsbattleCurrentUri = Uri.parse(lordsbattleStartUrl);

    for (int lordsbattleI = 0; lordsbattleI < lordsbattleMaxHops; lordsbattleI++) {
      final HttpClientRequest lordsbattleRequest =
      await lordsbattleClient.getUrl(lordsbattleCurrentUri);
      lordsbattleRequest.followRedirects = false;
      final HttpClientResponse lordsbattleResponse =
      await lordsbattleRequest.close();

      if (lordsbattleResponse.isRedirect) {
        final String? lordsbattleLoc =
        lordsbattleResponse.headers.value(HttpHeaders.locationHeader);
        if (lordsbattleLoc == null || lordsbattleLoc.isEmpty) break;

        final Uri lordsbattleNextUri = Uri.parse(lordsbattleLoc);
        lordsbattleCurrentUri = lordsbattleNextUri.hasScheme
            ? lordsbattleNextUri
            : lordsbattleCurrentUri.resolveUri(lordsbattleNextUri);
        continue;
      }

      return lordsbattleCurrentUri.toString();
    }

    return lordsbattleCurrentUri.toString();
  } catch (lordsbattleError) {
    debugPrint('wheelFinalUrl error: $lordsbattleError');
    return lordsbattleStartUrl;
  } finally {
    lordsbattleClient.close(force: true);
  }
}

Future<void> lordsbattlePostStat({
  required String lordsbattleEvent,
  required int lordsbattleTimeStart,
  required String lordsbattleUrl,
  required int lordsbattleTimeFinish,
  required String lordsbattleAppSid,
  int? lordsbattleFirstPageTs,
}) async {
  try {
    final String lordsbattleResolvedUrl =
    await lordsbattleFinalUrl(lordsbattleUrl);
    final Map<String, dynamic> lordsbattlePayload = <String, dynamic>{
      'event': lordsbattleEvent,
      'timestart': lordsbattleTimeStart,
      'timefinsh': lordsbattleTimeFinish,
      'url': lordsbattleResolvedUrl,
      'appleID': '6755681349',
      'open_count': '$lordsbattleAppSid/$lordsbattleTimeStart',
    };

    debugPrint('wheelStat $lordsbattlePayload');

    final http.Response lordsbattleResp = await http.post(
      Uri.parse('$lordsbattleMetrStatEndpoint/$lordsbattleAppSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(lordsbattlePayload),
    );

    debugPrint(
        'wheelStat resp=${lordsbattleResp.statusCode} body=${lordsbattleResp.body}');
  } catch (lordsbattleError) {
    debugPrint('wheelPostStat error: $lordsbattleError');
  }
}

// ============================================================================
// WebView-экран: LordsbattleTableView (бывший NcupTableView / DressRetroTableView)
// ============================================================================

class LordsbattleTableView extends StatefulWidget
    with WidgetsBindingObserver {
  String lordsbattleStartingUrl;
  LordsbattleTableView(this.lordsbattleStartingUrl, {super.key});

  @override
  State<LordsbattleTableView> createState() =>
      _LordsbattleTableViewState(lordsbattleStartingUrl);
}

class _LordsbattleTableViewState extends State<LordsbattleTableView>
    with WidgetsBindingObserver {
  _LordsbattleTableViewState(this.lordsbattleCurrentUrl);

  final LordsbattleVault lordsbattleVaultInstance = LordsbattleVault();

  late InAppWebViewController lordsbattleWebViewController;
  String? lordsbattlePushToken;
  final LordsbattleDeviceProfile lordsbattleDeviceProfileInstance =
  LordsbattleDeviceProfile();

  bool lordsbattleOverlayBusy = false;
  String lordsbattleCurrentUrl;
  DateTime? lordsbattleLastPausedAt;

  bool lordsbattleLoadedOnceSent = false;
  int? lordsbattleFirstPageTimestamp;
  int lordsbattleStartLoadTimestamp = 0;

  final Set<String> lordsbattleExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'bnl.com',
    'www.bnl.com',
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'instagram.com',
    'www.instagram.com',
    'twitter.com',
    'www.twitter.com',
    'x.com',
    'www.x.com',
  };

  final Set<String> lordsbattleExternalSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'bnl',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
  };

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(lordsbattleFcmBackgroundHandler);

    lordsbattleFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;

    lordsbattleInitPushAndGetToken();
    lordsbattleDeviceProfileInstance.lordsbattleInitialize();
    lordsbattleWireForegroundPushHandlers();
    lordsbattleBindPlatformNotificationTap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lordsbattleState) {
    if (lordsbattleState == AppLifecycleState.paused) {
      lordsbattleLastPausedAt = DateTime.now();
    }
    if (lordsbattleState == AppLifecycleState.resumed) {
      if (Platform.isIOS && lordsbattleLastPausedAt != null) {
        final DateTime lordsbattleNow = DateTime.now();
        final Duration lordsbattleDrift =
        lordsbattleNow.difference(lordsbattleLastPausedAt!);
        if (lordsbattleDrift > const Duration(minutes: 25)) {
          lordsbattleForceReloadToLobby();
        }
      }
      lordsbattleLastPausedAt = null;
    }
  }

  void lordsbattleForceReloadToLobby() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((Duration lordsbattleDuration) {
      if (!mounted) return;
      // Здесь можно вернуть в лобби (MafiaHarbor / CaptainHarbor / BillHarbor),
      // если нужно.
    });
  }

  // --------------------------------------------------------------------------
  // Push / FCM
  // --------------------------------------------------------------------------

  void lordsbattleWireForegroundPushHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage lordsbattleMsg) {
      if (lordsbattleMsg.data['uri'] != null) {
        lordsbattleNavigateTo(lordsbattleMsg.data['uri'].toString());
      } else {
        lordsbattleReturnToCurrentUrl();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage lordsbattleMsg) {
      if (lordsbattleMsg.data['uri'] != null) {
        lordsbattleNavigateTo(lordsbattleMsg.data['uri'].toString());
      } else {
        lordsbattleReturnToCurrentUrl();
      }
    });
  }

  void lordsbattleNavigateTo(String lordsbattleNewUrl) async {
    await lordsbattleWebViewController.loadUrl(
      urlRequest: URLRequest(url: WebUri(lordsbattleNewUrl)),
    );
  }

  void lordsbattleReturnToCurrentUrl() async {
    Future<void>.delayed(const Duration(seconds: 3), () {
      lordsbattleWebViewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(lordsbattleCurrentUrl)),
      );
    });
  }

  Future<void> lordsbattleInitPushAndGetToken() async {
    final FirebaseMessaging lordsbattleFm = FirebaseMessaging.instance;
    await lordsbattleFm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    lordsbattlePushToken = await lordsbattleFm.getToken();
  }

  // --------------------------------------------------------------------------
  // Привязка канала: тап по уведомлению из native
  // --------------------------------------------------------------------------

  void lordsbattleBindPlatformNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall lordsbattleCall) async {
      if (lordsbattleCall.method == "onNotificationTap") {
        final Map<String, dynamic> lordsbattlePayload =
        Map<String, dynamic>.from(lordsbattleCall.arguments);
        debugPrint("URI from platform tap: ${lordsbattlePayload['uri']}");
        final String? lordsbattleUriString =
        lordsbattlePayload["uri"]?.toString();
        if (lordsbattleUriString != null &&
            !lordsbattleUriString.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext lordsbattleContext) =>
                  LordsbattleTableView(lordsbattleUriString),
            ),
                (Route<dynamic> lordsbattleRoute) => false,
          );
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    lordsbattleBindPlatformNotificationTap();

    final bool lordsbattleIsDark =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
      lordsbattleIsDark ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: <Widget>[
            InAppWebView(
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                disableDefaultErrorPage: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                allowsPictureInPictureMediaPlayback: true,
                useOnDownloadStart: true,
                javaScriptCanOpenWindowsAutomatically: true,
                useShouldOverrideUrlLoading: true,
                supportMultipleWindows: true,
              ),
              initialUrlRequest: URLRequest(
                url: WebUri(lordsbattleCurrentUrl),
              ),
              onWebViewCreated:
                  (InAppWebViewController lordsbattleController) {
                lordsbattleWebViewController = lordsbattleController;

                lordsbattleWebViewController.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (List<dynamic> lordsbattleArgs) {
                    lordsbattleVaultInstance.lordsbattleLoggerInstance
                        .lordsbattleLogInfo("JS Args: $lordsbattleArgs");
                    try {
                      return lordsbattleArgs.reduce((dynamic lordsbattleV,
                          dynamic lordsbattleE) =>
                      lordsbattleV + lordsbattleE);
                    } catch (_) {
                      return lordsbattleArgs.toString();
                    }
                  },
                );
              },
              onLoadStart: (
                  InAppWebViewController lordsbattleController,
                  Uri? lordsbattleUri,
                  ) async {
                lordsbattleStartLoadTimestamp =
                    DateTime.now().millisecondsSinceEpoch;

                if (lordsbattleUri != null) {
                  if (LordsbattleKit.lordsbattleLooksLikeBareMail(
                      lordsbattleUri)) {
                    try {
                      await lordsbattleController.stopLoading();
                    } catch (_) {}
                    final Uri lordsbattleMailto =
                    LordsbattleKit.lordsbattleToMailto(lordsbattleUri);
                    await LordsbattleLinker.lordsbattleOpen(
                      LordsbattleKit.lordsbattleGmailize(
                          lordsbattleMailto),
                    );
                    return;
                  }

                  final String lordsbattleScheme =
                  lordsbattleUri.scheme.toLowerCase();
                  if (lordsbattleScheme != 'http' &&
                      lordsbattleScheme != 'https') {
                    try {
                      await lordsbattleController.stopLoading();
                    } catch (_) {}
                  }
                }
              },
              onLoadStop: (
                  InAppWebViewController lordsbattleController,
                  Uri? lordsbattleUri,
                  ) async {
                await lordsbattleController.evaluateJavascript(
                  source: "console.log('Hello from Roulette JS!');",
                );

                setState(() {
                  lordsbattleCurrentUrl =
                      lordsbattleUri?.toString() ?? lordsbattleCurrentUrl;
                });

                Future<void>.delayed(const Duration(seconds: 20), () {
                  lordsbattleSendLoadedOnce();
                });
              },
              shouldOverrideUrlLoading: (
                  InAppWebViewController lordsbattleController,
                  NavigationAction lordsbattleNav,
                  ) async {
                final Uri? lordsbattleUri = lordsbattleNav.request.url;
                if (lordsbattleUri == null) {
                  return NavigationActionPolicy.ALLOW;
                }

                if (LordsbattleKit.lordsbattleLooksLikeBareMail(
                    lordsbattleUri)) {
                  final Uri lordsbattleMailto =
                  LordsbattleKit.lordsbattleToMailto(lordsbattleUri);
                  await LordsbattleLinker.lordsbattleOpen(
                    LordsbattleKit.lordsbattleGmailize(lordsbattleMailto),
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                final String lordsbattleScheme =
                lordsbattleUri.scheme.toLowerCase();

                if (lordsbattleScheme == 'mailto') {
                  await LordsbattleLinker.lordsbattleOpen(
                    LordsbattleKit.lordsbattleGmailize(lordsbattleUri),
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                if (lordsbattleScheme == 'tel') {
                  await launchUrl(
                    lordsbattleUri,
                    mode: LaunchMode.externalApplication,
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                final String lordsbattleHost =
                lordsbattleUri.host.toLowerCase();
                final bool lordsbattleIsSocial =
                    lordsbattleHost.endsWith('facebook.com') ||
                        lordsbattleHost.endsWith('instagram.com') ||
                        lordsbattleHost.endsWith('twitter.com') ||
                        lordsbattleHost.endsWith('x.com');

                if (lordsbattleIsSocial) {
                  await LordsbattleLinker.lordsbattleOpen(lordsbattleUri);
                  return NavigationActionPolicy.CANCEL;
                }

                if (lordsbattleIsExternalDestination(lordsbattleUri)) {
                  final Uri lordsbattleMapped =
                  lordsbattleMapExternalToHttp(lordsbattleUri);
                  await LordsbattleLinker.lordsbattleOpen(lordsbattleMapped);
                  return NavigationActionPolicy.CANCEL;
                }

                if (lordsbattleScheme != 'http' &&
                    lordsbattleScheme != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow: (
                  InAppWebViewController lordsbattleController,
                  CreateWindowAction lordsbattleReq,
                  ) async {
                final Uri? lordsbattleUrl = lordsbattleReq.request.url;
                if (lordsbattleUrl == null) return false;

                if (LordsbattleKit.lordsbattleLooksLikeBareMail(
                    lordsbattleUrl)) {
                  final Uri lordsbattleMail =
                  LordsbattleKit.lordsbattleToMailto(lordsbattleUrl);
                  await LordsbattleLinker.lordsbattleOpen(
                    LordsbattleKit.lordsbattleGmailize(lordsbattleMail),
                  );
                  return false;
                }

                final String lordsbattleScheme =
                lordsbattleUrl.scheme.toLowerCase();

                if (lordsbattleScheme == 'mailto') {
                  await LordsbattleLinker.lordsbattleOpen(
                    LordsbattleKit.lordsbattleGmailize(lordsbattleUrl),
                  );
                  return false;
                }

                if (lordsbattleScheme == 'tel') {
                  await launchUrl(
                    lordsbattleUrl,
                    mode: LaunchMode.externalApplication,
                  );
                  return false;
                }

                final String lordsbattleHost =
                lordsbattleUrl.host.toLowerCase();
                final bool lordsbattleIsSocial =
                    lordsbattleHost.endsWith('facebook.com') ||
                        lordsbattleHost.endsWith('instagram.com') ||
                        lordsbattleHost.endsWith('twitter.com') ||
                        lordsbattleHost.endsWith('x.com');

                if (lordsbattleIsSocial) {
                  await LordsbattleLinker.lordsbattleOpen(lordsbattleUrl);
                  return false;
                }

                if (lordsbattleIsExternalDestination(lordsbattleUrl)) {
                  final Uri lordsbattleMapped =
                  lordsbattleMapExternalToHttp(lordsbattleUrl);
                  await LordsbattleLinker.lordsbattleOpen(lordsbattleMapped);
                  return false;
                }

                if (lordsbattleScheme == 'http' ||
                    lordsbattleScheme == 'https') {
                  lordsbattleController.loadUrl(
                    urlRequest: URLRequest(
                        url: WebUri(lordsbattleUrl.toString())),
                  );
                }

                return false;
              },
            ),
            if (lordsbattleOverlayBusy)
              const Positioned.fill(
                child:
                LordsbattleSwordsLoader(), // ЗДЕСЬ НОВЫЙ LOADER С МЕЧАМИ
              ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // Внешние “столы” (протоколы/мессенджеры/соцсети)
  // ========================================================================

  bool lordsbattleIsExternalDestination(Uri lordsbattleUri) {
    final String lordsbattleScheme = lordsbattleUri.scheme.toLowerCase();
    if (lordsbattleExternalSchemes.contains(lordsbattleScheme)) {
      return true;
    }

    if (lordsbattleScheme == 'http' || lordsbattleScheme == 'https') {
      final String lordsbattleHost =
      lordsbattleUri.host.toLowerCase();
      if (lordsbattleExternalHosts.contains(lordsbattleHost)) {
        return true;
      }
      if (lordsbattleHost.endsWith('t.me')) return true;
      if (lordsbattleHost.endsWith('wa.me')) return true;
      if (lordsbattleHost.endsWith('m.me')) return true;
      if (lordsbattleHost.endsWith('signal.me')) return true;
      if (lordsbattleHost.endsWith('facebook.com')) return true;
      if (lordsbattleHost.endsWith('instagram.com')) return true;
      if (lordsbattleHost.endsWith('twitter.com')) return true;
      if (lordsbattleHost.endsWith('x.com')) return true;
    }

    return false;
  }

  Uri lordsbattleMapExternalToHttp(Uri lordsbattleUri) {
    final String lordsbattleScheme = lordsbattleUri.scheme.toLowerCase();

    if (lordsbattleScheme == 'tg' || lordsbattleScheme == 'telegram') {
      final Map<String, String> lordsbattleQp =
          lordsbattleUri.queryParameters;
      final String? lordsbattleDomain = lordsbattleQp['domain'];
      if (lordsbattleDomain != null && lordsbattleDomain.isNotEmpty) {
        return Uri.https('t.me', '/$lordsbattleDomain', <String, String>{
          if (lordsbattleQp['start'] != null)
            'start': lordsbattleQp['start']!,
        });
      }
      final String lordsbattlePath =
      lordsbattleUri.path.isNotEmpty ? lordsbattleUri.path : '';
      return Uri.https(
        't.me',
        '/$lordsbattlePath',
        lordsbattleUri.queryParameters.isEmpty
            ? null
            : lordsbattleUri.queryParameters,
      );
    }

    if (lordsbattleScheme == 'whatsapp') {
      final Map<String, String> lordsbattleQp =
          lordsbattleUri.queryParameters;
      final String? lordsbattlePhone = lordsbattleQp['phone'];
      final String? lordsbattleText = lordsbattleQp['text'];
      if (lordsbattlePhone != null && lordsbattlePhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${LordsbattleKit.lordsbattleDigitsOnly(lordsbattlePhone)}',
          <String, String>{
            if (lordsbattleText != null && lordsbattleText.isNotEmpty)
              'text': lordsbattleText,
          },
        );
      }
      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (lordsbattleText != null && lordsbattleText.isNotEmpty)
            'text': lordsbattleText,
        },
      );
    }

    if (lordsbattleScheme == 'bnl') {
      final String lordsbattleNewPath =
      lordsbattleUri.path.isNotEmpty ? lordsbattleUri.path : '';
      return Uri.https(
        'bnl.com',
        '/$lordsbattleNewPath',
        lordsbattleUri.queryParameters.isEmpty
            ? null
            : lordsbattleUri.queryParameters,
      );
    }

    return lordsbattleUri;
  }

  Future<void> lordsbattleSendLoadedOnce() async {
    if (lordsbattleLoadedOnceSent) {
      debugPrint('Wheel Loaded already sent, skip');
      return;
    }

    final int lordsbattleNow = DateTime.now().millisecondsSinceEpoch;

    // тут, как и было, можешь добавить lordsbattlePostStat при необходимости

    lordsbattleLoadedOnceSent = true;
  }
}