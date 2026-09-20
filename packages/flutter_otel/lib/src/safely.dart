void safely(void Function() body) {
  try {
    body();
  } catch (_) {}
}
