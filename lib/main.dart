import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'accounts.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'attendance_log.dart';
import 'group_picker_page.dart';
import 'l10n.dart';
import 'nearby_receive_page.dart';
import 'nearby_share_page.dart';
import 'pulse_api.dart';
import 'pulse_login.dart';
import 'queue_scan_page.dart';
import 'schedule_api.dart';
import 'schedule_page.dart';
import 'session_import_page.dart';
import 'session_share_page.dart';
import 'settings_page.dart';
import 'update_service.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.paper,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: AppColors.paper,
    ),
  );
  runApp(const AntiattendanceApp());
}

class AntiattendanceApp extends StatefulWidget {
  const AntiattendanceApp({super.key});

  @override
  State<AntiattendanceApp> createState() => _AntiattendanceAppState();
}

class _AntiattendanceAppState extends State<AntiattendanceApp>
    with WidgetsBindingObserver {
  static const _monetChannel = MethodChannel('antiattendance/monet');
  final AppSettingsStore _settingsStore = AppSettingsStore();
  final UpdateController _updates = UpdateController();
  String? _language;
  AppThemeMode _themeMode = AppThemeMode.light;
  bool _monetEnabled = false;
  Color? _monetSeed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLanguage();
    _loadAppearance();
    unawaited(_updates.check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updates.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_loadAppearance());
  }

  Future<void> _loadLanguage() async {
    try {
      final language = await _settingsStore.loadLanguage();
      if (mounted) setState(() => _language = language);
    } catch (_) {
      // A fresh install uses the phone language if settings are unavailable.
    }
  }

  Future<void> _loadAppearance() async {
    var mode = AppThemeMode.light;
    var monet = false;
    int? color;
    try {
      mode = await _settingsStore.loadThemeMode();
      monet = await _settingsStore.loadMonetEnabled();
    } catch (_) {
      // Keep default appearance if saved preferences cannot be read.
    }
    if (Platform.isAndroid) {
      try {
        color = await _monetChannel.invokeMethod<int>('getSeedColor');
      } catch (_) {
        // Android without wallpaper colors keeps the app accent.
      }
    }
    if (mounted) {
      setState(() {
        _themeMode = mode;
        _monetEnabled = monet;
        _monetSeed = color == null ? null : Color(color);
      });
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AntiAttendance',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.build(
      _themeMode,
      monetSeed: _monetEnabled ? _monetSeed : null,
    ),
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: _themeMode == AppThemeMode.amoled
            ? Colors.black
            : _themeMode == AppThemeMode.dark
            ? const Color(0xFF101820)
            : AppColors.paper,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: _themeMode == AppThemeMode.light
            ? Brightness.dark
            : Brightness.light,
      ),
      child: child!,
    ),
    locale: _language == null ? null : Locale(_language!),
    supportedLocales: const [
      Locale('en'),
      Locale('ru'),
      Locale('fr'),
      Locale('pt'),
      Locale('zh'),
    ],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: HomePage(
      settingsStore: _settingsStore,
      language: _language,
      onLanguageChanged: (language) => setState(() => _language = language),
      themeMode: _themeMode,
      onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
      monetEnabled: _monetEnabled,
      monetAvailable: _monetSeed != null,
      onMonetChanged: (value) => setState(() => _monetEnabled = value),
      updates: _updates,
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.store,
    this.api,
    this.scanQr,
    this.scheduleApi,
    this.logStore,
    this.settingsStore,
    this.language,
    this.onLanguageChanged,
    this.themeMode = AppThemeMode.light,
    this.onThemeModeChanged,
    this.monetEnabled = false,
    this.monetAvailable = false,
    this.onMonetChanged,
    this.updates,
  });

  final AccountStore? store;
  final PulseApi? api;
  final ScheduleApi? scheduleApi;
  final AttendanceLogStore? logStore;
  final AppSettingsStore? settingsStore;
  final String? language;
  final ValueChanged<String?>? onLanguageChanged;
  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode>? onThemeModeChanged;
  final bool monetEnabled;
  final bool monetAvailable;
  final ValueChanged<bool>? onMonetChanged;
  final UpdateController? updates;
  final Future<String?> Function(BuildContext context)? scanQr;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _widgetChannel = MethodChannel('antiattendance/launcher_widget');
  late final AccountStore _store = widget.store ?? AccountStore();
  late final PulseApi _api = widget.api ?? PulseApi();
  late final ScheduleApi _scheduleApi = widget.scheduleApi ?? ScheduleApi();
  late final AttendanceLogStore _logStore =
      widget.logStore ?? AttendanceLogStore();
  late final AppSettingsStore _settingsStore =
      widget.settingsStore ?? AppSettingsStore();
  int _tab = 0;
  DateTime? _scheduleDay;
  int? _scheduleGroupId;
  final _selected = <String>{};
  final _results = <String, ApprovalResult>{};
  final _errors = <String, String>{};
  List<SavedAccount> _accounts = [];
  List<AttendanceMark>? _marks;
  bool _loading = true;
  bool _loadError = false;
  bool _scanning = false;
  bool _submitting = false;
  bool _widgetScanPending = false;
  bool _widgetScanScheduled = false;
  Timer? _counterRefreshTimer;

  bool get _busy => _scanning || _submitting;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _widgetChannel.setMethodCallHandler(_onWidgetCall);
      unawaited(_takeInitialWidgetRequest());
    }
    _scheduleCounterRefresh();
    _load();
  }

  void _scheduleCounterRefresh() {
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _counterRefreshTimer = Timer(nextDay.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleCounterRefresh();
    });
  }

  Future<void> _onWidgetCall(MethodCall call) async {
    if (call.method == 'scanAll') _requestWidgetScan();
  }

  Future<void> _takeInitialWidgetRequest() async {
    try {
      if (await _widgetChannel.invokeMethod<bool>('takeScanAllRequest') ==
          true) {
        _requestWidgetScan();
      }
    } catch (_) {
      // Normal app launches continue if the native widget bridge is unavailable.
    }
  }

  void _requestWidgetScan() {
    if (!mounted) return;
    _widgetScanPending = true;
    _openPendingWidgetScan();
  }

  void _openPendingWidgetScan() {
    if (!_widgetScanPending ||
        _widgetScanScheduled ||
        _loading ||
        _loadError ||
        _busy ||
        !mounted) {
      return;
    }
    _widgetScanScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _widgetScanScheduled = false;
      if (!_widgetScanPending || _loading || _loadError || _busy || !mounted) {
        return;
      }
      _widgetScanPending = false;
      if (_accounts.isEmpty) {
        _message(
          tr(context, 'Сначала добавьте аккаунты.', 'Add accounts first.'),
        );
        return;
      }
      setState(() => _tab = 0);
      unawaited(_scanQueue(overrideAccounts: List.of(_accounts)));
    });
  }

  @override
  void dispose() {
    if (Platform.isAndroid) _widgetChannel.setMethodCallHandler(null);
    _counterRefreshTimer?.cancel();
    if (widget.api == null) _api.close();
    if (widget.scheduleApi == null) _scheduleApi.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_loading && mounted) setState(() => _loading = true);
    try {
      final accounts = await _store.load();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _marks = accounts.isEmpty ? [] : null;
        _selected.clear();
        _selected.addAll(accounts.map((account) => account.id));
        _loading = false;
        _loadError = false;
      });
      if (accounts.isNotEmpty) unawaited(_refreshMarks());
      _openPendingWidgetScan();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    }
  }

  Future<void> _refreshMarks() async {
    try {
      final marks = await _logStore.load();
      if (mounted) setState(() => _marks = marks);
    } catch (_) {
      if (mounted) setState(() => _marks = null);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(trMessage(context, message))));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          store: _settingsStore,
          language: widget.language,
          onLanguageChanged: widget.onLanguageChanged ?? (_) {},
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged ?? (_) {},
          monetEnabled: widget.monetEnabled,
          monetAvailable: widget.monetAvailable,
          onMonetChanged: widget.onMonetChanged ?? (_) {},
          updates: widget.updates,
        ),
      ),
    );
  }

  Future<String?> _askText({
    required String title,
    required String hint,
    required String action,
    String? initial,
    int? maxLength,
  }) => showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      hint: hint,
      action: action,
      initial: initial,
      maxLength: maxLength,
    ),
  );

  Future<void> _login({SavedAccount? replace}) async {
    if (_busy) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      _message(
        tr(
          context,
          'Вход через МИРЭА доступен на Android и iOS.',
          'MIREA sign-in is available on Android and iOS.',
        ),
      );
      return;
    }
    final cookie = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const PulseLoginPage()));
    if (!mounted || cookie == null) return;
    final label = await _askText(
      title: tr(context, 'Имя аккаунта', 'Account name'),
      hint: tr(context, 'Например, имя друга', 'For example, a friend’s name'),
      action: tr(context, 'Сохранить', 'Save'),
      initial: replace?.label,
      maxLength: 60,
    );
    if (!mounted || label == null) return;
    if (_accounts.any(
      (item) => item.id != replace?.id && item.cookie == cookie,
    )) {
      _message(
        tr(
          context,
          'Этот аккаунт уже добавлен.',
          'This account is already added.',
        ),
      );
      return;
    }
    final id = replace?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final next = [
      ..._accounts.where((item) => item.id != id),
      SavedAccount(
        id: id,
        label: label,
        cookie: cookie,
        groupId: replace?.groupId,
        groupName: replace?.groupName,
      ),
    ];
    try {
      await _store.save(next);
      if (mounted) {
        setState(() {
          _accounts = next;
          _selected.add(id);
          _results.remove(id);
          _errors.remove(id);
        });
      }
    } catch (_) {
      if (mounted) {
        _message(
          tr(
            context,
            'Не удалось сохранить аккаунт.',
            'Could not save the account.',
          ),
        );
      }
    }
  }

  Future<void> _remove(SavedAccount account) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          trf(context, 'Удалить {name}?', 'Delete {name}?', {
            'name': account.label,
          }),
        ),
        content: Text(
          tr(
            context,
            'Сохранённый вход будет удалён с устройства.',
            'The saved session will be removed from this device.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Удалить', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final next = _accounts.where((item) => item.id != account.id).toList();
    try {
      await _store.save(next);
      if (mounted) {
        setState(() {
          _accounts = next;
          _selected.remove(account.id);
          _results.remove(account.id);
          _errors.remove(account.id);
        });
      }
    } catch (_) {
      if (mounted) {
        _message(
          tr(
            context,
            'Не удалось удалить аккаунт.',
            'Could not delete the account.',
          ),
        );
      }
    }
  }

  Future<void> _scan() async {
    if (_busy) return;
    if (widget.scanQr == null) {
      await _scanQueue();
      return;
    }
    if (_selected.isEmpty) {
      _message(
        tr(context, 'Сначала выберите аккаунты.', 'Select accounts first.'),
      );
      return;
    }
    setState(() => _scanning = true);
    String? raw;
    try {
      raw = await widget.scanQr!(context);
    } catch (_) {
      if (mounted) {
        _message(
          tr(
            context,
            'Не удалось открыть камеру.',
            'Could not open the camera.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
        _openPendingWidgetScan();
      }
    }
    if (mounted && raw != null) await _submitLink(raw);
  }

  Future<void> _scanQueue({
    ScheduleLesson? lesson,
    List<SavedAccount>? overrideAccounts,
  }) async {
    if (_busy) return;
    final accounts =
        overrideAccounts ??
        _accounts.where((account) => _selected.contains(account.id)).toList();
    if (accounts.isEmpty) {
      _message(
        tr(context, 'Сначала выберите аккаунты.', 'Select accounts first.'),
      );
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      _message(
        tr(
          context,
          'Камера доступна на Android и iOS.',
          'The camera is available on Android and iOS.',
        ),
      );
      return;
    }
    setState(() {
      _scanning = true;
      _results.clear();
      _errors.clear();
    });
    final recorded = <String>{};
    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          transitionDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          pageBuilder: (_, _, _) => QueueScanPage(
            accounts: accounts,
            api: _api,
            onUpdate: (queue) {
              for (final account in accounts) {
                final result = queue.results[account.id];
                if (result?.state == ApprovalState.approved &&
                    recorded.add(account.id)) {
                  unawaited(_recordApproval(account, result!, lesson: lesson));
                }
              }
              if (!mounted) return;
              setState(() {
                _results
                  ..clear()
                  ..addAll(queue.results);
                _errors
                  ..clear()
                  ..addAll(queue.errors);
              });
            },
          ),
          transitionsBuilder: (context, animation, _, child) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
          ),
        ),
      );
      await _logStore.flush();
      await _refreshMarks();
    } catch (_) {
      if (mounted) {
        _message(
          tr(
            context,
            'Не удалось открыть камеру.',
            'Could not open the camera.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
        _openPendingWidgetScan();
      }
    }
  }

  Future<void> _shareSessions() async {
    if (_busy) return;
    final accounts = _accounts.where((a) => _selected.contains(a.id)).toList();
    if (accounts.isEmpty) {
      _message(
        tr(context, 'Сначала выберите аккаунты.', 'Select accounts first.'),
      );
      return;
    }
    final method = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.wifi_tethering_rounded),
              title: Text(tr(context, 'Передать рядом', 'Share nearby')),
              subtitle: Text(
                tr(
                  context,
                  'Несколько телефонов в одной Wi‑Fi сети',
                  'Multiple phones on the same Wi‑Fi',
                ),
              ),
              onTap: () => Navigator.pop(context, 'nearby'),
            ),
            ListTile(
              leading: Icon(Icons.qr_code_rounded),
              title: Text(tr(context, 'Передать через QR', 'Share by QR')),
              onTap: () => Navigator.pop(context, 'qr'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || method == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => method == 'nearby'
            ? NearbySharePage(accounts: accounts)
            : SessionSharePage(accounts: accounts),
      ),
    );
  }

  Future<void> _importSessions() async {
    if (_busy) return;
    final method = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.wifi_tethering_rounded),
              title: Text(tr(context, 'Получить рядом', 'Receive nearby')),
              subtitle: Text(
                tr(
                  context,
                  'Откройте этот экран на каждом получателе',
                  'Open this on each receiving phone',
                ),
              ),
              onTap: () => Navigator.pop(context, 'nearby'),
            ),
            ListTile(
              leading: Icon(Icons.qr_code_scanner_rounded),
              title: Text(
                tr(context, 'Сканировать QR передачи', 'Scan transfer QR'),
              ),
              onTap: () => Navigator.pop(context, 'qr'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || method == null) return;
    if (method == 'qr' && !Platform.isAndroid && !Platform.isIOS) {
      _message(
        tr(
          context,
          'Импорт через камеру доступен на Android и iOS.',
          'Camera import is available on Android and iOS.',
        ),
      );
      return;
    }
    final imported = await Navigator.of(context).push<List<SavedAccount>>(
      MaterialPageRoute(
        builder: (_) => method == 'nearby'
            ? const NearbyReceivePage()
            : const SessionImportPage(),
      ),
    );
    if (!mounted || imported == null) return;
    final known = _accounts.map((a) => a.cookie).toSet();
    final added = <SavedAccount>[];
    final base = DateTime.now().microsecondsSinceEpoch;
    for (final account in imported) {
      if (!known.add(account.cookie)) continue;
      added.add(
        SavedAccount(
          id: '${base}_${added.length}',
          label: account.label,
          cookie: account.cookie,
          groupId: account.groupId,
          groupName: account.groupName,
        ),
      );
    }
    if (added.isEmpty) {
      _message(
        tr(
          context,
          'Все эти аккаунты уже сохранены.',
          'All these accounts are already saved.',
        ),
      );
      return;
    }
    final next = [..._accounts, ...added];
    try {
      await _store.save(next);
      if (!mounted) return;
      setState(() {
        _accounts = next;
        _selected.addAll(added.map((a) => a.id));
      });
      _message(
        trf(context, 'Импортировано: {count}', 'Imported: {count}', {
          'count': added.length,
        }),
      );
    } catch (_) {
      if (mounted) {
        _message(
          tr(
            context,
            'Не удалось сохранить аккаунты.',
            'Could not save accounts.',
          ),
        );
      }
    }
  }

  Future<void> _pasteLink() async {
    if (_busy) return;
    if (_selected.isEmpty) {
      _message(
        tr(context, 'Сначала выберите аккаунты.', 'Select accounts first.'),
      );
      return;
    }
    final raw = await _askText(
      title: tr(context, 'Ссылка QR-кода', 'QR code link'),
      hint: 'https://pulse.mirea.ru/...?token=...',
      action: tr(context, 'Отправить', 'Submit'),
    );
    if (mounted && raw != null) await _submitLink(raw);
  }

  Future<void> _pasteLesson(
    ScheduleLesson lesson,
    List<SavedAccount> accounts,
  ) async {
    final raw = await _askText(
      title: tr(context, 'Ссылка QR-кода', 'QR code link'),
      hint: 'https://pulse.mirea.ru/...?token=...',
      action: tr(context, 'Отправить', 'Submit'),
    );
    if (mounted && raw != null) {
      await _submitLink(raw, lesson: lesson, overrideAccounts: accounts);
    }
  }

  Future<void> _submitLink(
    String raw, {
    ScheduleLesson? lesson,
    List<SavedAccount>? overrideAccounts,
  }) async {
    if (_submitting) return;
    final String token;
    try {
      token = attendanceTokenFromQr(raw);
    } on FormatException catch (error) {
      _message(error.message);
      return;
    }
    final accounts =
        overrideAccounts ??
        _accounts.where((account) => _selected.contains(account.id)).toList();
    if (accounts.isEmpty) {
      _message(
        tr(context, 'Сначала выберите аккаунты.', 'Select accounts first.'),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _results.clear();
      _errors.clear();
    });
    // Every request starts immediately: the lecture QR token can rotate quickly.
    await Future.wait(
      accounts.map((account) async {
        try {
          final result = await _api.approve(token, account.cookie);
          if (result.state == ApprovalState.approved) {
            unawaited(_recordApproval(account, result, lesson: lesson));
          }
          if (mounted) setState(() => _results[account.id] = result);
        } catch (error) {
          if (mounted) {
            setState(
              () => _errors[account.id] = error is PulseApiException
                  ? error.message
                  : 'Ошибка сети. Попробуйте снова.',
            );
          }
        }
      }),
    );
    await _logStore.flush();
    await _refreshMarks();
    if (mounted) {
      setState(() => _submitting = false);
      _openPendingWidgetScan();
    }
  }

  Future<void> _recordApproval(
    SavedAccount account,
    ApprovalResult result, {
    ScheduleLesson? lesson,
  }) async {
    try {
      await _logStore.add(
        AttendanceMark(
          accountId: account.id,
          accountLabel: account.label,
          at: DateTime.now(),
          groupId: account.groupId,
          lessonKey: lesson?.key,
          pulseLessonId: result.lessonId,
        ),
      );
    } catch (_) {
      if (mounted) {
        _message(
          tr(
            context,
            'Отметка подтверждена, но история не сохранилась.',
            'Attendance confirmed, but history could not be saved.',
          ),
        );
      }
    }
  }

  Future<void> _chooseGroup(Set<String> accountIds) async {
    if (_busy || accountIds.isEmpty) return;
    final group = await Navigator.of(context).push<ScheduleGroup>(
      MaterialPageRoute(builder: (_) => GroupPickerPage(api: _scheduleApi)),
    );
    if (!mounted || group == null) return;
    final next = _accounts
        .map(
          (item) => accountIds.contains(item.id)
              ? SavedAccount(
                  id: item.id,
                  label: item.label,
                  cookie: item.cookie,
                  groupId: group.id,
                  groupName: group.name,
                )
              : item,
        )
        .toList();
    try {
      await _store.save(next);
      if (mounted) setState(() => _accounts = next);
    } catch (_) {
      if (mounted) {
        _message(
          tr(context, 'Не удалось сохранить группу.', 'Could not save group.'),
        );
      }
    }
  }

  Widget _settingsButton(BuildContext context) {
    final updates = widget.updates;
    Widget button(bool available) => IconButton(
      onPressed: _openSettings,
      tooltip: tr(context, 'Настройки', 'Settings'),
      icon: Badge(
        isLabelVisible: available,
        backgroundColor: context.palette.blue,
        child: Icon(Icons.settings_outlined),
      ),
    );
    if (updates == null) return button(false);
    return AnimatedBuilder(
      animation: updates,
      builder: (context, _) => button(updates.updateAvailable),
    );
  }

  @override
  Widget build(BuildContext context) {
    final countsByAccount = _marks == null
        ? null
        : AttendanceCounts.fromMarks(_marks!);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SvgPicture.asset(
              'icon/brand.svg',
              width: 28,
              height: 28,
              semanticsLabel: tr(context, 'Логотип приложения', 'App logo'),
            ),
            const SizedBox(width: 6),
            const Flexible(
              child: Text(
                'AntiAttendance',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [_settingsButton(context), const SizedBox(width: 8)],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: context.palette.paper,
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_rounded),
            label: tr(context, 'Посещаемость', 'Attendance'),
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_rounded),
            label: tr(context, 'Расписание', 'Schedule'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tr(
                          context,
                          'Не удалось загрузить сохранённые аккаунты.',
                          'Could not load saved accounts.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: Text(tr(context, 'Повторить', 'Retry')),
                      ),
                    ],
                  ),
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: _tab == 1
                      ? SchedulePage(
                          key: const ValueKey('schedule-tab'),
                          accounts: _accounts,
                          api: _scheduleApi,
                          log: _logStore,
                          onScanLesson: (lesson, accounts) => _scanQueue(
                            lesson: lesson,
                            overrideAccounts: accounts,
                          ),
                          onPasteLesson: _pasteLesson,
                          initialDay: _scheduleDay,
                          initialGroupId: _scheduleGroupId,
                          onDayChanged: (day) => _scheduleDay = day,
                          onGroupChanged: (id) => _scheduleGroupId = id,
                        )
                      : ListView(
                          key: const ValueKey('attendance-tab'),
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                          children: [
                            Text(
                              tr(context, 'Посещаемость', 'Attendance'),
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tr(
                                context,
                                'Наведите камеру на QR-код — отметим выбранных. Если не вышло, попробуем снова.',
                                'Scan a QR to mark selected accounts. Keep it in view for retries.',
                              ),
                              style: TextStyle(
                                color: context.palette.muted,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _busy ? null : _scan,
                                icon: Icon(Icons.qr_code_scanner_rounded),
                                label: Text(
                                  tr(context, 'Сканировать QR', 'Scan QR'),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : _pasteLink,
                                icon: Icon(Icons.link_rounded, size: 20),
                                label: Text(
                                  tr(context, 'Вставить ссылку', 'Paste link'),
                                ),
                              ),
                            ),
                            if (_submitting) ...[
                              const SizedBox(height: 12),
                              const LinearProgressIndicator(),
                              const SizedBox(height: 6),
                              Text(
                                tr(
                                  context,
                                  'Отправляем отметки…',
                                  'Submitting attendance…',
                                ),
                                style: TextStyle(
                                  color: context.palette.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: _busy ? null : _shareSessions,
                                    icon: Icon(
                                      Icons.ios_share_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      tr(context, 'Передать', 'Share'),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: _busy ? null : _importSessions,
                                    icon: Icon(
                                      Icons.download_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      tr(context, 'Получить', 'Receive'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    tr(context, 'Аккаунты', 'Accounts'),
                                    style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _busy ? null : () => _login(),
                                  icon: Icon(Icons.add_rounded, size: 19),
                                  label: Text(tr(context, 'Добавить', 'Add')),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_accounts.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 30,
                                ),
                                child: Text(
                                  tr(
                                    context,
                                    'Добавьте первый аккаунт через МИРЭА.',
                                    'Add your first account through MIREA.',
                                  ),
                                  style: TextStyle(
                                    color: context.palette.muted,
                                  ),
                                ),
                              ),
                            if (_accounts.isNotEmpty) ...[
                              Row(
                                children: [
                                  Text(
                                    trf(
                                      context,
                                      'Выбрано: {count}',
                                      'Selected: {count}',
                                      {
                                        'count': _selected
                                            .where(
                                              (id) => _accounts.any(
                                                (a) => a.id == id,
                                              ),
                                            )
                                            .length,
                                      },
                                    ),
                                    style: TextStyle(
                                      color: context.palette.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() {
                                            if (_selected.length ==
                                                _accounts.length) {
                                              _selected.clear();
                                            } else {
                                              _selected
                                                ..clear()
                                                ..addAll(
                                                  _accounts.map((a) => a.id),
                                                );
                                            }
                                          }),
                                    child: Text(
                                      _selected.length == _accounts.length
                                          ? tr(
                                              context,
                                              'Снять выбор',
                                              'Clear selection',
                                            )
                                          : tr(
                                              context,
                                              'Выбрать все',
                                              'Select all',
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: _busy || _selected.isEmpty
                                      ? null
                                      : () => _chooseGroup(Set.of(_selected)),
                                  icon: Icon(Icons.groups_rounded, size: 18),
                                  label: Text(
                                    tr(
                                      context,
                                      'Назначить группу',
                                      'Assign group',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            for (final account in _accounts)
                              _AccountRow(
                                account: account,
                                counts: countsByAccount == null
                                    ? null
                                    : (countsByAccount[account.id] ??
                                          AttendanceCounts.zero),
                                selected: _selected.contains(account.id),
                                busy: _submitting,
                                result: _results[account.id],
                                error: _errors[account.id],
                                onTap: () => setState(() {
                                  if (!_selected.add(account.id)) {
                                    _selected.remove(account.id);
                                  }
                                }),
                                onReauth: () => _login(replace: account),
                                onGroup: () => _chooseGroup({account.id}),
                                onRemove: () => _remove(account),
                              ),
                          ],
                        ),
                ),
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.counts,
    required this.selected,
    required this.busy,
    required this.result,
    required this.error,
    required this.onTap,
    required this.onReauth,
    required this.onGroup,
    required this.onRemove,
  });

  final SavedAccount account;
  final AttendanceCounts? counts;
  final bool selected;
  final bool busy;
  final ApprovalResult? result;
  final String? error;
  final VoidCallback onTap;
  final VoidCallback onReauth;
  final VoidCallback onGroup;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final status =
        error ??
        result?.message ??
        (busy && selected ? 'Отправка…' : 'Сессия сохранена');
    final color = error != null || result?.state == ApprovalState.rejected
        ? Theme.of(context).colorScheme.error
        : result?.state == ApprovalState.approved
        ? context.palette.success
        : context.palette.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? context.palette.blue.withValues(alpha: .07)
              : context.palette.surface,
          border: Border.all(
            color: selected
                ? context.palette.blue.withValues(alpha: .35)
                : context.palette.line,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: busy ? null : onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 4, 9),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: selected
                        ? context.palette.blue
                        : context.palette.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (account.groupName != null)
                          Text(
                            account.groupName!,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.palette.muted,
                            ),
                          ),
                        Text(
                          trMessage(context, status),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: color),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 10,
                          runSpacing: 2,
                          children: [
                            _countText(
                              context,
                              'Сегодня',
                              'Today',
                              counts?.today,
                            ),
                            _countText(context, 'Неделя', 'Week', counts?.week),
                            _countText(
                              context,
                              'Всего',
                              'Total',
                              counts?.total,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    enabled: !busy,
                    tooltip: tr(
                      context,
                      'Действия с аккаунтом',
                      'Account actions',
                    ),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: context.palette.muted,
                    ),
                    onSelected: (value) {
                      if (value == 'login') onReauth();
                      if (value == 'group') onGroup();
                      if (value == 'remove') onRemove();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'login',
                        child: Text(
                          tr(context, 'Войти снова', 'Sign in again'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'group',
                        child: Text(
                          tr(context, 'Выбрать группу', 'Choose group'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text(tr(context, 'Удалить', 'Delete')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _countText(BuildContext context, String ru, String en, int? count) =>
      Text(
        '${tr(context, ru, en)} ${count ?? '—'}',
        style: TextStyle(fontSize: 11, color: context.palette.muted),
      );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.hint,
    required this.action,
    this.initial,
    this.maxLength,
  });
  final String title;
  final String hint;
  final String action;
  final String? initial;
  final int? maxLength;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: widget.maxLength,
      decoration: InputDecoration(hintText: widget.hint),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, 'Отмена', 'Cancel')),
      ),
      FilledButton(
        onPressed: () {
          final value = _controller.text.trim();
          if (value.isNotEmpty) Navigator.pop(context, value);
        },
        child: Text(widget.action),
      ),
    ],
  );
}
