import 'dart:convert';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/notifications/domain/repositories/notifications_repository.dart';

typedef NotificationTapHandler = void Function(Map<String, dynamic> data);

class NotificationService {
  final NotificationsRepository repository;

  NotificationTapHandler? _onTap;

  /// A tap that arrived before [onTap] was wired (e.g. a cold-start invite tap
  /// routed via [FirebaseMessaging.getInitialMessage] during the auth flow,
  /// which runs before `MyApp` assigns [onTap]). Drained the moment a handler
  /// is assigned, so the tap is never lost.
  Map<String, dynamic>? _pendingTap;

  NotificationTapHandler? get onTap => _onTap;

  set onTap(NotificationTapHandler? handler) {
    _onTap = handler;
    final pending = _pendingTap;
    if (handler != null && pending != null) {
      _pendingTap = null;
      handler(pending);
    }
  }

  /// Route a tap immediately if a handler is wired, otherwise buffer it until
  /// one is assigned. Never drops the tap.
  void _dispatchTap(Map<String, dynamic> data) {
    final handler = _onTap;
    if (handler != null) {
      handler(data);
    } else {
      _pendingTap = data;
    }
  }

  bool _initialized = false;
  String? _registeredToken;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenRefreshSub;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'soplay_default',
    'SoPlay bildirishnomalari',
    description: 'Asosiy bildirishnomalar kanali',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  NotificationService({required this.repository});

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      _initialized = true;
      return;
    }
    // Push is Android-only here, but the LOCAL plugin is what schedules airing
    // reminders — so iOS initialises it even though it never registers for FCM.
    if (Platform.isAndroid && Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    tz.initializeTimeZones();
    // Scheduling is done in the device's own zone: an airing time converted to
    // UTC and back through the wrong zone fires hours out.
    tz.setLocalLocation(tz.getLocation(await _deviceTimeZone()));

    await _local.initialize(
      InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: const DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (resp) {
        final payload = _decodePayload(resp.payload);
        if (payload != null) _dispatchTap(payload);
      },
    );
    final androidImpl = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_channel);
    await androidImpl?.createNotificationChannel(_airingChannel);
    _initialized = true;
  }

  /// The zone the phone is actually in.
  ///
  /// Falls back to UTC rather than throwing: a reminder in the wrong zone is
  /// bad, but a notification service that fails to start is worse.
  Future<String> _deviceTimeZone() async {
    try {
      return await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      return 'UTC';
    }
  }

  /// Reminders for episodes about to air.
  ///
  /// Its own channel so a person can silence airing reminders without losing
  /// the notifications that matter to their account.
  static const AndroidNotificationChannel _airingChannel =
      AndroidNotificationChannel(
    'sozo_airing',
    'Airing reminders',
    description: 'Fires shortly before an episode you follow goes out',
    importance: Importance.defaultImportance,
  );

  /// Schedules one reminder. Ids are the caller's, so it can replace its own.
  ///
  /// Inexact on purpose: exact alarms need a special permission on Android 12+
  /// that a user has to grant by hand, and "a few minutes either side of the
  /// episode" is what this is for anyway.
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    await ensureInitialized();
    if (!Platform.isAndroid && !Platform.isIOS) return;
    // A reminder for a moment that has passed would fire immediately.
    if (!when.isAfter(DateTime.now())) return;

    await _local.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _airingChannel.id,
          _airingChannel.name,
          channelDescription: _airingChannel.description,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload == null ? null : jsonEncode(payload),
    );
  }

  Future<void> cancelScheduled(int id) async {
    if (!_initialized) return;
    await _local.cancel(id);
  }

  /// Every id in [ids]. Used to clear a whole batch before scheduling the next.
  Future<void> cancelAllScheduled(Iterable<int> ids) async {
    if (!_initialized) return;
    for (final id in ids) {
      await _local.cancel(id);
    }
  }

  Future<void> setup() async {
    if (!Platform.isAndroid) return;
    await ensureInitialized();

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _registerToken(token);
    }

    _tokenRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      _registerToken,
    );

    _foregroundSub ??= FirebaseMessaging.onMessage.listen(_showLocal);

    _openedSub ??= FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _dispatchTap(_normalizeData(msg.data));
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _dispatchTap(_normalizeData(initial.data));
    }
  }

  Future<void> unregister() async {
    if (!Platform.isAndroid) return;
    final token = _registeredToken ??
        await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      await repository.unregisterFcmToken(token);
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _registeredToken = null;
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _foregroundSub = null;
    _openedSub = null;
    _tokenRefreshSub = null;
  }

  Future<void> _registerToken(String token) async {
    if (_registeredToken == token) return;
    final platform = Platform.isIOS ? 'ios' : 'android';
    final result = await repository.registerFcmToken(
      token: token,
      platform: platform,
    );
    if (result is Success) {
      _registeredToken = token;
    } else if (kDebugMode) {
      debugPrint('[FCM] register failed');
    }
  }

  /// Show a local notification not tied to FCM (e.g. tracker "new episode").
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (!Platform.isAndroid) return;
    await ensureInitialized();
    await _local.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: (data == null || data.isEmpty) ? null : _encodePayload(data),
    );
  }

  Future<void> _showLocal(RemoteMessage msg) async {
    final n = msg.notification;
    if (n == null) return;
    final data = _normalizeData(msg.data);
    await _local.show(
      n.hashCode,
      n.title ?? 'SoPlay',
      n.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: _encodePayload(data),
    );
  }

  Map<String, dynamic> _normalizeData(Map<String, dynamic> data) {
    return data.map((k, v) => MapEntry(k.toString(), v));
  }

  String? _encodePayload(Map<String, dynamic> data) {
    if (data.isEmpty) return null;
    final entries = data.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}')
        .join('&');
    return entries;
  }

  Map<String, dynamic>? _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final out = <String, dynamic>{};
    for (final part in payload.split('&')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      out[Uri.decodeComponent(part.substring(0, i))] =
          Uri.decodeComponent(part.substring(i + 1));
    }
    return out;
  }
}
