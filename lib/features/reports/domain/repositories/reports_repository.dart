import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/reports/domain/entities/report_payload.dart';

abstract class ReportsRepository {
  Future<Result<void>> submit(ReportPayload payload);
}
