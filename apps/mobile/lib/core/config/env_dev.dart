import 'package:envied/envied.dart';

part 'env_dev.g.dart';

@Envied(obfuscate: true, path: '.env.dev')
abstract class DevEnv {
  @EnviedField(varName: 'BASE_URL')
  static final String baseUrl = _DevEnv.baseUrl;

  @EnviedField(varName: 'WS_URL')
  static final String wsUrl = _DevEnv.wsUrl;

  @EnviedField(varName: 'ENV')
  static final String env = _DevEnv.env;
}
