import 'dart:async';

import 'package:flutter/foundation.dart';

import 'nfc_pass.dart' show nfcPassChannel;
import 'server_api.dart';

/// Server numbers stay in memory, protected by a short foreground NFC lease.
/// A lease is a local permission deadline, not a claim about university expiry.
class ServerNfcController extends ChangeNotifier {
  ServerNfcController(this.api, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final AaServerApi api;
  final DateTime Function() _now;
  List<Map<String, dynamic>> cards = [];
  final selected = <String>{};
  final enrolled = <String, bool>{};
  bool single = true, busy = false, running = false;
  int seconds = 60;
  Object? error;
  Map<String, dynamic> status = {};
  List<Map<String, Object>> _credentials = [];
  Timer? _timer;
  DateTime? _validatedAt;
  bool _disposed = false, _polling = false;
  int _epoch = 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    if (busy || running || _disposed) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    _notify();
    try {
      final result = await api.digitalPasses();
      if (_disposed || epoch != _epoch) return;
      final updated = serverRows(result['passes']);
      final states = <String, bool>{};
      final allowed = updated.where((c) => c['pass_allowed'] == true).toList();
      // Keep only enrollment state; credentials are read afresh on activation.
      // Limit concurrent reads for large shared groups.
      for (var offset = 0; offset < allowed.length; offset += 4) {
        await Future.wait(
          allowed.skip(offset).take(4).map((card) async {
            if (_disposed || epoch != _epoch) return;
            final id = card['account_id'];
            if (id is! String) return;
            try {
              final pass = await api.digitalPass(id);
              if (pass['account_id'] == id && pass.containsKey('number')) {
                if (pass['number'] == null) states[id] = false;
                if (pass['number'] is String &&
                    (pass['number'] as String).isNotEmpty) {
                  states[id] = true;
                }
              }
            } catch (_) {
              // Unknown status must not offer unnecessary reissuance.
            }
          }),
        );
        if (_disposed || epoch != _epoch) return;
      }
      cards = updated;
      enrolled
        ..clear()
        ..addAll(states);
      selected.retainAll(
        cards
            .where((c) => c['pass_allowed'] == true)
            .map((c) => c['account_id'])
            .whereType<String>(),
      );
      if (selected.isEmpty) {
        final own = cards
            .where((c) => c['own'] == true && c['pass_allowed'] == true)
            .firstOrNull;
        if (own?['account_id'] case final String id) selected.add(id);
      }
    } catch (e) {
      if (!_disposed && epoch == _epoch) {
        error = e;
        cards = [];
        enrolled.clear();
        selected.clear();
      }
    } finally {
      if (!_disposed && epoch == _epoch) {
        busy = false;
        _notify();
      }
    }
  }

  void choose(String id) {
    if (busy || running) return;
    if (single) {
      selected.clear();
      selected.add(id);
    } else if (!selected.add(id)) {
      selected.remove(id);
    }
    _notify();
  }

  void setSingle(bool value) {
    if (busy || running) return;
    single = value;
    if (single && selected.length > 1) {
      final first = selected.first;
      selected.clear();
      selected.add(first);
    }
    _notify();
  }

  Future<List<Map<String, Object>>> _readNumbers(
    List<String> ids,
    int epoch,
  ) async {
    final values = <Map<String, Object>>[];
    for (final id in ids) {
      if (_disposed || epoch != _epoch) {
        throw StateError('Pass operation cancelled.');
      }
      final result = await api.digitalPass(id);
      if (_disposed || epoch != _epoch) {
        throw StateError('Pass operation cancelled.');
      }
      final number = result['number'];
      final parsed =
          number is String && RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(number)
          ? BigInt.tryParse(number)
          : null;
      if (result['account_id'] != id ||
          parsed == null ||
          parsed > BigInt.parse('9223372036854775807')) {
        throw const FormatException('No usable digital pass.');
      }
      values.add({'accountId': id, 'number': number as String});
    }
    return values;
  }

  List<Map<String, Object>> _leased(List<Map<String, Object>> values) {
    final deadline = _now()
        .add(const Duration(seconds: 90))
        .millisecondsSinceEpoch;
    return [
      for (final value in values) {...value, 'expiresAt': deadline},
    ];
  }

  Future<void> activate() async {
    if (busy || running || _disposed || selected.isEmpty) return;
    final epoch = ++_epoch;
    busy = true;
    error = null;
    _notify();
    try {
      final fresh = serverRows((await api.digitalPasses())['passes']);
      final chosen = fresh
          .where(
            (c) =>
                selected.contains(c['account_id']) && c['pass_allowed'] == true,
          )
          .toList();
      if (chosen.length != selected.length ||
          chosen.length > 100 ||
          (single && chosen.length != 1)) {
        throw const FormatException('Pass selection is no longer available.');
      }
      // Your pass is always last when a queue is used.
      final ordered = [
        ...chosen.where((c) => c['own'] != true),
        ...chosen.where((c) => c['own'] == true),
      ];
      final values = await _readNumbers(
        ordered.map((c) => c['account_id'] as String).toList(),
        epoch,
      );
      if (_disposed || epoch != _epoch) return;
      final result = await nfcPassChannel.invokeMapMethod<String, dynamic>(
        'start',
        {
          'passes': _leased(values),
          'single': single,
          'intervalSeconds': seconds,
        },
      );
      if (_disposed || epoch != _epoch) {
        await nfcPassChannel.invokeMethod<void>('stop');
        return;
      }
      _credentials = values;
      _validatedAt = _now();
      cards = fresh;
      status = result ?? {};
      running = true;
      _timer = Timer.periodic(
        const Duration(milliseconds: 400),
        (_) => unawaited(poll()),
      );
    } catch (e) {
      if (!_disposed && epoch == _epoch) {
        await stop();
        error = e;
        _notify();
      }
    } finally {
      if (!_disposed && epoch == _epoch) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> poll() async {
    if (_polling || !running || _disposed) return;
    _polling = true;
    final epoch = _epoch;
    try {
      final result =
          await nfcPassChannel.invokeMapMethod<String, dynamic>('status') ?? {};
      if (_disposed || epoch != _epoch) return;
      status = result;
      if (status['armed'] != true || status['expired'] == true) {
        await stop();
        return;
      }
      if (_validatedAt == null ||
          _now().difference(_validatedAt!) >= const Duration(seconds: 20)) {
        final fresh = await _readNumbers(
          _credentials.map((c) => c['accountId'] as String).toList(),
          epoch,
        );
        if (_disposed || epoch != _epoch) return;
        for (var i = 0; i < fresh.length; i++) {
          if (fresh[i]['number'] != _credentials[i]['number']) {
            throw const FormatException('The digital pass changed.');
          }
        }
        await nfcPassChannel.invokeMethod<void>('renew', {
          'passes': _leased(fresh),
        });
        if (_disposed || epoch != _epoch) return;
        _validatedAt = _now();
      }
      _notify();
    } catch (e) {
      if (!_disposed && epoch == _epoch) {
        await stop();
        error = e;
        _notify();
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> stop() async {
    ++_epoch;
    _timer?.cancel();
    _timer = null;
    running = false;
    busy = false;
    _credentials = [];
    _validatedAt = null;
    status = {};
    _notify();
    try {
      await nfcPassChannel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    _timer?.cancel();
    _credentials = [];
    unawaited(
      nfcPassChannel.invokeMethod<void>('stop').catchError((Object _) {}),
    );
    super.dispose();
  }
}
