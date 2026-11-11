import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'campus_design.dart';
import 'frontend/page_layout.dart';
import 'l10n.dart';
import 'server_api.dart';
import 'server_workspace.dart' show ServerMessage, serverError;

class ServerTodayPage extends StatefulWidget {
  const ServerTodayPage({super.key, required this.api});
  final AaServerApi api;
  @override
  State<ServerTodayPage> createState() => _ServerTodayPageState();
}

class _ServerTodayPageState extends State<ServerTodayPage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await widget.api.today();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = serverError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lessons = serverRows(_data?['lessons']);
    final people = serverRows(_data?['people']);
    return CampusScaffold(
      appBar: CampusAppBar(title: Text(tr(context, 'За день', 'Today'))),
      body: CampusRefresh(
        onRefresh: _load,
        child: ListView(
          padding: AaPageLayout.insets(context),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_busy) const CampusProgress.compact(),
            if (_error != null) ServerMessage(message: _error!),
            if (_data?['schedule_error'] != null)
              ServerMessage(message: '${_data!['schedule_error']}'),
            if (_data != null) ...[
              BrockmannText(
                '${_data!['group_name'] ?? ''} · ${_data!['date'] ?? ''}',
                role: BrockmannType.value,
              ),
              const SizedBox(height: 20),
              if (lessons.isEmpty)
                AaEmptyState(
                  title: tr(context, 'Занятий нет', 'No classes'),
                  detail: tr(
                    context,
                    'На сегодня занятия не найдены.',
                    'No classes were found for today.',
                  ),
                ),
              for (final person in people) ...[
                AaSectionHeading(
                  lowercase: false,
                  title: '${person['label'] ?? person['username'] ?? '—'}',
                ),
                for (final lesson in lessons)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BrockmannText(
                          '${lesson['start']}–${lesson['end']} · ${lesson['subject']}',
                          role: BrockmannType.body,
                        ),
                        const SizedBox(height: 6),
                        BrockmannText(
                          dayMark(
                                lesson,
                                '${person['id']}',
                              )?['message']?.toString() ??
                              dayMark(
                                lesson,
                                '${person['id']}',
                              )?['state']?.toString() ??
                              '—',
                          role: BrockmannType.caption,
                          color: context.brockmann.secondary,
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
