import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

class HttpApi {
  HttpApi(this.origin);

  final String origin;

  Uri _u(String path) => Uri.parse('$origin$path');

  Future<ServerInfo> info() async {
    final res = await http.get(_u('/info'));
    if (res.statusCode != 200) {
      throw ApiException('Could not reach host (${res.statusCode})');
    }
    return ServerInfo.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<String> login({
    required String identity,
    required String password,
    String? invite,
    String? deviceToken,
  }) async {
    final res = await http.post(
      _u('/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identity': identity.trim().toLowerCase(),
        'password': password,
        if (invite != null && invite.isNotEmpty) 'invite': invite,
        if (deviceToken != null) 'deviceToken': deviceToken,
      }),
    );
    final body = _decode(res.body);
    if (res.statusCode != 200) {
      throw ApiException(_errorFrom(body, 'Invalid credentials'));
    }
    final token = body['token'] as String?;
    if (token == null || token.isEmpty) {
      throw ApiException('Invalid credentials');
    }
    return token;
  }

  Future<String?> resetQuestion(String identity) async {
    final res = await http.post(
      _u('/reset-password/question'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'identity': identity.trim().toLowerCase()}),
    );
    final body = _decode(res.body);
    if (res.statusCode != 200) {
      throw ApiException(_errorFrom(body, 'Unable to reset password'));
    }
    return body['questionId'] as String? ?? body['securityQuestionId'] as String?;
  }

  Future<void> resetPassword({
    required String identity,
    required String answer,
    required String newPassword,
    required String confirmNewPassword,
  }) async {
    final res = await http.post(
      _u('/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identity': identity.trim().toLowerCase(),
        'answer': answer,
        'newPassword': newPassword,
        'confirmNewPassword': confirmNewPassword,
      }),
    );
    if (res.statusCode != 200) {
      throw ApiException(_errorFrom(_decode(res.body), 'Unable to reset password'));
    }
  }

  Future<Map<String, dynamic>> upload({
    required String token,
    required String originalName,
    required Uint8List bytes,
  }) async {
    final req = http.Request('POST', _u('/upload'))
      ..headers.addAll({
        'x-token': token,
        'x-file-name': Uri.encodeComponent(originalName),
        'content-length': '${bytes.length}',
        'content-type': 'application/octet-stream',
      })
      ..bodyBytes = bytes;
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    final body = _decode(res.body);
    if (res.statusCode != 200) {
      throw ApiException(_errorFrom(body, 'Upload failed'));
    }
    return body;
  }

  String publicUrl(KurierFile file) {
    final name = file.name.trim();
    if (name.isEmpty) return '';
    Uri uri;
    if (name.startsWith('http://') || name.startsWith('https://')) {
      uri = Uri.parse(name);
    } else {
      final path = name.startsWith('/') ? name : '/public/$name';
      uri = Uri.parse(origin).replace(path: path);
    }
    final token = file.accessToken?.trim();
    if (token != null && token.isNotEmpty) {
      return uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'accessToken': token,
          if (file.accessTokenExpiresAt != null)
            'expires': '${file.accessTokenExpiresAt}',
        },
      ).toString();
    }
    return uri.toString();
  }

  Future<({Uint8List bytes, String filename})> downloadBackup(
    String token,
  ) async {
    final res = await http.get(
      _u('/backup'),
      headers: {'Authorization': 'Bearer $token', 'x-token': token},
    );
    if (res.statusCode != 200) {
      throw ApiException('Backup export failed');
    }
    return (bytes: res.bodyBytes, filename: _backupFilename(res));
  }

  String _backupFilename(http.Response res) {
    final header = res.headers['content-disposition'] ?? '';
    final star = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false)
        .firstMatch(header);
    if (star != null) {
      return Uri.decodeComponent(star.group(1)!);
    }
    final quoted = RegExp(r'filename="([^"]+)"', caseSensitive: false)
        .firstMatch(header);
    if (quoted != null) return quoted.group(1)!;
    final plain =
        RegExp(r'filename=([^;]+)', caseSensitive: false).firstMatch(header);
    if (plain != null) return plain.group(1)!.trim();
    return 'kurier-backup.zip';
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return {};
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return {};
  }

  String _errorFrom(Map<String, dynamic> body, String fallback) {
    if (body['error'] is String) return body['error'] as String;
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      return '${errors.values.first}';
    }
    if (body['message'] is String) return body['message'] as String;
    return fallback;
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
