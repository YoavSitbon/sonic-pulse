class SongSearchResult {
  const SongSearchResult({
    required this.title,
    required this.artist,
    required this.album,
    this.artistId,
    this.artworkUrl,
    this.previewUrl,
  });

  final String title;
  final String artist;
  final String album;
  final int? artistId;
  final String? artworkUrl;
  final String? previewUrl;

  factory SongSearchResult.fromItunesJson(Map<String, dynamic> json) {
    return SongSearchResult(
      title: json['trackName'] as String? ?? 'Unknown title',
      artist: json['artistName'] as String? ?? 'Unknown artist',
      album: json['collectionName'] as String? ?? '',
      artistId: (json['artistId'] as num?)?.toInt(),
      artworkUrl: json['artworkUrl100'] as String?,
      previewUrl: json['previewUrl'] as String?,
    );
  }
}
