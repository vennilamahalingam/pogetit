import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

/// Error with a message that can be shown to the user as-is.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

/// Talks to the FastAPI backend. Every call carries the Firebase ID token.
class Api {
  final _client = http.Client();

  Future<Map<String, dynamic>> _send(String method, String path, [Map<String, dynamic>? body]) async {
    Future<http.Response> attempt(bool forceRefresh) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw ApiException('Not signed in. Restart the app.');
      final token = await user.getIdToken(forceRefresh);
      final req = http.Request(method, Uri.parse('${AppConfig.apiBase}$path'))
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Content-Type'] = 'application/json';
      if (body != null) req.body = jsonEncode(body);
      // 60 s: the free Render server sleeps when idle and needs ~50 s to wake on the first request.
      return http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 60)));
    }

    http.Response res;
    try {
      res = await attempt(false);
      if (res.statusCode == 401) res = await attempt(true); // token expired -> refresh once
    } on SocketException {
      throw ApiException('Can\'t reach the server at ${AppConfig.apiBase}. '
          'Is the backend running and is the phone on the same Wi-Fi?');
    } on TimeoutException {
      throw ApiException('The server took too long to answer. Check your connection and retry.');
    } on http.ClientException {
      throw ApiException('Network error talking to ${AppConfig.apiBase}. Retry.');
    }

    final data = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(data['detail']?.toString() ?? 'Server error (${res.statusCode}).', res.statusCode);
    }
    return data;
  }

  Future<({int xp, List<Quest> quests})> getQuests() async {
    final d = await _send('GET', '/quests');
    return (
      xp: (d['xp'] as num).toInt(),
      quests: (d['quests'] as List).map((q) => Quest.fromJson(q)).toList(),
    );
  }

  Future<void> accept(String questId) => _send('POST', '/quests/$questId/accept');

  /// Snapshot for restart recovery. [steps] null = no fresh Health Connect reading (server keeps old value).
  Future<void> saveProgress(String questId,
          {required double distanceM, int? steps, required Map<String, int> route}) =>
      _send('POST', '/quests/$questId/progress', {'distanceM': distanceM, 'steps': steps, 'route': route});

  /// Saves the user-confirmed pin (a fix map: lat, lng, accuracyM, timestamp, isMocked).
  Future<void> savePin(String questId, Map<String, dynamic> fix) => _send('POST', '/quests/$questId/pin', fix);

  /// Sends evidence; the server decides pass/fail and awards XP.
  Future<Map<String, dynamic>> validate(String questId, Map<String, dynamic> evidence) =>
      _send('POST', '/quests/$questId/validate', evidence);
}

/// Position -> the fix map the backend expects (timestamps in epoch ms).
Map<String, dynamic> fixToJson(Position p) => {
      'lat': p.latitude,
      'lng': p.longitude,
      'accuracyM': p.accuracy,
      'timestamp': p.timestamp.millisecondsSinceEpoch,
      'isMocked': p.isMocked,
    };
