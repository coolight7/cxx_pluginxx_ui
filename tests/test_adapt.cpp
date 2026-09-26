// 降级适配
#include "pluginxx/ui/adapt.h"

#include "pluginxx/ui/gen/adapt_rules.g.h"
#include "pluginxx/ui/parse.h"
#include "test_framework.h"

#include <utilxx_base/json.h>

#include <cstddef>
#include <string>
#include <vector>

using pluginxx::ui::AdaptReport;
using pluginxx::ui::Capabilities;
using pluginxx::ui::Item;
using utilxx_base::Json;

namespace {

std::vector<Item> parseFixture(const char* name) {
    const std::string text = pluginxx_ui_test::readFixture(name);
    return pluginxx::ui::parseBlocks(Json::parse(text));
}

/// 块树里出现过的组件名（含子块）
void collectKinds(const std::vector<Item>& items, std::vector<std::string>& out) {
    for (const Item& item : items) {
        out.push_back(item.kind);
        collectKinds(item.children, out);
    }
}

/// 去掉若干组件后的能力
Capabilities capsWithout(const std::vector<std::string>& remove) {
    Capabilities caps = pluginxx::ui::fullCapabilities();
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

PLUGINXX_UI_TEST(完整能力下适配不改结构) {
    const std::vector<Item> items = parseFixture("core.json");
    const auto              out   = pluginxx::ui::adaptBlocks(items, Capabilities::full());
    PLUGINXX_UI_CHECK_EQ(out.size(), items.size(), "块数不变");
    std::vector<std::string> kinds;
    collectKinds(out, kinds);
    for (const std::string& kind : kinds) {
        PLUGINXX_UI_CHECK(
            pluginxx::ui::canonicalKind(kind) == kind, "组件名都是规范名：" + kind
        );
    }
}

PLUGINXX_UI_TEST(最小能力全部收敛到文本) {
    const std::vector<Item> items = parseFixture("core.json");
    AdaptReport             report;
    const auto out = pluginxx::ui::adaptBlocks(items, Capabilities::minimal(), &report);
    PLUGINXX_UI_CHECK(!out.empty(), "仍有内容");
    for (const Item& item : out) {
        PLUGINXX_UI_CHECK_EQ(item.kind, std::string("Text"), "只剩 Text");
        PLUGINXX_UI_CHECK(item.children.empty(), "Text 不带子块");
    }
}

PLUGINXX_UI_TEST(终端能力下降级为文本) {
    // 终端常见能力：没有 Image / Stack / Icon / Sparkline / 着色器
    const Capabilities caps = capsWithout({"Image", "Stack", "Icon", "Sparkline", "musicxx.Shader"});
    const std::vector<Item> items = parseFixture("gui_heavy.json");
    AdaptReport             report;
    const auto              out = pluginxx::ui::adaptBlocks(items, caps, &report);
    std::vector<std::string> kinds;
    collectKinds(out, kinds);
    for (const std::string& kind : kinds) {
        PLUGINXX_UI_CHECK(caps.supportsBlock(kind), "只产出客户端支持的组件：" + kind);
    }
    // 图片退成 alt 文本（可能在子块里，递归找）
    std::vector<const Item*> queue;
    for (const Item& item : out) {
        queue.push_back(&item);
    }
    bool hasAltText = false;
    while (!queue.empty()) {
        const Item* item = queue.back();
        queue.pop_back();
        if (item->kind == "Text" && item->text.fallback == "封面") {
            hasAltText = true;
        }
        for (const Item& child : item->children) {
            queue.push_back(&child);
        }
    }
    PLUGINXX_UI_CHECK(hasAltText, "Image 退成 alt 文本");
}

PLUGINXX_UI_TEST(容器不支持时展开子块) {
    const Capabilities caps = capsWithout({"Block", "Padding", "Align", "Collapse"});
    const std::vector<Item> items = pluginxx::ui::parseBlocks(Json::parse(R"([
        {"kind":"Block","title":"卡片","children":[
            {"kind":"Text","text":"内容"},
            {"kind":"Text","text":"第二行"}
        ]}
    ])"));
    const auto out = pluginxx::ui::adaptBlocks(items, caps);
    PLUGINXX_UI_CHECK_EQ(out.size(), static_cast<std::size_t>(3), "标题行 + 两个子块");
    PLUGINXX_UI_CHECK_EQ(out[0].kind, std::string("Text"), "标题变成文本");
    PLUGINXX_UI_CHECK_EQ(out[0].text.fallback, std::string("卡片"), "标题内容");
    PLUGINXX_UI_CHECK_EQ(out[1].text.fallback, std::string("内容"), "子块一");
    PLUGINXX_UI_CHECK_EQ(out[2].text.fallback, std::string("第二行"), "子块二");
}

PLUGINXX_UI_TEST(不支持的可选块退成纯文本) {
    const Capabilities caps = capsWithout({"Sparkline", "Diff", "Diagram", "Markdown"});
    const std::vector<Item> items = pluginxx::ui::parseBlocks(Json::parse(R"([
        {"kind":"Sparkline","data":[1,2,3],"showLast":true},
        {"kind":"Markdown","text":"# 标题"}
    ])"));
    const auto out = pluginxx::ui::adaptBlocks(items, caps);
    PLUGINXX_UI_CHECK_EQ(out.size(), static_cast<std::size_t>(2), "都保留成文本");
    for (const Item& item : out) {
        PLUGINXX_UI_CHECK_EQ(item.kind, std::string("Text"), "退成 Text");
        PLUGINXX_UI_CHECK(!item.text.fallback.empty(), "文本非空");
    }
}

PLUGINXX_UI_TEST(未知组件用兜底文本) {
    const std::vector<Item> items = pluginxx::ui::parseBlocks(Json::parse(R"([
        {"kind":"Whatever","fallback":"兜底文本"}
    ])"));
    const auto out = pluginxx::ui::adaptBlocks(items, Capabilities::full());
    PLUGINXX_UI_CHECK_EQ(out.size(), static_cast<std::size_t>(1), "保留一个块");
    PLUGINXX_UI_CHECK_EQ(out[0].kind, std::string("Text"), "变成文本");
    PLUGINXX_UI_CHECK_EQ(out[0].text.fallback, std::string("兜底文本"), "用 fallback");
    PLUGINXX_UI_CHECK_EQ(out[0].tone, std::string("hint"), "次要样式");
}

PLUGINXX_UI_TEST(控件形态不支持时退成只读文本) {
    Capabilities caps = Capabilities::full();
    caps.controls     = {"checkbox"};
    const std::vector<Item> items = pluginxx::ui::parseBlocks(Json::parse(R"([
        {"kind":"Control","control":"select","id":"theme","label":"主题","value":"dark",
         "options":[{"value":"dark","label":"深色"}]}
    ])"));
    AdaptReport report;
    const auto  out = pluginxx::ui::adaptBlocks(items, caps, &report);
    PLUGINXX_UI_CHECK_EQ(out.size(), static_cast<std::size_t>(1), "保留一个块");
    PLUGINXX_UI_CHECK_EQ(out[0].kind, std::string("Text"), "退成只读文本");
    PLUGINXX_UI_CHECK_EQ(out[0].text.fallback, std::string("主题: 深色"), "文本含当前值");
    PLUGINXX_UI_CHECK(!report.notes.empty(), "记了一条说明");
}

PLUGINXX_UI_TEST(percent与aspect不支持时退回内容尺寸) {
    Capabilities caps = Capabilities::full();
    caps.percent      = false;
    caps.aspect       = false;
    const std::vector<Item> items = pluginxx::ui::parseBlocks(Json::parse(R"([
        {"kind":"SizedBox","width":{"percent":50},"height":40,"aspect":1.5}
    ])"));
    const auto out = pluginxx::ui::adaptBlocks(items, caps);
    PLUGINXX_UI_CHECK_EQ(out.size(), static_cast<std::size_t>(1), "保留一个块");
    PLUGINXX_UI_CHECK(out[0].width.isAuto(), "percent 宽度退成内容尺寸");
    PLUGINXX_UI_CHECK(out[0].height.isValue(), "数值高度保留");
    PLUGINXX_UI_CHECK_EQ(out[0].aspect, 0.0, "纵横比被忽略");
}

PLUGINXX_UI_TEST(层数上限按客户端能力截断) {
    Capabilities caps = Capabilities::full();
    caps.limits.maxDepth = 1;
    const std::vector<Item> items = pluginxx::ui::parseBlocks(Json::parse(R"([
        {"kind":"Block","children":[{"kind":"Block","children":[{"kind":"Text","text":"深处"}]}]}
    ])"));
    AdaptReport report;
    const auto  out = pluginxx::ui::adaptBlocks(items, caps, &report);
    PLUGINXX_UI_CHECK_EQ(out.size(), static_cast<std::size_t>(1), "顶层保留");
    PLUGINXX_UI_CHECK_EQ(out[0].children.size(), static_cast<std::size_t>(1), "保留一层子块");
    PLUGINXX_UI_CHECK(out[0].children[0].children.empty(), "超过层数的子块被丢弃");
    PLUGINXX_UI_CHECK(!report.notes.empty(), "记了一条说明");
}

PLUGINXX_UI_TEST(适配规则表与定义一致) {
    PLUGINXX_UI_CHECK(
        pluginxx::ui::adaptRuleOf("Stack") == pluginxx::ui::AdaptRule::LastChild, "Stack → lastChild"
    );
    PLUGINXX_UI_CHECK(
        pluginxx::ui::adaptRuleOf("Image") == pluginxx::ui::AdaptRule::AltText, "Image → altText"
    );
    PLUGINXX_UI_CHECK(
        pluginxx::ui::adaptRuleOf("Block") == pluginxx::ui::AdaptRule::Flatten, "Block → flatten"
    );
    PLUGINXX_UI_CHECK(
        pluginxx::ui::adaptRuleOf("Text") == pluginxx::ui::AdaptRule::Terminal, "Text → terminal"
    );
    PLUGINXX_UI_CHECK_EQ(
        pluginxx::ui::gen::kAdaptRuleCount, pluginxx::ui::gen::kBlockCount, "每个组件都有规则"
    );
}
