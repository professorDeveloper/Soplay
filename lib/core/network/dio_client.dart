import 'package:dio/dio.dart';
import '../constants/app_constants.dart';
import 'certificate_pinning.dart';

class DioClient {
  DioClient._();

  static final Dio instance = _build();

  static Dio _build() {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    dio.httpClientAdapter = CertificatePinning.adapter();
    return dio;
  }
}
