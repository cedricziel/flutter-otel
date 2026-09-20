import 'package:flutter_otel_api/flutter_otel_api.dart';

/// Spans a test's code under instrumentation started, in order.
class RecordingSpan implements Span {
  RecordingSpan(
    this.name,
    this.kind,
    this.spanContext, {
    this.links = const [],
  });

  @override
  final String name;
  final SpanKind kind;
  final List<SpanLink> links;
  @override
  final SpanContext spanContext;

  final Map<String, Object?> attributes = {};
  final List<String> events = [];
  StatusCode? status;
  String? statusDescription;
  bool ended = false;

  @override
  bool get isRecording => !ended;

  @override
  void setAttribute(String key, Object? value) => attributes[key] = value;

  @override
  void setAttributes(Map<String, Object?> attributes) =>
      this.attributes.addAll(attributes);

  @override
  void addEvent(
    String name, {
    Map<String, Object?>? attributes,
    DateTime? timestamp,
  }) =>
      events.add(name);

  @override
  void setStatus(StatusCode code, {String? description}) {
    status = code;
    statusDescription = description;
  }

  @override
  void recordException(
    Object exception, {
    StackTrace? stackTrace,
    Map<String, Object?>? attributes,
  }) =>
      events.add('exception');

  @override
  void end([DateTime? endTime]) => ended = true;
}

class RecordingTracer implements Tracer {
  final List<RecordingSpan> spans = [];
  var _next = 1;

  @override
  String get name => 'test';

  @override
  Span startSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    SpanContext? parentContext,
    List<SpanLink> links = const [],
  }) {
    final span = RecordingSpan(
      name,
      kind,
      SpanContext(
        traceId: 'a' * 32,
        spanId: (_next++).toRadixString(16).padLeft(16, '0'),
      ),
      links: links,
    );
    if (attributes != null) span.setAttributes(attributes);
    spans.add(span);
    return span;
  }

  @override
  Future<T> startActiveSpan<T>(
    String name,
    Future<T> Function(Span span) body, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    List<SpanLink> links = const [],
  }) =>
      throw UnimplementedError();
}

class ThrowingTracer extends RecordingTracer {
  @override
  Span startSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    SpanContext? parentContext,
    List<SpanLink> links = const [],
  }) =>
      throw StateError('tracer broke');
}
