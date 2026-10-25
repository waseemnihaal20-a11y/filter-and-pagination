/// A recoverable failure while fetching transactions (e.g. a network error).
///
/// [message] is safe to show to the user.
class TransactionFetchException implements Exception {
  const TransactionFetchException([
    this.message = "Couldn't load transactions. Please try again.",
  ]);

  final String message;

  @override
  String toString() => 'TransactionFetchException: $message';
}
