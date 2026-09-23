import 'package:envied/envied.dart';

part 'env_dev.g.dart';

@Envied(obfuscate: true, path: '.env.dev')
abstract class DevEnv {
  @EnviedField(varName: 'BASE_URL')
  static final String baseUrl = _DevEnv.baseUrl;

  @EnviedField(varName: 'WS_URL')
  static final String wsUrl = _DevEnv.wsUrl;

  @EnviedField(varName: 'PUSHER_KEY')
  static final String pusherKey = _DevEnv.pusherKey;

  @EnviedField(varName: 'PUSHER_CLUSTER')
  static final String pusherCluster = _DevEnv.pusherCluster;

  @EnviedField(varName: 'ENV')
  static final String env = _DevEnv.env;
}
