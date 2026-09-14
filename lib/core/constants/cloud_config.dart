/// WorkBuddy 云服务接入配置（AI 周报用）
///
/// 三个值全部来自开通云服务时返回的 `publicConfig`：
///   - endpoint：当前应用的发布域数据面基址（**必须**使用它，禁止写死其它域名，
///     也禁止从 location / 环境变量 / BFF 取；换域名会让 Origin 校验失败）
///   - publishableKey：标识「哪个应用」，本身不带权限，服务端用 Origin 精确匹配做校验
///     （可随源码分发，但不要打进日志）
///
/// ⚠️ 数据面路径由 SDK 约定，统一在 `/.cloud/**` 下，与 APP 自身路由不会冲突。
library;

class CloudConfig {
  CloudConfig._();

  /// 应用发布域数据面基址。
  static const String endpoint = 'https://muscle-gain-tracker.app.workbuddy.host';

  /// 应用级公开标识（wbpk_ 前缀，非密钥）。
  static const String publishableKey =
      'wbpk_jn8tR3OI2NLfcbWyCulsVe_tLU8XeAnU60JRFRFWqpjcWqKFu41dVCX';

  /// 数据面鉴权头（SDK 约定：webapp 访问键，匿名调用也带）。
  static const String accessKeyHeader = 'x-wb-webapp-access-key';

  /// LLM 模块基址。
  static const String llmBase = '$endpoint/.cloud/llm';

  static const String modelsPath = '$llmBase/models';
  static const String chatPath = '$llmBase/chat/completions';

  /// 周报请求超时（秒级；超时后走本地模板降级）。
  static const Duration requestTimeout = Duration(seconds: 45);

  /// 同一条周报的缓存有效期（spec 要求 24h 内不重复生成）。
  static const Duration cacheTtl = Duration(hours: 24);

  /// 每日 AI 调用上限（含自动生成与手动重新生成），防止额度被一次性刷完。
  static const int dailyCallLimit = 5;
}
