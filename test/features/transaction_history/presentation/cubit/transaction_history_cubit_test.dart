import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/fake_transaction_remote_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/in_memory_transaction_local_data_source.dart';
import 'package:filter_and_pagination/core/demo/request_failure_switch.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/sample_transactions.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/entities/transaction.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/transaction_local_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/entities/paginated_transactions.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/cubit/transaction_history_cubit.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/cubit/transaction_history_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/build_transaction_history.dart';
import '../../../../helpers/controllable_transaction_data_source.dart';

List<String> idsOf(TransactionHistoryState state) =>
    state.transactions.map((t) => t.id).toList();

void expectNoDuplicates(TransactionHistoryState state) {
  final ids = idsOf(state);
  expect(ids.toSet().length, ids.length, reason: 'duplicate rows: $ids');
}

int countWithStatus(TransactionStatus status) =>
    sampleTransactions.where((t) => t.status == status).length;

/// Cache whose reads stay pending until the test completes them.
class SlowReadCache extends InMemoryTransactionLocalDataSource {
  final List<Completer<void>> pendingReads = [];

  @override
  Future<List<Transaction>?> readFirstPage(String key) async {
    final gate = Completer<void>();
    pendingReads.add(gate);
    await gate.future;
    return super.readFirstPage(key);
  }
}

/// Cache whose reads and writes always fail, like broken storage.
class BrokenCache implements TransactionLocalDataSource {
  @override
  Future<List<Transaction>?> readFirstPage(String key) =>
      Future.error(Exception('disk error'));

  @override
  Future<void> writeFirstPage(String key, List<Transaction> transactions) =>
      Future.error(Exception('disk error'));
}

/// Loads the first page through [source] and completes it.
Future<void> loadFirstPage(
  TransactionHistoryCubit cubit,
  ControllableTransactionDataSource source,
) async {
  final initial = cubit.loadInitial();
  await source.lastCall.succeed();
  await initial;
}

void main() {
  final zeroDelay = FakeTransactionRemoteDataSource(delay: Duration.zero);

  group('initial load', () {
    blocTest<TransactionHistoryCubit, TransactionHistoryState>(
      'emits loading then success with 10 rows and a next offset',
      build: () => buildCubit(zeroDelay),
      act: (cubit) => cubit.loadInitial(),
      expect: () => [
        const TransactionHistoryState(),
        isA<TransactionHistoryState>()
            .having(
              (s) => s.firstPageStatus,
              'firstPageStatus',
              FirstPageStatus.success,
            )
            .having((s) => s.transactions.length, 'rows', 10)
            .having((s) => s.nextOffset, 'nextOffset', 10)
            .having((s) => s.filter, 'filter', isNull),
      ],
    );

    test('first-page failure then retryFirstPage succeeds', () async {
      final source = ControllableTransactionDataSource();
      final cubit = buildCubit(source);
      addTearDown(cubit.close);

      final initial = cubit.loadInitial();
      source.lastCall.fail();
      await initial;
      expect(cubit.state.firstPageStatus, FirstPageStatus.failure);
      expect(cubit.state.transactions, isEmpty);

      final retry = cubit.retryFirstPage();
      expect(cubit.state.firstPageStatus, FirstPageStatus.loading);
      await source.lastCall.succeed();
      await retry;
      expect(cubit.state.firstPageStatus, FirstPageStatus.success);
      expect(cubit.state.transactions, hasLength(10));
      expect(source.calls, hasLength(2));
    });

    blocTest<TransactionHistoryCubit, TransactionHistoryState>(
      'empty result shows the empty state',
      build: () => buildCubit(
        FakeTransactionRemoteDataSource(
          transactions: const [],
          delay: Duration.zero,
        ),
      ),
      act: (cubit) => cubit.loadInitial(),
      verify: (cubit) {
        expect(cubit.state.isEmpty, isTrue);
        expect(cubit.state.hasReachedEnd, isTrue);
      },
    );
  });

  group('pagination', () {
    test(
      'loadNextPage appends until the end, then makes no requests',
      () async {
        final source = ControllableTransactionDataSource();
        final cubit = buildCubit(source);
        addTearDown(cubit.close);

        final initial = cubit.loadInitial();
        await source.lastCall.succeed();
        await initial;

        for (final expectedRows in [20, 30, 36]) {
          final next = cubit.loadNextPage();
          expect(cubit.state.nextPageStatus, NextPageStatus.loading);
          await source.lastCall.succeed();
          await next;
          expect(cubit.state.transactions, hasLength(expectedRows));
          expect(cubit.state.nextPageStatus, NextPageStatus.idle);
        }
        expect(cubit.state.hasReachedEnd, isTrue);
        expectNoDuplicates(cubit.state);
        expect(idsOf(cubit.state), [for (final t in sampleTransactions) t.id]);

        final requests = source.calls.length;
        await cubit.loadNextPage();
        await cubit.loadNextPage();
        expect(source.calls, hasLength(requests));
      },
    );

    test('repeated loadNextPage while in flight issues one request', () async {
      final source = ControllableTransactionDataSource();
      final cubit = buildCubit(source);
      addTearDown(cubit.close);
      final initial = cubit.loadInitial();
      await source.lastCall.succeed();
      await initial;

      final first = cubit.loadNextPage();
      await cubit.loadNextPage();
      await cubit.loadNextPage();
      expect(source.calls, hasLength(2));

      await source.lastCall.succeed();
      await first;
      expect(cubit.state.transactions, hasLength(20));
      expectNoDuplicates(cubit.state);
    });

    test('next-page failure keeps rows; retry uses the same offset', () async {
      final source = ControllableTransactionDataSource();
      final cubit = buildCubit(source);
      addTearDown(cubit.close);
      final initial = cubit.loadInitial();
      await source.lastCall.succeed();
      await initial;
      final firstPageIds = idsOf(cubit.state);

      final next = cubit.loadNextPage();
      final failedOffset = source.lastCall.offset;
      expect(failedOffset, 10);
      source.lastCall.fail();
      await next;
      expect(cubit.state.nextPageStatus, NextPageStatus.failure);
      expect(idsOf(cubit.state), firstPageIds);

      await cubit.loadNextPage();
      expect(source.calls, hasLength(2), reason: 'no auto-retry on scroll');

      final retry = cubit.retryNextPage();
      expect(source.lastCall.offset, failedOffset);
      await source.lastCall.succeed();
      await retry;
      expect(cubit.state.nextPageStatus, NextPageStatus.idle);
      expect(cubit.state.transactions, hasLength(20));
      expectNoDuplicates(cubit.state);
    });

    test('rows already in the list are not appended twice', () async {
      final source = ControllableTransactionDataSource();
      final cubit = buildCubit(source);
      addTearDown(cubit.close);
      final initial = cubit.loadInitial();
      await source.lastCall.succeed();
      await initial;

      final next = cubit.loadNextPage();
      final overlapping = [
        cubit.state.transactions.last,
        ...sampleTransactions.skip(10).take(3),
      ];
      source.lastCall.succeedWith(
        PaginatedTransactions(transactions: overlapping),
      );
      await next;
      expect(cubit.state.transactions, hasLength(13));
      expectNoDuplicates(cubit.state);
    });
  });

  group('filters', () {
    blocTest<TransactionHistoryCubit, TransactionHistoryState>(
      'selectFilter(pending) resets pagination and shows only pending rows',
      build: () => buildCubit(zeroDelay),
      act: (cubit) async {
        await cubit.loadInitial();
        await cubit.loadNextPage();
        await cubit.selectFilter(TransactionStatus.pending);
      },
      skip: 4,
      expect: () => [
        const TransactionHistoryState(filter: TransactionStatus.pending),
        isA<TransactionHistoryState>()
            .having((s) => s.filter, 'filter', TransactionStatus.pending)
            .having((s) => s.transactions.length, 'rows', 10)
            .having(
              (s) => s.transactions.every(
                (t) => t.status == TransactionStatus.pending,
              ),
              'only pending',
              isTrue,
            ),
      ],
    );

    blocTest<TransactionHistoryCubit, TransactionHistoryState>(
      'selecting the already loaded filter does nothing',
      build: () => buildCubit(zeroDelay),
      act: (cubit) async {
        await cubit.loadInitial();
        await cubit.selectFilter(null);
      },
      skip: 2,
      expect: () => <TransactionHistoryState>[],
    );

    for (final newResolvesFirst in [true, false]) {
      test(
        'stale response for the previous filter is discarded '
        '(${newResolvesFirst ? 'new' : 'old'} response resolves first)',
        () async {
          final source = ControllableTransactionDataSource();
          final cubit = buildCubit(source);
          addTearDown(cubit.close);

          final all = cubit.loadInitial();
          final allCall = source.lastCall;
          final pending = cubit.selectFilter(TransactionStatus.pending);
          final pendingCall = source.lastCall;
          expect(cubit.state.transactions, isEmpty);
          expect(cubit.state.firstPageStatus, FirstPageStatus.loading);

          if (newResolvesFirst) {
            await pendingCall.succeed();
            await allCall.succeed();
          } else {
            await allCall.succeed();
            await pendingCall.succeed();
          }
          await Future.wait([all, pending]);

          expect(cubit.state.filter, TransactionStatus.pending);
          expect(cubit.state.firstPageStatus, FirstPageStatus.success);
          expect(cubit.state.transactions, hasLength(10));
          expect(
            cubit.state.transactions.every(
              (t) => t.status == TransactionStatus.pending,
            ),
            isTrue,
          );
        },
      );
    }

    test('rapid filter changes only land the last filter', () async {
      final source = ControllableTransactionDataSource();
      final cubit = buildCubit(source);
      addTearDown(cubit.close);

      final initial = cubit.loadInitial();
      await source.lastCall.succeed();
      await initial;

      final futures = [
        cubit.selectFilter(TransactionStatus.completed),
        cubit.selectFilter(TransactionStatus.pending),
        cubit.selectFilter(TransactionStatus.failed),
      ];
      final pendingCalls = source.calls.skip(1).toList();
      expect(pendingCalls.map((c) => c.status), [
        TransactionStatus.completed,
        TransactionStatus.pending,
        TransactionStatus.failed,
      ]);
      for (final call in pendingCalls.reversed) {
        await call.succeed();
      }
      await Future.wait(futures);

      expect(cubit.state.filter, TransactionStatus.failed);
      expect(
        cubit.state.transactions.every(
          (t) => t.status == TransactionStatus.failed,
        ),
        isTrue,
      );
      expect(cubit.state.transactions, hasLength(10));
    });
  });

  group('refresh', () {
    blocTest<TransactionHistoryCubit, TransactionHistoryState>(
      'replaces the list and keeps the current filter',
      build: () => buildCubit(zeroDelay),
      act: (cubit) async {
        await cubit.selectFilter(TransactionStatus.completed);
        await cubit.loadNextPage();
        expect(
          cubit.state.transactions,
          hasLength(countWithStatus(TransactionStatus.completed)),
        );
        await cubit.refresh();
      },
      verify: (cubit) {
        expect(cubit.state.filter, TransactionStatus.completed);
        expect(cubit.state.transactions, hasLength(10));
        expect(cubit.state.isRefreshing, isFalse);
        expect(cubit.state.nextOffset, isNotNull);
        expectNoDuplicates(cubit.state);
      },
    );

    test('keeps rows visible while refreshing', () async {
      final source = ControllableTransactionDataSource();
      final cubit = buildCubit(source);
      addTearDown(cubit.close);
      final initial = cubit.loadInitial();
      await source.lastCall.succeed();
      await initial;

      final refresh = cubit.refresh();
      expect(cubit.state.isRefreshing, isTrue);
      expect(cubit.state.transactions, hasLength(10));
      await source.lastCall.succeed();
      await refresh;
      expect(cubit.state.isRefreshing, isFalse);
    });

    for (final staleResolvesFirst in [true, false]) {
      test(
        'in-flight next page is discarded '
        '(${staleResolvesFirst ? 'stale' : 'fresh'} response resolves first)',
        () async {
          final source = ControllableTransactionDataSource();
          final cubit = buildCubit(source);
          addTearDown(cubit.close);
          final initial = cubit.loadInitial();
          await source.lastCall.succeed();
          await initial;
          final firstPageIds = idsOf(cubit.state);

          final next = cubit.loadNextPage();
          final nextCall = source.lastCall;
          final refresh = cubit.refresh();
          final refreshCall = source.lastCall;
          expect(cubit.state.nextPageStatus, NextPageStatus.idle);

          if (staleResolvesFirst) {
            await nextCall.succeed();
            await refreshCall.succeed();
          } else {
            await refreshCall.succeed();
            await nextCall.succeed();
          }
          await Future.wait([next, refresh]);

          expect(idsOf(cubit.state), firstPageIds);
          expect(cubit.state.nextPageStatus, NextPageStatus.idle);
          expectNoDuplicates(cubit.state);
        },
      );
    }

    test('failure with rows visible keeps rows and signals once', () async {
      final source = ControllableTransactionDataSource();
      final cubit = buildCubit(source);
      addTearDown(cubit.close);
      final initial = cubit.loadInitial();
      await source.lastCall.succeed();
      await initial;
      final rows = cubit.state.transactions;

      final refresh = cubit.refresh();
      source.lastCall.fail();
      await refresh;

      expect(cubit.state.transactions, rows);
      expect(cubit.state.firstPageStatus, FirstPageStatus.success);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.refreshFailureCount, 1);
    });

    test('failure from the empty state shows the first-page error', () async {
      final source = ControllableTransactionDataSource();
      final cubit = buildCubit(source);
      addTearDown(cubit.close);
      final initial = cubit.loadInitial();
      source.lastCall.succeedWith(
        PaginatedTransactions(transactions: const []),
      );
      await initial;
      expect(cubit.state.isEmpty, isTrue);

      final refresh = cubit.refresh();
      source.lastCall.fail();
      await refresh;
      expect(cubit.state.firstPageStatus, FirstPageStatus.failure);
      expect(cubit.state.refreshFailureCount, 0);
    });

    test('success from the first-page error shows data', () async {
      final source = ControllableTransactionDataSource();
      final cubit = buildCubit(source);
      addTearDown(cubit.close);
      final initial = cubit.loadInitial();
      source.lastCall.fail();
      await initial;

      final refresh = cubit.refresh();
      expect(cubit.state.firstPageStatus, FirstPageStatus.failure);
      expect(cubit.state.isRefreshing, isTrue);
      await source.lastCall.succeed();
      await refresh;
      expect(cubit.state.firstPageStatus, FirstPageStatus.success);
      expect(cubit.state.transactions, hasLength(10));
    });
  });

  group('fail all requests switch', () {
    late RequestFailureSwitch failureSwitch;
    late TransactionHistoryCubit cubit;

    setUp(() {
      failureSwitch = RequestFailureSwitch();
      cubit = buildCubit(
        FakeTransactionRemoteDataSource(
          delay: Duration.zero,
          failureSwitch: failureSwitch,
        ),
      );
    });

    tearDown(() async {
      await cubit.close();
      failureSwitch.dispose();
    });

    test('initial load fails, then retry succeeds once turned off', () async {
      failureSwitch.failAllRequests = true;
      await cubit.loadInitial();
      expect(cubit.state.firstPageStatus, FirstPageStatus.failure);

      failureSwitch.failAllRequests = false;
      await cubit.retryFirstPage();
      expect(cubit.state.firstPageStatus, FirstPageStatus.success);
      expect(cubit.state.transactions, hasLength(10));
    });

    test('next page fails with rows kept, then retry appends', () async {
      await cubit.loadInitial();
      failureSwitch.failAllRequests = true;
      await cubit.loadNextPage();
      expect(cubit.state.nextPageStatus, NextPageStatus.failure);
      expect(cubit.state.transactions, hasLength(10));

      failureSwitch.failAllRequests = false;
      await cubit.retryNextPage();
      expect(cubit.state.nextPageStatus, NextPageStatus.idle);
      expect(cubit.state.transactions, hasLength(20));
      expectNoDuplicates(cubit.state);
    });

    test('refresh keeps rows and signals failure', () async {
      await cubit.loadInitial();
      final rows = cubit.state.transactions;
      failureSwitch.failAllRequests = true;
      await cubit.refresh();
      expect(cubit.state.transactions, rows);
      expect(cubit.state.refreshFailureCount, 1);
    });

    test('filter change fails for the new filter', () async {
      await cubit.loadInitial();
      failureSwitch.failAllRequests = true;
      await cubit.selectFilter(TransactionStatus.failed);
      expect(cubit.state.filter, TransactionStatus.failed);
      expect(cubit.state.firstPageStatus, FirstPageStatus.failure);
      expect(cubit.state.transactions, isEmpty);
    });
  });

  test('no emissions after close when a request completes late', () async {
    final source = ControllableTransactionDataSource();
    final cubit = buildCubit(source);
    final states = <TransactionHistoryState>[];
    final subscription = cubit.stream.listen(states.add);

    final initial = cubit.loadInitial();
    await flush();
    final emittedBeforeClose = states.length;
    await cubit.close();

    await source.lastCall.succeed();
    await initial;
    await flush();
    expect(states, hasLength(emittedBeforeClose));
    await subscription.cancel();
  });

  group('search', () {
    TransactionHistoryCubit build(
      ControllableTransactionDataSource source, {
      Duration debounce = Duration.zero,
    }) {
      final cubit = buildCubit(source, searchDebounce: debounce);
      addTearDown(cubit.close);
      return cubit;
    }

    test('rapid typing sends a single request after the debounce', () async {
      final source = ControllableTransactionDataSource();
      final cubit = build(source, debounce: const Duration(milliseconds: 40));
      await loadFirstPage(cubit, source);

      for (final text in ['s', 'sw', 'swi', 'swig']) {
        cubit.searchChanged(text);
      }
      await flush();
      expect(source.calls, hasLength(1), reason: 'still debouncing');
      expect(cubit.state.searchQuery, isEmpty);
      expect(cubit.state.transactions, hasLength(10), reason: 'rows kept');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(source.calls, hasLength(2));
      expect(source.lastCall.query, 'swig');
      expect(source.lastCall.offset, 0);
      expect(cubit.state.searchQuery, 'swig');
      expect(cubit.state.firstPageStatus, FirstPageStatus.loading);

      await source.lastCall.succeed();
      await flush();
      expect(idsOf(cubit.state), ['txn_036', 'txn_023', 'txn_015', 'txn_001']);
      expect(cubit.state.hasReachedEnd, isTrue);
    });

    test(
      'typing pauses longer than the debounce send one request each',
      () async {
        final source = ControllableTransactionDataSource();
        final cubit = build(source, debounce: const Duration(milliseconds: 20));
        await loadFirstPage(cubit, source);

        cubit.searchChanged('a');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        cubit.searchChanged('am');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(source.calls.skip(1).map((c) => c.query), ['a', 'am']);
      },
    );

    test('the default debounce is 300 ms', () async {
      final source = ControllableTransactionDataSource();
      final cubit = buildCubit(source);
      addTearDown(cubit.close);
      await loadFirstPage(cubit, source);

      cubit.searchChanged('swig');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(source.calls, hasLength(1));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(source.calls, hasLength(2));
    });

    test(
      'whitespace is trimmed and a whitespace-only change sends nothing',
      () async {
        final source = ControllableTransactionDataSource();
        final cubit = build(source);
        await loadFirstPage(cubit, source);

        cubit.searchChanged('   ');
        await flush();
        expect(source.calls, hasLength(1));

        cubit.searchChanged('  swig ');
        await flush();
        expect(source.lastCall.query, 'swig');
        await source.lastCall.succeed();
        await flush();

        cubit.searchChanged('swig   ');
        await flush();
        expect(source.calls, hasLength(2));
      },
    );

    test('typing back to the current search cancels the pending one', () async {
      final source = ControllableTransactionDataSource();
      final cubit = build(source, debounce: const Duration(milliseconds: 20));
      await loadFirstPage(cubit, source);

      cubit.searchChanged('x');
      cubit.searchChanged('');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(source.calls, hasLength(1));
    });

    test('resets pagination', () async {
      final source = ControllableTransactionDataSource();
      final cubit = build(source);
      await loadFirstPage(cubit, source);
      final next = cubit.loadNextPage();
      await source.lastCall.succeed();
      await next;
      expect(cubit.state.transactions, hasLength(20));

      cubit.searchChanged('a');
      await flush();
      expect(cubit.state.transactions, isEmpty);
      expect(cubit.state.nextOffset, isNull);
      expect(cubit.state.firstPageStatus, FirstPageStatus.loading);
      expect(source.lastCall.offset, 0);
      expect(source.lastCall.query, 'a');

      await source.lastCall.succeed();
      await flush();
      expect(cubit.state.transactions, hasLength(10));
      expect(cubit.state.nextOffset, isNotNull);

      final searchNext = cubit.loadNextPage();
      expect(source.lastCall.query, 'a', reason: 'next page keeps the search');
      expect(source.lastCall.offset, cubit.state.nextOffset);
      await source.lastCall.succeed();
      await searchNext;
      expectNoDuplicates(cubit.state);
      expect(
        cubit.state.transactions.every(
          (t) =>
              t.merchantName.toLowerCase().contains('a') ||
              (t.reference?.toLowerCase().contains('a') ?? false),
        ),
        isTrue,
      );
    });

    test('a search change while an older request is pending lands only the '
        'latest results', () async {
      final source = ControllableTransactionDataSource();
      final cubit = build(source);
      await loadFirstPage(cubit, source);

      cubit.searchChanged('swig');
      await flush();
      final older = source.lastCall;
      cubit.searchChanged('uber');
      await flush();
      final newer = source.lastCall;
      expect([older.query, newer.query], ['swig', 'uber']);

      await newer.succeed();
      await flush();
      await older.succeed();
      await flush();
      expect(cubit.state.searchQuery, 'uber');
      expect(cubit.state.transactions.map((t) => t.merchantName).toSet(), {
        'Uber',
      });
    });

    test('a stale next page from before a search is not appended', () async {
      final source = ControllableTransactionDataSource();
      final cubit = build(source);
      await loadFirstPage(cubit, source);

      unawaited(cubit.loadNextPage());
      final staleNext = source.lastCall;
      cubit.searchChanged('uber');
      await flush();
      await source.lastCall.succeed();
      await staleNext.succeed();
      await flush();
      expect(cubit.state.transactions.map((t) => t.merchantName).toSet(), {
        'Uber',
      });
    });

    test(
      'a filter change during the debounce applies both in one request',
      () async {
        final source = ControllableTransactionDataSource();
        final cubit = build(source, debounce: const Duration(milliseconds: 20));
        await loadFirstPage(cubit, source);

        cubit.searchChanged('swig');
        final select = cubit.selectFilter(TransactionStatus.pending);
        expect(source.calls, hasLength(2));
        expect(source.lastCall.status, TransactionStatus.pending);
        expect(source.lastCall.query, 'swig');
        await source.lastCall.succeed();
        await select;

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(source.calls, hasLength(2), reason: 'debounce was cancelled');
        expect(idsOf(cubit.state), ['txn_036', 'txn_015']);
      },
    );

    test('search and filter racing: only the latest request lands', () async {
      final source = ControllableTransactionDataSource();
      final cubit = build(source);
      await loadFirstPage(cubit, source);

      final select = cubit.selectFilter(TransactionStatus.failed);
      final filterCall = source.lastCall;
      cubit.searchChanged('swig');
      await flush();
      final searchCall = source.lastCall;
      expect(searchCall.status, TransactionStatus.failed);
      expect(searchCall.query, 'swig');

      await searchCall.succeed();
      await flush();
      await filterCall.succeed();
      await select;
      expect(cubit.state.filter, TransactionStatus.failed);
      expect(cubit.state.searchQuery, 'swig');
      expect(idsOf(cubit.state), ['txn_023', 'txn_001']);

      // And the other way round: a search request overtaken by a filter.
      cubit.searchChanged('uber');
      await flush();
      final searchFirst = source.lastCall;
      final select2 = cubit.selectFilter(TransactionStatus.completed);
      final filterSecond = source.lastCall;
      await filterSecond.succeed();
      await select2;
      await searchFirst.succeed();
      await flush();
      expect(cubit.state.filter, TransactionStatus.completed);
      expect(cubit.state.searchQuery, 'uber');
      expect(idsOf(cubit.state), ['txn_019', 'txn_013']);
    });

    test('refresh keeps the search', () async {
      final source = ControllableTransactionDataSource();
      final cubit = build(source);
      await loadFirstPage(cubit, source);
      cubit.searchChanged('uber');
      await flush();
      await source.lastCall.succeed();
      await flush();

      final refresh = cubit.refresh();
      expect(source.lastCall.query, 'uber');
      await source.lastCall.succeed();
      await refresh;
      expect(cubit.state.searchQuery, 'uber');
    });

    test('a failed search can be retried', () async {
      final source = ControllableTransactionDataSource();
      final cubit = build(source);
      await loadFirstPage(cubit, source);
      cubit.searchChanged('uber');
      await flush();
      source.lastCall.fail();
      await flush();
      expect(cubit.state.firstPageStatus, FirstPageStatus.failure);

      final retry = cubit.retryFirstPage();
      expect(source.lastCall.query, 'uber');
      await source.lastCall.succeed();
      await retry;
      expect(cubit.state.firstPageStatus, FirstPageStatus.success);
    });

    test('close cancels a pending debounce', () async {
      final source = ControllableTransactionDataSource();
      final cubit = buildCubit(
        source,
        searchDebounce: const Duration(milliseconds: 20),
      );
      await loadFirstPage(cubit, source);
      cubit.searchChanged('swig');
      await cubit.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(source.calls, hasLength(1));
    });
  });

  group('saved results', () {
    final savedRows = sampleTransactions.reversed.take(3).toList();
    final allKey = TransactionLocalDataSource.keyFor(null, '');

    Future<InMemoryTransactionLocalDataSource> cacheWith(
      String key,
      List<Transaction> rows,
    ) async {
      final cache = InMemoryTransactionLocalDataSource();
      await cache.writeFirstPage(key, rows);
      return cache;
    }

    TransactionHistoryCubit build(
      ControllableTransactionDataSource source,
      TransactionLocalDataSource cache,
    ) {
      final cubit = buildCubit(
        source,
        cache: cache,
        searchDebounce: Duration.zero,
      );
      addTearDown(cubit.close);
      return cubit;
    }

    test('are shown first, then replaced by fresh rows', () async {
      final source = ControllableTransactionDataSource();
      final cubit = build(source, await cacheWith(allKey, savedRows));
      final states = <TransactionHistoryState>[];
      final subscription = cubit.stream.listen(states.add);
      addTearDown(subscription.cancel);

      final initial = cubit.loadInitial();
      await flush();
      expect(cubit.state.isShowingSavedResults, isTrue);
      expect(cubit.state.firstPageStatus, FirstPageStatus.loading);
      expect(cubit.state.transactions, savedRows);
      expect(cubit.state.nextOffset, isNull);

      await source.lastCall.succeed();
      await initial;
      expect(cubit.state.isShowingSavedResults, isFalse);
      expect(cubit.state.firstPageStatus, FirstPageStatus.success);
      expect(idsOf(cubit.state).first, 'txn_036');
      expect(cubit.state.nextOffset, isNotNull);
      await flush();
      expect(states.map((s) => s.isShowingSavedResults), [false, true, false]);
    });

    test('fresh success updates the cache', () async {
      final source = ControllableTransactionDataSource();
      final cache = await cacheWith(allKey, savedRows);
      final cubit = build(source, cache);
      await loadFirstPage(cubit, source);
      await flush();
      expect(await cache.readFirstPage(allKey), cubit.state.transactions);
    });

    test(
      'fresh failure keeps the saved rows and reports the failure',
      () async {
        final source = ControllableTransactionDataSource();
        final cache = await cacheWith(allKey, savedRows);
        final cubit = build(source, cache);

        final initial = cubit.loadInitial();
        await flush();
        source.lastCall.fail();
        await initial;
        expect(cubit.state.firstPageStatus, FirstPageStatus.failure);
        expect(cubit.state.isShowingSavedResults, isTrue);
        expect(cubit.state.transactions, savedRows);
        expect(await cache.readFirstPage(allKey), savedRows, reason: 'kept');

        final retry = cubit.retryFirstPage();
        expect(cubit.state.firstPageStatus, FirstPageStatus.loading);
        expect(cubit.state.transactions, savedRows, reason: 'still visible');
        await source.lastCall.succeed();
        await retry;
        expect(cubit.state.isShowingSavedResults, isFalse);
        expect(cubit.state.transactions, hasLength(10));
      },
    );

    test(
      'a failure that beats the cache read still shows saved rows',
      () async {
        final source = ControllableTransactionDataSource();
        final cache = SlowReadCache();
        await cache.writeFirstPage(allKey, savedRows);
        final cubit = build(source, cache);

        final initial = cubit.loadInitial();
        source.lastCall.fail();
        await initial;
        expect(cubit.state.firstPageStatus, FirstPageStatus.failure);
        cache.pendingReads.single.complete();
        await flush();
        expect(cubit.state.isShowingSavedResults, isTrue);
        expect(cubit.state.firstPageStatus, FirstPageStatus.failure);
      },
    );

    test('pagination is disabled while saved rows are shown', () async {
      final source = ControllableTransactionDataSource();
      final cubit = build(source, await cacheWith(allKey, savedRows));

      final initial = cubit.loadInitial();
      await flush();
      await cubit.loadNextPage();
      expect(source.calls, hasLength(1), reason: 'while updating');

      source.lastCall.fail();
      await initial;
      await cubit.loadNextPage();
      await cubit.retryNextPage();
      expect(source.calls, hasLength(1), reason: 'after the update failed');

      final retry = cubit.retryFirstPage();
      await source.lastCall.succeed();
      await retry;
      final next = cubit.loadNextPage();
      expect(source.calls, hasLength(3), reason: 'resumes after fresh rows');
      expect(source.lastCall.offset, greaterThan(0));
      await source.lastCall.succeed();
      await next;
    });

    test('a corrupt entry is ignored', () async {
      for (final raw in [
        '{not json',
        '[]',
        '{"version":1,"transactions":[7]}',
      ]) {
        final source = ControllableTransactionDataSource();
        final cache = InMemoryTransactionLocalDataSource()
          ..entries[allKey] = raw;
        final cubit = build(source, cache);
        final initial = cubit.loadInitial();
        await flush();
        expect(cubit.state.isShowingSavedResults, isFalse, reason: raw);
        expect(cubit.state.transactions, isEmpty, reason: raw);
        await source.lastCall.succeed();
        await initial;
        expect(cubit.state.transactions, hasLength(10));
        expect(
          await cache.readFirstPage(allKey),
          hasLength(10),
          reason: 'overwritten',
        );
      }
    });

    test('a cache that throws is treated as empty', () async {
      final source = ControllableTransactionDataSource();
      final cubit = build(source, BrokenCache());
      final initial = cubit.loadInitial();
      await flush();
      expect(cubit.state.isShowingSavedResults, isFalse);
      await source.lastCall.succeed();
      await initial;
      await flush();
      expect(cubit.state.firstPageStatus, FirstPageStatus.success);
    });

    test('an empty saved page is not shown', () async {
      final source = ControllableTransactionDataSource();
      final cubit = build(source, await cacheWith(allKey, const []));
      unawaited(cubit.loadInitial());
      await flush();
      expect(cubit.state.isShowingSavedResults, isFalse);
      expect(cubit.state.firstPageStatus, FirstPageStatus.loading);
    });

    test('only successful first pages are written', () async {
      final source = ControllableTransactionDataSource();
      final cache = InMemoryTransactionLocalDataSource();
      final cubit = build(source, cache);

      final failing = cubit.loadInitial();
      source.lastCall.fail();
      await failing;
      await flush();
      expect(cache.entries, isEmpty, reason: 'failed first page');

      final retry = cubit.retryFirstPage();
      await source.lastCall.succeed();
      await retry;
      await flush();
      final firstPage = List.of(cubit.state.transactions);
      expect(await cache.readFirstPage(allKey), firstPage);

      final next = cubit.loadNextPage();
      await source.lastCall.succeed();
      await next;
      await flush();
      expect(cubit.state.transactions, hasLength(20));
      expect(
        await cache.readFirstPage(allKey),
        firstPage,
        reason: 'next pages are not cached',
      );
      expect(cache.entries[allKey], isNot(contains('nextOffset')));

      final refresh = cubit.refresh();
      source.lastCall.fail();
      await refresh;
      await flush();
      expect(await cache.readFirstPage(allKey), firstPage);
    });

    test('refresh success writes the cache', () async {
      final source = ControllableTransactionDataSource();
      final cache = InMemoryTransactionLocalDataSource();
      final cubit = build(source, cache);
      await loadFirstPage(cubit, source);
      final refreshed = sampleTransactions.skip(5).take(2).toList();
      final refresh = cubit.refresh();
      source.lastCall.succeedWith(
        PaginatedTransactions(transactions: refreshed),
      );
      await refresh;
      await flush();
      expect(await cache.readFirstPage(allKey), refreshed);
    });

    test('the key includes the filter and the search', () async {
      final source = ControllableTransactionDataSource();
      final cache = InMemoryTransactionLocalDataSource();
      final cubit = build(source, cache);
      await loadFirstPage(cubit, source);

      final select = cubit.selectFilter(TransactionStatus.pending);
      await source.lastCall.succeed();
      await select;
      cubit.searchChanged('  SWIG ');
      await flush();
      await source.lastCall.succeed();
      await flush();

      expect(cache.entries.keys, {'all|', 'pending|', 'pending|swig'});
      expect((await cache.readFirstPage('pending|swig'))!.map((t) => t.id), [
        'txn_036',
        'txn_015',
      ]);
      expect(
        (await cache.readFirstPage(
          'pending|',
        ))!.every((t) => t.status == TransactionStatus.pending),
        isTrue,
      );
    });

    test('saved rows of another query are never shown', () async {
      final source = ControllableTransactionDataSource();
      final cache = await cacheWith(
        TransactionLocalDataSource.keyFor(TransactionStatus.failed, ''),
        savedRows,
      );
      final cubit = build(source, cache);
      await loadFirstPage(cubit, source);
      expect(cubit.state.isShowingSavedResults, isFalse);

      unawaited(cubit.selectFilter(TransactionStatus.failed));
      await flush();
      expect(cubit.state.isShowingSavedResults, isTrue);
      expect(cubit.state.transactions, savedRows);

      cubit.searchChanged('x');
      await flush();
      expect(cubit.state.isShowingSavedResults, isFalse);
      expect(cubit.state.transactions, isEmpty);
    });

    test('a slow cache read never replaces fresh rows', () async {
      final source = ControllableTransactionDataSource();
      final cache = SlowReadCache();
      await cache.writeFirstPage(allKey, savedRows);
      final cubit = build(source, cache);

      final initial = cubit.loadInitial();
      await source.lastCall.succeed();
      await initial;
      final fresh = List.of(cubit.state.transactions);

      cache.pendingReads.single.complete();
      await flush();
      expect(cubit.state.transactions, fresh);
      expect(cubit.state.isShowingSavedResults, isFalse);
    });

    test('a slow cache read from an older generation is dropped', () async {
      final source = ControllableTransactionDataSource();
      final cache = SlowReadCache();
      await cache.writeFirstPage(allKey, savedRows);
      final cubit = build(source, cache);

      unawaited(cubit.loadInitial());
      final select = cubit.selectFilter(TransactionStatus.completed);
      expect(cache.pendingReads, hasLength(2));

      cache.pendingReads.first.complete(); // the "All" read, now stale
      await flush();
      expect(cubit.state.filter, TransactionStatus.completed);
      expect(cubit.state.isShowingSavedResults, isFalse);
      expect(cubit.state.transactions, isEmpty);

      cache.pendingReads.last.complete();
      await source.lastCall.succeed();
      await select;
      expect(
        cubit.state.transactions.every(
          (t) => t.status == TransactionStatus.completed,
        ),
        isTrue,
      );
    });

    test('a stale response is not written to the cache', () async {
      final source = ControllableTransactionDataSource();
      final cache = InMemoryTransactionLocalDataSource();
      final cubit = build(source, cache);

      unawaited(cubit.loadInitial());
      final stale = source.lastCall;
      final select = cubit.selectFilter(TransactionStatus.failed);
      await source.lastCall.succeed();
      await select;
      await stale.succeed();
      await flush();
      expect(cache.entries.keys, {'failed|'});
    });

    test('a failing cache write does not break loading', () async {
      final source = ControllableTransactionDataSource();
      final cubit = build(source, BrokenCache());
      await loadFirstPage(cubit, source);
      await flush();
      expect(cubit.state.firstPageStatus, FirstPageStatus.success);
    });
  });
}
