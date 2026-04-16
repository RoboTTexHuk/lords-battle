import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show Platform, HttpHeaders, HttpClient, HttpClientRequest, HttpClientResponse;
import 'dart:math';

import 'package:appsflyer_sdk/appsflyer_sdk.dart' as appsflyer_core;
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodChannel, SystemChrome, SystemUiOverlayStyle, MethodCall, VoidCallback, DeviceOrientation;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:lordsbattle/pushbattlelords.dart';


import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;

// ============================================================================
// Константы
// ============================================================================

const String dressRetroLoadedOnceKey = 'loaded_once';
const String dressRetroStatEndpoint = 'https://src.lordbattles.team/stat';
const String dressRetroCachedFcmKey = 'cached_fcm';
const String dressRetroCachedDeepKey = 'cached_deep_push_uri';

const Set<String> kBankSchemes = {
  'td',
  'rbc',
  'cibc',
  'scotiabank',
  'bmo',
  'bmodigitalbanking',
  'desjardins',
  'tangerine',
  'nationalbank',
  'simplii',
  'dominotoronto',
};

const Set<String> kBankDomains = {
  'td.com',
  'tdcanadatrust.com',
  'easyweb.td.com',
  'rbc.com',
  'royalbank.com',
  'online.royalbank.com',
  'cibc.com',
  'cibc.ca',
  'online.cibc.com',
  'scotiabank.com',
  'scotiaonline.scotiabank.com',
  'bmo.com',
  'bmo.ca',
  'bmodigitalbanking.com',
  'desjardins.com',
  'tangerine.ca',
  'nbc.ca',
  'nationalbank.ca',
  'simplii.com',
  'simplii.ca',
  'dominotoronto.com',
  'dominobank.com',
};

// ============================================================================
// Лёгкие сервисы
// ============================================================================

class LordsbattleLoggerService {
  static final LordsbattleLoggerService sharedInstanceLordsbattle =
  LordsbattleLoggerService._internalConstructorLordsbattle();

  LordsbattleLoggerService._internalConstructorLordsbattle();

  factory LordsbattleLoggerService() => sharedInstanceLordsbattle;

  final Connectivity lordsbattleConnectivity = Connectivity();

  void lordsbattleLogInfo(Object message) => print('[I] $message');
  void lordsbattleLogWarn(Object message) => print('[W] $message');
  void lordsbattleLogError(Object message) => print('[E] $message');
}

class LordsbattleNetworkService {
  final LordsbattleLoggerService lordsbattleLogger = LordsbattleLoggerService();

  Future<void> lordsbattlePostJson(
      String url,
      Map<String, dynamic> data,
      ) async {
    try {
      await http.post(
        Uri.parse(url),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
    } catch (error) {
      lordsbattleLogger.lordsbattleLogError('postJson error: $error');
    }
  }
}

// ============================================================================
// Профиль устройства
// ============================================================================

class LordsbattleDeviceProfile {
  String? lordsbattleDeviceId;
  String? lordsbattleSessionId = '';
  String? lordsbattlePlatformName;
  String? lordsbattleOsVersion;
  String? lordsbattleAppVersion;
  String? lordsbattleLanguageCode;
  String? lordsbattleTimezoneName;
  bool lordsbattlePushEnabled = false;

  bool lordsbattleSafeAreaEnabled = false;
  String? lordsbattleSafeAreaColor;

  String? lordsbattleBaseUserAgent;

  Map<String, dynamic>? lordsbattleLastPushData;

  // savels с сервера
  Map<String, dynamic>? lordsbattleSavels;

  Future<void> lordsbattleInitialize() async {
    final DeviceInfoPlugin deviceInfoPluginLordsbattle = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo androidInfoLordsbattle =
      await deviceInfoPluginLordsbattle.androidInfo;
      lordsbattleDeviceId = androidInfoLordsbattle.id;
      lordsbattlePlatformName = 'android';
      lordsbattleOsVersion = androidInfoLordsbattle.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo iosInfoLordsbattle =
      await deviceInfoPluginLordsbattle.iosInfo;
      lordsbattleDeviceId = iosInfoLordsbattle.identifierForVendor;
      lordsbattlePlatformName = 'ios';
      lordsbattleOsVersion = iosInfoLordsbattle.systemVersion;
    }

    final PackageInfo packageInfoLordsbattle = await PackageInfo.fromPlatform();
    lordsbattleAppVersion = packageInfoLordsbattle.version;
    lordsbattleLanguageCode = Platform.localeName.split('_').first;
    lordsbattleTimezoneName = tz_zone.local.name;
    lordsbattleSessionId = 'test-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> lordsbattleToMap({String? fcmToken}) =>
      <String, dynamic>{
        'fcm_token': fcmToken ?? 'missing_token',
        'device_id': lordsbattleDeviceId ?? 'missing_id',
        'app_name': 'lordbattles',
        'instance_id': lordsbattleSessionId ?? 'missing_session',
        'platform': lordsbattlePlatformName ?? 'missing_system',
        'os_version': lordsbattleOsVersion ?? 'missing_build',
        'app_version': lordsbattleAppVersion ?? 'missing_app',
        'language': lordsbattleLanguageCode ?? 'en',
        'timezone': lordsbattleTimezoneName ?? 'UTC',
        'push_enabled': lordsbattlePushEnabled,
        'safe_area_native': lordsbattleSafeAreaEnabled,
        'useragent': lordsbattleBaseUserAgent ?? 'unknown_useragent',
        'savels': lordsbattleSavels ?? <String, dynamic>{},
        'fpscashier': 'true',
      };
}

// ============================================================================
// AppsFlyer Spy
// ============================================================================

class LordsbattleAnalyticsSpyService {
  appsflyer_core.AppsFlyerOptions? lordsbattleAppsFlyerOptions;
  appsflyer_core.AppsflyerSdk? lordsbattleAppsFlyerSdk;

  String lordsbattleAppsFlyerUid = '';
  String lordsbattleAppsFlyerData = '';

  Map<String, dynamic>? lordsbattleAppsFlyerOneLinkData;

  void lordsbattleStartTracking({VoidCallback? onUpdate}) {
    final appsflyer_core.AppsFlyerOptions configLordsbattle =
    appsflyer_core.AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6762364419',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    lordsbattleAppsFlyerOptions = configLordsbattle;
    lordsbattleAppsFlyerSdk = appsflyer_core.AppsflyerSdk(configLordsbattle);

    lordsbattleAppsFlyerSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    lordsbattleAppsFlyerSdk?.startSDK(
      onSuccess: () => LordsbattleLoggerService()
          .lordsbattleLogInfo('RetroCarAnalyticsSpy started'),
      onError: (int code, String msg) => LordsbattleLoggerService()
          .lordsbattleLogError('RetroCarAnalyticsSpy error $code: $msg'),
    );

    lordsbattleAppsFlyerSdk?.onInstallConversionData((dynamic value) {
      lordsbattleAppsFlyerData = value.toString();
      onUpdate?.call();
    });

    lordsbattleAppsFlyerSdk?.getAppsFlyerUID().then((dynamic value) {
      lordsbattleAppsFlyerUid = value.toString();
      onUpdate?.call();
    });
  }

  void lordsbattleSetOneLinkData(Map<String, dynamic> data) {
    lordsbattleAppsFlyerOneLinkData = data;
    LordsbattleLoggerService()
        .lordsbattleLogInfo('NcupAnalyticsSpyService: OneLink data updated: $data');
  }
}

// ============================================================================
// FCM фон
// ============================================================================

@pragma('vm:entry-point')
Future<void> lordsbattleFcmBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  LordsbattleLoggerService().lordsbattleLogInfo('bg-fcm: ${message.messageId}');
  LordsbattleLoggerService().lordsbattleLogInfo('bg-data: ${message.data}');

  final dynamic linkLordsbattle = message.data['uri'];
  if (linkLordsbattle != null) {
    try {
      final SharedPreferences prefsLordsbattle =
      await SharedPreferences.getInstance();
      await prefsLordsbattle.setString(
        dressRetroCachedDeepKey,
        linkLordsbattle.toString(),
      );
    } catch (e) {
      LordsbattleLoggerService()
          .lordsbattleLogError('bg-fcm save deep failed: $e');
    }
  }
}

// ============================================================================
// FCM Bridge — токен
// ============================================================================

class LordsbattleFcmBridge {
  final LordsbattleLoggerService lordsbattleLogger = LordsbattleLoggerService();

  static const MethodChannel _tokenChannelLordsbattle =
  MethodChannel('com.example.fcm/token');

  String? lordsbattleToken;
  final List<void Function(String)> lordsbattleTokenWaiters =
  <void Function(String)>[];

  String? get lordsbattleFcmToken => lordsbattleToken;

  Timer? _requestTimerLordsbattle;
  int _requestAttemptsLordsbattle = 0;
  final int _maxAttemptsLordsbattle = 10;

  LordsbattleFcmBridge() {
    _tokenChannelLordsbattle
        .setMethodCallHandler((MethodCall callLordsbattle) async {
      if (callLordsbattle.method == 'setToken') {
        final String tokenStringLordsbattle =
        callLordsbattle.arguments as String;
        lordsbattleLogger.lordsbattleLogInfo(
            'NcupFcmBridge: got token from native channel = $tokenStringLordsbattle');
        if (tokenStringLordsbattle.isNotEmpty) {
          lordsbattleSetToken(tokenStringLordsbattle);
        }
      }
    });

    lordsbattleRestoreToken();
    _requestNativeTokenLordsbattle();
    _startRequestTimerLordsbattle();
  }

  Future<void> _requestNativeTokenLordsbattle() async {
    try {
      lordsbattleLogger
          .lordsbattleLogInfo('NcupFcmBridge: request native getToken()');
      final String? token =
      await _tokenChannelLordsbattle.invokeMethod<String>('getToken');
      if (token != null && token.isNotEmpty) {
        lordsbattleLogger
            .lordsbattleLogInfo('NcupFcmBridge: native getToken() returns $token');
        lordsbattleSetToken(token);
      } else {
        lordsbattleLogger
            .lordsbattleLogWarn('NcupFcmBridge: native getToken() returned empty');
      }
    } catch (e) {
      lordsbattleLogger
          .lordsbattleLogWarn('NcupFcmBridge: getToken invoke error: $e');
    }
  }

  void _startRequestTimerLordsbattle() {
    _requestTimerLordsbattle?.cancel();
    _requestAttemptsLordsbattle = 0;

    _requestTimerLordsbattle =
        Timer.periodic(const Duration(seconds: 5), (Timer t) async {
          if ((lordsbattleToken ?? '').isNotEmpty) {
            lordsbattleLogger.lordsbattleLogInfo(
                'NcupFcmBridge: token already set, stop request timer');
            t.cancel();
            return;
          }

          if (_requestAttemptsLordsbattle >= _maxAttemptsLordsbattle) {
            lordsbattleLogger.lordsbattleLogWarn(
                'NcupFcmBridge: max getToken attempts reached, stop timer');
            t.cancel();
            return;
          }

          _requestAttemptsLordsbattle++;
          lordsbattleLogger.lordsbattleLogInfo(
              'NcupFcmBridge: retry getToken() attempt #$_requestAttemptsLordsbattle');
          await _requestNativeTokenLordsbattle();
        });
  }

  Future<void> lordsbattleRestoreToken() async {
    try {
      final SharedPreferences prefsLordsbattle =
      await SharedPreferences.getInstance();
      final String? cachedTokenLordsbattle =
      prefsLordsbattle.getString(dressRetroCachedFcmKey);
      if (cachedTokenLordsbattle != null &&
          cachedTokenLordsbattle.isNotEmpty) {
        lordsbattleLogger.lordsbattleLogInfo(
            'NcupFcmBridge: restored cached token = $cachedTokenLordsbattle');
        lordsbattleSetToken(cachedTokenLordsbattle, notify: false);
      }
    } catch (e) {
      lordsbattleLogger.lordsbattleLogError('NcupRestoreToken error: $e');
    }
  }

  Future<void> lordsbattlePersistToken(String newToken) async {
    try {
      final SharedPreferences prefsLordsbattle =
      await SharedPreferences.getInstance();
      await prefsLordsbattle.setString(dressRetroCachedFcmKey, newToken);
    } catch (e) {
      lordsbattleLogger.lordsbattleLogError('NcupPersistToken error: $e');
    }
  }

  void lordsbattleSetToken(
      String newToken, {
        bool notify = true,
      }) {
    lordsbattleToken = newToken;
    lordsbattlePersistToken(newToken);

    if (notify) {
      for (final void Function(String) callbackLordsbattle
      in List<void Function(String)>.from(lordsbattleTokenWaiters)) {
        try {
          callbackLordsbattle(newToken);
        } catch (error) {
          lordsbattleLogger.lordsbattleLogWarn('fcm waiter error: $error');
        }
      }
      lordsbattleTokenWaiters.clear();
    }
  }

  Future<void> lordsbattleWaitForToken(
      Function(String token) onTokenLordsbattle,
      ) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((lordsbattleToken ?? '').isNotEmpty) {
        onTokenLordsbattle(lordsbattleToken!);
        return;
      }

      lordsbattleTokenWaiters.add(onTokenLordsbattle);
    } catch (error) {
      lordsbattleLogger.lordsbattleLogError('NcupWaitForToken error: $error');
    }
  }

  void dispose() {
    _requestTimerLordsbattle?.cancel();
  }
}

// ============================================================================
// Лоадер: два оранжевых меча
// ============================================================================

class LordsbattleSwordsLoader extends StatefulWidget {
  const LordsbattleSwordsLoader({super.key});

  @override
  State<LordsbattleSwordsLoader> createState() =>
      _LordsbattleSwordsLoaderState();
}

class _LordsbattleSwordsLoaderState extends State<LordsbattleSwordsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controllerLordsbattle;
  late final Animation<double> _animationLordsbattle;

  @override
  void initState() {
    super.initState();
    _controllerLordsbattle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _animationLordsbattle =
        Tween<double>(begin: -0.35, end: 0.35).animate(CurvedAnimation(
          parent: _controllerLordsbattle,
          curve: Curves.easeInOut,
        ));
  }

  @override
  void dispose() {
    _controllerLordsbattle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color swordColorLordsbattle = Color(0xFFFF9800); // оранжевый

    return Center(
      child: SizedBox(
        width: 120,
        height: 120,
        child: AnimatedBuilder(
          animation: _animationLordsbattle,
          builder: (context, child) {
            return CustomPaint(
              painter: _LordsbattleSwordsPainter(
                angleLordsbattle: _animationLordsbattle.value,
                colorLordsbattle: swordColorLordsbattle,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LordsbattleSwordsPainter extends CustomPainter {
  final double angleLordsbattle;
  final Color colorLordsbattle;

  _LordsbattleSwordsPainter({
    required this.angleLordsbattle,
    required this.colorLordsbattle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paintLordsbattle = Paint()
      ..color = colorLordsbattle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final centerLordsbattle = Offset(size.width / 2, size.height / 2);
    final double swordLengthLordsbattle = size.height * 0.42;
    final double handleLengthLordsbattle = size.height * 0.14;

    void drawSword(double baseAngleLordsbattle) {
      final double radLordsbattle = baseAngleLordsbattle;

      final Offset tipLordsbattle = Offset(
        centerLordsbattle.dx + swordLengthLordsbattle * -sin(radLordsbattle),
        centerLordsbattle.dy + swordLengthLordsbattle * -cos(radLordsbattle),
      );

      final Offset handleEndLordsbattle = Offset(
        centerLordsbattle.dx +
            (swordLengthLordsbattle - handleLengthLordsbattle) *
                -sin(radLordsbattle),
        centerLordsbattle.dy +
            (swordLengthLordsbattle - handleLengthLordsbattle) *
                -cos(radLordsbattle),
      );

      final Path bladePathLordsbattle = Path()
        ..moveTo(centerLordsbattle.dx, centerLordsbattle.dy)
        ..lineTo(tipLordsbattle.dx, tipLordsbattle.dy);
      canvas.drawPath(bladePathLordsbattle, paintLordsbattle);

      final Path handlePathLordsbattle = Path()
        ..moveTo(centerLordsbattle.dx, centerLordsbattle.dy)
        ..lineTo(handleEndLordsbattle.dx, handleEndLordsbattle.dy);
      canvas.drawPath(handlePathLordsbattle, paintLordsbattle);

      final double crossSizeLordsbattle = 8;
      final Offset crossOffsetLordsbattle = Offset(
        handleEndLordsbattle.dx +
            crossSizeLordsbattle * cos(radLordsbattle),
        handleEndLordsbattle.dy -
            crossSizeLordsbattle * sin(radLordsbattle),
      );
      final Offset crossOffset2Lordsbattle = Offset(
        handleEndLordsbattle.dx -
            crossSizeLordsbattle * cos(radLordsbattle),
        handleEndLordsbattle.dy +
            crossSizeLordsbattle * sin(radLordsbattle),
      );

      canvas.drawLine(
        crossOffsetLordsbattle,
        crossOffset2Lordsbattle,
        paintLordsbattle,
      );
    }

    drawSword(angleLordsbattle);
    drawSword(-angleLordsbattle);
  }

  @override
  bool shouldRepaint(covariant _LordsbattleSwordsPainter oldDelegate) {
    return oldDelegate.angleLordsbattle != angleLordsbattle ||
        oldDelegate.colorLordsbattle != colorLordsbattle;
  }
}

// ============================================================================
// Splash / Hall с новым loader’ом
// ============================================================================

class LordsbattleHall extends StatefulWidget {
  const LordsbattleHall({Key? key}) : super(key: key);

  @override
  State<LordsbattleHall> createState() => _LordsbattleHallState();
}

class _LordsbattleHallState extends State<LordsbattleHall> {
  final LordsbattleFcmBridge lordsbattleFcmBridgeInstance =
  LordsbattleFcmBridge();
  bool lordsbattleNavigatedOnce = false;
  Timer? lordsbattleFallbackTimer;

  // для старого процентного лоадера (теперь не используется в UI, но оставлено для логики если нужно)
  late Timer _loaderTimerLordsbattle;
  double _loaderPercentLordsbattle = 0.0;
  final int _loaderDurationSecondsLordsbattle = 6;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    _startLoaderProgressLordsbattle();

    lordsbattleFcmBridgeInstance.lordsbattleWaitForToken(
          (String tokenLordsbattle) {
        lordsbattleGoToHarbor(tokenLordsbattle);
      },
    );

    lordsbattleFallbackTimer = Timer(
      const Duration(seconds: 8),
          () => lordsbattleGoToHarbor(''),
    );
  }

  void _startLoaderProgressLordsbattle() {
    int tickLordsbattle = 0;
    _loaderPercentLordsbattle = 0.0;
    _loaderTimerLordsbattle =
        Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
          if (!mounted) return;
          setState(() {
            tickLordsbattle++;
            _loaderPercentLordsbattle =
                tickLordsbattle / (_loaderDurationSecondsLordsbattle * 10);
            if (_loaderPercentLordsbattle >= 1.0) {
              _loaderPercentLordsbattle = 1.0;
              _loaderTimerLordsbattle.cancel();
            }
          });
        });
  }

  void lordsbattleGoToHarbor(String signalLordsbattle) {
    if (lordsbattleNavigatedOnce) return;
    lordsbattleNavigatedOnce = true;
    lordsbattleFallbackTimer?.cancel();
    _loaderTimerLordsbattle.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute<Widget>(
        builder: (BuildContext context) =>
            LordsbattleHarbor(lordsbattleSignal: signalLordsbattle),
      ),
    );
  }

  @override
  void dispose() {
    lordsbattleFallbackTimer?.cancel();
    lordsbattleFcmBridgeInstance.dispose();
    _loaderTimerLordsbattle.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Новый лоадер – два оранжевых меча
    return const Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LordsbattleSwordsLoader(),
      ),
    );
  }
}

// ============================================================================
// ViewModel + Courier
// ============================================================================

class LordsbattleBosunViewModel {
  final LordsbattleDeviceProfile lordsbattleDeviceProfileInstance;
  final LordsbattleAnalyticsSpyService lordsbattleAnalyticsSpyInstance;

  LordsbattleBosunViewModel({
    required this.lordsbattleDeviceProfileInstance,
    required this.lordsbattleAnalyticsSpyInstance,
  });

  Map<String, dynamic> lordsbattleDeviceMap(String? fcmToken) =>
      lordsbattleDeviceProfileInstance.lordsbattleToMap(fcmToken: fcmToken);

  Map<String, dynamic> lordsbattleAppsFlyerPayload(
      String? token, {
        String? deepLink,
      }) {
    final Map<String, dynamic> onelinkDataLordsbattle =
        lordsbattleAnalyticsSpyInstance.lordsbattleAppsFlyerOneLinkData ??
            <String, dynamic>{};

    return <String, dynamic>{
      'content': <String, dynamic>{
        'af_data': lordsbattleAnalyticsSpyInstance.lordsbattleAppsFlyerData,
        'af_id': lordsbattleAnalyticsSpyInstance.lordsbattleAppsFlyerUid,
        'fb_app_name': 'lordbattles',
        'app_name': 'lordbattles',
        'onelink': onelinkDataLordsbattle,
        'bundle_identifier': 'com.lordsbattle.batlords.lordsbattle',
        'app_version': '1.4.0',
        'apple_id': '6762364419',
        'fcm_token': token ?? 'no_token',
        'device_id':
        lordsbattleDeviceProfileInstance.lordsbattleDeviceId ?? 'no_device',
        'instance_id':
        lordsbattleDeviceProfileInstance.lordsbattleSessionId ??
            'no_instance',
        'platform':
        lordsbattleDeviceProfileInstance.lordsbattlePlatformName ??
            'no_type',
        'os_version':
        lordsbattleDeviceProfileInstance.lordsbattleOsVersion ?? 'no_os',
        'language':
        lordsbattleDeviceProfileInstance.lordsbattleLanguageCode ?? 'en',
        'timezone':
        lordsbattleDeviceProfileInstance.lordsbattleTimezoneName ?? 'UTC',
        'push_enabled':
        lordsbattleDeviceProfileInstance.lordsbattlePushEnabled,
        'useruid':
        lordsbattleAnalyticsSpyInstance.lordsbattleAppsFlyerUid,
        'safearea':
        lordsbattleDeviceProfileInstance.lordsbattleSafeAreaEnabled,
        'safearea_color':
        lordsbattleDeviceProfileInstance.lordsbattleSafeAreaColor ?? '',
        'useragent':
        lordsbattleDeviceProfileInstance.lordsbattleBaseUserAgent ??
            'unknown_useragent',
        'push': lordsbattleDeviceProfileInstance.lordsbattleLastPushData ??
            <String, dynamic>{},
        'deep': deepLink,
      },
    };
  }
}

class LordsbattleCourierService {
  final LordsbattleBosunViewModel lordsbattleBosun;
  final InAppWebViewController? Function() lordsbattleGetWebViewController;

  LordsbattleCourierService({
    required this.lordsbattleBosun,
    required this.lordsbattleGetWebViewController,
  });

  Future<InAppWebViewController?> _waitForControllerLordsbattle({
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 200),
  }) async {
    final LordsbattleLoggerService logger = LordsbattleLoggerService();
    final DateTime startLordsbattle = DateTime.now();

    while (DateTime.now().difference(startLordsbattle) < timeout) {
      final InAppWebViewController? c = lordsbattleGetWebViewController();
      if (c != null) {
        return c;
      }
      await Future<void>.delayed(interval);
    }

    logger.lordsbattleLogWarn(
        '_waitForController: timeout, controller is still null');
    return null;
  }

  Future<void> lordsbattlePutDeviceToLocalStorage(String? token) async {
    final InAppWebViewController? controllerLordsbattle =
    await _waitForControllerLordsbattle();
    if (controllerLordsbattle == null) return;

    final Map<String, dynamic> mapLordsbattle =
    lordsbattleBosun.lordsbattleDeviceMap(token);
    LordsbattleLoggerService()
        .lordsbattleLogInfo("applocal (${jsonEncode(mapLordsbattle)});");

    try {
      await controllerLordsbattle.evaluateJavascript(
        source:
        "localStorage.setItem('app_data', JSON.stringify(${jsonEncode(mapLordsbattle)}));",
      );
    } catch (e, st) {
      LordsbattleLoggerService()
          .lordsbattleLogError('NcupPutDeviceToLocalStorage error: $e\n$st');
    }
  }

  Future<void> lordsbattleSendRawToPage(
      String? token, {
        String? deepLink,
      }) async {
    final InAppWebViewController? controllerLordsbattle =
    await _waitForControllerLordsbattle();
    if (controllerLordsbattle == null) return;

    final Map<String, dynamic> payloadLordsbattle =
    lordsbattleBosun.lordsbattleAppsFlyerPayload(token, deepLink: deepLink);

    final String jsonStringLordsbattle = jsonEncode(payloadLordsbattle);

    LordsbattleLoggerService()
        .lordsbattleLogInfo('SendRawData: $jsonStringLordsbattle');

    final String jsSafeJsonLordsbattle = jsonEncode(jsonStringLordsbattle);
    final String jsCodeLordsbattle = 'sendRawData($jsSafeJsonLordsbattle);';

    try {
      await controllerLordsbattle.evaluateJavascript(source: jsCodeLordsbattle);
    } catch (e, st) {
      LordsbattleLoggerService().lordsbattleLogError(
          'NcupSendRawToPage evaluateJavascript error: $e\n$st');
    }
  }
}

// ============================================================================
// Статистика
// ============================================================================

Future<String> lordsbattleResolveFinalUrl(
    String startUrl, {
      int maxHops = 10,
    }) async {
  final HttpClient httpClientLordsbattle = HttpClient();

  try {
    Uri currentUriLordsbattle = Uri.parse(startUrl);

    for (int indexLordsbattle = 0;
    indexLordsbattle < maxHops;
    indexLordsbattle++) {
      final HttpClientRequest requestLordsbattle =
      await httpClientLordsbattle.getUrl(currentUriLordsbattle);
      requestLordsbattle.followRedirects = false;
      final HttpClientResponse responseLordsbattle =
      await requestLordsbattle.close();

      if (responseLordsbattle.isRedirect) {
        final String? locationHeaderLordsbattle =
        responseLordsbattle.headers.value(HttpHeaders.locationHeader);
        if (locationHeaderLordsbattle == null ||
            locationHeaderLordsbattle.isEmpty) {
          break;
        }

        final Uri nextUriLordsbattle = Uri.parse(locationHeaderLordsbattle);
        currentUriLordsbattle = nextUriLordsbattle.hasScheme
            ? nextUriLordsbattle
            : currentUriLordsbattle.resolveUri(nextUriLordsbattle);
        continue;
      }

      return currentUriLordsbattle.toString();
    }

    return currentUriLordsbattle.toString();
  } catch (error) {
    print('goldenLuxuryResolveFinalUrl error: $error');
    return startUrl;
  } finally {
    httpClientLordsbattle.close(force: true);
  }
}

Future<void> lordsbattlePostStat({
  required String event,
  required int timeStart,
  required String url,
  required int timeFinish,
  required String appSid,
  int? firstPageLoadTs,
}) async {
  try {
    final String resolvedUrlLordsbattle =
    await lordsbattleResolveFinalUrl(url);

    final Map<String, dynamic> payloadLordsbattle = <String, dynamic>{
      'event': event,
      'timestart': timeStart,
      'timefinsh': timeFinish,
      'url': resolvedUrlLordsbattle,
      'appleID': '6762364419',
      'open_count': '$appSid/$timeStart',
    };

    print('goldenLuxuryStat $payloadLordsbattle');

    final http.Response responseLordsbattle = await http.post(
      Uri.parse('$dressRetroStatEndpoint/$appSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payloadLordsbattle),
    );

    print(
        'goldenLuxuryStat resp=${responseLordsbattle.statusCode} body=${responseLordsbattle.body}');
  } catch (error) {
    print('goldenLuxuryPostStat error: $error');
  }
}

// ============================================================================
// Банковские утилиты
// ============================================================================

bool lordsbattleIsBankScheme(Uri uri) {
  final String schemeLordsbattle = uri.scheme.toLowerCase();
  return kBankSchemes.contains(schemeLordsbattle);
}

bool lordsbattleIsBankDomain(Uri uri) {
  final String hostLordsbattle = uri.host.toLowerCase();
  if (hostLordsbattle.isEmpty) return false;

  for (final String bank in kBankDomains) {
    final String bankHostLordsbattle = bank.toLowerCase();
    if (hostLordsbattle == bankHostLordsbattle ||
        hostLordsbattle.endsWith('.$bankHostLordsbattle')) {
      return true;
    }
  }
  return false;
}

Future<bool> lordsbattleOpenBank(Uri uri) async {
  try {
    if (lordsbattleIsBankScheme(uri)) {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return ok;
    }

    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        lordsbattleIsBankDomain(uri)) {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return ok;
    }
  } catch (e) {
    print('NcupOpenBank error: $e; url=$uri');
  }
  return false;
}

// ============================================================================
// Главный WebView — Harbor
// ============================================================================

class LordsbattleHarbor extends StatefulWidget {
  final String? lordsbattleSignal;

  const LordsbattleHarbor({super.key, required this.lordsbattleSignal});

  @override
  State<LordsbattleHarbor> createState() => _LordsbattleHarborState();
}

class _LordsbattleHarborState extends State<LordsbattleHarbor>
    with WidgetsBindingObserver {
  InAppWebViewController? lordsbattleWebViewController;
  final String lordsbattleHomeUrl = 'https://src.lordbattles.team/';

  int lordsbattleWebViewKeyCounter = 0;
  DateTime? lordsbattleSleepAt;
  bool lordsbattleVeilVisible = false;
  double lordsbattleWarmProgress = 0.0;
  late Timer lordsbattleWarmTimer;
  final int lordsbattleWarmSeconds = 6;
  bool lordsbattleCoverVisible = true;

  bool lordsbattleLoadedOnceSent = false;
  int? lordsbattleFirstPageTimestamp;

  LordsbattleCourierService? lordsbattleCourier;
  LordsbattleBosunViewModel? lordsbattleBosunInstance;

  String lordsbattleCurrentUrl = '';
  int lordsbattleStartLoadTimestamp = 0;

  final LordsbattleDeviceProfile lordsbattleDeviceProfileInstance =
  LordsbattleDeviceProfile();
  final LordsbattleAnalyticsSpyService lordsbattleAnalyticsSpyInstance =
  LordsbattleAnalyticsSpyService();

  final Set<String> lordsbattleSpecialSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
  };

  final Set<String> lordsbattleExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'm.me',
    'signal.me',
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

  String? lordsbattleDeepLinkFromPush;

  String? _baseUserAgentLordsbattle;
  String _currentUserAgentLordsbattle = "";
  String? _currentUrlLordsbattle;

  String? _serverUserAgentLordsbattle;

  bool _safeAreaEnabledLordsbattle = false;
  Color _safeAreaBackgroundColorLordsbattle = const Color(0xFF000000);

  bool _startupSendRawDoneLordsbattle = false;

  String? _pendingLoadedJsLordsbattle;

  bool _loadedJsExecutedOnceLordsbattle = false;

  bool _isInGoogleAuthLordsbattle = false;

  // buttonswl/back
  List<String> _buttonWhitelistLordsbattle = <String>[];
  bool _showBackButtonLordsbattle = false;

  static const MethodChannel _appsFlyerDeepLinkChannelLordsbattle =
  MethodChannel('appsflyer_deeplink_channel');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    lordsbattleFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;
    _currentUrlLordsbattle = lordsbattleHomeUrl;

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          lordsbattleCoverVisible = false;
        });
      }
    });

    Future<void>.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        lordsbattleVeilVisible = true;
      });
    });

    _bindPushChannelFromAppDelegateLordsbattle();
    _bindAppsFlyerDeepLinkChannelLordsbattle();
    lordsbattleBootHarbor();
  }

  // ======================= AppsFlyer deep link bridge =======================

  void _bindAppsFlyerDeepLinkChannelLordsbattle() {
    _appsFlyerDeepLinkChannelLordsbattle.setMethodCallHandler(
          (MethodCall call) async {
        if (call.method == 'onDeepLink') {
          try {
            final dynamic args = call.arguments;

            Map<String, dynamic> payload;

            print(" Data Deepl link ${args.toString()}");
            if (args is Map) {
              payload = Map<String, dynamic>.from(args as Map);
            } else if (args is String) {
              payload = jsonDecode(args) as Map<String, dynamic>;
            } else {
              payload = <String, dynamic>{'raw': args.toString()};
            }

            LordsbattleLoggerService()
                .lordsbattleLogInfo('AppsFlyer onDeepLink from iOS: $payload');

            final dynamic raw = payload['raw'];
            if (raw is Map) {
              final Map<String, dynamic> normalized =
              Map<String, dynamic>.from(raw as Map);

              print("One Link Data $normalized");
              lordsbattleAnalyticsSpyInstance
                  .lordsbattleSetOneLinkData(normalized);
            } else {
              lordsbattleAnalyticsSpyInstance.lordsbattleSetOneLinkData(payload);
            }
          } catch (e, st) {
            LordsbattleLoggerService().lordsbattleLogError(
                'Error in onDeepLink handler: $e\n$st');
          }
        }
      },
    );
  }

  // ======================= Push Data bridge из AppDelegate ==================

  void _bindPushChannelFromAppDelegateLordsbattle() {
    const MethodChannel pushChannelLordsbattle =
    MethodChannel('com.example.fcm/push');

    pushChannelLordsbattle.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'setPushData') {
        try {
          Map<String, dynamic> pushData;
          if (call.arguments is Map) {
            pushData = Map<String, dynamic>.from(call.arguments);
            print("Get Push Data $pushData");
          } else if (call.arguments is String) {
            pushData =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
          } else {
            pushData = <String, dynamic>{'raw': call.arguments.toString()};
          }

          LordsbattleLoggerService()
              .lordsbattleLogInfo('Got push data from AppDelegate: $pushData');

          lordsbattleDeviceProfileInstance.lordsbattleLastPushData = pushData;

          final dynamic uriRaw =
              pushData['uri'] ?? pushData['deep_link'];
          if (uriRaw != null && uriRaw.toString().isNotEmpty) {
            final String u = uriRaw.toString();
            lordsbattleDeepLinkFromPush = u;
            await lordsbattleSaveCachedDeep(u);
          }
        } catch (e, st) {
          LordsbattleLoggerService()
              .lordsbattleLogError('setPushData handler error: $e\n$st');
        }
      }
    });
  }

  // ---------------- User-Agent ----------------

  Future<void> _updateUserAgentFromServerPayloadLordsbattle(
      Map<dynamic, dynamic> root) async {
    String? fullua;
    String? uatail;

    final dynamic content = root['content'];
    if (content is Map) {
      if (content['fullua'] != null &&
          content['fullua'].toString().trim().isNotEmpty) {
        fullua = content['fullua'].toString().trim();
      }
      if (content['uatail'] != null &&
          content['uatail'].toString().trim().isNotEmpty) {
        uatail = content['uatail'].toString().trim();
      }
    }

    if (fullua == null &&
        root['fullua'] != null &&
        root['fullua'].toString().trim().isNotEmpty) {
      fullua = root['fullua'].toString().trim();
    }
    if (uatail == null &&
        root['uatail'] != null &&
        root['uatail'].toString().trim().isNotEmpty) {
      uatail = root['uatail'].toString().trim();
    }

    if (uatail == null) {
      final dynamic adata = root['adata'];
      if (adata is Map &&
          adata['uatail'] != null &&
          adata['uatail'].toString().trim().isNotEmpty) {
        uatail = adata['uatail'].toString().trim();
      }
    }

    await _applyUserAgentLordsbattle(fullua: fullua, uatail: uatail);
  }

  Future<void> _applyUserAgentLordsbattle(
      {String? fullua, String? uatail}) async {
    if (lordsbattleWebViewController == null) return;

    if (_baseUserAgentLordsbattle == null ||
        _baseUserAgentLordsbattle!.trim().isEmpty) {
      try {
        final ua = await lordsbattleWebViewController!.evaluateJavascript(
          source: "navigator.userAgent",
        );
        if (ua is String && ua.trim().isNotEmpty) {
          _baseUserAgentLordsbattle = ua.trim();
          _currentUserAgentLordsbattle = _baseUserAgentLordsbattle!;
          lordsbattleDeviceProfileInstance.lordsbattleBaseUserAgent =
              _baseUserAgentLordsbattle;
          LordsbattleLoggerService().lordsbattleLogInfo(
              'Base User-Agent detected: $_baseUserAgentLordsbattle');
        }
      } catch (e) {
        LordsbattleLoggerService().lordsbattleLogWarn(
            'Failed to get base userAgent from JS: $e');
      }
    }

    if (_baseUserAgentLordsbattle == null ||
        _baseUserAgentLordsbattle!.trim().isEmpty) {
      LordsbattleLoggerService().lordsbattleLogWarn(
          'Base User-Agent is still null/empty, skip UA update');
      return;
    }

    LordsbattleLoggerService().lordsbattleLogInfo(
        'Server UA payload: fullua="$fullua", uatail="$uatail", base="$_baseUserAgentLordsbattle"');

    String newUa;
    if (fullua != null && fullua.trim().isNotEmpty) {
      newUa = fullua.trim();
    } else if (uatail != null && uatail.trim().isNotEmpty) {
      newUa = "${_baseUserAgentLordsbattle!}/${uatail.trim()}";
    } else {
      newUa = "${_baseUserAgentLordsbattle!}";
    }

    _serverUserAgentLordsbattle = newUa;
    LordsbattleLoggerService()
        .lordsbattleLogInfo('Server UA calculated and stored: $_serverUserAgentLordsbattle');
  }

  Future<void> _applyNormalUserAgentIfNeededLordsbattle() async {
    if (lordsbattleWebViewController == null) return;

    if (_isInGoogleAuthLordsbattle) {
      LordsbattleLoggerService().lordsbattleLogInfo(
          'Skip normal UA apply because we are in Google auth flow');
      return;
    }

    final String targetUaLordsbattle =
        _serverUserAgentLordsbattle ?? _baseUserAgentLordsbattle ?? 'random';

    if (targetUaLordsbattle == _currentUserAgentLordsbattle) {
      LordsbattleLoggerService().lordsbattleLogInfo(
          'Normal UA unchanged, keeping: $_currentUserAgentLordsbattle');
      return;
    }

    LordsbattleLoggerService().lordsbattleLogInfo(
        'Applying NORMAL WebView User-Agent: $targetUaLordsbattle');

    try {
      await lordsbattleWebViewController!.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUaLordsbattle),
      );
      _currentUserAgentLordsbattle = targetUaLordsbattle;
      print('[UA] NORMAL WEBVIEW USER AGENT: $_currentUserAgentLordsbattle');
    } catch (e) {
      LordsbattleLoggerService().lordsbattleLogError(
          'Error while setting normal User-Agent "$targetUaLordsbattle": $e');
    }
  }

  Future<void> printJsUserAgentLordsbattle() async {
    if (lordsbattleWebViewController == null) return;

    try {
      final ua = await lordsbattleWebViewController!.evaluateJavascript(
        source: "navigator.userAgent",
      );

      if (ua is String) {
        print('[JS UA] navigator.userAgent = $ua');
      } else {
        print('[JS UA] navigator.userAgent (non-string) = $ua');
      }
    } catch (e, st) {
      print('Error reading navigator.userAgent: $e\n$st');
    }
  }

  Future<void> debugPrintCurrentUserAgentLordsbattle() async {
    LordsbattleLoggerService().lordsbattleLogInfo(
        '[STATE UA] _currentUserAgent = $_currentUserAgentLordsbattle');
    await printJsUserAgentLordsbattle();
  }

  // ---------- Логика для Google ----------

  bool _isGoogleUrlLordsbattle(Uri uri) {
    final String fullLordsbattle = uri.toString().toLowerCase();
    return fullLordsbattle.contains('google');
  }

  Future<void> _addRandomToUserAgentForGoogleLordsbattle() async {
    if (lordsbattleWebViewController == null) return;

    const String targetUaLordsbattle = 'random';

    if (_currentUserAgentLordsbattle == targetUaLordsbattle &&
        _isInGoogleAuthLordsbattle) {
      LordsbattleLoggerService().lordsbattleLogInfo(
          'Already in Google flow with random UA, skip reapply');
      return;
    }

    LordsbattleLoggerService().lordsbattleLogInfo(
        'Switching User-Agent to RANDOM for Google URL: $targetUaLordsbattle');

    try {
      await lordsbattleWebViewController!.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUaLordsbattle),
      );
      _currentUserAgentLordsbattle = targetUaLordsbattle;
      _isInGoogleAuthLordsbattle = true;
      print('[UA] GOOGLE RANDOM USER AGENT: $_currentUserAgentLordsbattle');
    } catch (e) {
      LordsbattleLoggerService().lordsbattleLogError(
          'Error while setting RANDOM User-Agent for Google URL: $e');
    }
  }

  Future<void> _restoreUserAgentAfterGoogleIfNeededLordsbattle() async {
    if (!_isInGoogleAuthLordsbattle) {
      return;
    }
    LordsbattleLoggerService().lordsbattleLogInfo(
        'Restoring normal User-Agent after leaving Google URL');
    _isInGoogleAuthLordsbattle = false;
    await _applyNormalUserAgentIfNeededLordsbattle();
  }

  Future<void> lordsbattleLoadLoadedFlag() async {
    final SharedPreferences prefsLordsbattle =
    await SharedPreferences.getInstance();
    lordsbattleLoadedOnceSent =
        prefsLordsbattle.getBool(dressRetroLoadedOnceKey) ?? false;
  }

  Future<void> lordsbattleSaveLoadedFlag() async {
    final SharedPreferences prefsLordsbattle =
    await SharedPreferences.getInstance();
    await prefsLordsbattle.setBool(dressRetroLoadedOnceKey, true);
    lordsbattleLoadedOnceSent = true;
  }

  Future<void> lordsbattleLoadCachedDeep() async {
    try {
      final SharedPreferences prefsLordsbattle =
      await SharedPreferences.getInstance();
      final String? cachedLordsbattle =
      prefsLordsbattle.getString(dressRetroCachedDeepKey);
      if ((cachedLordsbattle ?? '').isNotEmpty) {
        lordsbattleDeepLinkFromPush = cachedLordsbattle;
      }
    } catch (_) {}
  }

  Future<void> lordsbattleSaveCachedDeep(String uri) async {
    try {
      final SharedPreferences prefsLordsbattle =
      await SharedPreferences.getInstance();
      await prefsLordsbattle.setString(dressRetroCachedDeepKey, uri);
    } catch (_) {}
  }

  Future<void> lordsbattleSendLoadedOnce({
    required String url,
    required int timestart,
  }) async {
    if (lordsbattleLoadedOnceSent) return;

    final int nowLordsbattle = DateTime.now().millisecondsSinceEpoch;

    await lordsbattlePostStat(
      event: 'Loaded',
      timeStart: timestart,
      timeFinish: nowLordsbattle,
      url: url,
      appSid: lordsbattleAnalyticsSpyInstance.lordsbattleAppsFlyerUid,
      firstPageLoadTs: lordsbattleFirstPageTimestamp,
    );

    await lordsbattleSaveLoadedFlag();
  }

  void lordsbattleBootHarbor() {
    lordsbattleStartWarmProgress();
    lordsbattleWireFcmHandlers();
    lordsbattleAnalyticsSpyInstance.lordsbattleStartTracking(
      onUpdate: () => setState(() {}),
    );
    lordsbattleBindNotificationTap();
    lordsbattlePrepareDeviceProfile();
  }

  // ====================== FCM ========================

  void lordsbattleWireFcmHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage messageLordsbattle) async {
      final dynamic linkLordsbattle = messageLordsbattle.data['uri'];
      if (linkLordsbattle != null) {
        final String uriLordsbattle = linkLordsbattle.toString();
        lordsbattleDeepLinkFromPush = uriLordsbattle;
        await lordsbattleSaveCachedDeep(uriLordsbattle);
      } else {
        lordsbattleResetHomeAfterDelay();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage messageLordsbattle) async {
      final dynamic linkLordsbattle = messageLordsbattle.data['uri'];
      if (linkLordsbattle != null) {
        final String uriLordsbattle = linkLordsbattle.toString();
        lordsbattleDeepLinkFromPush = uriLordsbattle;
        await lordsbattleSaveCachedDeep(uriLordsbattle);

        lordsbattleNavigateToUri(uriLordsbattle);

        await lordsbattlePushDeviceInfo();
        await lordsbattlePushAppsFlyerData();
      } else {
        lordsbattleResetHomeAfterDelay();
      }
    });
  }

  // ====================== Tap по пушу с native ============================

  void lordsbattleBindNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onNotificationTap') {
        final Map<String, dynamic> payloadLordsbattle =
        Map<String, dynamic>.from(call.arguments);
        final String? uriRawLordsbattle =
        payloadLordsbattle['uri']?.toString();

        if (uriRawLordsbattle != null &&
            uriRawLordsbattle.isNotEmpty &&
            !uriRawLordsbattle.contains('Нет URI')) {
          final String uriLordsbattle = uriRawLordsbattle;
          lordsbattleDeepLinkFromPush = uriLordsbattle;
          await lordsbattleSaveCachedDeep(uriLordsbattle);

          if (!context.mounted) return;

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext context) =>
                  LordsbattleTableView(uriLordsbattle),
            ),
                (Route<dynamic> route) => false,
          );

          await lordsbattlePushDeviceInfo();
          await lordsbattlePushAppsFlyerData();
        }
      }
    });
  }

  Future<void> lordsbattlePrepareDeviceProfile() async {
    try {
      await lordsbattleDeviceProfileInstance.lordsbattleInitialize();

      final FirebaseMessaging messagingLordsbattle = FirebaseMessaging.instance;
      final NotificationSettings settingsLordsbattle =
      await messagingLordsbattle.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      lordsbattleDeviceProfileInstance.lordsbattlePushEnabled =
          settingsLordsbattle.authorizationStatus ==
              AuthorizationStatus.authorized ||
              settingsLordsbattle.authorizationStatus ==
                  AuthorizationStatus.provisional;

      await lordsbattleLoadLoadedFlag();
      await lordsbattleLoadCachedDeep();

      lordsbattleBosunInstance = LordsbattleBosunViewModel(
        lordsbattleDeviceProfileInstance: lordsbattleDeviceProfileInstance,
        lordsbattleAnalyticsSpyInstance: lordsbattleAnalyticsSpyInstance,
      );

      lordsbattleCourier = LordsbattleCourierService(
        lordsbattleBosun: lordsbattleBosunInstance!,
        lordsbattleGetWebViewController: () => lordsbattleWebViewController,
      );
    } catch (error) {
      LordsbattleLoggerService()
          .lordsbattleLogError('prepareDeviceProfile fail: $error');
    }
  }

  void lordsbattleNavigateToUri(String link) async {
    try {
      await lordsbattleWebViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(link)),
      );
    } catch (error) {
      LordsbattleLoggerService()
          .lordsbattleLogError('navigate error: $error');
    }
  }

  void lordsbattleResetHomeAfterDelay() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      try {
        lordsbattleWebViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(lordsbattleHomeUrl)),
        );
      } catch (_) {}
    });
  }

  String? _resolveTokenForShipLordsbattle() {
    if (widget.lordsbattleSignal != null &&
        widget.lordsbattleSignal!.isNotEmpty) {
      return widget.lordsbattleSignal;
    }
    return null;
  }

  Future<void> _sendAllDataToPageTwiceLordsbattle() async {
    await lordsbattlePushDeviceInfo();

    Future<void>.delayed(const Duration(seconds: 6), () async {
      await lordsbattlePushDeviceInfo();
      await lordsbattlePushAppsFlyerData();
    });
  }

  Future<void> lordsbattlePushDeviceInfo() async {
    final String? tokenLordsbattle = _resolveTokenForShipLordsbattle();

    try {
      await lordsbattleCourier
          ?.lordsbattlePutDeviceToLocalStorage(tokenLordsbattle);
    } catch (error) {
      LordsbattleLoggerService()
          .lordsbattleLogError('pushDeviceInfo error: $error');
    }
  }

  Future<void> lordsbattlePushAppsFlyerData() async {
    final String? tokenLordsbattle = _resolveTokenForShipLordsbattle();

    try {
      await lordsbattleCourier?.lordsbattleSendRawToPage(
        tokenLordsbattle,
        deepLink: lordsbattleDeepLinkFromPush,
      );
    } catch (error) {
      LordsbattleLoggerService()
          .lordsbattleLogError('pushAppsFlyerData error: $error');
    }
  }

  void lordsbattleStartWarmProgress() {
    int tickLordsbattle = 0;
    lordsbattleWarmProgress = 0.0;

    lordsbattleWarmTimer =
        Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
          if (!mounted) return;

          setState(() {
            tickLordsbattle++;
            lordsbattleWarmProgress =
                tickLordsbattle / (lordsbattleWarmSeconds * 10);

            if (lordsbattleWarmProgress >= 1.0) {
              lordsbattleWarmProgress = 1.0;
              lordsbattleWarmTimer.cancel();
            }
          });
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      lordsbattleSleepAt = DateTime.now();
    }

    if (state == AppLifecycleState.resumed) {
      if (Platform.isIOS && lordsbattleSleepAt != null) {
        final DateTime nowLordsbattle = DateTime.now();
        final Duration driftLordsbattle =
        nowLordsbattle.difference(lordsbattleSleepAt!);

        if (driftLordsbattle > const Duration(minutes: 25)) {
          lordsbattleReboardHarbor();
        }
      }
      lordsbattleSleepAt = null;
    }
  }

  void lordsbattleReboardHarbor() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext context) =>
              LordsbattleHarbor(lordsbattleSignal: widget.lordsbattleSignal),
        ),
            (Route<dynamic> route) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    lordsbattleWarmTimer.cancel();
    super.dispose();
  }

  // ===================== Email / mailto =====================

  bool lordsbattleIsBareEmail(Uri uri) {
    final String schemeLordsbattle = uri.scheme;
    if (schemeLordsbattle.isNotEmpty) return false;
    final String rawLordsbattle = uri.toString();
    return rawLordsbattle.contains('@') && !rawLordsbattle.contains(' ');
  }

  Uri lordsbattleToMailto(Uri uri) {
    final String fullLordsbattle = uri.toString();
    final List<String> partsLordsbattle = fullLordsbattle.split('?');
    final String emailLordsbattle = partsLordsbattle.first;
    final Map<String, String> queryParamsLordsbattle =
    partsLordsbattle.length > 1
        ? Uri.splitQueryString(partsLordsbattle[1])
        : <String, String>{};

    return Uri(
      scheme: 'mailto',
      path: emailLordsbattle,
      queryParameters:
      queryParamsLordsbattle.isEmpty ? null : queryParamsLordsbattle,
    );
  }

  Future<bool> lordsbattleOpenMailExternal(Uri mailto) async {
    try {
      final String schemeLordsbattle = mailto.scheme.toLowerCase();
      final String pathLordsbattle = mailto.path.toLowerCase();

      LordsbattleLoggerService().lordsbattleLogInfo(
          'NcupOpenMailExternal: scheme=$schemeLordsbattle path=$pathLordsbattle uri=$mailto');

      if (schemeLordsbattle != 'mailto') {
        final bool ok = await launchUrl(
          mailto,
          mode: LaunchMode.externalApplication,
        );
        LordsbattleLoggerService().lordsbattleLogInfo(
            'NcupOpenMailExternal: non-mailto result=$ok');
        return ok;
      }

      final bool can = await canLaunchUrl(mailto);
      LordsbattleLoggerService()
          .lordsbattleLogInfo('NcupOpenMailExternal: canLaunchUrl(mailto) = $can');

      if (can) {
        final bool ok = await launchUrl(
          mailto,
          mode: LaunchMode.externalApplication,
        );
        LordsbattleLoggerService().lordsbattleLogInfo(
            'NcupOpenMailExternal: externalApplication result=$ok');
        if (ok) return true;
      }

      LordsbattleLoggerService().lordsbattleLogWarn(
          'NcupOpenMailExternal: no native handler for mailto, fallback to Gmail Web');
      final Uri gmailUriLordsbattle = lordsbattleGmailizeMailto(mailto);
      final bool webOk =
      await lordsbattleOpenWeb(gmailUriLordsbattle);
      LordsbattleLoggerService().lordsbattleLogInfo(
          'NcupOpenMailExternal: Gmail Web fallback result=$webOk');
      return webOk;
    } catch (e, st) {
      LordsbattleLoggerService().lordsbattleLogError(
          'NcupOpenMailExternal error: $e\n$st; url=$mailto');
      return false;
    }
  }

  Future<bool> lordsbattleOpenMailWeb(Uri mailto) async {
    final Uri gmailUriLordsbattle = lordsbattleGmailizeMailto(mailto);
    return lordsbattleOpenWeb(gmailUriLordsbattle);
  }

  Uri lordsbattleGmailizeMailto(Uri mailUri) {
    final Map<String, String> queryParamsLordsbattle =
        mailUri.queryParameters;

    final Map<String, String> paramsLordsbattle = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (mailUri.path.isNotEmpty) 'to': mailUri.path,
      if ((queryParamsLordsbattle['subject'] ?? '').isNotEmpty)
        'su': queryParamsLordsbattle['subject']!,
      if ((queryParamsLordsbattle['body'] ?? '').isNotEmpty)
        'body': queryParamsLordsbattle['body']!,
      if ((queryParamsLordsbattle['cc'] ?? '').isNotEmpty)
        'cc': queryParamsLordsbattle['cc']!,
      if ((queryParamsLordsbattle['bcc'] ?? '').isNotEmpty)
        'bcc': queryParamsLordsbattle['bcc']!,
    };

    return Uri.https('mail.google.com', '/mail/', paramsLordsbattle);
  }

  // =========================================================

  bool lordsbattleIsPlatformLink(Uri uri) {
    final String schemeLordsbattle = uri.scheme.toLowerCase();
    if (lordsbattleSpecialSchemes.contains(schemeLordsbattle)) {
      return true;
    }

    if (schemeLordsbattle == 'http' || schemeLordsbattle == 'https') {
      final String hostLordsbattle = uri.host.toLowerCase();

      if (lordsbattleExternalHosts.contains(hostLordsbattle)) {
        return true;
      }

      if (hostLordsbattle.endsWith('t.me')) return true;
      if (hostLordsbattle.endsWith('wa.me')) return true;
      if (hostLordsbattle.endsWith('m.me')) return true;
      if (hostLordsbattle.endsWith('signal.me')) return true;
      if (hostLordsbattle.endsWith('facebook.com')) return true;
      if (hostLordsbattle.endsWith('instagram.com')) return true;
      if (hostLordsbattle.endsWith('twitter.com')) return true;
      if (hostLordsbattle.endsWith('x.com')) return true;
    }

    return false;
  }

  String lordsbattleDigitsOnly(String source) =>
      source.replaceAll(RegExp(r'[^0-9+]'), '');

  Uri lordsbattleHttpizePlatformUri(Uri uri) {
    final String schemeLordsbattle = uri.scheme.toLowerCase();

    if (schemeLordsbattle == 'tg' || schemeLordsbattle == 'telegram') {
      final Map<String, String> qpLordsbattle = uri.queryParameters;
      final String? domainLordsbattle = qpLordsbattle['domain'];

      if (domainLordsbattle != null && domainLordsbattle.isNotEmpty) {
        return Uri.https(
          't.me',
          '/$domainLordsbattle',
          <String, String>{
            if (qpLordsbattle['start'] != null)
              'start': qpLordsbattle['start']!,
          },
        );
      }

      final String pathLordsbattle =
      uri.path.isNotEmpty ? uri.path : '';

      return Uri.https(
        't.me',
        '/$pathLordsbattle',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    if ((schemeLordsbattle == 'http' || schemeLordsbattle == 'https') &&
        uri.host.toLowerCase().endsWith('t.me')) {
      return uri;
    }

    if (schemeLordsbattle == 'viber') {
      return uri;
    }

    if (schemeLordsbattle == 'whatsapp') {
      final Map<String, String> qpLordsbattle = uri.queryParameters;
      final String? phoneLordsbattle = qpLordsbattle['phone'];
      final String? textLordsbattle = qpLordsbattle['text'];

      if (phoneLordsbattle != null && phoneLordsbattle.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${lordsbattleDigitsOnly(phoneLordsbattle)}',
          <String, String>{
            if (textLordsbattle != null && textLordsbattle.isNotEmpty)
              'text': textLordsbattle,
          },
        );
      }

      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (textLordsbattle != null && textLordsbattle.isNotEmpty)
            'text': textLordsbattle,
        },
      );
    }

    if ((schemeLordsbattle == 'http' || schemeLordsbattle == 'https') &&
        (uri.host.toLowerCase().endsWith('wa.me') ||
            uri.host.toLowerCase().endsWith('whatsapp.com'))) {
      return uri;
    }

    if (schemeLordsbattle == 'skype') {
      return uri;
    }

    if (schemeLordsbattle == 'fb-messenger') {
      final String pathLordsbattle =
      uri.pathSegments.isNotEmpty ? uri.pathSegments.join('/') : '';
      final Map<String, String> qpLordsbattle = uri.queryParameters;

      final String idLordsbattle =
          qpLordsbattle['id'] ?? qpLordsbattle['user'] ?? pathLordsbattle;

      if (idLordsbattle.isNotEmpty) {
        return Uri.https(
          'm.me',
          '/$idLordsbattle',
          uri.queryParameters.isEmpty ? null : uri.queryParameters,
        );
      }

      return Uri.https(
        'm.me',
        '/',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    if (schemeLordsbattle == 'sgnl') {
      final Map<String, String> qpLordsbattle = uri.queryParameters;
      final String? phoneLordsbattle = qpLordsbattle['phone'];
      final String? usernameLordsbattle = qpLordsbattle['username'];

      if (phoneLordsbattle != null && phoneLordsbattle.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#p/${lordsbattleDigitsOnly(phoneLordsbattle)}',
        );
      }

      if (usernameLordsbattle != null && usernameLordsbattle.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#u/$usernameLordsbattle',
        );
      }

      final String pathLordsbattle = uri.pathSegments.join('/');
      if (pathLordsbattle.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/$pathLordsbattle',
          uri.queryParameters.isEmpty ? null : uri.queryParameters,
        );
      }

      return uri;
    }

    if (schemeLordsbattle == 'tel') {
      return Uri.parse('tel:${lordsbattleDigitsOnly(uri.path)}');
    }

    if (schemeLordsbattle == 'mailto') {
      return uri;
    }

    if (schemeLordsbattle == 'bnl') {
      final String newPathLordsbattle =
      uri.path.isNotEmpty ? uri.path : '';
      return Uri.https(
        'bnl.com',
        '/$newPathLordsbattle',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    return uri;
  }

  Future<bool> lordsbattleOpenWeb(Uri uri) async {
    try {
      if (await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }

      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      try {
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> lordsbattleOpenExternal(Uri uri) async {
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      return false;
    }
  }

  void lordsbattleHandleServerSavedata(String savedata) async{
    print('onServerResponse savedata: $savedata');

    if(savedata=='false'){
      await SystemChrome.setPreferredOrientations(
        <DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );
    }
  }

  Color _parseHexColorLordsbattle(String hex) {
    String valueLordsbattle = hex.trim();
    if (valueLordsbattle.startsWith('#')) {
      valueLordsbattle = valueLordsbattle.substring(1);
    }
    if (valueLordsbattle.length == 6) {
      valueLordsbattle = 'FF$valueLordsbattle';
    }
    final intColorLordsbattle =
        int.tryParse(valueLordsbattle, radix: 16) ?? 0xFF000000;
    return Color(intColorLordsbattle);
  }

  Future<void> _updateAppDataInLocalStorageFromProfileLordsbattle() async {
    if (lordsbattleWebViewController == null) return;

    final String? tokenLordsbattle = _resolveTokenForShipLordsbattle();
    final Map<String, dynamic> mapLordsbattle =
    lordsbattleDeviceProfileInstance.lordsbattleToMap(
        fcmToken: tokenLordsbattle);

    LordsbattleLoggerService().lordsbattleLogInfo(
        'updateAppDataFromProfile: ${jsonEncode(mapLordsbattle)}');

    try {
      await lordsbattleWebViewController!.evaluateJavascript(
        source:
        "localStorage.setItem('app_data', JSON.stringify(${jsonEncode(mapLordsbattle)}));",
      );
    } catch (e, st) {
      LordsbattleLoggerService().lordsbattleLogError(
          'updateAppDataInLocalStorageFromProfile error: $e\n$st');
    }
  }

  void _updateExtraDataFromServerPayloadLordsbattle(
      Map<dynamic, dynamic> root) {
    try {
      final dynamic adataRaw = root['adata'];
      if (adataRaw is Map) {
        final Map adata = adataRaw;

        final dynamic buttonswlRaw = adata['buttonswl'];
        if (buttonswlRaw is List) {
          final List<String> listLordsbattle = buttonswlRaw
              .where((e) => e != null)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          setState(() {
            _buttonWhitelistLordsbattle = listLordsbattle;
          });
          LordsbattleLoggerService().lordsbattleLogInfo(
              'buttonswl updated: $_buttonWhitelistLordsbattle');
          _updateBackButtonVisibilityLordsbattle();
        }

        final dynamic savelsRaw = adata['savels'];
        if (savelsRaw is Map) {
          lordsbattleDeviceProfileInstance.lordsbattleSavels =
          Map<String, dynamic>.from(savelsRaw);
          LordsbattleLoggerService().lordsbattleLogInfo(
              'savels stored in profile: ${lordsbattleDeviceProfileInstance.lordsbattleSavels}');
          _updateAppDataInLocalStorageFromProfileLordsbattle();
        }
      }
    } catch (e, st) {
      LordsbattleLoggerService().lordsbattleLogError(
          'Error in _updateExtraDataFromServerPayload: $e\n$st');
    }
  }

  void _updateSafeAreaFromServerPayloadLordsbattle(
      Map<dynamic, dynamic> root) {
    LordsbattleLoggerService().lordsbattleLogInfo(
        'SAFEAREA RAW PAYLOAD: ${jsonEncode(root)}');

    bool? safeareaLordsbattle;
    String? bgLightHexLordsbattle;
    String? bgDarkHexLordsbattle;

    final dynamic content = root['content'];
    if (content is Map) {
      if (content['safearea'] != null) {
        final dynamic raw = content['safearea'];
        if (raw is bool) {
          safeareaLordsbattle = raw;
        } else if (raw is String) {
          final String v = raw.toLowerCase().trim();
          if (v == 'true' || v == '1' || v == 'yes') {
            safeareaLordsbattle = true;
          }
          if (v == 'false' || v == '0' || v == 'no') {
            safeareaLordsbattle = false;
          }
        } else if (raw is num) {
          safeareaLordsbattle = raw != 0;
        }
      }

      if (content['safearea_color'] != null &&
          content['safearea_color'].toString().trim().isNotEmpty) {
        bgLightHexLordsbattle = content['safearea_color'].toString().trim();
        bgDarkHexLordsbattle = bgLightHexLordsbattle;
      }
    }

    final dynamic adata = root['adata'];
    if (adata is Map) {
      if (safeareaLordsbattle == null && adata['safearea'] != null) {
        final dynamic raw = adata['safearea'];
        if (raw is bool) {
          safeareaLordsbattle = raw;
        } else if (raw is String) {
          final String v = raw.toLowerCase().trim();
          if (v == 'true' || v == '1' || v == 'yes') {
            safeareaLordsbattle = true;
          }
          if (v == 'false' || v == '0' || v == 'no') {
            safeareaLordsbattle = false;
          }
        } else if (raw is num) {
          safeareaLordsbattle = raw != 0;
        }
      }

      if (adata['bgsareaw'] != null &&
          adata['bgsareaw'].toString().trim().isNotEmpty) {
        bgLightHexLordsbattle = adata['bgsareaw'].toString().trim();
      }
      if (adata['bgsareab'] != null &&
          adata['bgsareab'].toString().trim().isNotEmpty) {
        bgDarkHexLordsbattle = adata['bgsareab'].toString().trim();
      }
    }

    if (safeareaLordsbattle == null && root['safearea'] != null) {
      final dynamic raw = root['safearea'];
      if (raw is bool) {
        safeareaLordsbattle = raw;
      } else if (raw is String) {
        final String v = raw.toLowerCase().trim();
        if (v == 'true' || v == '1' || v == 'yes') {
          safeareaLordsbattle = true;
        }
        if (v == 'false' || v == '0' || v == 'no') {
          safeareaLordsbattle = false;
        }
      } else if (raw is num) {
        safeareaLordsbattle = raw != 0;
      }
    }

    LordsbattleLoggerService().lordsbattleLogInfo(
        'SAFEAREA PARSED: enabled=$safeareaLordsbattle, light=$bgLightHexLordsbattle, dark=$bgDarkHexLordsbattle');

    if (safeareaLordsbattle == null) {
      return;
    }

    final Brightness platformBrightnessLordsbattle =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    String? chosenHexLordsbattle;
    if (platformBrightnessLordsbattle == Brightness.light) {
      chosenHexLordsbattle = bgLightHexLordsbattle ?? bgDarkHexLordsbattle;
    } else {
      chosenHexLordsbattle = bgDarkHexLordsbattle ?? bgLightHexLordsbattle;
    }

    final bool enabledLordsbattle = safeareaLordsbattle;
    Color backgroundLordsbattle =
    enabledLordsbattle ? const Color(0xFF1A1A22) : const Color(0xFF000000);

    if (enabledLordsbattle &&
        chosenHexLordsbattle != null &&
        chosenHexLordsbattle.isNotEmpty) {
      backgroundLordsbattle = _parseHexColorLordsbattle(chosenHexLordsbattle);
    }

    setState(() {
      _safeAreaEnabledLordsbattle = enabledLordsbattle;
      _safeAreaBackgroundColorLordsbattle = backgroundLordsbattle;
      lordsbattleDeviceProfileInstance.lordsbattleSafeAreaEnabled =
          enabledLordsbattle;
      lordsbattleDeviceProfileInstance.lordsbattleSafeAreaColor =
      enabledLordsbattle ? (chosenHexLordsbattle ?? '#1A1A22') : '';
    });

    LordsbattleLoggerService().lordsbattleLogInfo(
        'SAFEAREA STATE UPDATED: enabled=$_safeAreaEnabledLordsbattle, color=$_safeAreaBackgroundColorLordsbattle (brightness=$platformBrightnessLordsbattle)');
  }

  bool _matchesButtonWhitelistLordsbattle(String url) {
    if (url.isEmpty) return false;
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return false;
    }

    final String hostLordsbattle = uri.host.toLowerCase();
    final String fullLordsbattle = uri.toString();

    for (final String item in _buttonWhitelistLordsbattle) {
      final String trimmed = item.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        if (fullLordsbattle.startsWith(trimmed)) return true;
      } else {
        final String domainLordsbattle = trimmed.toLowerCase();
        if (hostLordsbattle == domainLordsbattle ||
            hostLordsbattle.endsWith('.$domainLordsbattle')) {
          return true;
        }
      }
    }

    return false;
  }

  Future<void> _updateBackButtonVisibilityLordsbattle() async {
    final String currentLordsbattle =
        _currentUrlLordsbattle ?? lordsbattleCurrentUrl;
    final bool shouldShowLordsbattle =
    _matchesButtonWhitelistLordsbattle(currentLordsbattle);
    if (shouldShowLordsbattle != _showBackButtonLordsbattle) {
      setState(() {
        _showBackButtonLordsbattle = shouldShowLordsbattle;
      });
    }
  }

  Future<void> _handleBackButtonPressedLordsbattle() async {
    if (lordsbattleWebViewController == null) return;
    try {
      if (await lordsbattleWebViewController!.canGoBack()) {
        await lordsbattleWebViewController!.goBack();
      } else {
        await lordsbattleWebViewController!.loadUrl(
          urlRequest: URLRequest(url: WebUri(lordsbattleHomeUrl)),
        );
      }
    } catch (e, st) {
      LordsbattleLoggerService()
          .lordsbattleLogError('Error on back button pressed: $e\n$st');
    }
  }






  @override
  Widget build(BuildContext context) {
    lordsbattleBindNotificationTap();

    final Color bgColorLordsbattle = _safeAreaEnabledLordsbattle
        ? _safeAreaBackgroundColorLordsbattle
        : Colors.black;

    final Widget warmLoaderLordsbattle =
    const LordsbattleSwordsLoader();

    final Widget webViewLordsbattle = Stack(
      children: <Widget>[
        if (lordsbattleCoverVisible)
          warmLoaderLordsbattle
        else
          Container(
            color: bgColorLordsbattle,
            child: Stack(
              children: <Widget>[
                InAppWebView(
                  key: ValueKey<int>(lordsbattleWebViewKeyCounter),
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

                    transparentBackground: true,
                  ),
                  initialUrlRequest: URLRequest(
                    url: WebUri(lordsbattleHomeUrl),
                  ),
                  onWebViewCreated:
                      (InAppWebViewController controller) async {
                    lordsbattleWebViewController = controller;
                    _currentUrlLordsbattle = lordsbattleHomeUrl;

                    lordsbattleBosunInstance ??= LordsbattleBosunViewModel(
                      lordsbattleDeviceProfileInstance:
                      lordsbattleDeviceProfileInstance,
                      lordsbattleAnalyticsSpyInstance:
                      lordsbattleAnalyticsSpyInstance,
                    );

                    lordsbattleCourier ??= LordsbattleCourierService(
                      lordsbattleBosun: lordsbattleBosunInstance!,
                      lordsbattleGetWebViewController: () =>
                      lordsbattleWebViewController,
                    );

                    try {
                      final ua = await controller.evaluateJavascript(
                        source: "navigator.userAgent",
                      );
                      if (ua is String && ua.trim().isNotEmpty) {
                        _baseUserAgentLordsbattle = ua.trim();
                        _currentUserAgentLordsbattle =
                        _baseUserAgentLordsbattle!;
                        lordsbattleDeviceProfileInstance
                            .lordsbattleBaseUserAgent =
                            _baseUserAgentLordsbattle;
                        LordsbattleLoggerService().lordsbattleLogInfo(
                            'Initial WebView User-Agent: $_baseUserAgentLordsbattle');
                        print(
                            '[UA] INITIAL WEBVIEW USER AGENT: $_baseUserAgentLordsbattle');
                      }
                    } catch (e) {
                      LordsbattleLoggerService().lordsbattleLogWarn(
                          'Failed to read navigator.userAgent on create: $e');
                    }

                    await _applyNormalUserAgentIfNeededLordsbattle();

                    controller.addJavaScriptHandler(
                      handlerName: 'onServerResponse',
                      callback: (List<dynamic> args) async {
                        if (args.isEmpty) return null;

                        print("Get Data server $args");

                        try {
                          dynamic first = args[0];

                          if (first is List && first.isNotEmpty) {
                            first = first.first;
                          }

                          if (first is Map) {
                            final Map<dynamic, dynamic> root = first;

                            if (root['savedata'] != null) {
                              lordsbattleHandleServerSavedata(
                                  root['savedata'].toString());
                            }

                            _updateExtraDataFromServerPayloadLordsbattle(
                                root);
                            _updateSafeAreaFromServerPayloadLordsbattle(
                                root);
                            await _updateUserAgentFromServerPayloadLordsbattle(
                                root);

                            await _applyNormalUserAgentIfNeededLordsbattle();

                            try {
                              if (!_loadedJsExecutedOnceLordsbattle) {
                                final dynamic adataRaw = root['adata'];
                                if (adataRaw is Map) {
                                  final Map adata = adataRaw;
                                  final dynamic loadedJsRaw =
                                  adata['loadedjs'];
                                  if (loadedJsRaw != null) {
                                    final String loadedJs =
                                    loadedJsRaw.toString().trim();
                                    if (loadedJs.isNotEmpty) {
                                      _pendingLoadedJsLordsbattle =
                                          loadedJs;
                                      LordsbattleLoggerService()
                                          .lordsbattleLogInfo(
                                        'loadedjs received, will execute ONCE after 6 seconds',
                                      );

                                      Future<void>.delayed(
                                        const Duration(seconds: 6),
                                            () async {
                                          if (!mounted) return;
                                          if (_loadedJsExecutedOnceLordsbattle) {
                                            LordsbattleLoggerService()
                                                .lordsbattleLogInfo(
                                                'Skipping loadedjs: already executed once');
                                            return;
                                          }
                                          if (lordsbattleWebViewController ==
                                              null) {
                                            LordsbattleLoggerService()
                                                .lordsbattleLogWarn(
                                                'Skipping loadedjs execution: controller is null');
                                            return;
                                          }
                                          final String? jsToRunLordsbattle =
                                              _pendingLoadedJsLordsbattle;
                                          if (jsToRunLordsbattle == null ||
                                              jsToRunLordsbattle.isEmpty) {
                                            return;
                                          }
                                          LordsbattleLoggerService()
                                              .lordsbattleLogInfo(
                                              'Executing loadedjs from server payload (ONCE, delayed 6s)');
                                          try {
                                            await lordsbattleWebViewController
                                                ?.evaluateJavascript(
                                              source: jsToRunLordsbattle,
                                            );
                                            _loadedJsExecutedOnceLordsbattle =
                                            true;
                                          } catch (e, st) {
                                            LordsbattleLoggerService()
                                                .lordsbattleLogError(
                                                'Error executing delayed loadedjs: $e\n$st');
                                          }
                                        },
                                      );
                                    }
                                  }
                                }
                              } else {
                                LordsbattleLoggerService().lordsbattleLogInfo(
                                    'loadedjs ignored: already executed once earlier');
                              }
                            } catch (e, st) {
                              LordsbattleLoggerService().lordsbattleLogError(
                                  'Error scheduling loadedjs: $e\n$st');
                            }
                          }
                        } catch (e, st) {
                          print('onServerResponse error: $e\n$st');
                        }

                        return null;
                      },
                    );
                  },
                  onPermissionRequest: (controller, request) async {
                    return PermissionResponse(
                      resources: request.resources,
                      action: PermissionResponseAction.GRANT,
                    );
                  },
                  onLoadStart:
                      (InAppWebViewController controller, Uri? uri) async {
                    setState(() {
                      lordsbattleStartLoadTimestamp =
                          DateTime.now().millisecondsSinceEpoch;
                    });

                    final Uri? viewUriLordsbattle = uri;
                    if (viewUriLordsbattle != null) {
                      _currentUrlLordsbattle =
                          viewUriLordsbattle.toString();

                      if (_isGoogleUrlLordsbattle(viewUriLordsbattle)) {
                        await _addRandomToUserAgentForGoogleLordsbattle();
                      } else {
                        await _restoreUserAgentAfterGoogleIfNeededLordsbattle();
                        await _applyNormalUserAgentIfNeededLordsbattle();
                      }

                      await _updateBackButtonVisibilityLordsbattle();

                      if (lordsbattleIsBareEmail(viewUriLordsbattle)) {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        final Uri mailtoLordsbattle =
                        lordsbattleToMailto(viewUriLordsbattle);
                        await lordsbattleOpenMailExternal(
                            mailtoLordsbattle);
                        return;
                      }

                      final String schemeLordsbattle =
                      viewUriLordsbattle.scheme.toLowerCase();

                      if (schemeLordsbattle == 'mailto') {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        await lordsbattleOpenMailExternal(
                            viewUriLordsbattle);
                        return;
                      }

                      if (lordsbattleIsBankScheme(viewUriLordsbattle)) {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        await lordsbattleOpenBank(viewUriLordsbattle);
                        return;
                      }

                      if (schemeLordsbattle != 'http' &&
                          schemeLordsbattle != 'https') {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                      }
                    }
                  },
                  onLoadError: (
                      InAppWebViewController controller,
                      Uri? uri,
                      int code,
                      String message,
                      ) async {
                    final int nowLordsbattle =
                        DateTime.now().millisecondsSinceEpoch;
                    final String eventLordsbattle =
                        'InAppWebViewError(code=$code, message=$message)';

                    await lordsbattlePostStat(
                      event: eventLordsbattle,
                      timeStart: nowLordsbattle,
                      timeFinish: nowLordsbattle,
                      url: uri?.toString() ?? '',
                      appSid:
                      lordsbattleAnalyticsSpyInstance.lordsbattleAppsFlyerUid,
                      firstPageLoadTs: lordsbattleFirstPageTimestamp,
                    );
                  },
                  onReceivedError: (
                      InAppWebViewController controller,
                      WebResourceRequest request,
                      WebResourceError error,
                      ) async {
                    final int nowLordsbattle =
                        DateTime.now().millisecondsSinceEpoch;
                    final String descriptionLordsbattle =
                    (error.description ?? '').toString();
                    final String eventLordsbattle =
                        'WebResourceError(code=$error, message=$descriptionLordsbattle)';

                    await lordsbattlePostStat(
                      event: eventLordsbattle,
                      timeStart: nowLordsbattle,
                      timeFinish: nowLordsbattle,
                      url: request.url?.toString() ?? '',
                      appSid:
                      lordsbattleAnalyticsSpyInstance.lordsbattleAppsFlyerUid,
                      firstPageLoadTs: lordsbattleFirstPageTimestamp,
                    );
                  },
                  onLoadStop:
                      (InAppWebViewController controller, Uri? uri) async {
                    setState(() {
                      lordsbattleCurrentUrl = uri.toString();
                      _currentUrlLordsbattle = lordsbattleCurrentUrl;
                    });

                    if (uri != null && !_isGoogleUrlLordsbattle(uri)) {
                      await _restoreUserAgentAfterGoogleIfNeededLordsbattle();
                      await _applyNormalUserAgentIfNeededLordsbattle();
                    }

                    await debugPrintCurrentUserAgentLordsbattle();

                    await _sendAllDataToPageTwiceLordsbattle();
                    await _updateBackButtonVisibilityLordsbattle();

                    Future<void>.delayed(
                      const Duration(seconds: 20),
                          () {
                        lordsbattleSendLoadedOnce(
                          url: lordsbattleCurrentUrl.toString(),
                          timestart: lordsbattleStartLoadTimestamp,
                        );
                      },
                    );
                  },
                  shouldOverrideUrlLoading:
                      (InAppWebViewController controller,
                      NavigationAction action) async {
                    final Uri? uriLordsbattle = action.request.url;
                    if (uriLordsbattle == null) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    _currentUrlLordsbattle = uriLordsbattle.toString();
                    await _updateBackButtonVisibilityLordsbattle();

                    if (_isGoogleUrlLordsbattle(uriLordsbattle)) {
                      await _addRandomToUserAgentForGoogleLordsbattle();
                    } else {
                      await _restoreUserAgentAfterGoogleIfNeededLordsbattle();
                      await _applyNormalUserAgentIfNeededLordsbattle();
                    }

                    if (lordsbattleIsBareEmail(uriLordsbattle)) {
                      final Uri mailtoLordsbattle =
                      lordsbattleToMailto(uriLordsbattle);
                      await lordsbattleOpenMailExternal(mailtoLordsbattle);
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String schemeLordsbattle =
                    uriLordsbattle.scheme.toLowerCase();

                    if (schemeLordsbattle == 'mailto') {
                      await lordsbattleOpenMailExternal(uriLordsbattle);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (lordsbattleIsBankScheme(uriLordsbattle)) {
                      await lordsbattleOpenBank(uriLordsbattle);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if ((schemeLordsbattle == 'http' ||
                        schemeLordsbattle == 'https') &&
                        lordsbattleIsBankDomain(uriLordsbattle)) {
                      await lordsbattleOpenBank(uriLordsbattle);

                      if (_isAdobeRedirectLordsbattle(uriLordsbattle)) {
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  LordsbattleAdobeRedirectScreen(uri: uriLordsbattle),
                            ),
                          );
                        }
                        return NavigationActionPolicy.CANCEL;
                      }
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (schemeLordsbattle == 'tel') {
                      await launchUrl(
                        uriLordsbattle,
                        mode: LaunchMode.externalApplication,
                      );
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String hostLordsbattle =
                    uriLordsbattle.host.toLowerCase();
                    final bool isSocialLordsbattle =
                        hostLordsbattle.endsWith('facebook.com') ||
                            hostLordsbattle.endsWith('instagram.com') ||
                            hostLordsbattle.endsWith('twitter.com') ||
                            hostLordsbattle.endsWith('x.com');

                    if (isSocialLordsbattle) {
                      await lordsbattleOpenExternal(uriLordsbattle);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (lordsbattleIsPlatformLink(uriLordsbattle)) {
                      final Uri webUriLordsbattle =
                      lordsbattleHttpizePlatformUri(uriLordsbattle);
                      await lordsbattleOpenExternal(webUriLordsbattle);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (schemeLordsbattle != 'http' &&
                        schemeLordsbattle != 'https') {
                      return NavigationActionPolicy.CANCEL;
                    }

                    return NavigationActionPolicy.ALLOW;
                  },
                  onCreateWindow:
                      (InAppWebViewController controller,
                      CreateWindowAction request) async {
                    final Uri? uriLordsbattle = request.request.url;
                    if (uriLordsbattle == null) {
                      return false;
                    }

                    _currentUrlLordsbattle = uriLordsbattle.toString();
                    await _updateBackButtonVisibilityLordsbattle();

                    if (_isGoogleUrlLordsbattle(uriLordsbattle)) {
                      await _addRandomToUserAgentForGoogleLordsbattle();
                    } else {
                      await _restoreUserAgentAfterGoogleIfNeededLordsbattle();
                      await _applyNormalUserAgentIfNeededLordsbattle();
                    }

                    if (lordsbattleIsBankScheme(uriLordsbattle) ||
                        ((uriLordsbattle.scheme == 'http' ||
                            uriLordsbattle.scheme == 'https') &&
                            lordsbattleIsBankDomain(uriLordsbattle))) {
                      await lordsbattleOpenBank(uriLordsbattle);
                      return false;
                    }

                    if (lordsbattleIsBareEmail(uriLordsbattle)) {
                      final Uri mailtoLordsbattle =
                      lordsbattleToMailto(uriLordsbattle);
                      await lordsbattleOpenMailExternal(mailtoLordsbattle);
                      return false;
                    }

                    final String schemeLordsbattle =
                    uriLordsbattle.scheme.toLowerCase();

                    if (schemeLordsbattle == 'mailto') {
                      await lordsbattleOpenMailExternal(uriLordsbattle);
                      return false;
                    }

                    if (schemeLordsbattle == 'tel') {
                      await launchUrl(
                        uriLordsbattle,
                        mode: LaunchMode.externalApplication,
                      );
                      return false;
                    }

                    final String hostLordsbattle =
                    uriLordsbattle.host.toLowerCase();
                    final bool isSocialLordsbattle =
                        hostLordsbattle.endsWith('facebook.com') ||
                            hostLordsbattle.endsWith('instagram.com') ||
                            hostLordsbattle.endsWith('twitter.com') ||
                            hostLordsbattle.endsWith('x.com');

                    if (isSocialLordsbattle) {
                      await lordsbattleOpenExternal(uriLordsbattle);
                      return false;
                    }

                    if (lordsbattleIsPlatformLink(uriLordsbattle)) {
                      final Uri webUriLordsbattle =
                      lordsbattleHttpizePlatformUri(uriLordsbattle);
                      await lordsbattleOpenExternal(webUriLordsbattle);
                      return false;
                    }

                    if (schemeLordsbattle == 'http' ||
                        schemeLordsbattle == 'https') {
                      controller.loadUrl(
                        urlRequest: URLRequest(
                          url: WebUri(uriLordsbattle.toString()),
                        ),
                      );
                    }

                    return false;
                  },
                  onDownloadStartRequest:
                      (InAppWebViewController controller,
                      DownloadStartRequest req) async {
                    await lordsbattleOpenExternal(req.url);
                  },
                ),
                Visibility(
                  visible: !lordsbattleVeilVisible,
                  child: warmLoaderLordsbattle,
                ),
              ],
            ),
          ),
      ],
    );

    final Widget topBackBarLordsbattle =
    (_safeAreaEnabledLordsbattle && _showBackButtonLordsbattle)
        ? Container(
      color: _safeAreaBackgroundColorLordsbattle,
      padding: const EdgeInsets.only(left: 4, right: 4),
      height: 48,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _handleBackButtonPressedLordsbattle,
          ),
        ],
      ),
    )
        : const SizedBox.shrink();

    final Widget fullScreenLordsbattle = Column(
      children: [
        topBackBarLordsbattle,
        Expanded(child: webViewLordsbattle),
      ],
    );

    final Widget bodyLordsbattle = _safeAreaEnabledLordsbattle
        ? SafeArea(
      child: fullScreenLordsbattle,
    )
        : fullScreenLordsbattle;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: bgColorLordsbattle,
        body: SizedBox.expand(
          child: ColoredBox(
            color: bgColorLordsbattle,
            child: bodyLordsbattle,
          ),
        ),
      ),
    );
  }

  bool _isAdobeRedirectLordsbattle(Uri uri) {
    final String hostLordsbattle = uri.host.toLowerCase();
    return hostLordsbattle == 'c00.adobe.com';
  }
}

// ---------------------- Экран для c00.adobe.com ----------------------

class LordsbattleAdobeRedirectScreen extends StatelessWidget {
  final Uri uri;

  const LordsbattleAdobeRedirectScreen({super.key, required this.uri});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF111111),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Go to the App Store and download the app.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
              SizedBox(height: 24),
              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}



// ============================================================================
// main()
// ============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(lordsbattleFcmBackgroundHandler);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  tz_data.initializeTimeZones();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LordsbattleHall(),
    ),
  );
}