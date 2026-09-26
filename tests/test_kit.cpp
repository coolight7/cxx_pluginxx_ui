// kit 展开（模板 + 参数 + 变体选择）
#include "pluginxx/ui/gen/blocks.g.h"
#include "pluginxx/ui/gen/kit.g.h"

#include "pluginxx/ui/parse.h"
#include "test_framework.h"

#include <utilxx_base/json.h>

#include <cstddef>
#include <string>
#include <vector>

using pluginxx::ui::Capabilities;
using pluginxx::ui::Item;
using utilxx_base::Json;

namespace {

/// 去掉若干组件后的能力
Capabilities capsWithout(const std::vector<std::string>& remove) {
    Capabilities caps = Capabilities::full();
    std::vector<std::string> kept;
    for (const std::string& name : caps.blocks) {
        bool drop = false;
        for (const std::string& r : remove) {
            if (pluginxx::ui::detail::iequals(name, r)) {
                drop = true;
                break;
            }
        }
        if (!drop) {
            kept.push_back(name);
        }
    }
    caps.blocks = kept;
    return caps;
}

} // namespace

PLUGINXX_UI_TEST(kit_列表行按参数装配) {
    const Item row = pluginxx::ui::kit::listRow({{"title", "切歌次数"}, {"trailing", "3"}});
    PLUGINXX_UI_CHECK_EQ(row.kind, std::string("Block"), "外层是内容块");
    PLUGINXX_UI_CHECK_EQ(row.variant, std::string("inset"), "内嵌样式");
    PLUGINXX_UI_CHECK_EQ(row.children.size(), static_cast<std::size_t>(1), "一个子块");
    const Item& line = row.children[0];
    PLUGINXX_UI_CHECK_EQ(line.kind, std::string("Row"), "行");
    PLUGINXX_UI_CHECK_EQ(line.cross, std::string("center"), "垂直居中");
    PLUGINXX_UI_CHECK_EQ(line.children.size(), static_cast<std::size_t>(2), "左侧 + 右侧");
    PLUGINXX_UI_CHECK_EQ(line.children[0].kind, std::string("Expanded"), "左侧占满剩余");
    PLUGINXX_UI_CHECK_EQ(
        line.children[0].children[0].children[0].text.fallback, std::string("切歌次数"), "标题文本"
    );
    PLUGINXX_UI_CHECK_EQ(line.children[1].text.fallback, std::string("3"), "右侧文本");
}

PLUGINXX_UI_TEST(kit_缺省参数让节点退掉) {
    const Item row = pluginxx::ui::kit::listRow({{"title", "只有标题"}});
    PLUGINXX_UI_CHECK_EQ(row.children.size(), static_cast<std::size_t>(1), "一个子块");
    const Item& line = row.children[0];
    PLUGINXX_UI_CHECK_EQ(line.children.size(), static_cast<std::size_t>(1), "没有右侧文本");
    const Item& column = line.children[0].children[0];
    PLUGINXX_UI_CHECK_EQ(column.kind, std::string("Column"), "左列");
    PLUGINXX_UI_CHECK_EQ(column.children.size(), static_cast<std::size_t>(1), "没有副标题");
}

PLUGINXX_UI_TEST(kit_列表映射生成等宽按钮) {
    Json buttons = Json::array();
    buttons.push_back(Json::object({{"kind", "Button"}, {"label", "保存"}, {"action", "apply"}}));
    buttons.push_back(Json::object({{"kind", "Button"}, {"label", "取消"}, {"action", "cancel"}}));
    const Item row = pluginxx::ui::kit::actionsRow({{"buttons", buttons}});
    PLUGINXX_UI_CHECK_EQ(row.kind, std::string("Row"), "一排");
    PLUGINXX_UI_CHECK_EQ(row.children.size(), static_cast<std::size_t>(2), "两个等份");
    for (const Item& child : row.children) {
        PLUGINXX_UI_CHECK_EQ(child.kind, std::string("Expanded"), "每项占一等份");
        PLUGINXX_UI_CHECK_EQ(child.children[0].kind, std::string("Button"), "里面是按钮");
    }
    PLUGINXX_UI_CHECK_EQ(row.children[0].children[0].label.fallback, std::string("保存"), "按钮一");
    PLUGINXX_UI_CHECK_EQ(row.children[1].children[0].label.fallback, std::string("取消"), "按钮二");
}

PLUGINXX_UI_TEST(kit_按目标选择变体) {
    const Capabilities withIcon = Capabilities::full();
    const Item         icon      = pluginxx::ui::kit::icon({{"name", "play"}, {"glyph", "▶"}}, &withIcon);
    PLUGINXX_UI_CHECK_EQ(icon.kind, std::string("Icon"), "支持 Icon 时用它");

    const Capabilities     noIcon = capsWithout({"Icon"});
    const Item             text   = pluginxx::ui::kit::icon({{"name", "play"}, {"glyph", "▶"}}, &noIcon);
    PLUGINXX_UI_CHECK_EQ(text.kind, std::string("Text"), "不支持 Icon 时退成文本");
    PLUGINXX_UI_CHECK_EQ(text.text.fallback, std::string("▶"), "用 glyph");

    // 目标未知（没有 env）：给中立描述，由客户端的 adapt() 收口
    const Item neutral = pluginxx::ui::kit::icon({{"name", "play"}, {"glyph", "▶"}});
    PLUGINXX_UI_CHECK_EQ(neutral.kind, std::string("Icon"), "中立描述用第一个变体");
}

PLUGINXX_UI_TEST(kit_默认留白交给客户端) {
    const Item gap = pluginxx::ui::kit::gap();
    PLUGINXX_UI_CHECK_EQ(gap.kind, std::string("Gap"), "留白块");
    PLUGINXX_UI_CHECK(gap.size.isAuto(), "缺省不写死尺寸（客户端用 caps.gap）");

    const Item sized = pluginxx::ui::kit::gap({{"size", 24}});
    PLUGINXX_UI_CHECK(sized.size.isValue(), "给了尺寸就用它");
    PLUGINXX_UI_CHECK_EQ(sized.size.value, 24.0, "尺寸值");
}

PLUGINXX_UI_TEST(kit_展开结果可以直接解析) {
    const Item row = pluginxx::ui::kit::listRow({{"title", "标题"}, {"subtitle", "副标题"}});
    const Json json = pluginxx::ui::dumpItem(row);
    const Item again = pluginxx::ui::parseBlock(json);
    PLUGINXX_UI_CHECK(again.known, "展开结果能重新解析");
    PLUGINXX_UI_CHECK_EQ(again.kind, row.kind, "组件名一致");
    PLUGINXX_UI_CHECK_EQ(again.children.size(), row.children.size(), "结构一致");
}

PLUGINXX_UI_TEST(kit_按格换算) {
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::kit::cols(2), 16.0, "默认格宽 8u");
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::kit::rows(3), 60.0, "默认格高 20u");
    Capabilities caps = Capabilities::full();
    caps.cell.width   = 10.0;
    caps.cell.height  = 24.0;
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::kit::cols(2, &caps), 20.0, "客户端上报的格宽");
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::kit::rows(2, &caps), 48.0, "客户端上报的格高");
}

PLUGINXX_UI_TEST(kit_组件表与定义一致) {
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::kit::kKitVersion, 1, "kit 版本");
    PLUGINXX_UI_CHECK_EQ(
        pluginxx::ui::gen::kBlockCount, static_cast<std::size_t>(27), "组件数量"
    );
    PLUGINXX_UI_CHECK(pluginxx::ui::isKnownBlock("musicxx.Shader"), "客户端专属块在表里");
    PLUGINXX_UI_CHECK(
        pluginxx::ui::findBlockMeta("musicxx.Shader")->level == pluginxx::ui::BlockLevel::Client,
        "客户端专属块级别"
    );
}
