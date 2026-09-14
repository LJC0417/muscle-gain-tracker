// AI 周报文本层单元测试（AI-WEEKLY-REVIEW-SPEC 验收 AI-02 / AI-09 + 长度约束）
// 覆盖：
//   - 合规输出原样通过（含具体数字）
//   - 黑名单句整句丢弃；全篇命中 → 返回空串（走本地降级）
//   - Markdown / emoji 剥离
//   - 超长截断到 200 字以内、过短判定不可用
//   - system prompt 不含内联 (?m) 之类的非法正则（历史上踩过：Dart RegExp 不支持 (?m)）
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_gain_tracker/application/ai/ai_review_text.dart';

void main() {
  group('sanitizeAiText', () {
    test('合规输出原样通过且保留数字', () {
      const raw = '你这周体重周均62.2kg，比上周涨了0.30kg，节奏刚好踩在目标线上，'
          '训练容量也从14600kg提到15800kg。最该改的是蛋白，日均104g离110g差6g，'
          '下周把蛋白拉到115g，卧推22.5kg争取做到12次。';
      final got = sanitizeAiText(raw);
      expect(got.isNotEmpty, isTrue);
      expect(aiBlacklistScan.hasMatch(got), isFalse);
      expect(aiMarkdownScan.hasMatch(got), isFalse);
      expect(got.contains('110g'), isTrue);
    });

    test('含黑名单的句子被整句丢弃，其余保留', () {
      // 注意：剔除黑名单句后剩余文本必须 >= aiMinChars(30)，否则会被
      // 最短长度门槛清空。样本共 44 字（去 1 句黑名单后 44 字）。
      const raw = '这周体重涨了0.3kg，节奏正常，训练也全勤。希望对您有帮助。'
          '下周把蛋白补到110g，卧推加2.5kg。';
      final got = sanitizeAiText(raw);
      expect(got.contains('希望'), isFalse);
      expect(got.contains('110g'), isTrue);
      expect(aiBlacklistScan.hasMatch(got), isFalse);
    });

    test('剔除后不足 aiMinChars 的文本 → 返回空串（触发本地降级）', () {
      // 真实案例：两句话的输出剔除黑名单句后仅 29 字，低于门槛必须降级
      final got = sanitizeAiText('这周体重涨了0.3kg，节奏正常。希望对您有帮助。下周把蛋白补到110g。');
      expect(got, '');
    });

    test('全篇命中黑名单/过短 → 返回空串（触发本地降级）', () {
      expect(sanitizeAiText('希望对您有帮助，加油，坚持下去。'), '');
      expect(sanitizeAiText('继续保持。'), '');
    });

    test('Markdown 标记与 emoji 被剥离', () {
      const raw = '**本周总结**\n- 体重 +0.3kg 💪\n- 蛋白差 6g 🔥\n下周把蛋白补到 110g。';
      final got = sanitizeAiText(raw);
      expect(aiMarkdownScan.hasMatch(got), isFalse);
      expect(got.contains('💪'), isFalse);
      expect(got.contains('🔥'), isFalse);
      expect(got.isNotEmpty, isTrue);
    });

    test('超长文本截断到 aiMaxChars 以内并以句号收尾', () {
      final raw = '体重这周上涨了零点三公斤，整体节奏还算正常。' * 12;
      final got = sanitizeAiText(raw);
      expect(got.runes.length <= aiMaxChars, isTrue);
      expect(got.endsWith('。'), isTrue);
    });

    test('敬语「您」统一替换为「你」', () {
      final got = sanitizeAiText('您的蛋白日均差 6g，建议您下周把早餐那勺蛋白粉挪到训练后。');
      expect(got.contains('您'), isFalse);
      expect(got.contains('你'), isTrue);
    });
  });

  group('system prompt', () {
    test('包含核心约束且不含内联正则标志', () {
      expect(kAiSystemPrompt.contains('90–150 字'), isTrue);
      expect(kAiSystemPrompt.contains('Markdown'), isTrue);
      expect(kAiSystemPrompt.contains('作为 AI'), isTrue); // 作为禁用项列出
      expect(kAiSystemPrompt.contains('(?m)'), isFalse);
    });
  });

  group('黑名单扫描口径', () {
    test('合并扫描能命中各类禁词', () {
      for (final bad in [
        '作为 AI 我来分析',
        '我是人工智能',
        '希望对您有帮助',
        '加油',
        '综上所述',
        '以上仅供参考',
      ]) {
        expect(aiBlacklistScan.hasMatch(bad), isTrue, reason: bad);
      }
    });
  });
}
