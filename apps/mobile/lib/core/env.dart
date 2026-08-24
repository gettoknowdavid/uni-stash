import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(obfuscate: true)
abstract class Env {
  @EnviedField(varName: 'BASE_URL')
  static final String baseUrl = _Env.baseUrl;

  @EnviedField(varName: 'WS_URL')
  static final String wsUrl = _Env.wsUrl;

  @EnviedField(varName: 'ENV')
  static final String env = _Env.env;
}
