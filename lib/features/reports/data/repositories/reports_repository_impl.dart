import 'package:dio/dio.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/reports/data/datasources/reports_data_source.dart';
import 'package:soplay/features/reports/domain/entities/report_payload.dart';
import 'package:soplay/features/reports/domain/repositories/reports_repository.dart';

class ReportsRepositoryImpl implements ReportsRepository {
  final ReportsDataSource dataSource;
  const ReportsRepositoryImpl(this.dataSource);

  @override
  Future<Result<void>> submit(ReportPayload payload) async {
    try {
      await dataSource.submit(payload);
      return const Success(null);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final serverMessage =
          (e.response?.data as Map<String, dynamic>?)?['message'] as String?;
      switch (code) {
        case 400:
          return Failure(
            Exception(serverMessage ?? 'Invalid reason or type'),
          );
        case 403:
          return Failure(Exception(
            serverMessage ??
                'New accounts cannot submit reports',
          ));
        case 409:
          return Failure(
            Exception('You have already reported this item'),
          );
        case 429:
          return Failure(Exception(
            serverMessage ?? 'Too many requests, try again later',
          ));
      }
      return Failure(
        Exception(serverMessage ?? e.message ?? 'Something went wrong'),
      );
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }
}
