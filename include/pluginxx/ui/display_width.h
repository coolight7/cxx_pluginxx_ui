#pragma once

/// 显示列宽口径（终端渲染与文本降级共用）
///
/// - CJK 与全角符号按 2 列，其余按 1 列；
/// - 组合字符、变体选择符、零宽连接符按 0 列；
/// - 非法 UTF-8 字节按 1 列跳过（不抛异常）。
#include "pluginxx/ui/export.h"

#include <string_view>

namespace pluginxx {
namespace ui {

/// 文本占多少显示列
PLUGINXX_UI_API int displayWidth(std::string_view text);

} // namespace ui
} // namespace pluginxx
