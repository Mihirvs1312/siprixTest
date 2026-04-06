class ApiResponse<T> {
  final String status;
  final String? message;

  ApiResponse({required this.status, this.message});

  factory ApiResponse.fromMap(Map<String, dynamic> map) {
    return ApiResponse<T>(
      status: map['status'] as String? ?? 'error',
      message: map['message'] as String?,
    );
  }
}
