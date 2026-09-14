/// AI 周报的纯文本层：教练人设 + 输出合规过滤（spec 二节黑名单 / 四节格式约束）。
///
/// 刻意保持**零 Flutter / 零 drift 依赖**：这一层是纯函数，既便于 `flutter test` 断言，
/// 也能在命令行用裸 Dart 直接跑，方便回归。
library;

/// 教练人设 + 硬性约束（system 消息，end-user 输入不得进这一条）。
const String kAiSystemPrompt =
    '你是一位有 8 年以上带训经验的运动营养师兼力量训练教练，正在给一位增肌学员写每周复盘。'
    '硬性要求：'
    '1) 用口语化但专业的教练口吻，直接对学员说「你」，不要用敬语「您」；'
    '2) 只输出一段中文纯文本，90–150 字，不要换行、不要分点、不要任何 Markdown 符号；'
    '3) 必须至少引用两个来自数据的具体数字，例如体重变化、蛋白缺口克数、训练容量、某个动作的重量；'
    '4) 最后必须给出一条下周可立刻执行的具体动作，例如热量调多少 kcal、蛋白补多少克、哪个动作加多少重量；'
    '5) 禁止出现：自报身份（如「作为 AI」）、客服腔（如「希望对您有帮助」）、空泛祝福（如「加油」）、'
    '免责声明、emoji、总结套话（如「综上所述」）。';

/// 露马脚黑名单（spec 二节）。命中的**整句**会被丢弃。
final List<RegExp> aiBlacklist = [
  RegExp(r'作为\s*AI', caseSensitive: false),
  RegExp(r'我(是|作为)人工智能'),
  RegExp(r'作为一个?(大)?语言模型'),
  RegExp(r'以下是我的分析'),
  RegExp(r'希望对您?有帮助'),
  RegExp(r'如果您?有任何(问题|疑问)'),
  RegExp(r'请随时(告诉|联系)我'),
  RegExp(r'非常理解您?的感受'),
  RegExp(r'加油'),
  RegExp(r'坚持下去'),
  RegExp(r'祝您?健身愉快'),
  RegExp(r'期待您?的进步'),
  RegExp(r'这是一个很好的开始'),
  RegExp(r'您?已经做得很好了'),
  RegExp(r'不要灰心'),
  RegExp(r'以上仅供参考'),
  RegExp(r'请咨询(专业)?(医师|医生|教练)'),
  RegExp(r'不构成(医疗|医学)建议'),
  RegExp(r'综上所述'),
  RegExp(r'总体而言'),
  RegExp(r'总的来说'),
];

/// 供测试与自检使用的合并扫描（spec AI-02 口径）。
final RegExp aiBlacklistScan = RegExp(aiBlacklist.map((r) => r.pattern).join('|'));

final RegExp _emoji = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2600}-\u{27BF}\u{FE0F}\u{2B00}-\u{2BFF}]',
  unicode: true,
);

/// Markdown 残留扫描（spec AI-09 口径）。
final RegExp aiMarkdownScan = RegExp(r'[*#>`]|^\s*-\s|^\s*\d+[.、)]\s', multiLine: true);

/// 单段文本上限（spec：超过 200 字折叠，这里直接压到 200 以内）。
const int aiMaxChars = 200;

/// 过短直接判定不可用（宁可回落本地模板，也不给用户半句话）。
const int aiMinChars = 30;

/// 返回合规文本；不合规到无法修补时返回空串（调用方走本地模板降级）。
String sanitizeAiText(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';

  // 1) 去代码围栏 / Markdown 标记
  //    注意：Dart RegExp 不支持内联 (?m) 标志，必须用 multiLine 参数
  s = s.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  s = s.replaceAll(RegExp(r'[`*_#>\[\]|]'), '');
  s = s.replaceAll(RegExp(r'^\s*[-•]\s*', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*\d+[.、)]\s*', multiLine: true), '');

  // 2) 去 emoji
  s = s.replaceAll(_emoji, '');

  // 3) 黑名单：命中的整句丢弃（保留其余句子）
  final sentences = s
      .split(RegExp(r'(?<=[。！？!?])|\n+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final kept = <String>[];
  for (final sent in sentences) {
    var bad = false;
    for (final re in aiBlacklist) {
      if (re.hasMatch(sent)) {
        bad = true;
        break;
      }
    }
    if (!bad) kept.add(sent);
  }
  s = kept.join('');

  // 4) 兜底：仍有漏网禁词则直接剔除词本身
  for (final re in aiBlacklist) {
    s = s.replaceAll(re, '');
  }

  // 5) 称呼统一 + 空白折叠
  s = s.replaceAll('您', '你');
  s = s.replaceAll(RegExp(r'[\s\u3000]+'), ' ').trim();
  s = s.replaceAll(RegExp(r'^[，,、。：:；;]+'), '');

  if (s.isEmpty) return '';

  // 6) 收尾：确保以句号结束
  if (!RegExp(r'[。！？!?]$').hasMatch(s)) s = '$s。';

  // 7) 长度上限（截到最后一个完整句）
  if (s.runes.length > aiMaxChars) {
    final cut = String.fromCharCodes(s.runes.take(aiMaxChars));
    final lastStop = cut.lastIndexOf('。');
    s = lastStop >= aiMinChars * 4 ? cut.substring(0, lastStop + 1) : '$cut。';
  }

  if (s.runes.length < aiMinChars) return '';
  return s;
}
