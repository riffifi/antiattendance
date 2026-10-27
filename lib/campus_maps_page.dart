import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'campus_design.dart';
import 'expressive.dart';
import 'external_links.dart';
import 'l10n.dart';
import 'schedule_api.dart';
import 'maps/campus_location.dart';
import 'maps/campus_map_canvas.dart';
import 'maps/campus_map_data.dart';
import 'maps/floor_georeference.dart';
import 'maps/indoor_route_planner.dart';

class CampusMapsPage extends StatefulWidget {
  const CampusMapsPage({
    super.key,
    this.room = '',
    this.repository,
    this.location,
    this.savedPlaces,
    this.lessons = const [],
  });
  final String room;
  final List<ScheduleLesson> lessons;
  final CampusMapRepository? repository;
  final CampusLocationService? location;
  final MapSavedPlacesStore? savedPlaces;
  @override
  State<CampusMapsPage> createState() => _CampusMapsPageState();
}

class _CampusMapsPageState extends State<CampusMapsPage>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  late final _repository = widget.repository ?? CampusMapRepository();
  late final _locator = widget.location ?? CampusLocationService();
  late final _saved = widget.savedPlaces ?? MapSavedPlacesStore();
  List<CampusMap> _campuses = [];
  int _campus = 0;
  String? _floorId;
  CampusPlace? _selected, _start;
  IndoorRoute? _route;
  Set<String> _favorites = {};
  String? _kind, _gpsError;
  bool _favoritesOnly = false,
      _failed = false,
      _routing = false,
      _routeFailed = false;
  bool _locating = false, _tracking = false, _saving = false;
  bool _avoidStairs = false;
  bool _resultsVisible = false;
  int _routeGeneration = 0, _locationGeneration = 0;
  int _positionFocus = 0;
  CampusPosition? _position;
  String? _positionCampus, _positionFloor;
  StreamSubscription<CampusPosition>? _positions;
  CampusMap get _map => _campuses[_campus];
  CampusFloor get _floor => _map.floor(_floorId ?? _map.floors.first.id);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final room = RegExp(r'[А-Яа-яA-Za-z]-\d+[А-Яа-яA-Za-z0-9-]*')
        .firstMatch(widget.room);
    _search.text = room?.group(0) ?? widget.room;
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final campuses = await _repository.load();
      Set<String> favorites = {};
      try {
        favorites = await _saved.load();
      } catch (_) {
        /* Map browsing remains available when storage fails. */
      }
      if (!mounted) return;
      setState(() {
        _campuses = campuses;
        _favorites = favorites;
        if (widget.room.contains('86')) _campus = 1;
        if (widget.room.contains('С-20') || widget.room.contains('Стромын')) {
          _campus = 2;
        }
        _floorId = _map.floors.first.id;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    ++_locationGeneration;
    _positions?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_tracking) _watchLocation();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _positions?.cancel();
      _positions = null;
    }
  }

  void _invalidateRoute() {
    ++_routeGeneration;
    _routing = false;
    _route = null;
    _routeFailed = false;
  }

  void _select(CampusPlace place, int campus) {
    FocusScope.of(context).unfocus();
    setState(() {
      if (campus != _campus) _start = null;
      _campus = campus;
      _floorId = place.floorId;
      _selected = place;
      _search.clear();
      _kind = null;
      _favoritesOnly = false;
      _resultsVisible = false;
      _invalidateRoute();
    });
  }

  Future<void> _favorite(CampusPlace place) async {
    if (_saving) return;
    final previous = Set<String>.of(_favorites);
    setState(() {
      _saving = true;
      if (!_favorites.add(place.id)) _favorites.remove(place.id);
    });
    try {
      await _saved.save(Set.of(_favorites));
    } catch (_) {
      if (mounted) {
        setState(() => _favorites = previous);
        _message(
          tr(
            context,
            'Не удалось сохранить место.',
            'Could not save the place.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _directions() async {
    final destination = _selected;
    if (destination == null) return;
    if (_start == null) {
      final origin = await showExpressiveSheet<CampusPlace>(
        context: context,
        builder: (context) => _PlacePicker(
          campus: _map,
          title: tr(context, 'Откуда идём?', 'Choose starting place'),
          position: _positionCampus == _map.id && _position?.usable == true
              ? _position
              : null,
          floorId: _positionFloor,
        ),
      );
      if (!mounted || origin == null) return;
      setState(() => _start = origin);
    }
    final generation = ++_routeGeneration;
    final campus = _map.id;
    setState(() {
      _routing = true;
      _routeFailed = false;
      _route = null;
    });
    try {
      final result = await _repository.route(
        campus,
        _start!,
        destination,
        avoidStairs: _avoidStairs,
      );
      if (!mounted || generation != _routeGeneration) return;
      setState(() {
        _route = result.route;
        _routeFailed = !result.hasRoute;
        _floorId = _start!.floorId;
      });
    } catch (_) {
      if (mounted && generation == _routeGeneration) {
        setState(() => _routeFailed = true);
      }
    } finally {
      if (mounted && generation == _routeGeneration) {
        setState(() => _routing = false);
      }
    }
  }

  Future<void> _locate() async {
    if (_locating) return;
    final generation = ++_locationGeneration;
    setState(() {
      _locating = true;
      _gpsError = null;
    });
    try {
      final position = await _locator.locate();
      if (!mounted || generation != _locationGeneration) return;
      if (!position.usable) throw const CampusLocationException('timeout');
      var nearest = 0;
      for (var c = 1; c < _campuses.length; c++) {
        if (campusDistance(
              position.latitude,
              position.longitude,
              _campuses[c],
            ) <
            campusDistance(
              position.latitude,
              position.longitude,
              _campuses[nearest],
            )) {
          nearest = c;
        }
      }
      if (campusDistance(
            position.latitude,
            position.longitude,
            _campuses[nearest],
          ) >
          1000) {
        throw const CampusLocationException('outside');
      }
      final campus = _campuses[nearest];
      setState(() => _locating = false);
      final floor = await showExpressiveSheet<String>(
        context: context,
        builder: (context) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${campus.shortTitle} · ${tr(context, 'На каком вы этаже?', 'Which floor are you on?')}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  tr(
                    context,
                    'GPS не определяет этаж. Выберите его вручную.',
                    'GPS cannot identify your floor. Select it manually.',
                  ),
                ),
              ),
              for (final floor in campus.floors)
                CampusListItem(
                  headline: campusFloorLabel(context, floor),
                  onTap: () => Navigator.pop(context, floor.id),
                ),
            ],
          ),
        ),
      );
      if (!mounted || generation != _locationGeneration || floor == null) {
        return;
      }
      setState(() {
        if (_campus != nearest) {
          _start = null;
          _selected = null;
          _invalidateRoute();
        }
        _campus = nearest;
        _floorId = floor;
        _positionCampus = campus.id;
        _positionFloor = floor;
        _position = position;
        _tracking = true;
        ++_positionFocus;
      });
      _watchLocation();
    } on CampusLocationException catch (e) {
      if (mounted && generation == _locationGeneration) {
        setState(() => _gpsError = e.reason);
      }
    } catch (_) {
      if (mounted && generation == _locationGeneration) {
        setState(() => _gpsError = 'unavailable');
      }
    } finally {
      if (mounted && generation == _locationGeneration) {
        setState(() => _locating = false);
      }
    }
  }

  void _watchLocation() {
    _positions?.cancel();
    _positions = _locator.watch().listen(
      (position) {
        if (mounted && _tracking) {
          setState(() {
            _position = position;
            _gpsError = null;
          });
        }
      },
      onError: (Object _) {
        if (mounted) {
          setState(() {
            _gpsError = 'unavailable';
            _tracking = false;
            _position = null;
          });
        }
        _positions?.cancel();
        _positions = null;
      },
    );
  }

  String _locationError() => switch (_gpsError) {
    'disabled' => tr(
      context,
      'Включите геолокацию на устройстве.',
      'Turn on device location.',
    ),
    'permanent' || 'denied' => tr(
      context,
      'Разрешите геолокацию или выберите начало маршрута вручную.',
      'Allow location access or choose a starting place manually.',
    ),
    'outside' => tr(
      context,
      'Вы за пределами доступных кампусов.',
      'You are outside the mapped campuses.',
    ),
    _ => tr(
      context,
      'Местоположение недоступно. Начало маршрута можно выбрать вручную.',
      'Location unavailable. You can choose a starting place manually.',
    ),
  };

  Future<void> _lessonPlaces() async {
    final lesson = await showExpressiveSheet<ScheduleLesson>(
      context: context,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr(context, 'Аудитории из расписания', 'Rooms from schedule'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final lesson in widget.lessons.where(
              (l) => l.location.isNotEmpty,
            ))
              CampusListItem(
                headline: lesson.subject,
                supportingText:
                    '${lesson.start.hour.toString().padLeft(2, '0')}:${lesson.start.minute.toString().padLeft(2, '0')} · ${lesson.location}',
                onTap: () => Navigator.pop(context, lesson),
              ),
          ],
        ),
      ),
    );
    if (!mounted || lesson == null) return;
    final room =
        RegExp(r'[А-Яа-яA-Za-z]-\d+[А-Яа-яA-Za-z0-9-]*')
            .firstMatch(lesson.location)
            ?.group(0) ??
        lesson.location;
    setState(() {
      _search.text = room;
      _kind = null;
      _favoritesOnly = false;
      _resultsVisible = false;
    });
  }

  Future<void> _openSource() async {
    final url = Uri.tryParse(
      _selected?.sourceUrl ?? 'https://pulse.mirea.ru/services/maps',
    );
    if (url == null || url.scheme != 'https' || url.host != 'pulse.mirea.ru') {
      return;
    }
    if (!await openWebPage(url) && mounted) {
      _message(
        tr(context, 'Не удалось открыть ссылку.', 'Could not open the link.'),
      );
    }
  }

  Future<void> _campusDirections() async {
    final campus = _map;
    final url = Uri.https('yandex.ru', '/maps/', {
      'rtext': '~${campus.latitude},${campus.longitude}',
      'rtt': 'pd',
    });
    if (!await openWebPage(url) && mounted) {
      _message(
        tr(context, 'Не удалось открыть ссылку.', 'Could not open the link.'),
      );
    }
  }

  Future<void> _showInstructions() => showExpressiveSheet<void>(
    context: context,
    builder: (context) {
      final route = _route!;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Text(
              '${_start!.label} → ${_selected!.label}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                context,
                'Маршрут по сохранённому плану. Проверяйте проходы и указатели на месте.',
                'Route uses the saved floor plan. Check passages and signs on site.',
              ),
            ),
            for (final instruction in route.instructions)
              CampusListItem(
                headline: _instruction(instruction),
                supportingText:
                    '${campusFloorLabel(context, _map.floor(instruction.floorId))}${instruction.distanceMeters == null || instruction.distanceMeters == 0 ? '' : ' · ≈${instruction.distanceMeters!.round()} m'}',
                onTap: () {
                  setState(() => _floorId = instruction.floorId);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      );
    },
  );
  String _instruction(
    IndoorRouteInstruction instruction,
  ) => switch (instruction.maneuver) {
    IndoorManeuver.depart => tr(context, 'Начало маршрута', 'Start walking'),
    IndoorManeuver.arrive => tr(
      context,
      'Вы на месте',
      'Arrive at destination',
    ),
    IndoorManeuver.turnLeft => tr(context, 'Поверните налево', 'Turn left'),
    IndoorManeuver.turnRight => tr(context, 'Поверните направо', 'Turn right'),
    IndoorManeuver.turnBack => tr(context, 'Развернитесь', 'Turn back'),
    IndoorManeuver.stairs =>
      '${tr(context, 'По лестнице', 'Take the stairs')} → ${campusFloorLabel(context, _map.floor(instruction.destinationFloorId ?? instruction.floorId))}',
    IndoorManeuver.elevator => tr(
      context,
      'Воспользуйтесь лифтом',
      'Take the elevator',
    ),
    IndoorManeuver.ramp => tr(context, 'По пандусу', 'Take the ramp'),
    IndoorManeuver.escalator => tr(
      context,
      'По эскалатору',
      'Take the escalator',
    ),
    IndoorManeuver.floorTransition =>
      '${tr(context, 'Смените этаж', 'Change floor')} → ${campusFloorLabel(context, _map.floor(instruction.destinationFloorId ?? instruction.floorId))}',
    IndoorManeuver.straight => tr(
      context,
      'Продолжайте прямо',
      'Continue straight',
    ),
  };

  @override
  Widget build(BuildContext context) {
    if (_campuses.isEmpty) {
      return Scaffold(
        appBar: CampusAppBar(
          title: Text(tr(context, 'Карты кампусов', 'Campus maps')),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: _failed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tr(
                          context,
                          'Не удалось загрузить карты.',
                          'Could not load campus maps.',
                        ),
                      ),
                      CampusButton.text(
                        onPressed: _load,
                        child: Text(tr(context, 'Повторить', 'Retry')),
                      ),
                    ],
                  )
                : const CampusProgress.compact(),
          ),
        ),
      );
    }
    final query = _search.text.trim();
    final searching = query.isNotEmpty || _favoritesOnly || _resultsVisible;
    final results = <({int campus, CampusPlace place})>[];
    if (searching || _kind != null) {
      for (var c = 0; c < _campuses.length; c++) {
        if (_kind != null && c != _campus) continue;
        for (final place in _campuses[c].search(
          query,
          kind: _kind,
          ids: _favoritesOnly ? _favorites : null,
        )) {
          results.add((campus: c, place: place));
        }
      }
    }
    FloorPoint? position;
    if (_position?.usable == true &&
        _positionCampus == _map.id &&
        _positionFloor == _floor.id) {
      final p = _floor.georeference.geographicToPixel(
        _position!.latitude,
        _position!.longitude,
      );
      if (_floor.contains(p)) position = p;
    }
    // The anchors are approximate, so include alignment uncertainty in the circle.
    final accuracy = _position == null
        ? null
        : math.sqrt(_position!.accuracy * _position!.accuracy + 25 * 25);
    return Scaffold(
      appBar: CampusAppBar(
        title: Text(tr(context, 'Карты кампусов', 'Campus maps')),
        actions: [
          CampusTextAction(
            onPressed: _locating ? null : _locate,
            tooltip: tr(context, 'Моё местоположение', 'My location'),
            label: tr(context, 'Моё местоположение', 'My location'),
          ),
          AppActionMenu(
            entries: [
              CampusMenuEntry(
                value: 'campus',
                label: tr(
                  context,
                  'Как добраться до кампуса',
                  'Directions to campus',
                ),
              ),
              CampusMenuEntry(
                value: 'pulse',
                label: tr(context, 'Открыть в Пульсе', 'Open in Pulse'),
              ),
            ],
            onSelected: (value) {
              if (value == 'campus') {
                _campusDirections();
              } else {
                _openSource();
              }
            },
            anchorBuilder: (_, open) => CampusTextAction(
              onPressed: open,
              tooltip: tr(context, 'Действия', 'Actions'),
              label: tr(context, 'Действия', 'Actions'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: CampusTextField(
                controller: _search,
                label: tr(context, 'Аудитория или место', 'Room or place'),
                trailing: CampusTextAction(
                  icon: Icons.close_rounded,
                  onPressed: () => setState(() {
                    _search.clear();
                    _kind = null;
                    _favoritesOnly = false;
                    _resultsVisible = false;
                  }),
                  tooltip: tr(context, 'Очистить', 'Clear'),
                  label: tr(context, 'Очистить', 'Clear'),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: AppActionMenu(
                      entries: [
                        for (var c = 0; c < _campuses.length; c++)
                          CampusMenuEntry(value: c, label: _campuses[c].title),
                      ],
                      onSelected: (value) => setState(() {
                        _campus = value as int;
                        _floorId = _map.floors.first.id;
                        _selected = null;
                        _start = null;
                        _invalidateRoute();
                      }),
                      anchorBuilder: (_, open) => CampusButton.action(
                        style: CampusButtonStyle.tonal,
                        onPressed: open,
                        label: Text(_map.shortTitle),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppActionMenu(
                      entries: [
                        for (final floor in _map.floors)
                          CampusMenuEntry(
                            value: floor.id,
                            label: campusFloorLabel(context, floor),
                          ),
                      ],
                      onSelected: (value) =>
                          setState(() => _floorId = value as String),
                      anchorBuilder: (_, open) => CampusButton.action(
                        style: CampusButtonStyle.tonal,
                        onPressed: open,
                        label: Text(campusFloorLabel(context, _floor)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _tag(null, tr(context, 'Все места', 'All places')),
                  _tag('toilet', tr(context, 'Туалеты', 'Toilets')),
                  _tag('cafeteria', tr(context, 'Еда', 'Food')),
                  _tag('entrance', tr(context, 'Входы', 'Entrances')),
                  _tag('cloakroom', tr(context, 'Гардероб', 'Cloakroom')),
                  _tag('medical', tr(context, 'Медпункт', 'Medical')),
                  CampusButton.action(
                    onPressed: () => setState(() {
                      _favoritesOnly = !_favoritesOnly;
                      _kind = null;
                    }),
                    label: Text(tr(context, 'Избранное', 'Saved places')),
                  ),
                ],
              ),
            ),
            if (_gpsError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _locationError(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_gpsError == 'disabled' || _gpsError == 'permanent')
                      CampusButton.text(
                        onPressed: () => _locator.openSettings(
                          app: _gpsError == 'permanent',
                        ),
                        child: Text(tr(context, 'Настройки', 'Settings')),
                      ),
                    CampusTextAction(
                      icon: Icons.close_rounded,
                      onPressed: () => setState(() => _gpsError = null),
                      tooltip: tr(context, 'Закрыть', 'Dismiss'),
                      label: tr(context, 'Закрыть', 'Dismiss'),
                    ),
                  ],
                ),
              ),
            if (_position != null && _positionCampus == _map.id)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Text(
                  trf(
                    context,
                    'Примерно ±{meters} м · этаж выбран вручную',
                    'Approx. ±{meters} m · floor selected manually',
                    {'meters': accuracy!.round()},
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_kind != null && !searching)
              CampusButton.text(
                onPressed: () => setState(() => _resultsVisible = true),
                child: Text(
                  '${tr(context, 'Список мест', 'Place list')} · ${results.length}',
                ),
              ),
            if (widget.lessons.isNotEmpty && !searching)
              CampusButton.action(
                onPressed: _lessonPlaces,
                label: Text(
                  tr(context, 'Аудитории из расписания', 'Rooms from schedule'),
                ),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CampusMapCanvas(
                      floor: _floor,
                      places: _map.places
                          .where((p) => p.floorId == _floor.id)
                          .toList(),
                      selected: _selected,
                      start: _start,
                      route: _route,
                      position: position,
                      locationFocus: _positionFocus,
                      accuracyMeters: accuracy,
                      kind: _kind,
                      favorites: _favorites,
                      onPlace: (place) => _select(place, _campus),
                    ),
                  ),
                  if (searching)
                    Positioned.fill(
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: results.isEmpty
                            ? Center(
                                child: Text(
                                  tr(
                                    context,
                                    'Места не найдены.',
                                    'No places found.',
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: results.length,
                                itemBuilder: (context, index) {
                                  final result = results[index],
                                      place = result.place,
                                      campus = _campuses[result.campus];
                                  return CampusListItem(
                                    headline: place.label,
                                    supportingText:
                                        '${campus.shortTitle} · ${campusFloorLabel(context, campus.floor(place.floorId))} · ${placeKindLabel(context, place.kind)}',
                                    onTap: () => _select(place, result.campus),
                                  );
                                },
                              ),
                      ),
                    ),
                ],
              ),
            ),
            if (!searching && (_selected != null || _start != null))
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .32,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: _details(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Пульс РТУ МИРЭА · 12.09.2026',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String? kind, String label) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: CampusButton.action(
      style: _kind == kind && !_favoritesOnly
          ? CampusButtonStyle.tonal
          : CampusButtonStyle.text,
      onPressed: () => setState(() {
        _kind = kind;
        _favoritesOnly = false;
        _resultsVisible = false;
      }),
      label: Text(label),
    ),
  );
  Widget _details() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_start != null)
        Row(
          children: [
            Expanded(
              child: Text(
                '${tr(context, 'Откуда', 'From')}: ${_start!.label} · ${campusFloorLabel(context, _map.floor(_start!.floorId))}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            CampusTextAction(
              onPressed: () => setState(() {
                _start = null;
                _invalidateRoute();
              }),
              tooltip: tr(context, 'Сбросить маршрут', 'Clear route'),
              label: tr(context, 'Сбросить маршрут', 'Clear route'),
            ),
          ],
        ),
      if (_selected case final place?) ...[
        Row(
          children: [
            Expanded(
              child: Text(
                '${place.label} · ${campusFloorLabel(context, _map.floor(place.floorId))}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            CampusTextAction(
              onPressed: _saving ? null : () => _favorite(place),
              tooltip: tr(context, 'Сохранить место', 'Save place'),
              label: tr(context, 'Сохранить место', 'Save place'),
            ),
            CampusTextAction(
              icon: Icons.close_rounded,
              onPressed: () => setState(() {
                _selected = null;
                _invalidateRoute();
              }),
              tooltip: tr(context, 'Закрыть', 'Close'),
              label: tr(context, 'Закрыть', 'Close'),
            ),
          ],
        ),
        Text(
          placeKindLabel(context, place.kind),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (place.equipment.isNotEmpty) Text(place.equipment.join(' · ')),
        if (place.menu.isNotEmpty) Text(place.menu.join(' · ')),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            CampusButton.action(
              onPressed: _routing ? null : _directions,
              label: Text(tr(context, 'Маршрут', 'Directions')),
            ),
            CampusButton.text(
              onPressed: () => setState(() {
                _start = place;
                _invalidateRoute();
              }),
              child: Text(tr(context, 'Я здесь', 'Start here')),
            ),
            CampusButton.text(
              onPressed: () {
                setState(() {
                  _avoidStairs = !_avoidStairs;
                  _invalidateRoute();
                });
                if (_start != null) _directions();
              },
              child: Text(
                '${_avoidStairs ? '✓ ' : ''}${tr(context, 'Без лестниц', 'Avoid stairs')}',
              ),
            ),
          ],
        ),
      ],
      if (_routing)
        const Padding(
          padding: EdgeInsets.all(8),
          child: CampusProgress.linear(),
        ),
      if (_routeFailed)
        Text(
          tr(
            context,
            'Проход не найден на сохранённом плане. Выберите другое начало или разрешите лестницы.',
            'No route found in the saved plan. Choose another start or allow stairs.',
          ),
        ),
      if (_route case final route?) ...[
        CampusButton.text(
          onPressed: _showInstructions,
          child: Text(
            '${route.distanceMeters == null ? '' : '≈${route.distanceMeters!.round()} m · '}${route.durationSeconds == null ? '' : '≈${(route.durationSeconds! / 60).ceil()} min · '}${tr(context, 'Шаги маршрута', 'Route steps')}',
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final id in route.floorIds)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: CampusButton.action(
                    style: id == _floor.id
                        ? CampusButtonStyle.tonal
                        : CampusButtonStyle.text,
                    onPressed: () => setState(() => _floorId = id),
                    label: Text(campusFloorLabel(context, _map.floor(id))),
                  ),
                ),
            ],
          ),
        ),
      ],
    ],
  );
}

String campusFloorLabel(BuildContext context, CampusFloor floor) =>
    trf(context, 'Этаж {floor}', 'Floor {floor}', {'floor': floor.level});

String placeKindLabel(BuildContext context, String kind) => switch (kind) {
  'toilet' => tr(context, 'Туалеты', 'Toilets'),
  'cafeteria' => tr(context, 'Еда', 'Food'),
  'entrance' => tr(context, 'Входы', 'Entrances'),
  'cloakroom' => tr(context, 'Гардероб', 'Cloakroom'),
  'medical' => tr(context, 'Медпункт', 'Medical'),
  _ => tr(context, 'Аудитория', 'Room'),
};

class _PlacePicker extends StatefulWidget {
  const _PlacePicker({
    required this.campus,
    required this.title,
    this.position,
    this.floorId,
  });
  final CampusMap campus;
  final String title;
  final CampusPosition? position;
  final String? floorId;
  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final places = widget.campus.search(_search.text);
    if (widget.position case final position?
        when widget.floorId != null && _search.text.isEmpty) {
      final floor = widget.campus.floor(widget.floorId!);
      final point = floor.georeference.geographicToPixel(
        position.latitude,
        position.longitude,
      );
      places.sort((a, b) {
        if ((a.floorId == floor.id) != (b.floorId == floor.id)) {
          return a.floorId == floor.id ? -1 : 1;
        }
        return (math.pow(a.x - point.x, 2) + math.pow(a.y - point.y, 2))
            .compareTo(math.pow(b.x - point.x, 2) + math.pow(b.y - point.y, 2));
      });
    }
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  CampusTextField(
                    controller: _search,
                    label: tr(context, 'Аудитория или место', 'Room or place'),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (widget.position != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      tr(
                        context,
                        'Ближайшие места по приблизительной позиции. Подтвердите, где вы находитесь.',
                        'Nearby places use approximate location. Confirm where you are.',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: places.length,
            itemBuilder: (context, index) {
              final place = places[index];
              return CampusListItem(
                headline: place.label,
                supportingText:
                    '${campusFloorLabel(context, widget.campus.floor(place.floorId))} · ${placeKindLabel(context, place.kind)}',
                onTap: () => Navigator.pop(context, place),
              );
            },
          ),
        ],
      ),
    );
  }
}
