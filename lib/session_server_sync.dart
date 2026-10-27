import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'accounts.dart';
import 'app_settings.dart';
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

/// The local secure account store is the outbox (only for accounts left by
/// older versions; pass numbers never enter it). A persistent journal
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

  static Future<void> groupChanges(List<SavedAccount> accounts) async {
    final client = ServerSessions.active;
    if (client == null) return;
    await _journal(() async {
      final journal = await _read(client);
      for (final account in accounts) {
        final id =
            serverAccountId(account.cookie) ?? client.importedIds[account.id];
        if (id == null) continue;
        final remote = client.accounts.where((a) => a['id'] == id).firstOrNull;
        if (remote == null ||
            remote['group_id'] == account.groupId &&
                remote['group_name'] == account.groupName) {
          continue;
        }
        final key = serverAccountId(account.cookie) == null
            ? account.id
            : 'remote:$id';
        final record =
            (journal[key] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        final desired = {'id': account.groupId, 'name': account.groupName};
        if (jsonEncode(record['pending_group']) != jsonEncode(desired)) {
          record['remote_id'] = id;
          record['pending_group'] = desired;
          record['pending_group_version'] = remote['version'];
          journal[key] = record;
        }
      }
      await _storage.write(key: _key(client), value: jsonEncode(journal));
    });
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
    client.setGroupFilter((await AppSettingsStore().loadMyGroup())?.id);
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
        if (serverAccountId(account.cookie) != null ||
            client.groupId != null && account.groupId != client.groupId) {
          continue;
        }
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
            if (remote['expires_at'] == null &&
                account.expiresAt?.isAfter(DateTime.now()) == true) {
              try {
                await client.publishExpiry(
                  id,
                  account.expiresAt!,
                  remote['session_version'] as int,
                );
                await client.fetch();
              } on SessionServerException catch (error) {
                if (error.status != 409) rethrow;
              }
            }
            record['session_version'] = remote['session_version'];
            journal[account.id] = record;
            await _storage.write(key: _key(client), value: jsonEncode(journal));
          });
        } catch (_) {
          pending++;
        }
      }
      await _journal(() async {
        final journal = await _read(client);
        for (final entry in journal.entries) {
          final record = (entry.value as Map).cast<String, dynamic>();
          final group = record['pending_group'] as Map?;
          if (group == null) continue;
          try {
            await client.publishGroup(
              record['remote_id'] as String,
              group['id'] as int?,
              group['name'] as String?,
              record['pending_group_version'] as int,
            );
            record.remove('pending_group');
            record.remove('pending_group_version');
          } on SessionServerException catch (error) {
            if (error.status == 409 || error.status == 404) {
              // A newer server edit wins; never rebase an old offline assignment.
              record.remove('pending_group');
              record.remove('pending_group_version');
            } else {
              pending++;
            }
          } catch (_) {
            pending++;
          }
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
