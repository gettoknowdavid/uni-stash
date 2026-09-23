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
  final String pusherKey;
  final String pusherCluster;
}
