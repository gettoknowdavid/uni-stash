import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:uni_stash_mobile/core/api/dio_error.dart';
import 'package:uni_stash_mobile/core/result/_result.dart';
import 'package:uni_stash_mobile/features/images/data/images_api.dart';
import 'package:uni_stash_mobile/features/images/models/images_dto.dart';

/// Result of a completed upload: the confirmed server-side image.
typedef UploadedImage = ConfirmResponse;

/// File plus its sniffed content type, ready for [ImagesRepository.upload].
class ImageUpload {
  const ImageUpload({required this.path, required this.contentType});

  /// Local file path from the image picker.
  final String path;

  /// MIME type — must match what was presigned, or the storage provider
  /// rejects the PUT because the header is part of the signature.
  final ImageContentType contentType;
}

abstract interface class ImagesRepository {
  /// Issues a presigned PUT URL for [listingId] (CM-6.1).
  Future<Result<PresignResponse>> presign(
    String listingId,
    ImageContentType contentType,
  );

  /// Uploads the file at [path] to a presigned URL (CM-6.1, direct to B2).
  Future<Result<void>> uploadToPresignedUrl(
    String uploadUrl,
    String path,
    ImageContentType contentType,
  );

  /// Registers an uploaded object server-side after a HEAD check (CM-6.2).
  Future<Result<UploadedImage>> confirm(String listingId, String objectKey);

  /// Full pipeline for one photo: presign → direct PUT → confirm.
  Future<Result<UploadedImage>> upload(String listingId, ImageUpload photo);
}

class ImagesRepositoryImpl implements ImagesRepository {
  ImagesRepositoryImpl(this._client, this._logger);

  final ImagesApiClient _client;
  final Logger _logger;

  /// Plain Dio for the direct-to-storage PUT: deliberately NO auth
  /// interceptor and NO JSON headers — presigned URLs stop working if
  /// extra headers sneak into the signature, and the response is not the
  /// app's `{status, message, data}` envelope anyway.
  static final Dio _storageDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  @override
  Future<Result<PresignResponse>> presign(
    String listingId,
    ImageContentType contentType,
  ) async {
    try {
      final response = await _client.presign(
        PresignRequest(
          listingId: listingId,
          contentType: contentType.mime,
        ),
      );
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ImagesRepository] presign failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ImagesRepository] presign unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<void>> uploadToPresignedUrl(
    String uploadUrl,
    String path,
    ImageContentType contentType,
  ) async {
    try {
      // Presigned PUTs sign the exact request body, so the raw file bytes go
      // up as-is — no multipart wrapping, no auth interceptor, no JSON
      // envelope. Photos are ≤10 MiB (server enforces via HEAD check), so
      // reading them into memory is fine.
      await _storageDio.put<void>(
        uploadUrl,
        data: File(path).readAsBytesSync(),
        options: Options(
          headers: <String, String>{'Content-Type': contentType.mime},
        ),
      );
      return const Result.success(null);
    } on DioException catch (e) {
      _logger.e('[ImagesRepository] direct upload failed', error: e);
      return Result.failure(_humanizeStorageError(e));
    } on Object catch (e) {
      _logger.e('[ImagesRepository] direct upload unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<UploadedImage>> confirm(
    String listingId,
    String objectKey,
  ) async {
    try {
      final response = await _client.confirm(
        ConfirmRequest(listingId: listingId, objectKey: objectKey),
      );
      if (!response.status) return Result.failure(response.message);
      final data = response.data;
      if (data == null) return const Result.failure('No data');
      return Result.success(data);
    } on DioException catch (e) {
      _logger.e('[ImagesRepository] confirm failed', error: e);
      return dioFailure(e);
    } on Object catch (e) {
      _logger.e('[ImagesRepository] confirm unexpected error', error: e);
      return const Result.failure('An unexpected error occurred.');
    }
  }

  @override
  Future<Result<UploadedImage>> upload(
    String listingId,
    ImageUpload photo,
  ) async {
    final presigned = await presign(listingId, photo.contentType);
    final PresignResponse presignData;
    switch (presigned) {
      case Success(:final value):
        presignData = value;
      case Failure(:final message):
        return Result.failure('Could not start photo upload: $message');
    }

    final uploaded = await uploadToPresignedUrl(
      presignData.uploadUrl,
      photo.path,
      photo.contentType,
    );
    switch (uploaded) {
      case Success():
        break;
      case Failure(:final message):
        return Result.failure(message);
    }

    return confirm(listingId, presignData.objectKey);
  }
}

/// Storage PUTs fail with the provider's XML error page, not the app
/// envelope — translate the common cases into something actionable.
String _humanizeStorageError(DioException e) {
  final status = e.response?.statusCode;
  return switch (status) {
    403 => 'Photo upload was rejected (expired or invalid signature).',
    null => 'Photo upload failed. Please check your connection.',
    _ => 'Photo upload failed (${e.response?.statusCode}).',
  };
}
