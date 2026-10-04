import 'campus_design.dart';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import 'l10n.dart';
import 'schedule_api.dart';

class GroupPickerPage extends StatefulWidget {
  const GroupPickerPage({super.key, required this.api});
  final ScheduleApi api;

  @override
  State<GroupPickerPage> createState() => _GroupPickerPageState();
}

class _GroupPickerPageState extends State<GroupPickerPage> {
  final _controller = TextEditingController();
  List<ScheduleGroup> _groups = [];
  String? _error;
  bool _loading = false;
  int _generation = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final generation = ++_generation;
    final query = _controller.text.trim();
    if (query.length < 2) {
      setState(() => _groups = []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await widget.api.searchGroups(query);
      if (mounted && generation == _generation) {
        setState(() => _groups = groups);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = tr(
            context,
            'Не удалось найти группы.',
            'Could not search groups.',
          ),
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'Выбрать группу', 'Choose group')),
      automaticallyImplyLeading: true,
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: CampusTextField(
                controller: _controller,
                autofocus: true,
                label: tr(
                  context,
                  'Например, ИНБО-10-23',
                  'For example, ИНБО-10-23',
                ),
                leading: const Icon(Icons.search_rounded),
                trailing: M3EIconButton(
                  suppressInk: true,
                  onPressed: _search,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  variant: M3EIconButtonVariant.standard,
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            if (_loading) const M3EProgressIndicator.linearWavy(),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
            Expanded(
              child: ListView.builder(
                itemCount: _groups.length,
                itemBuilder: (context, index) {
                  final group = _groups[index];
                  return CampusListItem(
                    headline: (group.name),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(context, group),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
