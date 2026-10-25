import 'package:filter_and_pagination/app.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/fake_transaction_remote_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/in_memory_transaction_local_data_source.dart';
import 'package:filter_and_pagination/core/demo/request_failure_switch.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/sample_transactions.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/shared_preferences_transaction_local_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/entities/transaction.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/transaction_local_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/data/repositories/transaction_repository_impl.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/transaction_remote_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/entities/paginated_transactions.dart';
import 'package:filter_and_pagination/core/formatting/date_formatter.dart';
import 'package:filter_and_pagination/core/formatting/money_formatter.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/cubit/transaction_history_cubit.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/cubit/transaction_history_state.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/pages/transaction_details_page.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/pages/transaction_history_page.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/utils/transaction_status_text.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/widgets/status_badge.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/widgets/status_views.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/widgets/transaction_tile.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/widgets/transaction_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Short enough to keep the suite fast, long enough that loading states are
/// actually on screen.
const _delay = Duration(milliseconds: 300);

/// Wraps the real fake data source and records every request, so the tests
/// can assert how many requests the UI made.
class RecordingDataSource implements TransactionRemoteDataSource {
  RecordingDataSource(this._inner);

  final FakeTransactionRemoteDataSource _inner;
  final List<({int offset, TransactionStatus? status, String? query})> calls =
      [];

  @override
  Future<PaginatedTransactions> fetchTransactions({
    int offset = 0,
    TransactionStatus? status,
    String? query,
  }) {
    calls.add((offset: offset, status: status, query: query));
    return _inner.fetchTransactions(
      offset: offset,
      status: status,
      query: query,
    );
  }
}

late IntegrationTestWidgetsFlutterBinding binding;

class TestApp {
  TestApp(this.tester, this.dataSource, this.failureSwitch);

  final WidgetTester tester;
  final RecordingDataSource dataSource;
  final RequestFailureSwitch failureSwitch;

  TransactionHistoryState get state => BlocProvider.of<TransactionHistoryCubit>(
    tester.element(find.byType(TransactionHistoryView)),
  ).state;

  List<String> get ids => state.transactions.map((t) => t.id).toList();

  ScrollPosition get listPosition =>
      tester.state<ScrollableState>(listScrollable).position;
}

/// Pumps the app. Each test gets an empty in-memory cache unless it passes
/// one, so saved results from one test never leak into another.
Future<TestApp> pumpApp(
  WidgetTester tester, {
  List<Transaction>? transactions,
  Duration delay = _delay,
  TransactionLocalDataSource? cache,
  bool failAllRequests = false,
  bool convertSurface = true,
}) async {
  if (convertSurface) await binding.convertFlutterSurfaceToImage();
  final failureSwitch = RequestFailureSwitch(failAllRequests: failAllRequests);
  addTearDown(failureSwitch.dispose);
  final dataSource = RecordingDataSource(
    FakeTransactionRemoteDataSource(
      transactions: transactions,
      delay: delay,
      failureSwitch: failureSwitch,
    ),
  );
  await tester.pumpWidget(
    TransactionHistoryApp(
      repository: TransactionRepositoryImpl(
        remote: dataSource,
        local: cache ?? InMemoryTransactionLocalDataSource(),
      ),
      failureSwitch: failureSwitch,
    ),
  );
  return TestApp(tester, dataSource, failureSwitch);
}

Finder get list => find.byType(ListView);

Finder get listScrollable =>
    find.descendant(of: list, matching: find.byType(Scrollable));

Finder row(String id) => find.byKey(ValueKey(id));

Finder get statusDropdown =>
    find.byType(DropdownButtonFormField<TransactionStatus?>);

Finder get searchField => find.byType(TextField);

Finder get failAllRequestsTile =>
    find.widgetWithText(SwitchListTile, 'Fail all requests');

/// Opens the status dropdown and picks [label], pumping one frame after the
/// pick so the caller can see the loading state.
Future<void> selectStatus(WidgetTester tester, String label) async {
  await tester.ensureVisible(statusDropdown);
  await tester.pumpAndSettle();
  await tester.tap(statusDropdown);
  await tester.pumpAndSettle();
  // While the menu is open the selected label also shows in the field; the
  // menu items are built last.
  await tester.tap(find.text(label).last);
  await tester.pump();
}

/// Types [text] into the search field and waits out the 300 ms debounce.
Future<void> search(WidgetTester tester, String text) async {
  await tester.enterText(searchField, text);
  await tester.pump(const Duration(milliseconds: 350));
}

WidgetPredicate isSpinner(String semanticsLabel) =>
    (widget) =>
        widget is CircularProgressIndicator &&
        widget.semanticsLabel == semanticsLabel;

Finder get firstPageError => find.text("Couldn't load transactions.");

Finder get nextPageError => find.text("Couldn't load more transactions");

Finder get refreshFailure =>
    find.text("Couldn't refresh. Showing previous results.");

/// Pumps frames until [condition] holds, failing after [timeout].
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String? reason,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      fail('Timed out waiting for ${reason ?? 'condition'}');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpUntilFound(WidgetTester tester, Finder finder) => pumpUntil(
  tester,
  () => finder.evaluate().isNotEmpty,
  reason: finder.toString(),
);

/// Waits until no request is in flight and all animations have finished.
///
/// The list may start another next-page request after a frame (when the rows
/// end within the load-more threshold), so this loops until a settled frame
/// has no request in flight.
Future<void> settle(TestApp app) async {
  bool idle() =>
      app.state.firstPageStatus != FirstPageStatus.loading &&
      app.state.nextPageStatus != NextPageStatus.loading &&
      !app.state.isRefreshing;
  do {
    await pumpUntil(app.tester, idle, reason: 'requests to finish');
    await app.tester.pumpAndSettle();
  } while (!idle());
}

Future<void> screenshot(WidgetTester tester, String name) async {
  await tester.pump();
  await binding.takeScreenshot(name);
}

Future<void> toggleFailAllRequests(TestApp app) async {
  final before = app.failureSwitch.failAllRequests;
  expect(app.tester.widget<SwitchListTile>(failAllRequestsTile).value, before);
  final requests = app.dataSource.calls.length;
  await app.tester.tap(failAllRequestsTile);
  await app.tester.pumpAndSettle();
  expect(app.failureSwitch.failAllRequests, !before);
  expect(app.tester.widget<SwitchListTile>(failAllRequestsTile).value, !before);
  expect(
    find.text('All requests will fail'),
    before ? findsNothing : findsOneWidget,
  );
  expect(app.dataSource.calls, hasLength(requests), reason: 'no refetch');
}

/// Drags to the end of the list. `ListView.builder` only estimates its
/// extent for rows it has not built yet, so one fling can stop at the
/// estimated end; keep dragging until the real end is reached.
Future<void> scrollToEnd(WidgetTester tester) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester.drag(list, const Offset(0, -4000));
    await tester.pump();
    final position = tester.state<ScrollableState>(listScrollable).position;
    if (position.pixels >= position.maxScrollExtent) return;
  }
  fail('Could not scroll to the end of the list');
}

Future<void> pullToRefresh(WidgetTester tester, Finder scrollable) async {
  await tester.fling(scrollable, const Offset(0, 500), 1000);
  await tester.pump();
}

/// Loads every page by scrolling until the end-of-list marker is shown.
Future<void> loadAllPages(TestApp app) async {
  while (!app.state.hasReachedEnd) {
    await scrollToEnd(app.tester);
    await settle(app);
  }
  await scrollToEnd(app.tester);
  await app.tester.pumpAndSettle();
}

List<String> expectedIds(TransactionStatus? filter) => [
  for (final t in sampleTransactions)
    if (filter == null || t.status == filter) t.id,
];

/// The rows are exactly the first N items of [filter]'s newest-first order:
/// nothing duplicated, skipped, reordered or carried over from elsewhere.
void expectInOrderPrefix(TestApp app, TransactionStatus? filter) {
  final expected = expectedIds(filter);
  expect(app.ids, isNotEmpty);
  expect(app.ids, expected.take(app.ids.length).toList());
}

void expectNoDuplicates(TestApp app) {
  expect(app.ids.toSet().length, app.ids.length, reason: 'duplicate rows');
}

void expectOnlyStatus(TestApp app, TransactionStatus? status) {
  final badges = app.tester.widgetList<StatusBadge>(find.byType(StatusBadge));
  expect(badges, isNotEmpty);
  if (status == null) return;
  expect(badges.every((b) => b.status == status), isTrue);
  expect(app.state.transactions.every((t) => t.status == status), isTrue);
}

/// The search hint is shown in full, whichever toolbar layout was chosen.
void expectHintNotTruncated(WidgetTester tester) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.text(TransactionToolbar.searchHint),
      matching: find.byType(RichText),
    ),
  );
  expect(paragraph.didExceedMaxLines, isFalse, reason: 'hint truncated');
}

void expectSelectedStatus(WidgetTester tester, String label) {
  final field = tester.state<FormFieldState<TransactionStatus?>>(
    statusDropdown,
  );
  expect(filterLabel(field.value), label);
  expect(
    find.descendant(of: statusDropdown, matching: find.text(label)),
    findsOneWidget,
  );
}

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a. launch shows loading, then the first 10 rows', (
    tester,
  ) async {
    final app = await pumpApp(tester, delay: const Duration(milliseconds: 800));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byWidgetPredicate(isSpinner('Loading transactions')),
      findsOneWidget,
    );

    await settle(app);
    expectInOrderPrefix(app, null);
    expect(app.dataSource.calls.first.offset, 0);
    expectHintNotTruncated(tester);
    await screenshot(tester, '01_list_loaded');

    for (final transaction in sampleTransactions.take(10)) {
      await tester.scrollUntilVisible(
        row(transaction.id),
        100,
        scrollable: listScrollable,
        continuous: true,
      );
      Finder inRow(String text) =>
          find.descendant(of: row(transaction.id), matching: find.text(text));
      expect(inRow(transaction.merchantName), findsOneWidget);
      expect(
        inRow(formatMoney(transaction.amountMinor, transaction.currencyCode)),
        findsOneWidget,
      );
      expect(
        inRow(formatTransactionDate(transaction.createdAt)),
        findsOneWidget,
      );
      expect(inRow(transaction.status.label), findsOneWidget);
    }
    expect(find.textContaining('₹'), findsWidgets);
    expect(find.textContaining(r'$'), findsWidgets);
  });

  testWidgets('b. scrolling paginates to the end without duplicates', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await settle(app);
    final before = app.ids.length;

    await scrollToEnd(tester);
    await pumpUntilFound(
      tester,
      find.byWidgetPredicate(isSpinner('Loading more transactions')),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await screenshot(tester, '02_loading_more');
    await settle(app);
    expect(app.ids.length, greaterThan(before));
    expectInOrderPrefix(app, null);
    expectNoDuplicates(app);

    await loadAllPages(app);
    expect(app.state.transactions, hasLength(sampleTransactions.length));
    expectNoDuplicates(app);
    expect(app.ids, [for (final t in sampleTransactions) t.id]);
    expect(find.text('No more transactions'), findsOneWidget);
    expect(row('txn_001'), findsOneWidget);

    final requests = app.dataSource.calls.length;
    expect(requests, 4, reason: 'one request per page (10 + 10 + 10 + 6)');
    final offsets = app.dataSource.calls.map((c) => c.offset).toList();
    expect(offsets.toSet().length, offsets.length, reason: 'no page twice');
    for (var i = 0; i < 3; i++) {
      await scrollToEnd(tester);
      await tester.pump(_delay * 2);
    }
    expect(app.dataSource.calls, hasLength(requests));
  });

  testWidgets('c. each filter shows only matching rows from the top', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await settle(app);

    const filters = <TransactionStatus?>[
      TransactionStatus.completed,
      TransactionStatus.pending,
      TransactionStatus.failed,
      null,
    ];
    for (final filter in filters) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(app.listPosition.pixels, greaterThan(0));

      final label = filterLabel(filter);
      await selectStatus(tester, label);
      expect(app.state.firstPageStatus, FirstPageStatus.loading);
      if (filter == null) {
        // "All" was loaded at launch, so its saved first page is shown while
        // it updates instead of a blank spinner.
        await pumpUntilFound(
          tester,
          find.text('Showing saved results · Updating…'),
        );
        expect(find.byType(LoadingView), findsNothing);
        expectInOrderPrefix(app, null);
      } else {
        expect(find.byType(LoadingView), findsOneWidget);
      }
      await settle(app);

      expectSelectedStatus(tester, label);
      expect(app.state.filter, filter);
      expectOnlyStatus(app, filter);
      expect(app.listPosition.pixels, 0, reason: 'starts from the top');
      final newest = sampleTransactions.firstWhere(
        (t) => filter == null || t.status == filter,
      );
      expect(row(newest.id), findsOneWidget);
      await screenshot(tester, '03_filter_${label.toLowerCase()}');

      await loadAllPages(app);
      final expectedCount = sampleTransactions
          .where((t) => filter == null || t.status == filter)
          .length;
      expect(app.state.transactions, hasLength(expectedCount));
      expectOnlyStatus(app, filter);
      expectNoDuplicates(app);
    }
  });

  testWidgets('d. rapid filter changes land only the last filter', (
    tester,
  ) async {
    // Long enough that all three requests are in flight together even though
    // each pick has to open the dropdown menu first.
    final app = await pumpApp(tester, delay: const Duration(seconds: 3));
    await settle(app);

    await selectStatus(tester, 'Completed');
    await selectStatus(tester, 'Pending');
    await selectStatus(tester, 'Failed');
    expect(
      app.dataSource.calls.where((c) => c.offset == 0),
      hasLength(4),
      reason: 'all three filter requests started',
    );
    await settle(app);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    final firstPageRequests = app.dataSource.calls.where((c) => c.offset == 0);
    expect(firstPageRequests.map((c) => c.status), [
      null,
      TransactionStatus.completed,
      TransactionStatus.pending,
      TransactionStatus.failed,
    ]);
    expectSelectedStatus(tester, 'Failed');
    expect(app.state.filter, TransactionStatus.failed);
    expectOnlyStatus(app, TransactionStatus.failed);
    expectInOrderPrefix(app, TransactionStatus.failed);
    expectNoDuplicates(app);
    await screenshot(tester, '04_rapid_filters_failed');
  });

  testWidgets('e. pull to refresh replaces the list and keeps the filter', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await settle(app);
    await selectStatus(tester, 'Pending');
    await settle(app);

    await loadAllPages(app);
    expect(app.ids, expectedIds(TransactionStatus.pending));

    await tester.fling(list, const Offset(0, 4000), 5000);
    await tester.pumpAndSettle();
    expect(app.listPosition.pixels, 0);

    final requests = app.dataSource.calls.length;
    await pullToRefresh(tester, list);
    await pumpUntil(
      tester,
      () => app.dataSource.calls.length == requests + 1,
      reason: 'refresh request',
    );
    expect(app.dataSource.calls.last.offset, 0);
    expect(app.dataSource.calls.last.status, TransactionStatus.pending);
    await settle(app);

    expect(app.state.filter, TransactionStatus.pending);
    expectInOrderPrefix(app, TransactionStatus.pending);
    expectSelectedStatus(tester, 'Pending');
    expectOnlyStatus(app, TransactionStatus.pending);
    expectNoDuplicates(app);
    expect(app.listPosition.pixels, 0);
    expect(row(app.ids.first), findsOneWidget);
    await screenshot(tester, '05_refreshed_pending');
  });

  testWidgets('f. fail all requests: first-page error and retry', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await settle(app);

    await toggleFailAllRequests(app);
    await screenshot(tester, '17_fail_all_switch_on');
    await selectStatus(tester, 'Completed');
    await settle(app);
    expect(firstPageError, findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(find.byType(TransactionTile), findsNothing);
    expectSelectedStatus(tester, 'Completed');
    await screenshot(tester, '06_first_page_error');

    await toggleFailAllRequests(app);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await settle(app);
    expect(firstPageError, findsNothing);
    expectOnlyStatus(app, TransactionStatus.completed);
    expectInOrderPrefix(app, TransactionStatus.completed);
  });

  testWidgets('g. fail all requests: next-page error and retry', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await settle(app);
    final before = app.ids;

    await toggleFailAllRequests(app);
    await scrollToEnd(tester);
    await settle(app);
    await scrollToEnd(tester);
    await tester.pumpAndSettle();
    expect(nextPageError, findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
    expect(app.ids, before, reason: 'earlier rows kept');
    expect(row(before.last), findsOneWidget);
    await screenshot(tester, '07_next_page_error');

    final requests = app.dataSource.calls.length;
    final failedOffset = app.dataSource.calls.last.offset;
    expect(failedOffset, greaterThan(0));
    await scrollToEnd(tester);
    await tester.pump(_delay * 2);
    expect(app.dataSource.calls, hasLength(requests), reason: 'no auto-retry');

    await toggleFailAllRequests(app);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await settle(app);
    expect(nextPageError, findsNothing);
    expect(app.dataSource.calls[requests].offset, failedOffset);
    expect(app.ids.length, greaterThan(before.length), reason: 'appended');
    expect(app.ids.take(before.length), before);
    expectInOrderPrefix(app, null);
    expectNoDuplicates(app);
  });

  testWidgets('h. fail all requests: refresh keeps rows and shows SnackBar', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await settle(app);
    final rows = app.ids;

    await toggleFailAllRequests(app);
    await pullToRefresh(tester, list);
    await pumpUntilFound(tester, refreshFailure);
    expect(app.ids, rows);
    expect(row(rows.first), findsOneWidget);
    expect(app.state.refreshFailureCount, 1);
    await tester.pumpAndSettle();
    await screenshot(tester, '08_refresh_failure_snackbar');

    await toggleFailAllRequests(app);
    expect(app.failureSwitch.failAllRequests, isFalse);
  });

  testWidgets('i. empty state for a filter without results', (tester) async {
    final app = await pumpApp(
      tester,
      transactions: sampleTransactions
          .where((t) => t.status != TransactionStatus.failed)
          .toList(),
    );
    await settle(app);
    await selectStatus(tester, 'Failed');
    await settle(app);
    expect(find.text('No failed transactions'), findsOneWidget);
    expect(find.byType(TransactionTile), findsNothing);
    await screenshot(tester, '09_empty_state');

    final requests = app.dataSource.calls.length;
    await pullToRefresh(tester, find.byType(MessageView));
    await pumpUntil(
      tester,
      () => app.dataSource.calls.length == requests + 1,
      reason: 'refresh request from empty state',
    );
    await settle(app);
    expect(find.text('No failed transactions'), findsOneWidget);
  });

  testWidgets('j. large text: scroll, filter and search without overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = await pumpApp(tester);
    await settle(app);
    expect(
      tester.getBottomLeft(searchField).dy,
      lessThanOrEqualTo(tester.getTopLeft(statusDropdown).dy),
      reason: 'toolbar stacks at 2x text on a phone',
    );
    expectHintNotTruncated(tester);
    await screenshot(tester, '10_large_text');

    await loadAllPages(app);
    expect(app.state.transactions, hasLength(sampleTransactions.length));

    for (final label in ['Completed', 'Pending', 'Failed', 'All']) {
      await selectStatus(tester, label);
      await settle(app);
      expectSelectedStatus(tester, label);
      if (label == 'Pending') {
        await screenshot(tester, '11_large_text_pending');
      }
    }
    await search(tester, 'swiggy');
    await settle(app);
    expect(app.ids, ['txn_036', 'txn_023', 'txn_015', 'txn_001']);
    await tester.tap(find.byType(TransactionTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailsPage), findsOneWidget);
    await screenshot(tester, '18_large_text_details');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester.takeException(), isNull);
  });

  testWidgets('k. accessibility: combined row labels, status as text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final app = await pumpApp(tester);
    await settle(app);

    final visible = app.state.transactions.where(
      (t) => row(t.id).evaluate().isNotEmpty,
    );
    expect(visible, isNotEmpty);
    for (final transaction in visible) {
      final label = TransactionTile.semanticsLabel(transaction);
      expect(label, contains(transaction.status.label));
      final node = tester.getSemantics(row(transaction.id));
      expect(node.label, label);
      expect(node.childrenCount, 0, reason: 'one combined node per row');

      final badge = find.descendant(
        of: row(transaction.id),
        matching: find.byType(StatusBadge),
      );
      expect(
        find.descendant(of: badge, matching: find.byType(Icon)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: badge,
          matching: find.text(transaction.status.label),
        ),
        findsOneWidget,
      );
    }
    final firstRow = tester.getSemantics(row(app.ids.first));
    expect(firstRow, containsSemantics(isButton: true, hasTapAction: true));
    expect(
      tester.getSemantics(find.byType(Switch)),
      containsSemantics(
        label: 'Fail all requests',
        hasToggledState: true,
        isToggled: false,
      ),
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await search(tester, 'x');
    await tester.pump();
    expect(
      tester.getSemantics(find.widgetWithIcon(IconButton, Icons.close)),
      containsSemantics(label: 'Clear search', isButton: true),
    );
    await settle(app);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('l. search: debounced, combined with filter and pagination', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await settle(app);
    final requests = app.dataSource.calls.length;

    for (final text in ['s', 'sw', 'swi', 'swig']) {
      await tester.enterText(searchField, text);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(app.dataSource.calls, hasLength(requests), reason: 'debouncing');
    await pumpUntil(
      tester,
      () => app.dataSource.calls.length > requests,
      reason: 'debounced search request',
    );
    expect(app.dataSource.calls, hasLength(requests + 1));
    expect(app.dataSource.calls.last.query, 'swig');
    await settle(app);
    expect(app.ids, ['txn_036', 'txn_023', 'txn_015', 'txn_001']);
    expect(find.text('No more transactions'), findsOneWidget);
    await screenshot(tester, '12_search_results');

    await selectStatus(tester, 'Pending');
    await settle(app);
    expect(app.ids, ['txn_036', 'txn_015']);
    expect(app.dataSource.calls.last.query, 'swig');
    expect(app.dataSource.calls.last.status, TransactionStatus.pending);

    await search(tester, 'zzz');
    await settle(app);
    expect(find.text("No pending transactions matching 'zzz'"), findsOneWidget);
    await screenshot(tester, '13_search_empty');

    await selectStatus(tester, 'All');
    await search(tester, 'a');
    await settle(app);
    final expected = [
      for (final t in sampleTransactions)
        if (t.merchantName.toLowerCase().contains('a') ||
            (t.reference?.toLowerCase().contains('a') ?? false))
          t.id,
    ];
    expect(expected.length, greaterThan(10));
    await loadAllPages(app);
    expect(app.ids, expected, reason: 'search applied before pagination');
    expectNoDuplicates(app);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    expect(tester.widget<TextField>(searchField).controller!.text, isEmpty);
    // Clearing goes through the same debounce as typing.
    await pumpUntil(
      tester,
      () => app.state.searchQuery.isEmpty,
      reason: 'debounced clear',
    );
    await settle(app);
    expect(app.state.searchQuery, isEmpty);
    expectInOrderPrefix(app, null);
  });

  testWidgets('m. tapping a row opens its details', (tester) async {
    final app = await pumpApp(tester);
    await settle(app);
    final requests = app.dataSource.calls.length;
    final amazon = sampleTransactions.firstWhere((t) => t.id == 'txn_034');

    await tester.tap(row('txn_034'));
    await tester.pumpAndSettle();
    final details = find.byType(TransactionDetailsPage);
    expect(details, findsOneWidget);
    Finder inDetails(String text) =>
        find.descendant(of: details, matching: find.text(text));
    expect(inDetails('Amazon'), findsOneWidget);
    expect(inDetails('₹1,29,900.00'), findsOneWidget);
    expect(inDetails('Completed'), findsOneWidget);
    expect(inDetails(formatTransactionDate(amazon.createdAt)), findsOneWidget);
    expect(inDetails('2026-10-20 13:00:00 UTC'), findsOneWidget);
    expect(inDetails('AMZ-403-9921'), findsOneWidget);
    expect(inDetails('txn_034'), findsOneWidget);
    await screenshot(tester, '14_details');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(row('txn_033'));
    await tester.pumpAndSettle();
    expect(inDetails('No reference'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(app.dataSource.calls, hasLength(requests), reason: 'no refetch');
  });

  testWidgets('n. saved results survive a restart', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.clear();
    addTearDown(preferences.clear);

    // First run: load fresh rows, which are written to shared_preferences.
    final first = await pumpApp(
      tester,
      cache: SharedPreferencesTransactionLocalDataSource(preferences),
    );
    await settle(first);
    final firstPage = first.ids.take(10).toList();
    await tester.pump(const Duration(milliseconds: 200));

    // "Restart": drop the widget tree and re-read storage from the platform.
    await tester.pumpWidget(const SizedBox());
    await preferences.reload();
    final second = await pumpApp(
      tester,
      cache: SharedPreferencesTransactionLocalDataSource(preferences),
      delay: const Duration(seconds: 2),
      convertSurface: false,
    );
    await pumpUntilFound(
      tester,
      find.text('Showing saved results · Updating…'),
    );
    expect(second.state.isShowingSavedResults, isTrue);
    expect(second.ids, firstPage);
    expect(find.byType(LoadingView), findsNothing);
    await screenshot(tester, '15_saved_results_updating');
    await settle(second);
    expect(find.textContaining('saved results'), findsNothing);
    expect(second.state.isShowingSavedResults, isFalse);
    expectInOrderPrefix(second, null);

    // Third run with every request failing: saved rows stay, with Retry.
    await tester.pumpWidget(const SizedBox());
    await preferences.reload();
    final third = await pumpApp(
      tester,
      cache: SharedPreferencesTransactionLocalDataSource(preferences),
      failAllRequests: true,
      convertSurface: false,
    );
    await pumpUntilFound(
      tester,
      find.text("Couldn't update. Showing saved results."),
    );
    await settle(third);
    expect(third.ids, firstPage);
    expect(firstPageError, findsNothing);
    final requests = third.dataSource.calls.length;
    await scrollToEnd(tester);
    await tester.pump(_delay * 2);
    expect(third.dataSource.calls, hasLength(requests), reason: 'no paging');
    await tester.fling(list, const Offset(0, 4000), 5000);
    await tester.pumpAndSettle();
    await screenshot(tester, '16_saved_results_failed');

    await toggleFailAllRequests(third);
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await settle(third);
    expect(third.state.isShowingSavedResults, isFalse);
    expectInOrderPrefix(third, null);
  });
}
