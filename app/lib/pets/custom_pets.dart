// Custom pet packs that live outside the APK, in `filesDir/pets/<id>/`.
//
// The loader already knows that folder (`PetSprites.sourceFor`, Kotlin side), and
// `PetPack` only needs an [AssetBundle]; so a pack on disk is the same pack with a
// different bundle: `assets/pets/<id>/<file>` is read from `<filesDir>/pets/<id>/<file>`.
//
// Importing is Android's job (SAF picker, validation, atomic move); this file is the
// Dart half: the channel, the list provider, and the file-backed bundle.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Matches `pet/PetPackImportPlugin.kt`.
const _channel = MethodChannel('dsh/pet_pack');

@immutable
class CustomPetPack {
  const CustomPetPack({required this.id, required this.name});

  final String id;
  final String name;

  static CustomPetPack? parse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final name = raw['name'];
    return CustomPetPack(id: id, name: name is String && name.isNotEmpty ? name : id);
  }
}

/// The Android side of importing custom pet packs.
class CustomPetPacks {
  const CustomPetPacks._();

  /// Packs already under `filesDir/pets/`.
  static Future<List<CustomPetPack>> list() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('list');
      return [for (final item in raw ?? const <Object?>[]) if (CustomPetPack.parse(item) case final pack?) pack];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Opens the system picker, validates what was picked, installs it and returns it.
  ///
  /// [problem] is a stable code (`missing-pack-json`, `bad-id`, `missing-sheet:<file>`,
  /// `cancelled`, `too-large`, `nested`), which the UI turns into a sentence.
  static Future<({CustomPetPack? pack, String? problem})> pick() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('pick');
      if (raw == null) return (pack: null, problem: 'cancelled');
      final pack = CustomPetPack.parse(raw);
      return (pack: pack, problem: pack == null ? (raw['problem'] as String? ?? 'invalid') : null);
    } on PlatformException catch (e) {
      return (pack: null, problem: e.code);
    } on MissingPluginException {
      return (pack: null, problem: 'unsupported');
    }
  }

  static Future<bool> delete(String id) async {
    try {
      return await _channel.invokeMethod<bool>('delete', {'id': id}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Where packs are installed (shown in the settings footnote).
  static Future<String?> rootPath() async {
    try {
      return await _channel.invokeMethod<String>('root');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Every custom pack on disk; rebuilt after an import or a removal.
final customPetPacksProvider = FutureProvider<List<CustomPetPack>>((ref) => CustomPetPacks.list());

/// The bundle a pack's `pack.json` and sheets are read from: the APK for built-in
/// packs, `filesDir/pets/<id>/` for imported ones.
final petBundleForProvider = Provider<AssetBundle Function(String)>((ref) {
  final custom = ref.watch(customPetPacksProvider).value ?? const <CustomPetPack>[];
  final ids = {for (final pack in custom) pack.id};
  return (id) => ids.contains(id) ? PetDirectoryBundle(id) : rootBundle;
});

/// `assets/pets/<id>/<file>` → `<root>/pets/<id>/<file>`.
///
/// [root] is only set by tests; the app uses the support directory, which on
/// Android is the same `filesDir` the native loader reads.
class PetDirectoryBundle extends AssetBundle {
  PetDirectoryBundle(this.id, {Directory? root}) : _root = root;

  final String id;
  final Directory? _root;

  static final Map<String, Future<Directory?>> _roots = {};

  Future<Directory?> _dir() async {
    if (_root != null) return _root;
    return _roots[id] ??= getApplicationSupportDirectory().then<Directory?>((d) => d, onError: (_) => null);
  }

  String get _prefix => 'assets/pets/$id/';

  Future<File?> _file(String key) async {
    if (!key.startsWith(_prefix)) return null;
    final rel = key.substring(_prefix.length);
    if (rel.isEmpty || rel.contains('..') || rel.startsWith('/')) return null;
    final root = await _dir();
    if (root == null) return null;
    final file = File('${root.path}/pets/$id/$rel');
    return await file.exists() ? file : null;
  }

  @override
  Future<ByteData> load(String key) async {
    final file = await _file(key);
    if (file == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.sublistView(await file.readAsBytes());
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final data = await load(key);
    return utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  @override
  Future<T> loadStructuredData<T>(String key, Future<T> Function(String value) parser) async =>
      parser(await loadString(key));

  @override
  String toString() => 'PetDirectoryBundle($id';
}
