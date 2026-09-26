// 本文件由 tools/gen_ui.dart 生成，请勿手工修改。
// 定义来源：schema/ui.def.json / schema/kit.def.json
#pragma once

// 组件表（kind / 级别 / 归属客户端 / 适配规则）、枚举取值、默认值与解析上限。

#include <pluginxx/ui/item.h>

#include <cstddef>
#include <string_view>

namespace pluginxx {
namespace ui {
namespace gen {

/// 定义文件结构版本（字段/组件结构变化时递增）
inline constexpr int kSchemaVersion = 1;
/// 组件词汇版本（新增 kind / 字段 / 枚举值时递增，只增不改）
inline constexpr int kUiApiVersion = 1;

/// 默认留白（u）：Gap.size 的缺省值与基础 kit 的默认行距
inline constexpr double kDefaultGap = 12;
/// 终端"每个字符格相当于多少 u"的默认值（横向）
inline constexpr double kDefaultCellWidth = 8;
/// 终端"每个字符格相当于多少 u"的默认值（纵向）
inline constexpr double kDefaultCellHeight = 20;

/// 默认解析上限
inline constexpr int kMaxDepth = 8;
inline constexpr std::size_t kMaxItems = 512;
inline constexpr std::size_t kMaxTextBytes = 65536;
inline constexpr std::size_t kMaxDocumentBytes = 1048576;
inline constexpr std::size_t kMaxTableRows = 512;
inline constexpr int kMaxTableColumns = 16;
inline constexpr std::size_t kMaxTreeNodes = 1024;
inline constexpr std::size_t kMaxDataPoints = 4096;

/// 组件表（顺序与定义文件一致）
inline constexpr BlockMeta kBlockTable[] = {
    {"Text", BlockLevel::Core,
     "", AdaptRule::Terminal,
     "一段文字"},
    {"Divider", BlockLevel::Core,
     "", AdaptRule::PlainTextMono,
     "分隔线（样式由客户端主题决定）"},
    {"Gap", BlockLevel::Core,
     "", AdaptRule::PlainTextMono,
     "竖直留白（缺省取 defaults.gap）"},
    {"Button", BlockLevel::Core,
     "", AdaptRule::PlainTextMono,
     "按钮（自己处理点击）"},
    {"Block", BlockLevel::Core,
     "", AdaptRule::Flatten,
     "卡片/内容块"},
    {"Row", BlockLevel::Core,
     "", AdaptRule::Flatten,
     "横向排列"},
    {"Column", BlockLevel::Core,
     "", AdaptRule::Flatten,
     "纵向排列"},
    {"Expanded", BlockLevel::Core,
     "", AdaptRule::Flatten,
     "按比例分剩余空间"},
    {"Spacer", BlockLevel::Core,
     "", AdaptRule::Skip,
     "纯占位（撑开）"},
    {"SizedBox", BlockLevel::Core,
     "", AdaptRule::Flatten,
     "固定尺寸/占位"},
    {"Padding", BlockLevel::Core,
     "", AdaptRule::Flatten,
     "内边距"},
    {"Align", BlockLevel::Core,
     "", AdaptRule::Flatten,
     "对齐（终端垂直分量尽力而为）"},
    {"Collapse", BlockLevel::Core,
     "", AdaptRule::Flatten,
     "折叠分组（展开状态由客户端按 id 维护）"},
    {"KV", BlockLevel::Core,
     "", AdaptRule::PlainTextMono,
     "键值两列"},
    {"Table", BlockLevel::Core,
     "", AdaptRule::PlainTextMono,
     "表格（未指定宽度的列按内容比例分剩余空间）"},
    {"Tree", BlockLevel::Core,
     "", AdaptRule::PlainTextMono,
     "层级列表"},
    {"Progress", BlockLevel::Core,
     "", AdaptRule::PlainTextMono,
     "进度/计量"},
    {"Badge", BlockLevel::Core,
     "", AdaptRule::PlainTextMono,
     "状态小标签"},
    {"Control", BlockLevel::Core,
     "", AdaptRule::PlainTextMono,
     "交互控件（值变化即派发）"},
    {"Markdown", BlockLevel::Core,
     "", AdaptRule::PlainTextMono,
     "markdown 源码"},
    {"Icon", BlockLevel::Optional,
     "", AdaptRule::GlyphText,
     "图标：GUI 用 name，终端用 glyph（都没有就跳过）"},
    {"Stack", BlockLevel::Optional,
     "", AdaptRule::LastChild,
     "叠放（终端适配为取最后一个子节点）"},
    {"Image", BlockLevel::Optional,
     "", AdaptRule::AltText,
     "图片：source 不做限制（惯例 cover/file/asset/url），取不到用 alt 兜底"},
    {"Diff", BlockLevel::Optional,
     "", AdaptRule::PlainTextMono,
     "差异对比（未实现时适配为等宽文本）"},
    {"Sparkline", BlockLevel::Optional,
     "", AdaptRule::PlainTextMono,
     "迷你趋势图（未实现时适配为末值文本）"},
    {"Diagram", BlockLevel::Optional,
     "", AdaptRule::PlainTextMono,
     "状态图（未实现时适配为等宽文本）"},
    {"musicxx.Shader", BlockLevel::Client,
     "Musicxx", AdaptRule::Skip,
     "插件着色器（字段集照搬 shader bundle 文档；其他客户端跳过）"},
};
inline constexpr std::size_t kBlockCount = sizeof(kBlockTable) / sizeof(kBlockTable[0]);

/// 支持的控制形态（第一版）
inline constexpr std::string_view kControlKinds[] = {
    "buttons",
    "select",
    "checkbox",
    "switch",
    "text",
    "number",
};

/// 枚举取值表（解析时校验，未知取值退到默认值）
inline constexpr std::string_view kEnumTextType[] = {
    "body",
    "caption",
    "title",
};
inline constexpr std::string_view kEnumTone[] = {
    "normal",
    "hint",
    "accent",
    "title",
    "error",
    "warning",
    "success",
    "tool",
    "thinking",
    "user",
    "assistant",
    "system",
};
inline constexpr std::string_view kEnumAlignH[] = {
    "start",
    "center",
    "end",
};
inline constexpr std::string_view kEnumAlignHV[] = {
    "start",
    "center",
    "end",
    "stretch",
};
inline constexpr std::string_view kEnumMainAxis[] = {
    "start",
    "center",
    "end",
    "spaceBetween",
};
inline constexpr std::string_view kEnumBlockVariant[] = {
    "card",
    "inset",
    "plain",
};
inline constexpr std::string_view kEnumButtonVariant[] = {
    "primary",
    "secondary",
    "ghost",
    "link",
};
inline constexpr std::string_view kEnumControlKind[] = {
    "buttons",
    "select",
    "checkbox",
    "switch",
    "text",
    "number",
};
inline constexpr std::string_view kEnumActionKind[] = {
    "none",
    "dispatch",
    "route",
    "command",
};
inline constexpr std::string_view kEnumSparkStyle[] = {
    "block",
    "bar",
};
inline constexpr std::string_view kEnumImageFit[] = {
    "contain",
    "cover",
    "fill",
    "fitWidth",
    "fitHeight",
    "none",
};

} // namespace gen
} // namespace ui
} // namespace pluginxx
