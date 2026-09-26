#pragma once

/// 降级适配：规范模型 + 客户端能力 → 客户端能渲染的模型
///
/// `adapt()` 是纯函数（同一输入 + 同一能力 → 同一输出），规则表在
/// schema/ui.def.json 的 `adapt` 段定义、由生成器产出（gen/adapt_rules.g.h），
/// 客户端**不要**在渲染层再写一套"我不支持谁"的判断。
///
/// 保证：适配结果只包含该客户端声明支持的组件；最多降到 `Text`（terminal 规则）。
///
/// 处理器：
/// - 客户端不支持某块 → 按下表降级（展开子节点 / 纯文本 / 保留最后一个子节点…）；
/// - 降级结果仍不支持 → 继续降级（直到 Text）；
/// - `percent` 不支持 → 用内容尺寸；`aspect` 不支持 → 忽略比例；
/// - 超出上限（层级 / 数量 / 文本长度）→ 截断。
#include "pluginxx/ui/capabilities.h"
#include "pluginxx/ui/item.h"

#include <string>
#include <vector>

namespace pluginxx {
namespace ui {

/// 适配过程中的说明（客户端记日志）
struct AdaptReport {
    std::vector<std::string> notes;

    void note(std::string message);
};

/// 适配一组块（展开型降级可能让一个块变成多个）
PLUGINXX_UI_API std::vector<Item> adaptBlocks(
    const std::vector<Item>& items,
    const Capabilities&      caps,
    AdaptReport*             report = nullptr
);

/// 适配单个块（返回 0..N 个块：flatten 规则会展开子节点，skip 规则返回空）
PLUGINXX_UI_API std::vector<Item> adaptItem(
    const Item&         item,
    const Capabilities& caps,
    AdaptReport*        report = nullptr
);

/// 适配整份内容（标题/副标题保留，块逐个适配）
PLUGINXX_UI_API Document adaptDocument(
    const Document&     doc,
    const Capabilities& caps,
    AdaptReport*        report = nullptr
);

/// 某组件在当前能力下的适配规则（未声明返回 AdaptRule::Terminal）
PLUGINXX_UI_API AdaptRule adaptRuleOf(std::string_view kind);

} // namespace ui
} // namespace pluginxx
