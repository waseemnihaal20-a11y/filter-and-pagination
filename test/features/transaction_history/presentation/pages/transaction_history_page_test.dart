import 'package:filter_and_pagination/app.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/fake_transaction_remote_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/in_memory_transaction_local_data_source.dart';
import 'package:filter_and_pagination/core/demo/request_failure_switch.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/sample_transactions.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/entities/transaction.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/transaction_local_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/data/repositories/transaction_repository_impl.dart';
import 'package:filter_and_pagination/core/formatting/date_formatter.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/pages/transaction_details_page.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/widgets/status_badge.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/widgets/transaction_tile.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/widgets/transaction_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/recording_transaction_data_source.dart';

const _delay = Duration(milliseconds: 100);
const _debounce = Duration(milliseconds: 300);

typedef Harness = ({
  RequestFailureSwitch failureSwitch,
  RecordingTransactionDataSource source,
  InMemoryTransactionLocalDataSource cache,
});

Future<Harness> pumpApp(
  WidgetTester tester, {
  List<Transaction>? transactions,
  bool failAllRequests = false,
  InMemoryTransactionLocalDataSource? cache,
}) async {
  final failureSwitch = RequestFailureSwitch(failAllRequests: failAllRequests);
  addTearDown(failureSwitch.dispose);
  final source = RecordingTransactionDataSource(
    FakeTransactionRemoteDataSource(
      transactions: transactions,
      delay: _delay,
      failureSwitch: failureSwitch,
    ),
  );
  final usedCache = cache ?? InMemoryTransactionLocalDataSource();
  await tester.pumpWidget(
    TransactionHistoryApp(
      repository: TransactionRepositoryImpl(remote: source, local: usedCache),
      failureSwitch: failureSwitch,
      searchDebounce: _debounce,
    ),
  );
  return (failureSwitch: failureSwitch, source: source, cache: usedCache);
}

Finder row(String id) => find.byKey(ValueKey(id));

Finder get list => find.byType(ListView);

Finder get statusDropdown =>
    find.byType(DropdownButtonFormField<TransactionStatus?>);

Finder get searchField => find.byType(TextField);

Finder get clearSearchButton => find.widgetWithIcon(IconButton, Icons.close);

Finder get failAllRequestsTile =>
    find.widgetWithText(SwitchListTile, 'Fail all requests');

/// The filter the dropdown currently shows.
TransactionStatus? selectedStatus(WidgetTester tester) =>
    tester.state<FormFieldState<TransactionStatus?>>(statusDropdown).value;

/// Opens the status dropdown and picks [label]. Pumps one frame, so the
/// caller can observe the loading state before settling.
Future<void> selectStatus(WidgetTester tester, String label) async {
  await tester.ensureVisible(statusDropdown);
  await tester.tap(statusDropdown);
  await tester.pumpAndSettle();
  // While the menu is open the selected label is also shown in the field;
  // the menu items are built last.
  await tester.tap(find.text(label).last);
  await tester.pump();
}

/// Types [text] and waits for the search debounce to fire.
Future<void> search(WidgetTester tester, String text) async {
  await tester.enterText(searchField, text);
  await tester.pump(_debounce);
}

Future<void> scrollToEnd(WidgetTester tester) async {
  await tester.drag(list, const Offset(0, -5000));
  await tester.pump();
}

Future<void> toggleFailAllRequests(WidgetTester tester) async {
  await tester.tap(failAllRequestsTile);
  await tester.pumpAndSettle();
}

List<TransactionStatus> visibleStatuses(WidgetTester tester) => tester
    .widgetList<StatusBadge>(find.byType(StatusBadge))
    .map((b) => b.status)
    .toList();

List<String> visibleIds(WidgetTester tester) => tester
    .widgetList<TransactionTile>(find.byType(TransactionTile))
    .map((t) => t.transaction.id)
    .toList();

void useSmallScreen(WidgetTester tester, {required double width}) {
  tester.view.physicalSize = Size(width, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  testWidgets('shows a loading indicator, then rows', (tester) async {
    await pumpApp(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);

    await tester.pump(_delay);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(row('txn_036'), findsOneWidget);
    expect(
      find.descendant(of: row('txn_036'), matching: find.text('Swiggy')),
      findsOneWidget,
    );
    expect(find.text('₹1,299.00'), findsWidgets);
    expect(find.text(r'$15.99'), findsOneWidget);
    expect(
      find.descendant(of: row('txn_036'), matching: find.text('Pending')),
      findsOneWidget,
    );
  });

  group('status dropdown', () {
    testWidgets('is labelled "Status" and starts on All', (tester) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: statusDropdown, matching: find.text('Status')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: statusDropdown, matching: find.text('All')),
        findsOneWidget,
      );
      expect(selectedStatus(tester), isNull);
    });

    testWidgets('selecting Pending shows only pending rows', (tester) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();

      await selectStatus(tester, 'Pending');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();

      expect(selectedStatus(tester), TransactionStatus.pending);
      final statuses = visibleStatuses(tester);
      expect(statuses, isNotEmpty);
      expect(statuses.every((s) => s == TransactionStatus.pending), isTrue);
    });

    for (final status in TransactionStatus.values) {
      testWidgets('selecting ${status.name} shows exactly its first page', (
        tester,
      ) async {
        final harness = await pumpApp(tester);
        await tester.pumpAndSettle();

        final label =
            '${status.name[0].toUpperCase()}${status.name.substring(1)}';
        await selectStatus(tester, label);
        await tester.pumpAndSettle();

        expect(selectedStatus(tester), status);
        expect(harness.source.requests.last.status, status);
        expect(harness.source.requests.last.offset, 0);
        final expected = sampleTransactions
            .where((t) => t.status == status)
            .map((t) => t.id)
            .toList();
        final ids = visibleIds(tester);
        expect(ids, isNotEmpty);
        expect(ids, expected.take(ids.length).toList());
        expect(visibleStatuses(tester).every((s) => s == status), isTrue);
      });
    }

    testWidgets('selecting All again shows every status', (tester) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();
      await selectStatus(tester, 'Failed');
      await tester.pumpAndSettle();
      await selectStatus(tester, 'All');
      await tester.pumpAndSettle();

      expect(selectedStatus(tester), isNull);
      expect(visibleStatuses(tester).toSet(), TransactionStatus.values.toSet());
    });
  });

  testWidgets('scrolling to the end loads the next page', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();
    expect(row('txn_026'), findsNothing);

    await scrollToEnd(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    await tester.dragUntilVisible(row('txn_026'), list, const Offset(0, -100));
    expect(row('txn_026'), findsOneWidget);
  });

  testWidgets('reaching the end shows the end marker', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await scrollToEnd(tester);
      await tester.pumpAndSettle();
    }
    expect(find.text('No more transactions'), findsOneWidget);
    expect(row('txn_001'), findsOneWidget);
  });

  testWidgets('next-page error shows Retry and keeps rows', (tester) async {
    final harness = await pumpApp(tester);
    await tester.pumpAndSettle();

    harness.failureSwitch.failAllRequests = true;
    await scrollToEnd(tester);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load more transactions"), findsOneWidget);
    expect(find.byType(TransactionTile), findsWidgets);

    harness.failureSwitch.failAllRequests = false;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load more transactions"), findsNothing);
    await tester.dragUntilVisible(row('txn_026'), list, const Offset(0, -100));
    expect(row('txn_026'), findsOneWidget);
  });

  testWidgets('first-page error shows Retry that loads data', (tester) async {
    final harness = await pumpApp(tester, failAllRequests: true);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load transactions."), findsOneWidget);

    harness.failureSwitch.failAllRequests = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(row('txn_036'), findsOneWidget);
  });

  testWidgets('empty state for a filter with no results', (tester) async {
    await pumpApp(
      tester,
      transactions: sampleTransactions
          .where((t) => t.status != TransactionStatus.failed)
          .toList(),
    );
    await tester.pumpAndSettle();
    await selectStatus(tester, 'Failed');
    await tester.pumpAndSettle();
    expect(find.text('No failed transactions'), findsOneWidget);

    await tester.fling(
      find.text('No failed transactions'),
      const Offset(0, 400),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('No failed transactions'), findsOneWidget);
  });

  group('"Fail all requests" switch', () {
    testWidgets('is visible below the app bar and off by default', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();
      expect(failAllRequestsTile, findsOneWidget);
      expect(tester.widget<SwitchListTile>(failAllRequestsTile).value, isFalse);
      expect(find.text('All requests will fail'), findsNothing);
      expect(
        tester.getTopLeft(failAllRequestsTile).dy,
        tester.getBottomLeft(find.byType(AppBar)).dy,
      );
      expect(find.byType(PopupMenuButton), findsNothing);
    });

    testWidgets('on shows the helper line and a warning tint', (tester) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();
      Color tint() => tester
          .widget<Material>(
            find
                .ancestor(
                  of: failAllRequestsTile,
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!;
      final offTint = tint();

      await toggleFailAllRequests(tester);
      expect(tester.widget<SwitchListTile>(failAllRequestsTile).value, isTrue);
      expect(find.text('All requests will fail'), findsOneWidget);
      expect(tint(), isNot(offTint));
    });

    testWidgets('toggling on then refresh and filter show the error UI; '
        'off and Retry shows data', (tester) async {
      final harness = await pumpApp(tester);
      await tester.pumpAndSettle();

      await toggleFailAllRequests(tester);
      expect(harness.failureSwitch.failAllRequests, isTrue);
      expect(
        row('txn_036'),
        findsOneWidget,
        reason: 'toggling does not refetch',
      );
      expect(harness.source.requests, hasLength(1));

      await tester.fling(list, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't refresh. Showing previous results."),
        findsOneWidget,
      );
      expect(row('txn_036'), findsOneWidget);

      await selectStatus(tester, 'Completed');
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load transactions."), findsOneWidget);

      await toggleFailAllRequests(tester);
      expect(harness.failureSwitch.failAllRequests, isFalse);
      expect(find.text("Couldn't load transactions."), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(row('txn_035'), findsOneWidget);
      expect(selectedStatus(tester), TransactionStatus.completed);
    });

    testWidgets('a search while on shows the error UI', (tester) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();
      await toggleFailAllRequests(tester);

      await search(tester, 'swig');
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load transactions."), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('has a search icon and hint, and no clear button when empty', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: searchField, matching: find.byIcon(Icons.search)),
        findsOneWidget,
      );
      expect(find.text('Search merchant or reference'), findsOneWidget);
      expect(clearSearchButton, findsNothing);
    });

    testWidgets('typing quickly sends one request after the debounce', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      await tester.pumpAndSettle();
      expect(harness.source.requests, hasLength(1));

      for (final text in ['s', 'sw', 'swi', 'swig']) {
        await tester.enterText(searchField, text);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(harness.source.requests, hasLength(1));
      expect(row('txn_035'), findsOneWidget, reason: 'old rows still shown');

      await tester.pump(_debounce - const Duration(milliseconds: 100));
      expect(harness.source.requests, hasLength(2));
      expect(harness.source.requests.last.query, 'swig');
      expect(harness.source.requests.last.offset, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(visibleIds(tester), ['txn_036', 'txn_023', 'txn_015', 'txn_001']);
      expect(find.text('No more transactions'), findsOneWidget);
    });

    testWidgets('matches references and combines with the status filter', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      await tester.pumpAndSettle();

      await search(tester, 'NFLX');
      await tester.pumpAndSettle();
      expect(visibleIds(tester), ['txn_035', 'txn_020', 'txn_011']);

      await search(tester, 'swig');
      await selectStatus(tester, 'Pending');
      await tester.pumpAndSettle();
      expect(harness.source.requests.last.status, TransactionStatus.pending);
      expect(harness.source.requests.last.query, 'swig');
      expect(visibleIds(tester), ['txn_036', 'txn_015']);
    });

    testWidgets('empty state mentions the search', (tester) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();
      await selectStatus(tester, 'Pending');
      await tester.pumpAndSettle();

      await search(tester, 'zzz');
      await tester.pumpAndSettle();
      expect(
        find.text("No pending transactions matching 'zzz'"),
        findsOneWidget,
      );
    });

    testWidgets('clear button empties the field and restores all rows', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester);
      await tester.pumpAndSettle();
      await search(tester, 'uber');
      await tester.pumpAndSettle();
      expect(
        visibleIds(tester).every(
          (id) =>
              sampleTransactions.firstWhere((t) => t.id == id).merchantName ==
              'Uber',
        ),
        isTrue,
      );

      expect(
        tester.getSemantics(clearSearchButton),
        containsSemantics(
          label: 'Clear search',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(clearSearchButton);
      await tester.pump(_debounce);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(searchField).controller!.text, isEmpty);
      expect(clearSearchButton, findsNothing);
      expect(row('txn_036'), findsOneWidget);
      expect(row('txn_035'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('search results paginate to exactly the matching rows', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      await tester.pumpAndSettle();
      final expected = sampleTransactions
          .where(
            (t) =>
                t.merchantName.toLowerCase().contains('a') ||
                (t.reference?.toLowerCase().contains('a') ?? false),
          )
          .map((t) => t.id)
          .toList();
      expect(expected.length, greaterThan(10), reason: 'needs two pages');

      await search(tester, 'a');
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await scrollToEnd(tester);
        await tester.pumpAndSettle();
      }
      expect(find.text('No more transactions'), findsOneWidget);

      final searchRequests = harness.source.requests
          .where((r) => r.query == 'a')
          .toList();
      expect(searchRequests, hasLength((expected.length / 10).ceil()));
      expect(searchRequests.first.offset, 0);
      expect(
        searchRequests.skip(1).map((r) => r.offset).toSet(),
        hasLength(searchRequests.length - 1),
        reason: 'each page requested once with its own offset',
      );

      final loaded = tester
          .widget<ListView>(list)
          .childrenDelegate
          .estimatedChildCount;
      // Rows plus separators plus the footer.
      expect(loaded, expected.length * 2 + 1);
      await tester.drag(list, const Offset(0, 50000));
      await tester.pumpAndSettle();
      for (final id in expected) {
        await tester.dragUntilVisible(row(id), list, const Offset(0, -60));
      }
    });
  });

  group('large text on a small phone', () {
    for (final width in [320.0, 360.0]) {
      testWidgets('toolbar stacks and nothing overflows at ${width.toInt()} '
          'dp and 2x text', (tester) async {
        useSmallScreen(tester, width: width);

        await pumpApp(tester);
        await tester.pumpAndSettle();
        expect(
          tester.getBottomLeft(searchField).dy,
          lessThanOrEqualTo(tester.getTopLeft(statusDropdown).dy),
          reason: 'search field is stacked above the dropdown',
        );
        for (var i = 0; i < 6; i++) {
          await tester.drag(list, const Offset(0, -600));
          await tester.pumpAndSettle();
        }
        for (final label in ['Completed', 'Pending', 'Failed']) {
          await selectStatus(tester, label);
          await tester.pumpAndSettle();
          expect(visibleStatuses(tester).map((s) => s.name).toSet(), {
            label.toLowerCase(),
          });
        }
        await search(tester, 'swiggy reference text that is long');
        await tester.pumpAndSettle();
        expect(clearSearchButton, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    void expectHintNotTruncated(WidgetTester tester) {
      final hint = find.text(TransactionToolbar.searchHint);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: hint, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse, reason: 'hint truncated');
    }

    testWidgets('toolbar is one row with room to spare at 1x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpApp(tester);
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(searchField).dy,
        moreOrLessEquals(tester.getCenter(statusDropdown).dy, epsilon: 8),
      );
      expect(
        tester.getTopRight(searchField).dx,
        lessThan(tester.getTopLeft(statusDropdown).dx),
        reason: 'search on the left, status on the right',
      );
      expect(
        tester.getSize(searchField).width,
        greaterThan(tester.getSize(statusDropdown).width),
        reason: 'search field takes the remaining width',
      );
      expectHintNotTruncated(tester);
    });

    testWidgets('toolbar stacks on a 412 dp phone in the test font', (
      tester,
    ) async {
      // Pixel 8: 1080 px at a device pixel ratio of 2.625 = 411.4 dp.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await pumpApp(tester);
      await tester.pumpAndSettle();

      expect(
        tester.getBottomLeft(searchField).dy,
        lessThanOrEqualTo(tester.getTopLeft(statusDropdown).dy),
      );
      // Whether the hint is truncated depends on real font metrics (the test
      // font draws every glyph as a square), so that is checked on device in
      // integration test (a).
    });

    testWidgets('details screen does not overflow', (tester) async {
      useSmallScreen(tester, width: 320);
      await pumpApp(tester);
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        row('txn_034'),
        list,
        const Offset(0, -100),
      );
      // At 2x a row can be taller than the space left under the toolbar, so
      // tap its first line rather than its centre.
      final merchant = find.descendant(
        of: row('txn_034'),
        matching: find.text('Amazon'),
      );
      await tester.ensureVisible(merchant);
      await tester.pumpAndSettle();
      await tester.tap(merchant);
      await tester.pumpAndSettle();
      expect(find.byType(TransactionDetailsPage), findsOneWidget);
      expect(find.text('₹1,29,900.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('details', () {
    String valueBelow(WidgetTester tester, String label) {
      final column = find
          .ancestor(of: find.text(label), matching: find.byType(Column))
          .first;
      final value = find.descendant(
        of: column,
        matching: find.byType(SelectableText),
      );
      return tester.widget<SelectableText>(value).data!;
    }

    testWidgets('tapping a row opens its details', (tester) async {
      final harness = await pumpApp(tester);
      await tester.pumpAndSettle();
      final swiggy = sampleTransactions.first;

      await tester.tap(row('txn_036'));
      await tester.pumpAndSettle();

      final details = find.byType(TransactionDetailsPage);
      expect(details, findsOneWidget);
      expect(
        tester.widget<TransactionDetailsPage>(details).transaction,
        swiggy,
      );
      expect(find.text('Transaction details'), findsOneWidget);
      Finder inDetails(Finder f) => find.descendant(of: details, matching: f);
      expect(inDetails(find.text('Swiggy')), findsOneWidget);
      expect(inDetails(find.text('₹1,299.00')), findsOneWidget);
      final badge = tester.widget<StatusBadge>(
        inDetails(find.byType(StatusBadge)),
      );
      expect(badge.status, TransactionStatus.pending);
      expect(
        valueBelow(tester, 'Date'),
        formatTransactionDate(swiggy.createdAt),
      );
      expect(valueBelow(tester, 'UTC time'), '2026-10-20 18:00:00 UTC');
      expect(valueBelow(tester, 'Reference'), 'SWG-88213');
      expect(valueBelow(tester, 'Transaction ID'), 'txn_036');
      expect(harness.source.requests, hasLength(1), reason: 'no refetch');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(details, findsNothing);
      expect(row('txn_036'), findsOneWidget);
    });

    testWidgets('a transaction without a reference says so', (tester) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();
      final uber = sampleTransactions.firstWhere((t) => t.id == 'txn_033');
      expect(uber.reference, isNull);

      await tester.tap(row('txn_033'));
      await tester.pumpAndSettle();
      expect(valueBelow(tester, 'Reference'), 'No reference');
      expect(
        valueBelow(tester, 'UTC time'),
        formatUtcTimestamp(uber.createdAt),
      );
      expect(
        find.descendant(
          of: find.byType(TransactionDetailsPage),
          matching: find.text('₹49.50'),
        ),
        findsOneWidget,
      );
    });
  });

  group('saved results', () {
    final savedRows = sampleTransactions.reversed.take(3).toList();

    Future<InMemoryTransactionLocalDataSource> cacheWithSavedRows() async {
      final cache = InMemoryTransactionLocalDataSource();
      await cache.writeFirstPage(
        TransactionLocalDataSource.keyFor(null, ''),
        savedRows,
      );
      return cache;
    }

    testWidgets('are shown while updating, then replaced by fresh rows', (
      tester,
    ) async {
      final harness = await pumpApp(tester, cache: await cacheWithSavedRows());
      await tester.pump();

      expect(visibleIds(tester), ['txn_001', 'txn_002', 'txn_003']);
      expect(find.text('Showing saved results · Updating…'), findsOneWidget);
      expect(find.text('No more transactions'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('Showing saved results · Updating…'), findsNothing);
      expect(row('txn_036'), findsOneWidget);
      expect(row('txn_001'), findsNothing);
      final saved = await harness.cache.readFirstPage(
        TransactionLocalDataSource.keyFor(null, ''),
      );
      expect(saved!.map((t) => t.id).first, 'txn_036');
      expect(saved, hasLength(10));
    });

    testWidgets('stay visible with Retry when the update fails', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        cache: await cacheWithSavedRows(),
        failAllRequests: true,
      );
      await tester.pumpAndSettle();

      expect(visibleIds(tester), ['txn_001', 'txn_002', 'txn_003']);
      expect(
        find.text("Couldn't update. Showing saved results."),
        findsOneWidget,
      );
      expect(find.text("Couldn't load transactions."), findsNothing);

      harness.failureSwitch.failAllRequests = false;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();
      expect(find.text('Showing saved results · Updating…'), findsOneWidget);
      expect(row('txn_001'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(row('txn_036'), findsOneWidget);
      expect(find.textContaining('saved results'), findsNothing);
    });

    testWidgets('do not paginate', (tester) async {
      final harness = await pumpApp(
        tester,
        cache: await cacheWithSavedRows(),
        failAllRequests: true,
      );
      await tester.pumpAndSettle();
      await scrollToEnd(tester);
      await tester.pumpAndSettle();
      expect(harness.source.requests, hasLength(1));
      expect(harness.source.requests.single.offset, 0);
    });
  });

  testWidgets('a row exposes one combined label and a tap hint', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    await tester.pumpAndSettle();

    final swiggy = sampleTransactions.first;
    final label =
        'Swiggy, ₹1,299.00, Pending, '
        '${formatTransactionDate(swiggy.createdAt)}, reference SWG-88213';
    expect(TransactionTile.semanticsLabel(swiggy), label);
    expect(find.bySemanticsLabel(label), findsOneWidget);
    final rowSemantics = tester.getSemantics(find.bySemanticsLabel(label));
    expect(
      rowSemantics,
      containsSemantics(label: label, isButton: true, hasTapAction: true),
    );
    // Android reads this as "double tap to view details".
    expect(
      rowSemantics.getSemanticsData().customSemanticsActionIds,
      contains(
        CustomSemanticsAction.getIdentifier(
          const CustomSemanticsAction.overridingAction(
            hint: 'view details',
            action: SemanticsAction.tap,
          ),
        ),
      ),
    );

    final badge = find.byType(StatusBadge).first;
    expect(
      find.descendant(of: badge, matching: find.byType(Icon)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: badge, matching: find.text('Pending')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('the switch is announced as "Fail all requests" with its state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byType(Switch)),
      containsSemantics(
        label: 'Fail all requests',
        hasToggledState: true,
        isToggled: false,
        hasTapAction: true,
      ),
    );

    await toggleFailAllRequests(tester);
    expect(
      tester.getSemantics(find.byType(Switch)),
      containsSemantics(
        label: 'Fail all requests',
        hasToggledState: true,
        isToggled: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('the status dropdown is announced with its label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Status')), findsWidgets);
    semantics.dispose();
  });

  test('toolbar offers All plus every status', () {
    expect(TransactionToolbar.filters, [null, ...TransactionStatus.values]);
  });
}
