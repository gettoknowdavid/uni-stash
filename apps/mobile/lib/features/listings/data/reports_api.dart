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

  factory ReportResponse.fromJson(Map<String, dynamic> json) =>
      ReportResponse(
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
}
