class AiChatMessage {
  final String role;
  final String content;

  const AiChatMessage({required this.role, required this.content});

  Map<String, String> toJson() => {'role': role, 'content': content};
}
