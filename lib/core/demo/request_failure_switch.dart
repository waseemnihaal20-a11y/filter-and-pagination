import 'package:flutter/foundation.dart';

/// Demo control that makes every `FakeTransactionRemoteDataSource` request fail.
///
/// It exists so reviewers can see the error states while running the app
/// offline. It is owned by `main.dart`, handed to the fake data source and to
/// the "Fail all requests" row below the app bar, and is deliberately NOT part
/// of the cubit's business state: a real app would have no such switch.
///
/// Flipping it does not trigger a request by itself; it only affects requests
/// that start afterwards (scroll, filter change, search, refresh, retry).
class RequestFailureSwitch extends ValueNotifier<bool> {
  RequestFailureSwitch({bool failAllRequests = false}) : super(failAllRequests);

  bool get failAllRequests => value;

  set failAllRequests(bool enabled) => value = enabled;
}
