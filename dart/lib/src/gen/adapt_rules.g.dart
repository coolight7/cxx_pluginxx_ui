// 本文件由 tools/gen_ui.dart 生成，请勿手工修改。
// 定义来源：schema/ui.def.json / schema/kit.def.json
// 适配规则表：客户端不支持某个块时怎么降级（规则实现在 adapt.dart）。
import '../model.dart';

/// 适配规则表（组件名 → 规则）
const Map<String, AdaptRule> kAdaptRules = <String, AdaptRule>{
  'Text': AdaptRule.terminal,
  'Divider': AdaptRule.plainTextMono,
  'Gap': AdaptRule.plainTextMono,
  'Button': AdaptRule.plainTextMono,
  'Block': AdaptRule.flatten,
  'Row': AdaptRule.flatten,
  'Column': AdaptRule.flatten,
  'Expanded': AdaptRule.flatten,
  'Spacer': AdaptRule.skip,
  'SizedBox': AdaptRule.flatten,
  'Padding': AdaptRule.flatten,
  'Align': AdaptRule.flatten,
  'Collapse': AdaptRule.flatten,
  'KV': AdaptRule.plainTextMono,
  'Table': AdaptRule.plainTextMono,
  'Tree': AdaptRule.plainTextMono,
  'Progress': AdaptRule.plainTextMono,
  'Badge': AdaptRule.plainTextMono,
  'Control': AdaptRule.plainTextMono,
  'Markdown': AdaptRule.plainTextMono,
  'Icon': AdaptRule.glyphText,
  'Stack': AdaptRule.lastChild,
  'Image': AdaptRule.altText,
  'Diff': AdaptRule.plainTextMono,
  'Sparkline': AdaptRule.plainTextMono,
  'Diagram': AdaptRule.plainTextMono,
  'musicxx.Shader': AdaptRule.skip,
  'musicxx.AnimatedBuilder': AdaptRule.flatten,
  'musicxx.SizeTransition': AdaptRule.flatten,
  'musicxx.FadeTransition': AdaptRule.flatten,
  'musicxx.SlideTransition': AdaptRule.flatten,
  'musicxx.ScaleTransition': AdaptRule.flatten,
  'musicxx.RotationTransition': AdaptRule.flatten,
};
