import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// tRPC v11 keepAlive uses raw `PING` / `PONG` text frames (not JSON).
String? keepAliveReply(String raw) {
  if (raw == 'PING') return 'PONG';
  if (raw == 'ping') return 'pong';
  return null;
}

/// Official wsLink appends this so the server waits for the first JSON
/// `{ method: connectionParams, data: { token, deviceToken } }` message.
Uri trpcWsUrl(String httpOrigin) {
  var ws = httpOrigin;
  if (ws.startsWith('https://')) {
    ws = 'wss://${ws.substring('https://'.length)}';
  } else if (ws.startsWith('http://')) {
    ws = 'ws://${ws.substring('http://'.length)}';
  }
  return Uri.parse(ws).replace(queryParameters: {'connectionParams': '1'});
}

class TrpcException implements Exception {
  TrpcException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

class TrpcClient {
  TrpcClient({
    required this.url,
    required this.connectionParams,
  });

  final Uri url;
  final Map<String, dynamic> Function() connectionParams;

  WebSocketChannel? _channel;
  final _pending = <int, Completer<dynamic>>{};
  final _subs = <int, StreamController<dynamic>>{};
  int _nextId = 1;
  bool _opened = false;
  Completer<void>? _ready;
  Timer? _ping;
  void Function(int code, String reason)? onClose;

  Future<void> connect() async {
    await close(silent: true);
    _ready = Completer<void>();
    _channel = WebSocketChannel.connect(url);
    _channel!.stream.listen(
      _onMessage,
      onDone: () {
        final closeCode = _channel?.closeCode ?? 1006;
        final reason = _channel?.closeReason ?? '';
        _failAll('Disconnected');
        onClose?.call(closeCode, reason);
      },
      onError: (Object e) {
        _failAll('$e');
        onClose?.call(1006, '$e');
      },
    );
    await _channel!.ready;
    _opened = true;
    _send({
      'method': 'connectionParams',
      'data': connectionParams(),
    });
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(seconds: 30), (_) {
      _channel?.sink.add('PING');
    });
    _ready?.complete();
  }

  Future<dynamic> query(String path, [dynamic input]) {
    return _request('query', path, input);
  }

  Future<dynamic> mutate(String path, [dynamic input]) {
    return _request('mutation', path, input);
  }

  Stream<dynamic> subscribe(String path, [dynamic input]) {
    final id = _nextId++;
    final controller = StreamController<dynamic>.broadcast(
      onCancel: () {
        _send({
          'id': id,
          'method': 'subscription.stop',
        });
        _subs.remove(id);
      },
    );
    _subs[id] = controller;
    _send({
      'id': id,
      'method': 'subscription',
      'params': {
        'path': path,
        if (input != null) 'input': input,
      },
    });
    return controller.stream;
  }

  Future<dynamic> _request(String method, String path, dynamic input) async {
    if (!_opened) await _ready?.future;
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    _send({
      'id': id,
      'method': method,
      'params': {
        'path': path,
        if (input != null) 'input': input,
      },
    });
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        throw TrpcException('Request timed out: $path');
      },
    );
  }

  void _send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final pong = keepAliveReply(raw);
    if (pong != null) {
      _channel?.sink.add(pong);
      return;
    }
    if (raw == 'PONG' || raw == 'pong') return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (msg['method'] == 'ping') {
      _send({'method': 'pong'});
      return;
    }
    final error = msg['error'];
    final id = msg['id'];
    final idNum = id is int ? id : int.tryParse('$id');
    if (error != null) {
      final map = error is Map ? Map<String, dynamic>.from(error) : {};
      final message = '${map['message'] ?? map['data']?['message'] ?? error}';
      final code = map['data'] is Map
          ? '${(map['data'] as Map)['code'] ?? ''}'
          : '${map['code'] ?? ''}';
      if (idNum == null) {
        _failAll(message);
        return;
      }
      final pending = _pending.remove(idNum);
      if (pending != null && !pending.isCompleted) {
        pending.completeError(TrpcException(message, code: code));
      }
      final sub = _subs[idNum];
      sub?.addError(TrpcException(message, code: code));
      return;
    }

    if (idNum == null) return;

    final result = msg['result'];
    if (result is Map) {
      final type = result['type'];
      final data = result['data'];
      if (type == 'started') return;
      if (type == 'stopped') {
        _subs.remove(idNum)?.close();
        return;
      }
      final pending = _pending.remove(idNum);
      if (pending != null && !pending.isCompleted) {
        pending.complete(data);
        return;
      }
      _subs[idNum]?.add(data);
    }
  }

  void _failAll(String reason) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(TrpcException(reason));
    }
    _pending.clear();
    for (final s in _subs.values) {
      s.addError(TrpcException(reason));
      s.close();
    }
    _subs.clear();
  }

  Future<void> close({bool silent = false}) async {
    _opened = false;
    _ping?.cancel();
    _ping = null;
    if (!silent) _failAll('Closed');
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }
}
