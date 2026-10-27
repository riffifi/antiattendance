import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_settings.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/attendance_log.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/pulse_api.dart';
import 'package:antiattendance/session_check.dart';
import 'package:antiattendance/schedule_api.dart';
import 'package:antiattendance/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const delegates = GlobalMaterialLocalizations.delegates;

const qr =
    'https://pulse.mirea.ru/lessons/visiting-logs/self-approve?token=abc';

class MemoryAccountStore extends AccountStore {
  MemoryAccountStore(this.accounts);
  final List<SavedAccount> accounts;

  @override
  Future<List<SavedAccount>> load() async => accounts;

  @override
  Future<void> save(List<SavedAccount> value) async {
    accounts
      ..clear()
      ..addAll(value);
  }
}

class MemoryLogStore extends AttendanceLogStore {
  final marks = <AttendanceMark>[];
  @override
  Future<List<AttendanceMark>> load() async => List.of(marks);
  @override
  Future<void> add(AttendanceMark mark) async => marks.add(mark);
}

class MemorySettingsStore extends AppSettingsStore {
  String? language;
  AppThemeMode? themeMode;

  @override
  Future<void> saveLanguage(String? value) async => language = value;

  @override
  Future<void> saveThemeMode(AppThemeMode value) async => themeMode = value;
}

class RecordingApi extends PulseApi {
  final calls = <String>[];

  @override
  Future<ApprovalResult> approve(String token, String cookie) async {
    calls.add('$token:$cookie');
    return const ApprovalResult(
      ApprovalState.approved,
      'Присутствие подтверждено',
    );
  }
}

class FakeGroupApi extends ScheduleApi {
  @override
  Future<List<ScheduleGroup>> searchGroups(String query) async => const [
    ScheduleGroup(id: 42, name: 'ИНБО-10-23'),
  ];
}

void main() {
  testWidgets('account session check persists expired status', (tester) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryAccountStore([
      const SavedAccount(id: '1', label: 'User', cookie: 'one'),
    ]);
    var checks = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: delegates,
        home: HomePage(
          store: store,
          logStore: MemoryLogStore(),
          sessionChecker: (_) async {
            checks++;
            return const SessionCheckResult(SessionCheckState.expired);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('User'),
      150,
      scrollable: find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                (w.axisDirection == AxisDirection.down ||
                    w.axisDirection == AxisDirection.up),
          )
          .first,
    );
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CampusTextAction && w.tooltip == 'Account actions',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check session'));
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(store.accounts.single.sessionExpired, isTrue);
    expect(find.text('Session expired. Sign in again.'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('account rows show future and expired sessions', (tester) async {
    final expiry = DateTime.now().add(const Duration(days: 1));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: delegates,
        home: HomePage(
          store: MemoryAccountStore([
            SavedAccount(
              id: '1',
              label: 'User',
              cookie: 'one',
              expiresAt: expiry,
            ),
            SavedAccount(
              id: '2',
              label: 'Expired user',
              cookie: 'two',
              expiresAt: DateTime.now().subtract(const Duration(days: 1)),
            ),
          ]),
          logStore: MemoryLogStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Session expires:'), findsNothing);
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) => w is CampusTextAction && w.tooltip == 'Account actions',
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Session expires:'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Expired user'),
      150,
      scrollable: find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                (w.axisDirection == AxisDirection.down ||
                    w.axisDirection == AxisDirection.up),
          )
          .first,
    );
    expect(find.text('Session expired. Sign in again.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('appearance choices save dark mode without wallpaper colors', (
    tester,
  ) async {
    final store = MemorySettingsStore();
    AppThemeMode? chosenMode;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SettingsPage(
          store: store,
          language: null,
          onLanguageChanged: (_) {},
          onThemeModeChanged: (value) => chosenMode = value,
        ),
      ),
    );
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(find.text('Phone colors (Monet)'), findsNothing);
    expect(store.themeMode, AppThemeMode.dark);
    expect(chosenMode, AppThemeMode.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a simple scan and account list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: delegates,
        home: HomePage(store: MemoryAccountStore([])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Посещаемость'), findsNWidgets(2));
    expect(find.text('Сканировать QR · 0'), findsOneWidget);
    expect(find.text('Режим очереди'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Аккаунты'),
      200,
      scrollable: find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                (w.axisDirection == AxisDirection.down ||
                    w.axisDirection == AxisDirection.up),
          )
          .first,
    );
    expect(find.text('Аккаунты'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a scan immediately submits for selected accounts', (
    tester,
  ) async {
    final api = RecordingApi();
    final store = MemoryAccountStore([
      const SavedAccount(id: '1', label: 'Аня', cookie: 'one'),
      const SavedAccount(id: '2', label: 'Борис', cookie: 'two'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: delegates,
        home: HomePage(
          store: store,
          api: api,
          logStore: MemoryLogStore(),
          scanQr: (_) async => qr,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сканировать QR · 2'));
    await tester.pumpAndSettle();
    expect(api.calls, containsAll(['abc:one', 'abc:two']));
    await tester.scrollUntilVisible(
      find.text('Аня'),
      200,
      scrollable: find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                (w.axisDirection == AxisDirection.down ||
                    w.axisDirection == AxisDirection.up),
          )
          .first,
    );
    expect(find.text('Отметка подтверждена'), findsWidgets);
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) => w is CampusTextAction && w.tooltip == 'Действия с аккаунтом',
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подробнее'));
    await tester.pumpAndSettle();
    expect(find.text('Сегодня 1'), findsWidgets);
    expect(find.text('Неделя 1'), findsWidgets);
    expect(find.text('Всего 1'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected accounts can receive one group together', (
    tester,
  ) async {
    final store = MemoryAccountStore([
      const SavedAccount(id: '1', label: 'Аня', cookie: 'one'),
      const SavedAccount(id: '2', label: 'Борис', cookie: 'two'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: HomePage(
          store: store,
          logStore: MemoryLogStore(),
          scheduleApi: FakeGroupApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Борис'),
      200,
      scrollable: find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                (w.axisDirection == AxisDirection.down ||
                    w.axisDirection == AxisDirection.up),
          )
          .first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Борис'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Selected: 1'),
      -200,
      scrollable: find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                (w.axisDirection == AxisDirection.down ||
                    w.axisDirection == AxisDirection.up),
          )
          .first,
    );
    expect(find.text('Selected: 1'), findsOneWidget);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assign group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CampusTextField), 'ИНБО');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ИНБО-10-23'));
    await tester.pumpAndSettle();
    expect(store.accounts.first.groupId, 42);
    expect(store.accounts.last.groupId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid pasted link cannot submit a previous QR', (
    tester,
  ) async {
    final api = RecordingApi();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: delegates,
        home: HomePage(
          store: MemoryAccountStore([
            const SavedAccount(id: '1', label: 'Аня', cookie: 'one'),
          ]),
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CampusTextAction && w.tooltip == 'Вставить ссылку',
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(CampusTextField),
      'https://example.com/?token=bad',
    );
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows English text for an English phone locale', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: HomePage(store: MemoryAccountStore([])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Attendance'), findsNWidgets(2));
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
  });

  testWidgets('session actions fit on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: delegates,
        home: HomePage(store: MemoryAccountStore([])),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings changes language and opens About', (tester) async {
    final settings = MemorySettingsStore();
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: HomePage(
          store: MemoryAccountStore([]),
          settingsStore: settings,
          onLanguageChanged: (language) => chosen = language,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CampusBrand), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Use phone language'),
      200,
      scrollable: find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                (w.axisDirection == AxisDirection.down ||
                    w.axisDirection == AxisDirection.up),
          )
          .first,
    );
    await tester.tap(find.text('Use phone language'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Русский'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский'));
    await tester.pumpAndSettle();
    expect(chosen, 'ru');
    expect(settings.language, 'ru');
    await tester.scrollUntilVisible(
      find.text('NFC diagnostics'),
      300,
      scrollable: find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                (w.axisDirection == AxisDirection.down ||
                    w.axisDirection == AxisDirection.up),
          )
          .first,
    );
    await tester.ensureVisible(find.text('NFC diagnostics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NFC diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('Available on Android only.'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('About AntiAttendance'),
      300,
      scrollable: find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                (w.axisDirection == AxisDirection.down ||
                    w.axisDirection == AxisDirection.up),
          )
          .first,
    );
    await tester.ensureVisible(find.text('About AntiAttendance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About AntiAttendance'));
    await tester.pumpAndSettle();
    expect(find.text('AntiAttendance'), findsOneWidget);
    expect(find.textContaining('Pulse and your schedule'), findsOneWidget);
  });

  testWidgets('account rows are lazy and scrolling survives a tab round trip', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(
          store: MemoryAccountStore([
            for (var i = 0; i < 100; i++)
              SavedAccount(id: '$i', label: 'Account $i', cookie: 'test-$i'),
          ]),
          logStore: MemoryLogStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Account 99'), findsNothing);
    final scroll = find.byType(CustomScrollView);
    await tester.drag(scroll, const Offset(0, -600));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        )
        .position;
    final offset = position.pixels;
    expect(offset, greaterThan(0));
    final bar = find.byType(CampusNavigation);
    await tester.tap(find.descendant(of: bar, matching: find.text('Schedule')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: bar, matching: find.text('Attendance')),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, offset);
    expect(find.text('Account 99'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation bar uses the app palette', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(store: MemoryAccountStore([])),
      ),
    );
    await tester.pumpAndSettle();
    final bar = tester.widget<CampusNavigation>(find.byType(CampusNavigation));
    expect(bar.selectedIndex, 0);
    expect(bar.labels, ['Attendance', 'Schedule', 'Passes']);
    expect(
      find.descendant(
        of: find.byType(CampusNavigation),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).extendBody,
      isFalse,
    );
  });
}
