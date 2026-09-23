final class Config {
  const Config({
    required this.baseUrl,
    required this.wsUrl,
    required this.env,
    required this.pusherKey,
    required this.pusherCluster,
  });

  final String baseUrl;
  final String wsUrl;
  final String env;

  /// Pusher Channels credentials for the realtime chat client
  /// (`RealtimeClient`). The key is public by design; the secret never
  /// leaves the backend.
  final String pusherKey;
  final String pusherCluster;
}
