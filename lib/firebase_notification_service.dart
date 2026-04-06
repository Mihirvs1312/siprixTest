import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:siprix_voip_sdk/accounts_model.dart';
import 'package:siprix_voip_sdk/logs_model.dart';
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';

import 'firebase_options.dart';

const String kCallChannelId = 'incoming_call_channel';
const String kCallChannelName = 'Incoming Calls';
const String kCallChannelDesc = 'Notifications for incoming VoIP calls';

const String kHighChannelId = 'high_importance_channel';
const String kHighChannelName = 'High Importance Notifications';
const String kHighChannelDesc = 'Channel for important notifications';

const int kCallNotificationId = 9999;

const String kActionAcceptCall = 'ACCEPT_CALL';
const String kActionRejectCall = 'REJECT_CALL';

/// Channel id for full-screen call alerts (must match [showFullScreenNotification]).
const String kFullScreenCallChannelId = 'call_channel';


Future<void> setupAndroidCallNotificationChannel() async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  final plugin = FlutterLocalNotificationsPlugin();
  const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
    kFullScreenCallChannelId,
    kCallChannelName,
    description: kCallChannelDesc,
    importance: Importance.max,
  );

  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(callChannel);
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Already initialized by google-services.json / native plugin
  }

  debugPrint('Background FCM message: ${message.messageId} data: ${message.data}');

  final data = message.data;
  final bool isCallPush =
      data.containsKey('type') && data['type'] == 'incoming_call';

  // if (isCallPush) {
    await _handleBackgroundCallPush(data);
    await showFullScreenNotification(message);
  // } else if (message.notification != null) {
    // await showFullScreenNotification(message);
  // }
}

/// Shows a high-priority full-screen intent notification. Safe to call from the
/// FCM background isolate (initializes its own [FlutterLocalNotificationsPlugin]).
Future<void> showFullScreenNotification(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));

  const channel = AndroidNotificationChannel(
    kFullScreenCallChannelId,
    kCallChannelName,
    description: kCallChannelDesc,
    importance: Importance.max,
  );
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  final title = message.data['title']?.toString() ??
      message.notification?.title ??
      'Incoming call';
  final body = message.data['body']?.toString() ??
      message.notification?.body ??
      '';

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    kFullScreenCallChannelId,
    kCallChannelName,
    channelDescription: kCallChannelDesc,
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.call,
  );

  const NotificationDetails platformDetails =
      NotificationDetails(android: androidDetails);

  await plugin.show(
    0,
    title,
    body,
    platformDetails,
  );
}

Future<void> _handleBackgroundCallPush(Map<String, dynamic> data) async {
  debugPrint('Background call push received: $data');

  try {
    final ini = InitData()
      ..license = ''
      ..logLevelFile = LogLevel.debug
      ..logLevelIde = LogLevel.info
      ..useDnsSrv = false;

    await SiprixVoipSdk().initialize(ini);

    final prefs = await SharedPreferences.getInstance();
    final accJsonStr = prefs.getString('sipAccount') ?? '';
    if (accJsonStr.isNotEmpty) {
      final acc = AccountModel.fromJson(jsonDecode(accJsonStr));
      await SiprixVoipSdk().addAccount(acc);
      debugPrint('Background: Siprix initialized and account loaded for push wakeup');
    }
  } catch (e) {
    debugPrint('Background Siprix init error: $e');
  }
}

class FirebaseNotificationService {
  FirebaseNotificationService._();
  static final FirebaseNotificationService instance =
      FirebaseNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  void Function(Map<String, dynamic> data)? onNotificationTapped;
  void Function(Map<String, dynamic> data)? onCallAccepted;
  void Function(Map<String, dynamic> data)? onCallRejected;
  void Function(Map<String, dynamic> data)? onIncomingCallPush;

  // ---- Initialisation -------------------------------------------------------

  Future<void> initialize() async {
    await _requestPermission();
    await _initLocalNotifications();
    await _configureFCMListeners();
    await _fetchToken();
  }

  // ---- Permission -----------------------------------------------------------

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('FCM auth status: ${settings.authorizationStatus}');
  }

  // ---- Local Notifications --------------------------------------------------

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );

    await _ensureCallChannelCreated();

    const highChannel = AndroidNotificationChannel(
      kHighChannelId,
      kHighChannelName,
      description: kHighChannelDesc,
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(highChannel);
  }

  Future<void> _ensureCallChannelCreated() async {
    const callChannel = AndroidNotificationChannel(
      kCallChannelId,
      kCallChannelName,
      description: kCallChannelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(callChannel);
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(
      NotificationResponse response) {
    debugPrint(
        'Background notification action: ${response.actionId} payload: ${response.payload}');
    // Actions from killed state are handled when the app relaunches via
    // getInitialMessage / onMessageOpenedApp.
  }

  void _onLocalNotificationTapped(NotificationResponse response) {
    final String? payload = response.payload;
    Map<String, dynamic> data = {};
    if (payload != null) {
      try {
        data = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (response.actionId == kActionAcceptCall) {
      onCallAccepted?.call(data);
    } else if (response.actionId == kActionRejectCall) {
      onCallRejected?.call(data);
      cancelCallNotification();
    } else {
      onNotificationTapped?.call(data);
    }
  }

  // ---- FCM Listeners --------------------------------------------------------

  Future<void> _configureFCMListeners() async {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground message: ${message.messageId}');

      final data = message.data;
      final bool isCallPush =
          data.containsKey('type') && data['type'] == 'incoming_call';

      if (isCallPush) {
        onIncomingCallPush?.call(data);
        showIncomingCallNotification(
          callerName: data['caller_name'] ?? data['from'] ?? 'Unknown',
          callerNumber:
              data['caller_number'] ?? data['from_number'] ?? '',
          callPayload: data,
        );
      } else {
        showLocalNotification(message);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification opened app: ${message.messageId}');
      final data = message.data;
      final bool isCallPush =
          data.containsKey('type') && data['type'] == 'incoming_call';

      if (isCallPush) {
        onCallAccepted?.call(data);
      } else {
        onNotificationTapped?.call(data);
      }
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App opened from terminated via notification');
      final data = initialMessage.data;
      final bool isCallPush =
          data.containsKey('type') && data['type'] == 'incoming_call';

      if (isCallPush) {
        onCallAccepted?.call(data);
      } else {
        onNotificationTapped?.call(data);
      }
    }
  }

  // ---- Token ----------------------------------------------------------------

  Future<void> _fetchToken() async {
    try {
      _fcmToken = await _messaging.getToken();
      debugPrint('FCM Token: $_fcmToken');
    } catch (e) {
      debugPrint('Failed to get FCM token: $e');
    }

    _messaging.onTokenRefresh.listen((newToken) {
      _fcmToken = newToken;
      debugPrint('FCM Token refreshed: $newToken');
    });
  }

  // ---- Incoming Call Notification -------------------------------------------

  Future<void> showIncomingCallNotification({
    required String callerName,
    required String callerNumber,
    required Map<String, dynamic> callPayload,
  }) async {
    final String title = 'Incoming Call';
    final String body =
        callerNumber.isNotEmpty ? '$callerName ($callerNumber)' : callerName;

    final androidDetails = AndroidNotificationDetails(
      kCallChannelId,
      kCallChannelName,
      channelDescription: kCallChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      playSound: true,
      enableVibration: true,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          kActionAcceptCall,
          'Accept',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          kActionRejectCall,
          'Reject',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      kCallNotificationId,
      title,
      body,
      details,
      payload: jsonEncode(callPayload),
    );
  }

  Future<void> cancelCallNotification() async {
    await _localNotifications.cancel(kCallNotificationId);
  }

  // ---- Generic Notification -------------------------------------------------

  Future<void> showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      kHighChannelId,
      kHighChannelName,
      channelDescription: kHighChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  // ---- Topic Subscription ---------------------------------------------------

  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
    debugPrint('Subscribed to topic: $topic');
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
    debugPrint('Unsubscribed from topic: $topic');
  }
}
