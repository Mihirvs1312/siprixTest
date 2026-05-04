import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';

/// Logs HTTP requests/responses from Dio. Sensitive map keys are redacted.
class ApiLogInterceptor extends Interceptor {
  ApiLogInterceptor(this._logs);

  final ILogsModel? _logs;

  static bool _maskKey(String lower) {
    if (_sensitiveExact.contains(lower)) return true;
    if (lower == 'password' ||
        lower.endsWith('_token') ||
        lower.endsWith('_secret') ||
        lower.contains('authorization')) {
      return true;
    }
    return false;
  }

  static const _sensitiveExact = {
    'token',
    'password',
    'secret',
    'authorization',
    'api_key',
    'apikey',
    'access_token',
    'refresh_token',
  };

  void _log(String line) {
    debugPrint(line);
    _logs?.print(line);
  }

  static dynamic _redact(dynamic value) {
    if (value is Map) {
      return value.map((dynamic k, dynamic v) {
        final key = k.toString();
        final mask = _maskKey(key.toLowerCase());
        return MapEntry<dynamic, dynamic>(
          key,
          mask ? '***' : _redact(v),
        );
      });
    }
    if (value is List) {
      return value.map(_redact).toList();
    }
    return value;
  }

  static String _formatData(Object? data) {
    if (data == null) return '';
    try {
      if (data is Map || data is List) {
        final encoded = jsonEncode(_redact(data));
        return encoded.length > 2000 ? '${encoded.substring(0, 2000)}…' : encoded;
      }
      final s = data.toString();
      return s.length > 2000 ? '${s.substring(0, 2000)}…' : s;
    } catch (_) {
      return '(unreadable body)';
    }
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _log(
      '[API] → ${options.method} ${options.uri} ${_formatData(options.data)}',
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _log(
      '[API] ← ${response.statusCode} ${response.requestOptions.uri} '
      '${_formatData(response.data)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final res = err.response;
    if (res != null) {
      _log(
        '[API] ✕ ${res.statusCode} ${err.requestOptions.uri} '
        '${_formatData(res.data)} (${err.message})',
      );
    } else {
      _log('[API] ✕ ${err.requestOptions.uri} (${err.message})');
    }
    handler.next(err);
  }
}
