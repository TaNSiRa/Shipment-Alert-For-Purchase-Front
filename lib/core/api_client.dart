import 'dart:convert';
import 'dart:typed_data';

import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

class ApiClient {
  ApiClient({this.token, this.onUnauthorized}) {
    _client.withCredentials = true;
  }

  final BrowserClient _client = BrowserClient();
  String? token;
  String? csrfToken;
  String? sectionCode;
  void Function()? onUnauthorized;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        if (csrfToken != null) 'X-CSRF-Token': csrfToken!,
        if (sectionCode != null && sectionCode!.isNotEmpty) 'X-Section-Code': sectionCode!,
      };

  Future<Map<String, dynamic>> getJson(String path) async {
    final response = await _client.get(Uri.parse('${AppConfig.apiBaseUrl}$path'), headers: _headers);
    return _decode(response);
  }

  Future<String> getText(String path) async {
    final response = await _client.get(Uri.parse('${AppConfig.apiBaseUrl}$path'), headers: _headers);
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 && token != null) {
        onUnauthorized?.call();
        throw ApiException('Unauthorized', response.statusCode);
      }
      throw ApiException(response.body.isEmpty ? 'Request failed' : response.body, response.statusCode);
    }
    return response.body;
  }

  Future<Uint8List> getBytes(String path) async {
    final response = await _client.get(Uri.parse('${AppConfig.apiBaseUrl}$path'), headers: _headers);
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 && token != null) {
        onUnauthorized?.call();
        throw ApiException('Unauthorized', response.statusCode);
      }
      throw ApiException(response.body.isEmpty ? 'Request failed' : response.body, response.statusCode);
    }
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final response =
        await _client.post(Uri.parse('${AppConfig.apiBaseUrl}$path'), headers: _headers, body: jsonEncode(body));
    return _decode(response);
  }

  Future<Map<String, dynamic>> patchJson(String path, Map<String, dynamic> body) async {
    final response = await _client.patch(Uri.parse('${AppConfig.apiBaseUrl}$path'),
        headers: _headers, body: jsonEncode(body));
    return _decode(response);
  }

  Future<Map<String, dynamic>> putJson(String path, Map<String, dynamic> body) async {
    final response =
        await _client.put(Uri.parse('${AppConfig.apiBaseUrl}$path'), headers: _headers, body: jsonEncode(body));
    return _decode(response);
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    final response = await _client.delete(Uri.parse('${AppConfig.apiBaseUrl}$path'), headers: _headers);
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    var json = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{'data': decoded};
      } catch (_) {
        // Non-JSON body (e.g. a rate-limit/proxy plain-text response). Surface it
        // as a message instead of throwing a FormatException.
        json = <String, dynamic>{'message': response.body};
      }
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 && token != null) {
        onUnauthorized?.call();
        throw ApiException('Unauthorized', response.statusCode);
      }
      throw ApiException(json['message']?.toString() ?? 'Request failed', response.statusCode);
    }
    return json;
  }
}

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  @override
  String toString() => message;
}
