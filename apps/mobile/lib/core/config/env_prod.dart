import 'package:envied/envied.dart';

part 'env_prod.g.dart';

@Envied(obfuscate: true, path: '.env')
abstract class ProdEnv {
  @EnviedField(varName: 'BASE_URL')
  static final String baseUrl = _ProdEnv.baseUrl;

  @EnviedField(varName: 'WS_URL')
  static final String wsUrl = _ProdEnv.wsUrl;

  @EnviedField(varName: 'PUSHER_KEY')
  static final String pusherKey = _ProdEnv.pusherKey;

  @EnviedField(varName: 'PUSHER_CLUSTER')
  static final String pusherCluster = _ProdEnv.pusherCluster;

  @EnviedField(varName: 'ENV')
  static final String env = _ProdEnv.env;
}
