// 占位封面的「稳定 hash → 调色板索引」共享工具。
//
// 用于无封面时的确定性取色（ArtistPlaceholder / AudiobookCover）：同一名称
// 在任何位置、任何运行环境都取到同一渐变，视觉有归属感。

/// FNV-1a 32bit：跨 Dart 版本/平台稳定（`String.hashCode` 不保证稳定），
/// 保证同一名称在任何运行环境都取到同一颜色。
///
/// ⚠️ 乘法必须**溢出安全**：dart2js 下 `hash * 0x01000193` 中间积可达 2^56
/// 超过 JS 安全整数 2^53，低 32 位与原生 VM 不一致 → 拆段：
/// prime = 2^24 + 2^8 + 2^7 + 2^4 + 2^1 + 1，`hash*2^24 mod 2^32`
/// 等价 `(hash & 0xFF) << 24`，各中间项均 < 2^41，全程精确。
int stableCoverHash(String seed) {
  var hash = 0x811c9dc5;
  for (final unit in seed.codeUnits) {
    hash ^= unit;
    hash = (hash +
            (hash << 1) +
            (hash << 4) +
            (hash << 7) +
            (hash << 8) +
            ((hash & 0xFF) << 24)) &
        0xFFFFFFFF;
  }
  return hash;
}

/// 从 [paletteLength] 个调色板中确定性取索引。
/// 空名称固定返回 0，避免全空名称都撞到同一色之外的行为差异。
int coverPaletteIndex(String seed, int paletteLength) {
  if (paletteLength <= 0 || seed.isEmpty) return 0;
  return stableCoverHash(seed) % paletteLength;
}
