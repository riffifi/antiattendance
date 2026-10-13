import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'accounts.dart';
import 'nfc_pass.dart';
import 'server_sessions.dart';

class SessionSyncStatus {
  const SessionSyncStatus({
    this.running = false,
    this.pending = 0,
    this.lastSuccess,
    this.failed = false,
  });
  final bool running;
  final int pending;
  final DateTime? lastSuccess;
  final bool failed;
}

/// The local secure account/pass stores are the outbox. A persistent journal
/// records what was acknowledged and the revision observed before an offline
/// edit. Refetching never silently rebases an old edit onto a newer revision.
abstract final class SessionAutoSync {
  static const _storage = FlutterSecureStorage();
  static final status = ValueNotifier(const SessionSyncStatus());
  static Future<void>? _running;
  static bool _requested = false;
  static Future<void> _journalQueue = Future.value();
  static String _key(SessionServerClient client) =>
      'session_sync_${sha256.convert(utf8.encode(client.base.origin))}';
  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();
  static String _view(SessionServerClient client) => jsonEncode(
    client.accounts
        .map(
          (a) => {
            for (final field in [
              'id',
              'label',
              'state',
              'session_version',
              'pass_version',
              'expires_at',
              'group_id',
              'group_name',
            ])
              field: a[field],
          },
        )
        .toList(),
  );
  static Future<Map<String, dynamic>> _read(SessionServerClient client) async {
    final raw = await _storage.read(key: _key(client));
    return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<T> _journal<T>(Future<T> Function() action) {
    final result = _journalQueue.then((_) => action());
    _journalQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  static void install() {
    ServerSessions.syncHandler = sync;
  }

  static Future<void> accountChanges(
    List<SavedAccount> before,
    List<SavedAccount> after,
  ) async {
    final client = ServerSessions.active;
    if (client == null) return;
    final observed = {
      for (final a in client.accounts) a['id']: a['session_version'],
    };
    await _journal(() async {
      final journal = await _read(client);
      final old = {for (final a in before) a.id: a};
      for (final a in after) {
        if (serverAccountId(a.cookie) != null ||
            old[a.id]?.cookie == a.cookie) {
          continue;
        }
        final record = (journal[a.id] as Map?)?.cast<String, dynamic>();
        final id = record?['remote_id'] ?? client.importedIds[a.id];
        if (record != null) {
          record['pending_session_hash'] = _hash(a.cookie);
          final baseline = observed[id] ?? record['session_version'];
          final current = client.accounts
              .where((a) => a['id'] == id)
              .firstOrNull;
          record['pending_session_version'] =
              baseline == record['own_session_base'] &&
                  current?['session_version'] == record['own_session_version']
              ? record['own_session_version']
              : baseline;
          journal[a.id] = record;
        }
      }
      await _storage.write(key: _key(client), value: jsonEncode(journal));
    });
    request();
  }

  static Future<void> passChanged(SavedAccount account, String number) async {
    final client = ServerSessions.active;
    if (client == null) return;
    final id =
        serverAccountId(account.cookie) ?? client.importedIds[account.id];
    final observedVersion = id == null ? 0 : client.passVersion(id);
    await _journal(() async {
      final journal = await _read(client);
      final journalId = serverAccountId(account.cookie) == null
          ? account.id
          : 'remote:$id';
      final record =
          (journal[journalId] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      record['remote_id'] = id;
      record['pending_pass'] = number;
      record['pending_pass_version'] =
          observedVersion == record['own_pass_base'] &&
              id != null &&
              client.passVersion(id) == record['own_pass_version'] &&
              client.passNumber(id) == record['own_pass_number']
          ? record['own_pass_version']
          : observedVersion;
      journal[journalId] = record;
      await _storage.write(key: _key(client), value: jsonEncode(journal));
    });
    request();
  }

  static void request() {
    install();
    _requested = true;
    unawaited(sync());
  }

  static Future<void> sync() {
    install();
    final existing = _running;
    if (existing != null) return existing;
    final run = () async {
      do {
        _requested = false;
        try {
          await _sync();
        } catch (_) {
          status.value = SessionSyncStatus(
            failed: true,
            lastSuccess: status.value.lastSuccess,
          );
        }
      } while (_requested);
    }();
    _running = run;
    return run.whenComplete(() {
      if (identical(_running, run)) _running = null;
    });
  }

  static Future<void> _sync() async {
    await ServerSessions.initialize();
    final client = ServerSessions.active;
    if (client == null) return;
    final before = _view(client);
    status.value = SessionSyncStatus(
      running: true,
      lastSuccess: status.value.lastSuccess,
    );
    var pending = 0;
    try {
      await client.fetch();
      final local = await AccountStore().loadLocal();
      for (final account in local) {
        if (!identical(ServerSessions.active, client)) return;
        if (serverAccountId(account.cookie) != null) continue;
        try {
          // Only a single entry is locked, so a concurrent enrollment cannot
          // lose its pending edit while a network request is in flight.
          await _journal(() async {
            final journal = await _read(client);
            final record =
                (journal[account.id] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            final cookieHash = _hash(account.cookie);
            var id =
                record['remote_id'] as String? ??
                client.importedIds[account.id];
            var remote = client.accounts
                .where((r) => r['id'] == id)
                .firstOrNull;
            if (id != null) {
              client.importedIds[account.id] = id;
            }
            // A panel removal must not resurrect a retained old local copy.
            if (id != null &&
                remote == null &&
                record['cookie_hash'] == cookieHash) {
              return;
            }
            if (record['cookie_hash'] != cookieHash || id == null) {
              try {
                remote = await client.publishSession(
                  account.toJson(),
                  remoteId: remote == null ? null : id,
                  expectedSessionVersion:
                      remote == null || record['cookie_hash'] == null
                      ? null
                      : (record['pending_session_version'] ??
                                record['session_version'])
                            as int?,
                );
                record['own_session_base'] =
                    record['pending_session_version'] ??
                    record['session_version'];
                record['own_session_version'] = remote['session_version'];
                id = remote['id'] as String;
              } on SessionServerException catch (error) {
                if (error.status != 409) rethrow;
                await client.fetch();
                remote = client.accounts
                    .where((r) => r['id'] == id)
                    .firstOrNull;
                if (remote == null) rethrow;
              }
              record['cookie_hash'] = cookieHash;
              record.remove('pending_session_hash');
              record.remove('pending_session_version');
              record['remote_id'] = id;
              client.importedIds[account.id] = id!;
              await ServerSessions.saveMappings();
              await client.fetch();
              remote = client.accounts.where((r) => r['id'] == id).firstOrNull;
            }
            if (remote == null) return;
            final number = await NfcPassStore().number(account);
            if (number != null && record['pass_number'] != number) {
              final expected =
                  record['pending_pass_version'] as int? ??
                  record['pass_version'] as int? ??
                  0;
              // Initial enrollment on an unlinked phone adopts the shared pass.
              if (record['pass_number'] != null ||
                  client.passNumber(id) == null) {
                try {
                  await client.publishPass(
                    id,
                    number,
                    expectedVersion: expected,
                  );
                  record['own_pass_base'] = expected;
                  record['own_pass_version'] = expected + 1;
                  record['own_pass_number'] = number;
                } on SessionServerException catch (error) {
                  if (error.status != 409) rethrow;
                }
                await client.fetch();
              }
              record['pass_number'] = number;
              record.remove('pending_pass');
              record.remove('pending_pass_version');
            }
            record['session_version'] = remote['session_version'];
            record['pass_version'] = client.passVersion(id);
            journal[account.id] = record;
            await _storage.write(key: _key(client), value: jsonEncode(journal));
          });
        } catch (_) {
          pending++;
        }
      }
      await _journal(() async {
        final journal = await _read(client);
        for (final entry in journal.entries.where(
          (e) => e.key.startsWith('remote:'),
        )) {
          final record = (entry.value as Map).cast<String, dynamic>();
          final number = record['pending_pass'] as String?;
          if (number == null) continue;
          try {
            final id = record['remote_id'] as String;
            await client.publishPass(
              id,
              number,
              expectedVersion: record['pending_pass_version'] as int,
            );
            record.remove('pending_pass');
            record.remove('pending_pass_version');
          } on SessionServerException catch (error) {
            if (error.status == 409 || error.status == 404) {
              record.remove('pending_pass');
              record.remove('pending_pass_version');
            } else {
              pending++;
            }
          } catch (_) {
            pending++;
          }
          journal[entry.key] = record;
        }
        await _storage.write(key: _key(client), value: jsonEncode(journal));
      });
      await client.fetch();
      if (!identical(ServerSessions.active, client)) return;
      await ServerSessions.saveMappings();
      status.value = SessionSyncStatus(
        pending: pending,
        failed: pending > 0,
        lastSuccess: DateTime.now(),
      );
      if (before != _view(client)) ServerSessions.notify();
    } catch (_) {
      if (identical(ServerSessions.active, client)) {
        status.value = SessionSyncStatus(
          failed: true,
          pending: pending,
          lastSuccess: status.value.lastSuccess,
        );
      }
    }
  }
}
