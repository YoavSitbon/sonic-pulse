class SongSearchResult {
  const SongSearchResult({
    required this.title,
    required this.artist,
    required this.album,
    this.artworkUrl,
  });

  final String title;
  final String artist;
  final String album;
  final String? artworkUrl;

  factory SongSearchResult.fromItunesJson(Map<String, dynamic> json) {
    return SongSearchResult(
      title: json['trackName'] as String? ?? 'Unknown title',
      artist: json['artistName'] as String? ?? 'Unknown artist',
      album: json['collectionName'] as String? ?? '',
      artworkUrl: json['artworkUrl100'] as String?,
    );
  }
}
