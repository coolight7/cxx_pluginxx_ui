#pragma once

/// 纯文本降级：规范模型 → 行式文本
///
/// 用途：日志、CLI、终端的最小实现、以及适配时"不支持就退成文本"。**不是渲染**：
/// 只按显示列宽拼行，不管颜色与主题。
///
/// C++ 与 Dart 两份实现的输出**逐字节一致**（测试用 fixtures/schema_samples.json
/// 对比），所以这里只允许两端都能一致表达的写法：数值按 [detail::formatNumber]
/// 的形态输出、分隔用固定字符、不做语言相关的文案。
///
/// 各组件的大致形态：
/// | 组件 | 纯文本 |
/// |---|---|
/// | `Text` | 正文（按宽度硬折行） |
/// | `Divider` | 一行 `-` |
/// | `Gap` | 一个空行 |
/// | `Button` | `[标签]` |
/// | `Block` | 标题行 + 子块（缩进两格） |
/// | `Row` | 子块用 ` \| ` 连接 |
/// | `Column` | 子块逐行 |
/// | `KV` | `键 + 分隔符 + 值`（键列按最长键对齐） |
/// | `Table` | 列对齐文本（表头下加一行 `-`） |
/// | `Tree` | 缩进或连接线 |
/// | `Progress` | `[#####-----] 72%` |
/// | `Badge` | `[文本]` |
/// | `Control` | `标签: 当前值` |
/// | `Sparkline` | 迷你趋势图 + 末值 |
/// | `Icon` | `glyph`，没有则 `name`，都没有则空 |
/// | `Image` | `alt`（没有则空） |
/// | `Stack` | 最后一个子块 |
/// | `Markdown` / `Diagram` | 源码 |
/// | `Diff` | `@@ 路径` + `- 旧行` + `+ 新行` |
/// | `musicxx.Shader` | `fallback`（没有则空） |
#include "pluginxx/ui/display_width.h"
#include "pluginxx/ui/item.h"

#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace pluginxx {
namespace ui {

/// 语言表查询（键 → 文本；返回空串表示缺键）
using TextLookup = std::function<std::string(std::string_view)>;

/// 组件树 → 纯文本
/// - `width` > 0 时按显示列宽折行（<= 0 不折行）
/// - `lookup` 用来解析 TextValue 的 `key`（为空时用 `fallback`，再取不到用 key 原文）
PLUGINXX_UI_API std::string plainText(
    const std::vector<Item>& items,
    int                      width  = 0,
    const TextLookup&        lookup = {}
);

/// 单个组件 → 纯文本（多行时带换行）
PLUGINXX_UI_API std::string plainTextItem(
    const Item&       item,
    int               width  = 0,
    const TextLookup& lookup = {}
);

/// 整份内容 → 纯文本（标题 / 副标题在前，块依次跟上）
PLUGINXX_UI_API std::string plainTextDocument(
    const Document&   doc,
    int               width  = 0,
    const TextLookup& lookup = {}
);


} // namespace ui
} // namespace pluginxx
