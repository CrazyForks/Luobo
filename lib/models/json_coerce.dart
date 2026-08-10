/// XML→JSON 直转的服务端（daoliyu 的 Subsonic 兼容层）会把所有数值/布尔字段
/// 输出成字符串（`"songCount": "12"`、`"public": "false"`）。此时 `as int?`
/// 会抛 TypeError，整条记录解析失败 → UI 一条数据都拿不到。
/// 这里做宽容解析：已经是目标类型就直接用，字符串则尝试转换，转不出来返回 null。
int? jsonInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? double.tryParse(value)?.toInt();
  return null;
}

double? jsonDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool? jsonBool(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return null;
}

/// 同源问题：XML→JSON 直转的服务端在列表只剩 1 个元素时输出 Map 而非 List，
/// `is List` 守卫会把单条结果静默丢成空列表。统一收敛成 List。
List<dynamic> jsonList(dynamic value) {
  if (value == null) return const [];
  if (value is List) return value;
  return [value];
}
