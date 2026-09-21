import 'package:dart_otel_api/dart_otel_api.dart';

import 'safely.dart';

/// Records that something happened, with a few plain attributes.
///
/// Callers pass only fixed names and coarse values (a state, a status code, a
/// reason slug), never a URL, host or exception message, which can carry
/// addresses or input the user typed.
typedef AppEventLogger = void Function(
  String name, [
  Map<String, Object> attributes,
]);

/// An [AppEventLogger] that records nothing, for when telemetry is off.
void noopAppEventLogger(
  String name, [
  Map<String, Object> attributes = const {},
]) {}

/// Returns an [AppEventLogger] that emits each event through [logger] as an
/// info [LogRecord]. Never throws, even if [logger] does.
AppEventLogger appEventLogger(Logger logger) =>
    (name, [attributes = const {}]) => safely(
          () => logger.emit(
            LogRecord(
              body: name,
              severity: LogSeverity.info,
              attributes: attributes,
            ),
          ),
        );
