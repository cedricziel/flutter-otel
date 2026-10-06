import 'dart:io';

import 'package:flutter_otel_device_info/flutter_otel_device_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('installation_id');
  });

  tearDown(() => directory.delete(recursive: true));

  Future<Object?> detect(Directory directory) async =>
      (await detectAppInstallationId(
        directory: () async => directory,
      ))['app.installation.id'];

  group('on desktop', skip: Platform.isIOS || Platform.isAndroid, () {
    test('creates a random UUID and keeps it', () async {
      final first = await detect(directory);

      expect(first, isA<String>().having((id) => id.length, 'length', 36));
      expect(await detect(directory), first);
    });

    test('replaces a stored value that is not a UUID', () async {
      await detect(directory);
      File(
        '${directory.path}/opentelemetry_app_installation_id',
      ).writeAsStringSync('garbage');

      expect(await detect(directory), allOf(isNotNull, isNot('garbage')));
    });

    test('creates the directory when it is missing', () async {
      final nested = Directory('${directory.path}/a/b');

      expect(await detect(nested), isNotNull);
      expect(nested.existsSync(), isTrue);
    });
  });

  test('is empty when the ID cannot be stored', () async {
    final attributes = await detectAppInstallationId(
      directory: () async => throw const FileSystemException('read-only'),
    );

    expect(attributes, isEmpty);
  });
}
