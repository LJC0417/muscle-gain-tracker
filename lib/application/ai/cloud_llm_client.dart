/// WorkBuddy 云服务 · LLM 数据面客户端（Dart 原生实现）
///
/// 为什么手写而不用 SDK：官方 SDK 只有 JS 版（npm / CDN），Flutter 原生端无 SDK 可用。
/// 协议按 SDK 源码（`@tencent-ai/workbuddy-cloud-sdk` lib/index.global.js）逐条对齐：
///   - 基址：`{endpoint}/.cloud/llm`
///   - 列表：`GET  {base}/models`            → `Accept: application/json`
///   - 对话：`POST {base}/chat/completions`  → `Accept: text/event-stream`，SSE 流式
///   - 鉴权：`x-wb-webapp-access-key: {publishableKey}`；匿名调用不带 Authorization
///   - 仅支持 stream:true（非流式会被服务端拒绝）
///
/// 依赖只用 dart:io（不引入第三方包，避免破坏离线构建链路）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/cloud_config.dart';

/// 模型目录项（只取公开可用字段）。
class CloudModelRef {
  final String id;
  final String? name;
  final bool isDefault;
  final bool disabled;

  const CloudModelRef({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.disabled,
  });

  static CloudModelRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.trim().isEmpty) return null;
    final name = raw['name'];
    return CloudModelRef(
      id: id,
      name: name is String ? name : null,
      isDefault: raw['isDefault'] == true,
      // disabled === true 或 enabled === false 均视为不可选（缺省=可选）
      disabled: raw['disabled'] == true || raw['enabled'] == false,
    );
  }
}

/// 云端错误（对齐 SDK 的 CloudOpenAIError 公开字段：code / message / status）。
class CloudLlmException implements Exception {
  final String code;
  final String message;
  final int? status;

  const CloudLlmException(this.code, this.message, {this.status});

  bool get isQuota => code.startsWith('quota_');
  bool get isAuth => code.startsWith('auth_');

  /// 文案层用：不要暴露后端细节。
  String get friendly => isQuota
      ? 'AI 额度暂不可用'
      : isAuth
          ? '云服务鉴权失败'
          : '网络或服务不可用';

  @override
  String toString() => 'CloudLlmException($code: $message)';
}

class CloudLlmClient {
  CloudLlmClient._();
  static final CloudLlmClient instance = CloudLlmClient._();

  HttpClient? _http;
  List<CloudModelRef>? _models;
  DateTime? _modelsAt;

  HttpClient get _client => _http ??= (HttpClient()
    ..connectionTimeout = const Duration(seconds: 12));

  /// 模型列表（内存缓存 10 分钟；空列表是合法结果，调用方必须显式处理）。
  Future<List<CloudModelRef>> listModels({
    bool forceRefresh = false,
  }) async {
    final cached = _models;
    final at = _modelsAt;
    if (!forceRefresh &&
        cached != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 10)) {
      return cached;
    }
    final res = await _request('GET', CloudConfig.modelsPath);
    if (res.status != 200) {
      throw CloudLlmException(
        _codeOf(res.body) ?? 'gateway_http_${res.status}',
        'models ${res.status}',
        status: res.status,
      );
    }
    Object? parsed;
    try {
      parsed = jsonDecode(res.body);
    } catch (_) {
      throw const CloudLlmException(
          'gateway_invalid_response', '模型列表不是合法 JSON');
    }
    final raw = parsed is List
        ? parsed
        : (parsed is Map ? parsed['data'] : null);
    if (raw is! List) return const <CloudModelRef>[];
    final out = <CloudModelRef>[];
    for (final item in raw) {
      final m = CloudModelRef.fromJson(item);
      if (m != null) out.add(m);
    }
    _models = out;
    _modelsAt = DateTime.now();
    return out;
  }

  /// 选模型：优先 isDefault，其次第一个可用；无可用模型即抛错（**禁止硬编码 model id**）。
  Future<String> pickModelId() async {
    final models = await listModels();
    if (models.isEmpty) {
      throw const CloudLlmException('model_unavailable', '模型列表为空');
    }
    for (final m in models) {
      if (m.isDefault && !m.disabled) return m.id;
    }
    for (final m in models) {
      if (!m.disabled) return m.id;
    }
    throw const CloudLlmException('model_unavailable', '无可用模型');
  }

  /// 流式对话，收集完整文本返回（云服务只支持 streaming）。
  Future<String> complete({
    required String system,
    required String user,
    double temperature = 0.8,
    Duration timeout = CloudConfig.requestTimeout,
  }) async {
    final modelId = await pickModelId();
    HttpClientRequest req;
    try {
      req = await _client.postUrl(Uri.parse(CloudConfig.chatPath));
    } on SocketException catch (e) {
      throw CloudLlmException('gateway_network_error', e.message);
    }
    req.headers.set(CloudConfig.accessKeyHeader, CloudConfig.publishableKey);
    req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(<String, Object?>{
      'model': modelId,
      'stream': true,
      'temperature': temperature,
      'messages': <Map<String, String>>[
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
    }));

    HttpClientResponse res;
    try {
      res = await req.close().timeout(timeout);
    } on TimeoutException {
      throw const CloudLlmException('gateway_timeout', '请求超时');
    } on SocketException catch (e) {
      throw CloudLlmException('gateway_network_error', e.message);
    } on HttpException catch (e) {
      throw CloudLlmException('gateway_network_error', e.message);
    }

    if (res.statusCode != 200) {
      final body = await res.transform(utf8.decoder).join();
      throw CloudLlmException(
        _codeOf(body) ?? 'gateway_http_${res.statusCode}',
        _messageOf(body) ?? 'HTTP ${res.statusCode}',
        status: res.statusCode,
      );
    }

    final buf = StringBuffer();
    var done = false;
    try {
      await for (final line in res
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(timeout)) {
        if (line.startsWith('event:')) {
          if (line.contains('error')) {
            throw const CloudLlmException('gateway_error', '模型服务返回错误事件');
          }
          continue;
        }
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') {
          done = true;
          break;
        }
        Object? chunk;
        try {
          chunk = jsonDecode(payload);
        } catch (_) {
          continue; // 跳过无法解析的帧
        }
        if (chunk is! Map) continue;
        final err = chunk['error'];
        if (err != null) {
          throw CloudLlmException(
            _codeOfMap(err) ?? 'gateway_error',
            _messageOfMap(err) ?? 'stream error',
          );
        }
        final choices = chunk['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map) {
            final delta = first['delta'];
            if (delta is Map) {
              final c = delta['content'];
              if (c is String && c.isNotEmpty) buf.write(c);
            }
          }
        }
      }
    } on TimeoutException {
      throw const CloudLlmException('gateway_timeout', '流式响应超时');
    } on SocketException catch (e) {
      throw CloudLlmException('gateway_network_error', e.message);
    }

    final text = buf.toString();
    if (!done && text.isEmpty) {
      throw const CloudLlmException('gateway_stream_interrupted', '流式中断');
    }
    return text;
  }

  Future<({int status, String body})> _request(String method, String url) async {
    try {
      final req = await _client.openUrl(method, Uri.parse(url));
      req.headers.set(CloudConfig.accessKeyHeader, CloudConfig.publishableKey);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      return (status: res.statusCode, body: body);
    } on TimeoutException {
      throw const CloudLlmException('gateway_timeout', '请求超时');
    } on SocketException catch (e) {
      throw CloudLlmException('gateway_network_error', e.message);
    } on HttpException catch (e) {
      throw CloudLlmException('gateway_network_error', e.message);
    }
  }

  String? _codeOf(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) return _codeOfMap(j['error']);
    } catch (_) {}
    return null;
  }

  String? _messageOf(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) return _messageOfMap(j['error']);
    } catch (_) {}
    return null;
  }

  String? _codeOfMap(Object? err) {
    if (err is Map) {
      final c = err['code'];
      if (c is String && c.isNotEmpty) return c;
    }
    return null;
  }

  String? _messageOfMap(Object? err) {
    if (err is Map) {
      final m = err['message'];
      if (m is String && m.isNotEmpty) return m;
    }
    return null;
  }
}
