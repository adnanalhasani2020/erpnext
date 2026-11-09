import 'dart:async';
import 'dart:io';

/// Flutter's widget test binding replaces HttpClient with a fake client that
/// returns 400 for every request. The API integration tests use loopback
/// HttpServer fixtures, so run the test suite with a real HttpClient inside
/// the test zone while keeping all requests local to their fixture servers.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await HttpOverrides.runZoned(
    testMain,
    createHttpClient: (_) => HttpClient(),
  );
}
