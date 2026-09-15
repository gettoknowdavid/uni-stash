final class Config {
  const Config({
    required this.baseUrl,
    required this.wsUrl,
    required this.env,
  });

  final String baseUrl;
  final String wsUrl;
  final String env;
}
