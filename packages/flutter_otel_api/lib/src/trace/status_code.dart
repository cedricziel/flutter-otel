/// The outcome of the operation a span represents, matching OTel's
/// `Status.StatusCode`.
enum StatusCode {
  /// The default status; the operation's outcome wasn't set.
  unset,

  /// The operation completed successfully.
  ok,

  /// The operation failed.
  error,
}
