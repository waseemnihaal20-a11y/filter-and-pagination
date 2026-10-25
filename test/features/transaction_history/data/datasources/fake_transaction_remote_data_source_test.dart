import 'package:filter_and_pagination/features/transaction_history/data/datasources/fake_transaction_remote_data_source.dart';
import 'package:filter_and_pagination/core/demo/request_failure_switch.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/sample_transactions.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/entities/transaction.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/errors/transaction_fetch_exception.dart';
import 'package:flutter_test/flutter_test.dart';

/// Follows `nextOffset` until the end and returns every page.
Future<List<List<Transaction>>> walkAllPages(
  FakeTransactionRemoteDataSource source, {
  TransactionStatus? status,
  String? query,
}) async {
  final pages = <List<Transaction>>[];
  int? offset = 0;
  while (offset != null) {
    final page = await source.fetchTransactions(
      offset: offset,
      status: status,
      query: query,
    );
    pages.add(page.transactions);
    offset = page.nextOffset;
  }
  return pages;
}

void main() {
  late FakeTransactionRemoteDataSource source;

  setUp(() {
    source = FakeTransactionRemoteDataSource(delay: Duration.zero);
  });

  group('sample data', () {
    test('has at least 30 items covering both currencies and all statuses', () {
      expect(sampleTransactions.length, greaterThanOrEqualTo(30));
      expect(sampleTransactions.map((t) => t.currencyCode).toSet(), {
        'INR',
        'USD',
      });
      expect(
        sampleTransactions.map((t) => t.status).toSet(),
        TransactionStatus.values.toSet(),
      );
      expect(sampleTransactions.any((t) => t.reference == null), isTrue);
    });

    test('ids are unique and timestamps are UTC', () {
      final ids = sampleTransactions.map((t) => t.id).toSet();
      expect(ids.length, sampleTransactions.length);
      expect(sampleTransactions.every((t) => t.createdAt.isUtc), isTrue);
    });
  });

  test('orders newest first with id descending as tie-breaker', () async {
    final all = (await walkAllPages(source)).expand((p) => p).toList();
    for (var i = 1; i < all.length; i++) {
      final previous = all[i - 1];
      final current = all[i];
      final byTime = previous.createdAt.compareTo(current.createdAt);
      expect(
        byTime > 0 || (byTime == 0 && previous.id.compareTo(current.id) > 0),
        isTrue,
        reason: '${previous.id} must come before ${current.id}',
      );
    }
  });

  test('sorts regardless of input order', () async {
    final shuffled = FakeTransactionRemoteDataSource(
      transactions: sampleTransactions.reversed.toList(),
      delay: Duration.zero,
    );
    final page = await shuffled.fetchTransactions();
    expect(page.transactions.first.id, 'txn_036');
  });

  test('walking all pages returns every item exactly once', () async {
    final pages = await walkAllPages(source);
    expect(pages.map((p) => p.length), [10, 10, 10, 6]);
    final ids = pages.expand((p) => p).map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.toSet(), sampleTransactions.map((t) => t.id).toSet());
  });

  test('next offset follows each page and is null after the last', () async {
    final first = await source.fetchTransactions();
    expect(first.transactions, hasLength(10));
    expect(first.nextOffset, 10);
    final second = await source.fetchTransactions(offset: 10);
    expect(second.nextOffset, 20);
    final last = await source.fetchTransactions(offset: 30);
    expect(last.transactions, hasLength(6));
    expect(last.nextOffset, isNull);

    final exactFit = FakeTransactionRemoteDataSource(
      transactions: sampleTransactions.take(20).toList(),
      delay: Duration.zero,
    );
    final pages = await walkAllPages(exactFit);
    expect(
      pages.map((p) => p.length),
      [10, 10],
      reason: 'no next offset may lead to an empty page',
    );
  });

  for (final status in TransactionStatus.values) {
    test('filters by ${status.name} before paginating', () async {
      final expected = sampleTransactions.where((t) => t.status == status);
      final pages = await walkAllPages(source, status: status);

      expect(pages.length, greaterThan(1));
      expect(pages.last.length, lessThan(10), reason: 'partial last page');
      for (final page in pages) {
        expect(page.every((t) => t.status == status), isTrue);
      }
      final ids = pages.expand((p) => p).map((t) => t.id).toList();
      expect(ids.length, expected.length);
      expect(ids.toSet(), expected.map((t) => t.id).toSet());
    });
  }

  test('items with identical createdAt straddling a page boundary are neither '
      'duplicated nor skipped', () async {
    final first = await source.fetchTransactions();
    final second = await source.fetchTransactions(offset: first.nextOffset!);

    final lastOfFirst = first.transactions.last;
    final firstOfSecond = second.transactions.first;
    expect(lastOfFirst.id, 'txn_027');
    expect(firstOfSecond.id, 'txn_026');
    expect(lastOfFirst.createdAt, firstOfSecond.createdAt);
  });

  test('a negative offset throws RangeError', () {
    expect(() => source.fetchTransactions(offset: -1), throwsRangeError);
  });

  test(
    'an offset past the end returns an empty page with no next offset',
    () async {
      final page = await source.fetchTransactions(offset: 100);
      expect(page.transactions, isEmpty);
      expect(page.nextOffset, isNull);
    },
  );

  test(
    'fail all requests fails first and next pages until turned off',
    () async {
      final failureSwitch = RequestFailureSwitch();
      final failing = FakeTransactionRemoteDataSource(
        delay: Duration.zero,
        failureSwitch: failureSwitch,
      );
      final first = await failing.fetchTransactions();

      failureSwitch.failAllRequests = true;
      await expectLater(
        failing.fetchTransactions(),
        throwsA(isA<TransactionFetchException>()),
      );
      await expectLater(
        failing.fetchTransactions(offset: first.nextOffset!),
        throwsA(isA<TransactionFetchException>()),
      );

      failureSwitch.failAllRequests = false;
      expect(await failing.fetchTransactions(), first);
      final second = await failing.fetchTransactions(offset: first.nextOffset!);
      expect(second.transactions, hasLength(10));
    },
  );

  test('the switch is read when the request starts', () async {
    final failureSwitch = RequestFailureSwitch();
    final slow = FakeTransactionRemoteDataSource(
      delay: const Duration(milliseconds: 10),
      failureSwitch: failureSwitch,
    );
    final request = slow.fetchTransactions();
    failureSwitch.failAllRequests = true;
    expect((await request).transactions, hasLength(10));
  });

  group('search', () {
    Future<List<String>> idsFor(
      String query, {
      TransactionStatus? status,
    }) async {
      final pages = await walkAllPages(source, status: status, query: query);
      return [for (final page in pages) ...page.map((t) => t.id)];
    }

    test('matches merchant names ignoring case and whitespace', () async {
      const swiggy = ['txn_036', 'txn_023', 'txn_015', 'txn_001'];
      expect(await idsFor('swiggy'), swiggy);
      expect(await idsFor('SWIG'), swiggy);
      expect(await idsFor('  sWiG  '), swiggy);
    });

    test('matches references ignoring case', () async {
      // No merchant name contains "nflx"; only Netflix references do.
      expect(await idsFor('nflx'), ['txn_035', 'txn_020', 'txn_011']);
      expect(await idsFor('amz-us'), ['txn_022', 'txn_014']);
    });

    test('a match on either field is enough', () async {
      // "b" is in "Uber" (merchant) and in Apple's "APL-MBA13" (reference
      // only: "Apple" has no "b").
      final ids = await idsFor('b');
      expect(ids, contains('txn_033'));
      expect(ids, contains('txn_007'));
      // "bb" is only in BigBasket references, so BigBasket rows without a
      // reference do not match.
      expect(await idsFor('bb'), ['txn_031', 'txn_006']);
    });

    test('combines with the status filter', () async {
      expect(await idsFor('swiggy', status: TransactionStatus.pending), [
        'txn_036',
        'txn_015',
      ]);
      expect(
        await idsFor('swiggy', status: TransactionStatus.completed),
        isEmpty,
      );
    });

    for (final query in [null, '', '   ']) {
      test('${query == null ? 'null' : '"$query"'} means no search', () async {
        final ids = await idsFor(query ?? '');
        expect(ids, sampleTransactions.map((t) => t.id).toList());
        final page = await source.fetchTransactions(query: query);
        expect(page.transactions, hasLength(10));
      });
    }

    test('is applied before pagination: walking all pages returns exactly '
        'the matching set', () async {
      final small = FakeTransactionRemoteDataSource(
        delay: Duration.zero,
        pageSize: 3,
      );
      for (final status in [null, ...TransactionStatus.values]) {
        final expected = sampleTransactions
            .where(
              (t) =>
                  (status == null || t.status == status) &&
                  (t.merchantName.toLowerCase().contains('a') ||
                      (t.reference?.toLowerCase().contains('a') ?? false)),
            )
            .map((t) => t.id)
            .toList();
        final pages = await walkAllPages(small, status: status, query: 'A');
        final ids = [for (final page in pages) ...page.map((t) => t.id)];
        expect(ids, expected, reason: 'status: $status');
        expect(ids.toSet(), hasLength(ids.length), reason: 'no duplicates');
        expect(
          pages.take(pages.length - 1).every((p) => p.length == 3),
          isTrue,
          reason:
              'every page but the last is full, so nothing was dropped '
              'by filtering after slicing',
        );
      }
    });

    test('no matches returns an empty page with no next offset', () async {
      final page = await source.fetchTransactions(query: 'no such merchant');
      expect(page.transactions, isEmpty);
      expect(page.nextOffset, isNull);
    });
  });
}
