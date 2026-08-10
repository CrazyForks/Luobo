import 'json_coerce.dart';

class Genre {
  final String value;
  final int songCount;
  final int albumCount;

  Genre({
    required this.value,
    required this.songCount,
    required this.albumCount,
  });

  factory Genre.fromJson(Map<String, dynamic> json) {
    return Genre(
      value: json['value']?.toString() ?? '',
      songCount: jsonInt(json['songCount']) ?? 0,
      albumCount: jsonInt(json['albumCount']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {'value': value, 'songCount': songCount, 'albumCount': albumCount};
  }

  @override
  String toString() => value;
}
