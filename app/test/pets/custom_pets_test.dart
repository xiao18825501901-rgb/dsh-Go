import 'dart:io';

import 'package:dsh_app/pets/custom_pets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PetDirectoryBundle', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('pet-bundle-');
      final pack = Directory('${root.path}/pets/demo');
      await pack.create(recursive: true);
      await File('${pack.path}/pack.json').writeAsString('{"id": "demo"}');
    });

    tearDown(() => root.delete(recursive: true));

    test('reads a file under assets/pets/<id>/ from disk', () async {
      final bundle = PetDirectoryBundle('demo', root: root);
      expect(await bundle.loadString('assets/pets/demo/pack.json'), '{"id": "demo"}');
    });

    test('misses without throwing the wrong way', () async {
      final bundle = PetDirectoryBundle('demo', root: root);
      expect(bundle.loadString('assets/pets/other/pack.json'), throwsFlutterError);
      expect(bundle.loadString('assets/pets/demo/missing.png'), throwsFlutterError);
    });

    test('refuses to climb out of the pack folder', () async {
      final bundle = PetDirectoryBundle('demo', root: root);
      expect(bundle.loadString('assets/pets/demo/../../secret'), throwsFlutterError);
      expect(bundle.loadString('assets/pets/demo//etc/passwd'), throwsFlutterError);
    });
  });

  group('CustomPetPack.parse', () {
    test('keeps a usable record', () {
      final pack = CustomPetPack.parse({'id': 'sakura', 'name': 'Sakura'});
      expect(pack?.id, 'sakura');
      expect(pack?.name, 'Sakura');
    });

    test('falls back to the id for a missing name', () {
      expect(CustomPetPack.parse({'id': 'sakura'})?.name, 'sakura');
    });

    test('rejects records without an id', () {
      expect(CustomPetPack.parse({'name': 'nameless'}), isNull);
      expect(CustomPetPack.parse('nope'), isNull);
    });
  });
}
