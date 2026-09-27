#pragma once

/// 组件描述 → 规范模型（解析与序列化）
///
/// 输入是插件交上来的 JSON（本文件用 cxx_utilxx_base 的 Json），输出是 item.h 的
/// 规范模型。解析**不使整份描述失效**：未知组件、未知字段、未知枚举值、超限内容
/// 都按"跳过 / 用默认值 / 截断"处理，并记进 [ParseReport] 供客户端写日志。
///
/// 解析规则（两端一致）：
/// - 组件名（`kind`）忽略大小写：`text`、`TEXT` 与 `Text` 是同一个块；
/// - 未知 `kind` → `known = false`，保留 `fallback`（客户端显示它，或跳过）；
/// - 未知字段忽略；未知枚举值取默认值；
/// - 尺寸负值按 0 处理并记一条警告；`percent` 为负同样按 0；
/// - 超过上限的层级/数量/文本按截断处理（`maxItems` / `maxTextBytes` / …）。
#include "pluginxx/ui/capabilities.h"
#include "pluginxx/ui/item.h"

#include <utilxx_base/json.h>

#include <functional>
#include <string>
#include <vector>

namespace pluginxx {
namespace ui {

/// 解析过程中的提示（客户端记日志；不影响解析结果）
struct ParseReport {
    /// 提示信息（未知组件、截断、负值按 0…）
    std::vector<std::string> warnings;
    /// 是否存在任何截断
    bool truncated = false;

    void warn(std::string message);
};

/// 解析一份界面内容（`{title, subtitle, blocks}` 或裸块数组）
PLUGINXX_UI_API Document parseDocument(
    const utilxx_base::Json& json,
    const Limits&             limits = {},
    ParseReport*              report = nullptr
);

/// 解析块数组（也接受 `{"blocks":[…]}` / `{"items":[…]}` 包装）
PLUGINXX_UI_API std::vector<Item> parseBlocks(
    const utilxx_base::Json& json,
    const Limits&             limits = {},
    ParseReport*              report = nullptr
);

/// 解析单个块
PLUGINXX_UI_API Item parseBlock(
    const utilxx_base::Json& json,
    const Limits&             limits = {},
    ParseReport*              report = nullptr
);

/// 解析一个动作描述（块字段与客户端扩展点里的 `action` 共用同一套语义）
///
/// 允许的写法：字符串短写（= `dispatch`）、`{"kind":"dispatch"|"route"|"command"|"none"}`
/// （kind 忽略大小写；未知 kind 取 `none`）。解析失败返回空动作（`kind == None`）。
PLUGINXX_UI_API Action parseAction(const utilxx_base::Json& json);

/// 规范模型 → JSON（字段取缺省值时不输出；用于往返测试与日志）
PLUGINXX_UI_API utilxx_base::Json dumpDocument(const Document& doc);
PLUGINXX_UI_API utilxx_base::Json dumpItem(const Item& item);
PLUGINXX_UI_API utilxx_base::Json dumpBlocks(const std::vector<Item>& items);

/// 动作 → JSON（空动作输出 null；用于往返测试与日志）
PLUGINXX_UI_API utilxx_base::Json dumpAction(const Action& action);

/// 按名字查组件元信息（忽略大小写；未找到返回 nullptr）
PLUGINXX_UI_API const BlockMeta* findBlockMeta(std::string_view kind);

/// 组件名是否在组件表里（忽略大小写）
PLUGINXX_UI_API bool isKnownBlock(std::string_view kind);

/// 组件名的规范写法（未找到返回空串）
PLUGINXX_UI_API std::string_view canonicalKind(std::string_view kind);

/// 能力段 → JSON（客户端发布通道用它）
PLUGINXX_UI_API utilxx_base::Json capabilitiesToJson(const Capabilities& caps);

/// JSON → 能力段（缺字段取默认值；未知字段忽略）
PLUGINXX_UI_API Capabilities capabilitiesFromJson(const utilxx_base::Json& json);

/// 默认能力：全部组件与控件都支持（GUI 客户端的起点）
PLUGINXX_UI_API Capabilities fullCapabilities();

/// 最小能力：只支持 Text
PLUGINXX_UI_API Capabilities minimalCapabilities();

/// JSON（块数组或包装对象）→ 解析 → 纯文本（日志/CLI 的快速入口）
PLUGINXX_UI_API std::string plainTextJson(
    const utilxx_base::Json& json,
    int                      width             = 0,
    const std::function<std::string(std::string_view)>& lookup = {}
);

} // namespace ui
} // namespace pluginxx
