// Picks the pet (Deepy 小鲸鱼, 鲸娘, 不显示) with live previews, for 宠物设置 and the pet's
// long-press menu. Same grid as the other pickers on the 主题 page (PickerGrid:
// 16 in, 12 apart, label 8 under).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../pets/custom_pets.dart';
import '../../pets/pet_pack.dart';
import '../../pets/pet_prefs.dart';
import '../../pets/pet_signals.dart';
import '../../pets/pet_state.dart';
import '../common/pressable.dart';
import '../theme/theme.dart';
import 'pet_sprite.dart';

/// Names for the picker before a pack has loaded (and for 不显示).
Map<String, String> get petNames => {
  'deepy-whale': appL10n.botsPetDeepy,
  'whale-girl': appL10n.botsPetWhaleGirl,
  noPetId: appL10n.botsPetNone,
};

/// Three previews in a row, the chosen one ringed in the accent:
///
/// ```
/// ╭────────╮  ╭────────╮  ╭────────╮
/// │  🐋    │  │  👧    │  │        │   the pet standing on a little capsule
/// │ ▔▔▔▔▔▔ │  │ ▔▔▔▔▔▔ │  │ ▔▔▔▔▔▔ │
/// ╰────────╯  ╰────────╯  ╰────────╯
///  Deepy 小鲸鱼   鲸娘       不显示
/// ```
class PetPicker extends ConsumerWidget {
  const PetPicker({super.key, this.padding = const EdgeInsets.all(16), this.onPicked});

  final EdgeInsetsGeometry padding;

  /// After a choice (the menu's sheet closes).
  final ValueChanged<String>? onPicked;

  static const gap = 12.0;
  static const ring = 2.0;

  /// The capsule the preview pet stands on: its top at this share of the side.
  static const perchAt = 0.74;

  /// The preview pet's body height, as a share of the side.
  static const bodyShare = 0.34;

  static const choices = [...builtInPets, noPetId];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(petPrefsProvider.select((p) => p.packId));
    final custom = ref.watch(customPetPacksProvider).value ?? const <CustomPetPack>[];
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, id) in choices.indexed) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(
                  child: _Option(
                    id: id,
                    selected: id == selected,
                    onTap: () {
                      ref.read(petPrefsProvider.notifier).setPack(id);
                      onPicked?.call(id);
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final side = (constraints.maxWidth - gap * 2) / 3;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final pack in custom)
                    SizedBox(
                      width: side,
                      child: _Option(
                        id: pack.id,
                        selected: pack.id == selected,
                        onTap: () {
                          ref.read(petPrefsProvider.notifier).setPack(pack.id);
                          onPicked?.call(pack.id);
                        },
                        onRemove: () => _remove(context, ref, pack),
                      ),
                    ),
                  SizedBox(width: side, child: const _ImportTile()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Long-press on an imported pack: confirm, delete it, fall back to the default
  /// pet when it was the chosen one.
  Future<void> _remove(BuildContext context, WidgetRef ref, CustomPetPack pack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appL10n.catalogCordisRemoveTitle(pack.name)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(appL10n.commonCancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(appL10n.catalogCordisRemove)),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await CustomPetPacks.delete(pack.id);
    if (!context.mounted) return;
    if (ok && ref.read(petPrefsProvider).packId == pack.id) {
      ref.read(petPrefsProvider.notifier).setPack(defaultPetId);
    }
    ref.invalidate(customPetPacksProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? appL10n.catalogCordisRemoved : appL10n.catalogCordisRemoveFailed)),
    );
  }
}

/// 「导入」: the system picker, then the pack is installed and chosen.
class _ImportTile extends ConsumerStatefulWidget {
  const _ImportTile();

  @override
  ConsumerState<_ImportTile> createState() => _ImportTileState();
}

class _ImportTileState extends ConsumerState<_ImportTile> {
  String? _problem;
  bool _busy = false;

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final result = await CustomPetPacks.pick();
    if (!mounted) return;
    setState(() => _busy = false);
    final pack = result.pack;
    if (pack == null) {
      final problem = result.problem;
      if (problem != null && problem != 'cancelled') setState(() => _problem = problem);
      return;
    }
    ref.read(petPrefsProvider.notifier).setPack(pack.id);
    ref.invalidate(customPetPacksProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Pressable(
      onTap: _pick,
      semanticLabel: appL10n.pluginsImport,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                shape: const RoundedSuperellipseBorder(borderRadius: AppShape.radiusMd),
              ),
              child: Center(
                child: Icon(_busy ? Icons.hourglass_top : Icons.add, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _problem ?? appL10n.pluginsImport,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Option extends ConsumerWidget {
  const _Option({required this.id, required this.selected, required this.onTap, this.onRemove});

  final String id;
  final bool selected;
  final VoidCallback onTap;

  /// Imported packs only: long-press to remove.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final duration = AppMotion.of(context, AppMotion.quick);
    final pack = id == noPetId ? null : ref.watch(petPackProvider(id)).value;
    final name = AppLocale.isEnglish ? petNames[id] ?? pack?.name ?? id : pack?.name ?? petNames[id] ?? id;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Pressable(
        onTap: onTap,
        onLongPress: onRemove,
        semanticLabel: name,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: AnimatedContainer(
                key: ValueKey('pet-option-$id'),
                duration: duration,
                curve: AppMotion.std,
                decoration: ShapeDecoration(
                  color: dark ? Colors.white.withValues(alpha: 0.05) : scheme.onSurface.withValues(alpha: 0.04),
                  shape: const RoundedSuperellipseBorder(borderRadius: AppShape.radiusMd),
                ),
                foregroundDecoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: AppShape.radiusMd,
                    side: BorderSide(
                      color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: dark ? 0.5 : 0.7),
                      width: selected ? PetPicker.ring : 1,
                      strokeAlign: BorderSide.strokeAlignInside,
                    ),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => PetPreview(
                    pack: pack,
                    side: constraints.maxWidth,
                    bundle: pack == null ? null : ref.watch(petBundleForProvider)(pack.id),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedDefaultTextStyle(
              duration: duration,
              style: theme.textTheme.labelMedium!.copyWith(
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pet idling on a little capsule, in a [side]-square; just the capsule
/// for none.
class PetPreview extends StatelessWidget {
  const PetPreview({super.key, required this.pack, required this.side, this.bundle});

  final PetPack? pack;
  final double side;

  /// Sheets come from here when the pack was imported (`filesDir/pets/<id>/`).
  final AssetBundle? bundle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final pack = this.pack;
    final perchTop = side * PetPicker.perchAt;
    final perchWidth = side * 0.62;
    final perch = Positioned(
      left: (side - perchWidth) / 2,
      top: perchTop,
      width: perchWidth,
      height: math.max(6, side * 0.07),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: scheme.onSurface.withValues(alpha: 0.10), shape: const StadiumBorder()),
      ),
    );
    if (pack == null) return Stack(children: [perch]);
    // As big as on the chat page at 标准 (whole device pixels per art pixel),
    // a step smaller if the body would not fit over the capsule.
    var k = petDevicePixels(pack, PetSize.medium, dpr);
    final room = perchTop - 4;
    while (k > 1 && (pack.baseline - pack.contentBox.top) * k / dpr > room) {
      k--;
    }
    final s = pack.pixelArt ? k / dpr : side * PetPicker.bodyShare / pack.contentBox.height;
    final left = side / 2 - ((pack.contentBox.left + pack.contentBox.right) / 2) * s;
    final top = perchTop - pack.baseline * s;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        perch,
        Positioned(
          left: (left * dpr).roundToDouble() / dpr,
          top: (top * dpr).roundToDouble() / dpr,
          child: PetSprite(pack: pack, anim: pack.animFor(PetStateName.idle), scale: s, bundle: bundle),
        ),
      ],
    );
  }
}
