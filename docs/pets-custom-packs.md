# 自定义宠物包 / Custom pet packs

不用重新编译 APK，也能把一只自己做好的宠物放进「宠物设置」：导入的包放在
`filesDir/pets/<id>/`，和内置包同一套 `pack.json` + 精灵图格式。

Pet packs can be imported at runtime instead of being baked into the APK. They live in
`filesDir/pets/<id>/`, the folder the native loader already falls back to, and use the same
`pack.json` + sprite sheet format as `assets/pets/<id>/`.

## 用法 / How to use

1. 「设置 › 宠物」下方多出一行 **导入**。
2. 选中 `pack.json` 和它引用的透明 PNG（可多选），或直接选一个 `.zip`。
3. 校验通过后立即安装并选中；再次长按该角色可移除。

1. **Settings › Pet** gains an **Import** tile.
2. Pick `pack.json` plus the transparent PNGs it references (multi-select), or a single `.zip`.
3. A validated pack is installed and selected; long-press it to remove.

## 校验 / Validation

- `pack.json` 必须是 JSON 对象，`id` 匹配 `^[a-z0-9][a-z0-9-]{0,39}$`（缺省用文件夹名）。
- `pack.json` 里出现的每个 `.png` 都必须真的在包里；不允许 `..` 或绝对路径。
- 单包上限 48 MB、zip 最多 512 个条目。
- 失败时返回稳定错误码：`missing-pack-json`、`bad-pack-json`、`bad-id`、`missing-sheet:<file>`、
  `too-large`、`cancelled`。

## 实现 / Implementation

| 位置 | 作用 |
|---|---|
| `app/lib/pets/custom_pets.dart` | `dsh/pet_pack` 通道、`customPetPacksProvider`、`PetDirectoryBundle` |
| `app/android/.../pet/PetPackImportPlugin.kt` | SAF 选择、解压、校验、原子安装/删除 |
| `app/lib/ui/pets/pet_picker.dart` | 导入方块、长按移除、自定义包预览 |
| `PetSprites.kt`（已有） | 浮窗按 `filesDir/pets/<id>/` 读图，未改动 |

`PetPack` 本身不认识文件系统：给它的 `AssetBundle` 换成 `PetDirectoryBundle` 即可，聊天页和
浮窗共用同一份 `pack.json`、同一套状态与气泡。
