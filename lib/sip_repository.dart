import 'package:dio/dio.dart';

import 'api_response.dart';
import 'app_settings.dart';

class SipRepository {
  SipRepository._();

  static final Dio _dio = Dio();

  static Future<ApiResponse<void>> saveToken(Object data) async {
    try {
      final response = await _dio.post(
        '${AppSettings.baseUrlSip}/save-token',
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
