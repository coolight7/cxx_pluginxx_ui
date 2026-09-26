#pragma once

/// `cxx_pluginxx_ui`：插件界面描述层（与渲染器无关）
///
/// 一次包含全部公开头文件：
/// - `item.h`         规范模型（组件项、尺寸、文本、动作）
/// - `capabilities.h` 客户端能力与上限
/// - `parse.h`        JSON → 模型（校验 + 上限 + 提示）
/// - `adapt.h`        模型 + 能力 → 客户端可渲染的模型（降级规则）
/// - `plain_text.h`   模型 → 纯文本（日志 / CLI / 降级）
/// - `build.h`        构建器（header-only）
/// - `kit_runtime.h`  kit 模板展开；具体 kit 组件见生成的 gen/kit.g.h
/// - `lint.h`         开发期检查
///
/// 本库**不含渲染**：没有 FTXUI、没有 Flutter；`plainText` 是纯文本降级，不是渲染。
#include "pluginxx/ui/adapt.h"
#include "pluginxx/ui/build.h"
#include "pluginxx/ui/capabilities.h"
#include "pluginxx/ui/display_width.h"
#include "pluginxx/ui/gen/adapt_rules.g.h"
#include "pluginxx/ui/gen/blocks.g.h"
#include "pluginxx/ui/gen/kit.g.h"
#include "pluginxx/ui/item.h"
#include "pluginxx/ui/kit_runtime.h"
#include "pluginxx/ui/lint.h"
#include "pluginxx/ui/parse.h"
#include "pluginxx/ui/plain_text.h"

/// 版本号
#define PLUGINXX_UI_VERSION_MAJOR 0
#define PLUGINXX_UI_VERSION_MINOR 1
#define PLUGINXX_UI_VERSION_PATCH 0
