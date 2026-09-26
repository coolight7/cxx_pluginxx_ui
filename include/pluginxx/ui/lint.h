#pragma once

/// 开发期检查（客户端在 debug 构建里调用并记日志）
///
/// 只做"能立刻判断"的检查，不改变描述、不参与渲染：
/// - u 值不是格的整数倍（终端会取整，可能把留白吃掉或挤开布局）；
/// - 同一行/列里"固定宽度 + flex"混用（固定宽会把 flex 挤成 0）；
/// - `percent` 出现在高度无界的父容器中（会退化成内容尺寸）；
/// - `Table` 列宽合计明显超出可用宽度；
/// - 文本块同时给了 `wrap: false` 与 `maxLines`（两者互相抵消）。
#include "pluginxx/ui/capabilities.h"
#include "pluginxx/ui/item.h"

#include <string>
#include <vector>

namespace pluginxx {
namespace ui {

/// 一条检查结果
struct LintNote {
    /// 组件名（按路径上的第一个块给出）
    std::string kind;
    /// 位置（如 `blocks[2].children[0]`）
    std::string path;
    /// 说明（面向人的短句）
    std::string message;
};

/// 按客户端能力检查一组块
PLUGINXX_UI_API std::vector<LintNote>
    lintWithCaps(const std::vector<Item>& items, const Capabilities& caps);

/// 检查单块（`path` 是它的位置描述）
PLUGINXX_UI_API std::vector<LintNote>
    lintItem(const Item& item, const Capabilities& caps, std::string path);

} // namespace ui
} // namespace pluginxx
