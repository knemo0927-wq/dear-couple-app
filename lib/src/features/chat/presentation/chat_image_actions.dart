import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

typedef ChatFetchImageBytes = Future<Uint8List> Function(String imageUrl);
typedef ChatSaveImage = Future<ChatImageSaveResult> Function({
  required Uint8List bytes,
  required String name,
});
typedef ChatShareImage = Future<void> Function({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  Rect? sharePositionOrigin,
});

enum ChatImageSaveResult {
  saved,
  permissionDenied,
  unsupported,
  notEnoughSpace,
  unsupportedFormat,
}

final chatFetchImageBytesProvider = Provider<ChatFetchImageBytes>((ref) {
  return (imageUrl) async {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('INVALID_IMAGE_URL');
    }
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'IMAGE_DOWNLOAD_FAILED_${response.statusCode}',
        uri,
      );
    }
    if (response.bodyBytes.isEmpty) {
      throw const FormatException('EMPTY_IMAGE');
    }
    if (response.bodyBytes.lengthInBytes > 20 * 1024 * 1024) {
      throw const FormatException('IMAGE_TOO_LARGE');
    }
    return response.bodyBytes;
  };
});

final chatSaveImageProvider = Provider<ChatSaveImage>((ref) {
  return ({required bytes, required name}) async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) {
      return ChatImageSaveResult.unsupported;
    }

    final supportedPlatform = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
    if (!supportedPlatform) return ChatImageSaveResult.unsupported;

    try {
      var hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        hasAccess = await Gal.requestAccess();
      }
      if (!hasAccess) return ChatImageSaveResult.permissionDenied;
      await Gal.putImageBytes(bytes, name: name);
      return ChatImageSaveResult.saved;
    } on GalException catch (error) {
      switch (error.type) {
        case GalExceptionType.accessDenied:
          return ChatImageSaveResult.permissionDenied;
        case GalExceptionType.notEnoughSpace:
          return ChatImageSaveResult.notEnoughSpace;
        case GalExceptionType.notSupportedFormat:
          return ChatImageSaveResult.unsupportedFormat;
        case GalExceptionType.unexpected:
          rethrow;
      }
    } on UnimplementedError {
      return ChatImageSaveResult.unsupported;
    }
  };
});

final chatShareImageProvider = Provider<ChatShareImage>((ref) {
  return ({
    required bytes,
    required filename,
    required mimeType,
    sharePositionOrigin,
  }) async {
    final file = XFile.fromData(
      bytes,
      mimeType: mimeType,
      name: filename,
    );
    await Share.shareXFiles(
      [file],
      text: 'Dear에서 함께한 사진',
      sharePositionOrigin: sharePositionOrigin,
      fileNameOverrides: [filename],
    );
  };
});

String chatImageExtensionFromUrl(String imageUrl) {
  final path = Uri.tryParse(imageUrl)?.path.toLowerCase() ?? '';
  if (path.endsWith('.png')) return 'png';
  if (path.endsWith('.webp')) return 'webp';
  return 'jpg';
}

String chatImageMimeType(String extension) {
  return switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}
