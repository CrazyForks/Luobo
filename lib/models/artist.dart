import 'album.dart';

class Artist {
  final String id;
  final String name;
  final String? coverArt;
  final int? albumCount;
  final String? artistImageUrl;
  final bool isLocal;

  /// Albums inline in the `getArtist` response (Subsonic spec). Empty for
  /// artists from `getArtists` / cached index data.
  final List<Album> albums;

  Artist({
    required this.id,
    required this.name,
    this.coverArt,
    this.albumCount,
    this.artistImageUrl,
    this.isLocal = false,
    this.albums = const [],
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'Unknown Artist',
      coverArt: json['coverArt']?.toString(),
      albumCount: json['albumCount'] as int?,
      artistImageUrl: json['artistImageUrl']?.toString(),
      albums: [
        if (json['album'] is List)
          for (final a in json['album'] as List)
            if (a is Map) Album.fromJson(Map<String, dynamic>.from(a)),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'coverArt': coverArt,
      'albumCount': albumCount,
      'artistImageUrl': artistImageUrl,
      if (albums.isNotEmpty)
        'albums': albums.map((a) => a.toJson()).toList(),
    };
  }
}
