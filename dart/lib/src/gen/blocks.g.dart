// 本文件由 tools/gen_ui.dart 生成，请勿手工修改。
// 定义来源：schema/ui.def.json / schema/kit.def.json
// 组件表、枚举取值、默认值与解析上限（Dart 绑定）。

import '../model.dart';

/// 定义文件结构版本
const int kSchemaVersion = 1;
/// 组件词汇版本（新增 kind / 字段 / 枚举值时递增，只增不改）
const int kUiApiVersion = 1;

/// 默认留白（u）：Gap.size 的缺省值与基础 kit 的默认行距
const double kDefaultGap = 12;
/// 终端"每个字符格相当于多少 u"的默认值（横向）
const double kDefaultCellWidth = 8;
/// 终端"每个字符格相当于多少 u"的默认值（纵向）
const double kDefaultCellHeight = 20;

/// 组件表（组件名 / 级别 / 归属客户端 / 适配规则）
const List<BlockMeta> kBlockTable = <BlockMeta>[
  BlockMeta('Text', BlockLevel.core, '', AdaptRule.terminal),
  BlockMeta('Divider', BlockLevel.core, '', AdaptRule.plainTextMono),
  BlockMeta('Gap', BlockLevel.core, '', AdaptRule.plainTextMono),
  BlockMeta('Button', BlockLevel.core, '', AdaptRule.plainTextMono),
  BlockMeta('Block', BlockLevel.core, '', AdaptRule.flatten),
  BlockMeta('Row', BlockLevel.core, '', AdaptRule.flatten),
  BlockMeta('Column', BlockLevel.core, '', AdaptRule.flatten),
  BlockMeta('Expanded', BlockLevel.core, '', AdaptRule.flatten),
  BlockMeta('Spacer', BlockLevel.core, '', AdaptRule.skip),
  BlockMeta('SizedBox', BlockLevel.core, '', AdaptRule.flatten),
  BlockMeta('Padding', BlockLevel.core, '', AdaptRule.flatten),
  BlockMeta('Align', BlockLevel.core, '', AdaptRule.flatten),
  BlockMeta('Collapse', BlockLevel.core, '', AdaptRule.flatten),
  BlockMeta('KV', BlockLevel.core, '', AdaptRule.plainTextMono),
  BlockMeta('Table', BlockLevel.core, '', AdaptRule.plainTextMono),
  BlockMeta('Tree', BlockLevel.core, '', AdaptRule.plainTextMono),
  BlockMeta('Progress', BlockLevel.core, '', AdaptRule.plainTextMono),
  BlockMeta('Badge', BlockLevel.core, '', AdaptRule.plainTextMono),
  BlockMeta('Control', BlockLevel.core, '', AdaptRule.plainTextMono),
  BlockMeta('Markdown', BlockLevel.core, '', AdaptRule.plainTextMono),
  BlockMeta('Icon', BlockLevel.optional, '', AdaptRule.glyphText),
  BlockMeta('Stack', BlockLevel.optional, '', AdaptRule.lastChild),
  BlockMeta('Image', BlockLevel.optional, '', AdaptRule.altText),
  BlockMeta('Diff', BlockLevel.optional, '', AdaptRule.plainTextMono),
  BlockMeta('Sparkline', BlockLevel.optional, '', AdaptRule.plainTextMono),
  BlockMeta('Diagram', BlockLevel.optional, '', AdaptRule.plainTextMono),
  BlockMeta('musicxx.Shader', BlockLevel.client, 'musicxx', AdaptRule.skip),
];

/// 全部组件的名字（顺序与定义文件一致）
const List<String> kBlockNames = <String>[
  'Text',
  'Divider',
  'Gap',
  'Button',
  'Block',
  'Row',
  'Column',
  'Expanded',
  'Spacer',
  'SizedBox',
  'Padding',
  'Align',
  'Collapse',
  'KV',
  'Table',
  'Tree',
  'Progress',
  'Badge',
  'Control',
  'Markdown',
  'Icon',
  'Stack',
  'Image',
  'Diff',
  'Sparkline',
  'Diagram',
  'musicxx.Shader',
];

/// 支持的控制形态（第一版）
const List<String> kControlKinds = <String>[
  'buttons',
  'select',
  'checkbox',
  'switch',
  'text',
  'number',
];

/// 枚举 textType 的取值
const List<String> kEnumTextType = <String>[
  'body',
  'caption',
  'title',
];

/// 枚举 tone 的取值
const List<String> kEnumTone = <String>[
  'normal',
  'hint',
  'accent',
  'title',
  'error',
  'warning',
  'success',
  'tool',
  'thinking',
  'user',
  'assistant',
  'system',
];

/// 枚举 alignH 的取值
const List<String> kEnumAlignH = <String>[
  'start',
  'center',
  'end',
];

/// 枚举 alignHV 的取值
const List<String> kEnumAlignHV = <String>[
  'start',
  'center',
  'end',
  'stretch',
];

/// 枚举 mainAxis 的取值
const List<String> kEnumMainAxis = <String>[
  'start',
  'center',
  'end',
  'spaceBetween',
];

/// 枚举 blockVariant 的取值
const List<String> kEnumBlockVariant = <String>[
  'card',
  'inset',
  'plain',
];

/// 枚举 buttonVariant 的取值
const List<String> kEnumButtonVariant = <String>[
  'primary',
  'secondary',
  'ghost',
  'link',
];

/// 枚举 controlKind 的取值
const List<String> kEnumControlKind = <String>[
  'buttons',
  'select',
  'checkbox',
  'switch',
  'text',
  'number',
];

/// 枚举 actionKind 的取值
const List<String> kEnumActionKind = <String>[
  'none',
  'dispatch',
  'route',
  'command',
];

/// 枚举 sparkStyle 的取值
const List<String> kEnumSparkStyle = <String>[
  'block',
  'bar',
];

/// 枚举 imageFit 的取值
const List<String> kEnumImageFit = <String>[
  'contain',
  'cover',
  'fill',
  'fitWidth',
  'fitHeight',
  'none',
];

/// 枚举名 → 取值列表
const Map<String, List<String>> kEnums = <String, List<String>>{
  'textType': kEnumTextType,
  'tone': kEnumTone,
  'alignH': kEnumAlignH,
  'alignHV': kEnumAlignHV,
  'mainAxis': kEnumMainAxis,
  'blockVariant': kEnumBlockVariant,
  'buttonVariant': kEnumButtonVariant,
  'controlKind': kEnumControlKind,
  'actionKind': kEnumActionKind,
  'sparkStyle': kEnumSparkStyle,
  'imageFit': kEnumImageFit,
};
