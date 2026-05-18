import 'package:dio/dio.dart';
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';

import 'api_log_interceptor.dart';
import 'api_response.dart';
import 'app_settings.dart';

class SipRepository {
  SipRepository._();

  static final Dio _dio = Dio();
  static ILogsModel? _logs;

  /// Attach optional SDK logs sink and register the API log interceptor.
  static void configure({ILogsModel? logs}) {
    _logs = logs;
    _dio.interceptors.removeWhere((i) => i is ApiLogInterceptor);
    if (AppSettings.enableApiLog) {
      _dio.interceptors.add(ApiLogInterceptor(_logs));
    }
  }

  static Future<ApiResponse<void>> saveToken(Object data) async {
    try {
      final response = await _dio.post(
        '${AppSettings.baseUrlSip}/notification/save-token',
        data: data,
      );
      final raw = response.data;
      if (raw is! Map) {
        return ApiResponse<void>(status: 'error', message: 'Invalid response');
      }
      final apiResponse =
          ApiResponse<void>.fromMap(Map<String, dynamic>.from(raw));
      if (apiResponse.status == 'ok') {
        return apiResponse;
      }
      return ApiResponse<void>(
        status: 'error',
        message: apiResponse.message,
      );
    } on DioException catch (e) {
      return ApiResponse<void>(
        status: 'error',
        message: e.message ?? 'Network error',
      );
    }
  }

  static Future<ApiResponse<void>> deleteToken(Object data) async {
    try {
      final response = await _dio.delete(
        '${AppSettings.baseUrlSip}/notification/delete-token',
        data: data,
      );
      final raw = response.data;
      if (raw is! Map) {
        return ApiResponse<void>(status: 'error', message: 'Invalid response');
      }
      final apiResponse =
      ApiResponse<void>.fromMap(Map<String, dynamic>.from(raw));
      if (apiResponse.status == 'ok') {
        return apiResponse;
      }
      return ApiResponse<void>(
        status: 'error',
        message: apiResponse.message,
      );
    } on DioException catch (e) {
      return ApiResponse<void>(
        status: 'error',
        message: e.message ?? 'Network error',
      );
    }
  }
}
