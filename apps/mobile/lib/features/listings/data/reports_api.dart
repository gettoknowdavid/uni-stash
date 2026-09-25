import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:uni_stash_mobile/core/api/api_response.dart';

part 'reports_api.g.dart';

/// Wire shape of a report as returned by the backend.
class ReportResponse {
  const ReportResponse({
    required this.id,
    required this.reporterId,
    required this.listingId,
    required this.status,
    required this.createdAt,
    this.reason,
  });

  factory ReportResponse.fromJson(Map<String, dynamic> json) => ReportResponse(
        id: json['id'] as String,
        reporterId: json['reporter_id'] as String,
        listingId: json['listing_id'] as String,
        status: json['status'] as String,
        reason: json['reason'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String reporterId;
  final String listingId;
  final String? reason;
  final String status;
  final DateTime createdAt;
}

class ReportListResponse {
  const ReportListResponse({
    required this.reports,
    this.nextCursor,
  });

  factory ReportListResponse.fromJson(Map<String, dynamic> json) =>
      ReportListResponse(
        reports: (json['reports'] as List<dynamic>)
            .map((raw) => ReportResponse.fromJson(raw as Map<String, dynamic>))
            .toList(),
        nextCursor: json['next_cursor'] as String?,
      );

  final List<ReportResponse> reports;
  final String? nextCursor;
}

class CreateReportRequest {
  const CreateReportRequest({this.reason});

  Map<String, dynamic> toJson() => {'reason': reason};

  final String? reason;
}

@RestApi()
abstract class ReportsApiClient {
  factory ReportsApiClient(Dio dio, {String? baseUrl}) = _ReportsApiClient;

  /// Flags a listing for moderation. Idempotent per (reporter, listing).
  @POST('/api/v1/reports/{listing_id}')
  Future<ApiResponse<ReportResponse>> create(
    @Path('listing_id') String listingId,
    @Body() CreateReportRequest request,
  );

  /// The caller's own reports, newest first, cursor-paginated.
  @GET('/api/v1/reports/mine')
  Future<ApiResponse<ReportListResponse>> mine({
    @Query('cursor') String? cursor,
    @Query('limit') int? limit,
  });

  /// Updates the reason on one of the caller's open reports.
  @PATCH('/api/v1/reports/{report_id}')
  Future<ApiResponse<ReportResponse>> update(
    @Path('report_id') String reportId,
    @Body() CreateReportRequest request,
  );

  /// Withdraws one of the caller's open reports (204 on success).
  @DELETE('/api/v1/reports/{report_id}')
  Future<HttpResponse<void>> delete(@Path('report_id') String reportId);
}
