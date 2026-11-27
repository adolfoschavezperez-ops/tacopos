import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class PreviewApiException implements Exception {
  const PreviewApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  bool get isAuthRevokedOrDenied => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'PreviewApiException($statusCode, $code): $message';
}

/// Firestore-compatible [DocumentSnapshot] backed by JSON returned from the
/// authenticated Read-Only Preview API. Allows reusing 100% of existing
/// `Model.fromDoc` factories and canonical financial formulas without changes.
// ignore: subtype_of_sealed_class
class PreviewDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  PreviewDocumentSnapshot({
    required this.id,
    required Map<String, dynamic>? data,
  }) : _data = data;

  @override
  final String id;

  final Map<String, dynamic>? _data;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic get(Object field) {
    final d = _data;
    if (d == null) return null;
    if (field is String) return d[field];
    return null;
  }

  @override
  dynamic operator [](Object field) => get(field);

  @override
  SnapshotMetadata get metadata =>
      throw UnsupportedError('SnapshotMetadata not used in Preview.');

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnsupportedError('DocumentReference not writable in Preview.');
}

class PreviewQueryPage {
  const PreviewQueryPage({
    required this.docs,
    required this.nextCursor,
    required this.hasMore,
    required this.isPartial,
    required this.dataReads,
  });

  final List<PreviewDocumentSnapshot> docs;
  final Map<String, dynamic>? nextCursor;
  final bool hasMore;
  final bool isPartial;
  final int dataReads;
}

class PreviewSessionPayload {
  const PreviewSessionPayload({
    required this.restaurantId,
    required this.restaurantName,
    required this.uid,
    required this.employeeId,
    required this.displayName,
    required this.isSuperAdmin,
    required this.permissions,
    required this.branches,
  });

  final String restaurantId;
  final String restaurantName;
  final String uid;
  final String employeeId;
  final String displayName;
  final bool isSuperAdmin;
  final Map<String, bool> permissions;
  final List<PreviewDocumentSnapshot> branches;
}

/// Authenticated HTTP client for TacoPOS Backoffice 2.0 Preview (Read-Only).
///
/// - Never accesses Firestore directly.
/// - Never falls back to DEV or PROD on error.
/// - Attaches fresh Firebase ID Tokens and decodes serialized Timestamps.
class PreviewApiClient {
  PreviewApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    Future<String?> Function({bool forceRefresh})? idTokenProvider,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client(),
       _idTokenProvider = idTokenProvider ?? _defaultTokenProvider;

  final String baseUrl;
  final http.Client _http;
  final Future<String?> Function({bool forceRefresh}) _idTokenProvider;
  final Duration requestTimeout;
  final Map<String, Future<Map<String, dynamic>>> _inFlightDedup = {};

  static Future<String?> _defaultTokenProvider({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;
    return user.getIdToken(forceRefresh);
  }

  static dynamic decodeValue(dynamic value) {
    if (value is Map) {
      if (value.length == 1 && value.containsKey('__previewTsMs')) {
        final ms = value['__previewTsMs'];
        if (ms is num) {
          return Timestamp.fromMillisecondsSinceEpoch(ms.toInt());
        }
      }
      final out = <String, dynamic>{};
      value.forEach((k, v) {
        out[k.toString()] = decodeValue(v);
      });
      return out;
    }
    if (value is List) {
      return value.map(decodeValue).toList(growable: false);
    }
    return value;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool forceRefreshToken = false,
  }) async {
    final dedupKey = '$path|${jsonEncode(body)}';
    final existing = _inFlightDedup[dedupKey];
    if (existing != null && !forceRefreshToken) {
      return existing;
    }

    final future = _executePost(
      path,
      body,
      forceRefreshToken: forceRefreshToken,
    );
    _inFlightDedup[dedupKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightDedup[dedupKey], future)) {
        _inFlightDedup.remove(dedupKey);
      }
    }
  }

  Future<Map<String, dynamic>> _executePost(
    String path,
    Map<String, dynamic> body, {
    bool forceRefreshToken = false,
  }) async {
    final token = await _idTokenProvider(forceRefresh: forceRefreshToken);
    if (token == null || token.isEmpty) {
      throw const PreviewApiException(
        statusCode: 401,
        code: 'UNAUTHENTICATED',
        message: 'Se requiere una sesión autenticada para consultar Preview.',
      );
    }

    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse('$cleanBase$path');

    final http.Response res;
    try {
      res = await _http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const PreviewApiException(
        statusCode: 504,
        code: 'PREVIEW_TIMEOUT',
        message: 'Tiempo de espera agotado al consultar Preview API.',
      );
    } catch (e) {
      throw PreviewApiException(
        statusCode: 503,
        code: 'PREVIEW_UNAVAILABLE',
        message: 'No se pudo conectar con Preview API: $e',
      );
    }

    Map<String, dynamic> json;
    try {
      final parsed = jsonDecode(res.body);
      json = parsed is Map<String, dynamic>
          ? parsed
          : <String, dynamic>{};
    } catch (_) {
      json = <String, dynamic>{};
    }

    if (res.statusCode == 401 && !forceRefreshToken) {
      return _executePost(path, body, forceRefreshToken: true);
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw PreviewApiException(
        statusCode: res.statusCode,
        code: (json['code'] ?? 'PREVIEW_ERROR').toString(),
        message: (json['message'] ?? 'Error al consultar Preview API (${res.statusCode}).')
            .toString(),
      );
    }
    return json;
  }

  Future<PreviewSessionPayload> fetchSession({
    required String restaurantId,
  }) async {
    final json = await _post('/v1/preview/session', {
      'restaurantId': restaurantId.trim(),
    }, forceRefreshToken: true);

    final rest = json['restaurant'] as Map<String, dynamic>? ?? const {};
    final authz = json['authzUser'] as Map<String, dynamic>? ?? const {};
    final rawPerms = authz['permissions'] as Map<String, dynamic>? ?? const {};
    final perms = <String, bool>{};
    rawPerms.forEach((k, v) {
      perms[k] = v == true;
    });

    final rawBranches = json['branches'] as List<dynamic>? ?? const [];
    final branches = rawBranches
        .whereType<Map>()
        .map((b) {
          final map = decodeValue(b) as Map<String, dynamic>;
          final id = (map['id'] ?? '').toString();
          return PreviewDocumentSnapshot(id: id, data: map);
        })
        .toList(growable: false);

    return PreviewSessionPayload(
      restaurantId: (rest['id'] ?? restaurantId).toString(),
      restaurantName: (rest['name'] ?? restaurantId).toString(),
      uid: (authz['uid'] ?? '').toString(),
      employeeId: (authz['employeeId'] ?? '').toString(),
      displayName: (authz['displayName'] ?? 'Propietario').toString(),
      isSuperAdmin: authz['isSuperAdmin'] == true,
      permissions: perms,
      branches: branches,
    );
  }

  Future<PreviewQueryPage> queryPage({
    required String restaurantId,
    required String collection,
    String? subcollection,
    String? parentDocId,
    String? branchId,
    String? startBusinessDate,
    String? endBusinessDate,
    String? statusFilter,
    int limit = 100,
    Map<String, dynamic>? cursor,
  }) async {
    final body = <String, dynamic>{
      'restaurantId': restaurantId,
      'collection': collection,
      'limit': limit,
      'subcollection': ?subcollection,
      'parentDocId': ?parentDocId,
      if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
      'startBusinessDate': ?startBusinessDate,
      'endBusinessDate': ?endBusinessDate,
      if (statusFilter != null && statusFilter.isNotEmpty) 'statusFilter': statusFilter,
      'cursor': ?cursor,
    };

    final json = await _post('/v1/preview/query', body);
    final rawDocs = json['docs'] as List<dynamic>? ?? const [];
    final docs = rawDocs
        .whereType<Map>()
        .map((raw) {
          final decoded = decodeValue(raw) as Map<String, dynamic>;
          final id = (decoded['id'] ?? '').toString();
          return PreviewDocumentSnapshot(id: id, data: decoded);
        })
        .toList(growable: false);

    final usage = json['usage'] as Map<String, dynamic>? ?? const {};
    return PreviewQueryPage(
      docs: docs,
      nextCursor: json['nextCursor'] as Map<String, dynamic>?,
      hasMore: json['hasMore'] == true,
      isPartial: json['isPartial'] == true,
      dataReads: (usage['dataReads'] as num?)?.toInt() ?? docs.length,
    );
  }

  Future<({List<PreviewDocumentSnapshot> docs, bool isPartial, int dataReads})>
  queryAllPages({
    required String restaurantId,
    required String collection,
    String? subcollection,
    String? parentDocId,
    String? branchId,
    String? startBusinessDate,
    String? endBusinessDate,
    String? statusFilter,
    int pageSize = 250,
    int maxDocs = 3000,
    bool Function()? isCancelled,
  }) async {
    final collected = <PreviewDocumentSnapshot>[];
    Map<String, dynamic>? cursor;
    var totalReads = 0;
    var hitLimit = false;

    while (collected.length < maxDocs) {
      if (isCancelled != null && isCancelled()) {
        return (docs: collected, isPartial: true, dataReads: totalReads);
      }
      final remaining = maxDocs - collected.length;
      final page = await queryPage(
        restaurantId: restaurantId,
        collection: collection,
        subcollection: subcollection,
        parentDocId: parentDocId,
        branchId: branchId,
        startBusinessDate: startBusinessDate,
        endBusinessDate: endBusinessDate,
        statusFilter: statusFilter,
        limit: remaining < pageSize ? remaining : pageSize,
        cursor: cursor,
      );
      totalReads += page.dataReads;
      collected.addAll(page.docs);
      if (!page.hasMore || page.nextCursor == null) {
        break;
      }
      if (collected.length >= maxDocs) {
        hitLimit = true;
        break;
      }
      cursor = page.nextCursor;
    }

    return (docs: collected, isPartial: hitLimit, dataReads: totalReads);
  }

  Future<PreviewDocumentSnapshot?> fetchDoc({
    required String restaurantId,
    required String collection,
    String? subcollection,
    String? parentDocId,
    required String docId,
  }) async {
    try {
      final json = await _post('/v1/preview/doc', {
        'restaurantId': restaurantId,
        'collection': collection,
        'docId': docId,
        'subcollection': ?subcollection,
        'parentDocId': ?parentDocId,
      });
      final rawDoc = json['doc'];
      if (rawDoc is! Map) return null;
      final decoded = decodeValue(rawDoc) as Map<String, dynamic>;
      return PreviewDocumentSnapshot(
        id: (decoded['id'] ?? docId).toString(),
        data: decoded,
      );
    } on PreviewApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
