// 尺寸模型：u 与格的换算、最小格规则、能力查询
#include "pluginxx/ui/capabilities.h"

#include "pluginxx/ui/gen/blocks.g.h"
#include "pluginxx/ui/lint.h"
#include "pluginxx/ui/parse.h"
#include "test_framework.h"

#include <utilxx_base/json.h>

#include <cstddef>
#include <string>

using pluginxx::ui::Capabilities;
using pluginxx::ui::Item;
using utilxx_base::Json;

PLUGINXX_UI_TEST(默认格大小与留白常量) {
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::gen::kDefaultGap, 12.0, "默认留白");
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::gen::kDefaultCellWidth, 8.0, "默认格宽");
    PLUGINXX_UI_CHECK_EQ(pluginxx::ui::gen::kDefaultCellHeight, 20.0, "默认格高");
}

PLUGINXX_UI_TEST(u_换算成列与行) {
    Capabilities caps = Capabilities::full();
    caps.kind         = "tui";
    caps.cell         = pluginxx::ui::CellSize{8.0, 20.0};

    PLUGINXX_UI_CHECK_EQ(caps.colsOf(8.0), 1, "8u = 1 列");
    PLUGINXX_UI_CHECK_EQ(caps.colsOf(12.0), 2, "12u = 2 列");
    PLUGINXX_UI_CHECK_EQ(caps.colsOf(4.0), 1, "4u → 0.5 列，四舍五入到 1");
    PLUGINXX_UI_CHECK_EQ(caps.colsOf(2.0), 0, "太小 → 0 列（留白允许消失）");
    PLUGINXX_UI_CHECK_EQ(caps.colsOf(2.0, true), 1, "固定尺寸至少占 1 格");
    PLUGINXX_UI_CHECK_EQ(caps.colsOf(0.0, true), 0, "0 不会硬撑出一格");

    PLUGINXX_UI_CHECK_EQ(caps.rowsOf(12.0), 1, "12u = 1 行");
    PLUGINXX_UI_CHECK_EQ(caps.rowsOf(30.0), 2, "30u = 2 行");
    PLUGINXX_UI_CHECK_EQ(caps.rowsOf(4.0, true), 1, "固定高度至少 1 行");
}

PLUGINXX_UI_TEST(能力查询忽略大小写) {
    const Capabilities caps = Capabilities::full();
    PLUGINXX_UI_CHECK(caps.supportsBlock("Text"), "规范写法");
    PLUGINXX_UI_CHECK(caps.supportsBlock("text"), "小写");
    PLUGINXX_UI_CHECK(caps.supportsBlock("BLOCK"), "大写");
    PLUGINXX_UI_CHECK(!caps.supportsBlock("Whatever"), "不认识的组件");
    PLUGINXX_UI_CHECK(caps.supportsControl("checkbox"), "控件形态");
    PLUGINXX_UI_CHECK(!caps.supportsControl("slider"), "第一版没有 slider");
}

PLUGINXX_UI_TEST(能力表覆盖全部生成组件) {
    const Capabilities caps = Capabilities::full();
    PLUGINXX_UI_CHECK_EQ(caps.blocks.size(), pluginxx::ui::gen::kBlockCount, "组件数一致");
    PLUGINXX_UI_CHECK_EQ(
        caps.controls.size(), sizeof(pluginxx::ui::gen::kControlKinds) /
                                  sizeof(pluginxx::ui::gen::kControlKinds[0]),
        "控件数一致"
    );
    PLUGINXX_UI_CHECK(
        caps.supportsBlock("musicxx.Shader"), "GUI 客户端认识自己的专属块"
    );
    PLUGINXX_UI_CHECK(!Capabilities::minimal().supportsBlock("Divider"), "最小能力只有 Text");
}

PLUGINXX_UI_TEST(开发期检查提示非整数倍与混用) {
    Capabilities caps = Capabilities::full();
    caps.kind         = "tui";
    caps.cell         = pluginxx::ui::CellSize{8.0, 20.0};
    const std::vector<Item> items = pluginxx::ui::parseBlocks(Json::parse(R"([
        {"kind":"Gap","size":11},
        {"kind":"Row","children":[
            {"kind":"SizedBox","width":40},
            {"kind":"Expanded","children":[{"kind":"Text","text":"x"}]}
        ]},
        {"kind":"Text","text":"x","wrap":false,"maxLines":2}
    ])"));
    const auto notes = pluginxx::ui::lintWithCaps(items, caps);
    bool hasCellNote = false;
    bool hasMixNote  = false;
    bool hasWrapNote = false;
    for (const pluginxx::ui::LintNote& note : notes) {
        if (note.message.find("整数倍") != std::string::npos) {
            hasCellNote = true;
        }
        if (note.message.find("flex") != std::string::npos) {
            hasMixNote = true;
        }
        if (note.message.find("maxLines") != std::string::npos) {
            hasWrapNote = true;
        }
    }
    PLUGINXX_UI_CHECK(hasCellNote, "提示 u 值不是格的整数倍");
    PLUGINXX_UI_CHECK(hasMixNote, "提示固定尺寸与 flex 混用");
    PLUGINXX_UI_CHECK(hasWrapNote, "提示 wrap/maxLines 互相抵消");
}

PLUGINXX_UI_TEST(尺寸字段在模型里的三种形态) {
    const Item percent =
        pluginxx::ui::parseBlock(Json::parse(R"({"kind":"SizedBox","width":{"percent":50}})"));
    PLUGINXX_UI_CHECK(percent.width.isPercent(), "percent");
    PLUGINXX_UI_CHECK_EQ(percent.width.value, 50.0, "比例值");
    PLUGINXX_UI_CHECK(percent.height.isAuto(), "没给的高度是 auto");

    const Item edges = pluginxx::ui::parseBlock(Json::parse(
        R"({"kind":"Padding","padding":{"horizontal":20,"top":8},"children":[]})"
    ));
    PLUGINXX_UI_CHECK_EQ(edges.padding.left, 20.0, "左右取 horizontal");
    PLUGINXX_UI_CHECK_EQ(edges.padding.top, 8.0, "单边优先");
    PLUGINXX_UI_CHECK_EQ(edges.padding.bottom, 0.0, "没给的边是 0");
}
