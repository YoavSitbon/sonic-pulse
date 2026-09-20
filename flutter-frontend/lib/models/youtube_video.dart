class YouTubeVideo {
  final String videoId;
  final String title;
  final String channel;
  final int duration;
  final String thumbnail;
  final String url;

  const YouTubeVideo({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.duration,
    required this.thumbnail,
    required this.url,
  });

  factory YouTubeVideo.fromJson(Map<String, dynamic> json) {
    return YouTubeVideo(
      videoId: json['video_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown video',
      channel: json['channel']?.toString() ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      thumbnail: json['thumbnail']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }
}

class YouTubeSearchResults {
  final List<YouTubeVideo> videos;
  final List<YouTubeVideo> shorts;

  const YouTubeSearchResults({required this.videos, required this.shorts});
}
