// 本文件由 tools/gen_ui.dart 生成，请勿手工修改。
// 定义来源：schema/ui.def.json / schema/kit.def.json
#pragma once

// 适配规则表：客户端不支持某个块时怎么降级（规则实现在 adapt.cpp）。

#include <pluginxx/ui/item.h>

#include <cstddef>
#include <string_view>

namespace pluginxx {
namespace ui {
namespace gen {

struct AdaptRuleEntry {
    std::string_view kind;
    AdaptRule        rule;
};

/// 适配规则表（见 schema/ui.def.json 的 adapt 段）
inline constexpr AdaptRuleEntry kAdaptRules[] = {
    {"Text", AdaptRule::Terminal},
    {"Divider", AdaptRule::PlainTextMono},
    {"Gap", AdaptRule::PlainTextMono},
    {"Button", AdaptRule::PlainTextMono},
    {"Block", AdaptRule::Flatten},
    {"Row", AdaptRule::Flatten},
    {"Column", AdaptRule::Flatten},
    {"Expanded", AdaptRule::Flatten},
    {"Spacer", AdaptRule::Skip},
    {"SizedBox", AdaptRule::Flatten},
    {"Padding", AdaptRule::Flatten},
    {"Align", AdaptRule::Flatten},
    {"Collapse", AdaptRule::Flatten},
    {"KV", AdaptRule::PlainTextMono},
    {"Table", AdaptRule::PlainTextMono},
    {"Tree", AdaptRule::PlainTextMono},
    {"Progress", AdaptRule::PlainTextMono},
    {"Badge", AdaptRule::PlainTextMono},
    {"Control", AdaptRule::PlainTextMono},
    {"Markdown", AdaptRule::PlainTextMono},
    {"Icon", AdaptRule::GlyphText},
    {"Stack", AdaptRule::LastChild},
    {"Image", AdaptRule::AltText},
    {"Diff", AdaptRule::PlainTextMono},
    {"Sparkline", AdaptRule::PlainTextMono},
    {"Diagram", AdaptRule::PlainTextMono},
    {"musicxx.Shader", AdaptRule::Skip},
    {"musicxx.AnimatedBuilder", AdaptRule::Flatten},
    {"musicxx.SizeTransition", AdaptRule::Flatten},
    {"musicxx.FadeTransition", AdaptRule::Flatten},
};
inline constexpr std::size_t kAdaptRuleCount =
    sizeof(kAdaptRules) / sizeof(kAdaptRules[0]);

} // namespace gen
} // namespace ui
} // namespace pluginxx
