// 解析 / 往返 / 上限
#include "pluginxx/ui/parse.h"

#include "test_framework.h"

#include <utilxx_base/json.h>

#include <cstddef>
#include <string>

using pluginxx::ui::Action;
using pluginxx::ui::Document;
using pluginxx::ui::Item;
using pluginxx::ui::Limits;
using pluginxx::ui::ParseReport;
using pluginxx::ui::SizeValue;
using utilxx_base::Json;

PLUGINXX_UI_TEST(样例夹具里的组件全部被识别) {
    const std::string text = pluginxx_ui_test::readFixture("schema_samples.json");
    PLUGINXX_UI_CHECK(!text.empty(), "schema_samples.json 存在");
    ParseReport report;
    const Document doc = pluginxx::ui::parseDocument(Json::parse(text), {}, &report);
    PLUGINXX_UI_CHECK_EQ(doc.blocks.size(), pluginxx::ui::gen::kBlockCount, "样例块数 = 组件数");
    for (const Item& item : doc.blocks) {
        PLUGINXX_UI_CHECK(item.known, "样例组件被识别：" + item.kind);
    }
}

PLUGINXX_UI_TEST(组件名忽略大小写) {
    const Item item = pluginxx::ui::parseBlock(Json::parse(R"({"kind":"TEXT","text":"大小写"})"));
    PLUGINXX_UI_CHECK_EQ(item.kind, std::string("Text"), "规范名");
    PLUGINXX_UI_CHECK_EQ(item.text.fallback, std::string("大小写"), "文本");
}

PLUGINXX_UI_TEST(未知组件保留兜底文本) {
    const Item item =
        pluginxx::ui::parseBlock(Json::parse(R"({"kind":"Whatever","fallback":"兜底"})"));
    PLUGINXX_UI_CHECK(!item.known, "未知组件标记为未识别");
    PLUGINXX_UI_CHECK_EQ(item.fallback, std::string("兜底"), "保留 fallback");
}

PLUGINXX_UI_TEST(负尺寸按0处理并记提示) {
    ParseReport report;
    const Item  item =
        pluginxx::ui::parseBlock(Json::parse(R"({"kind":"SizedBox","width":-10})"), {}, &report);
    PLUGINXX_UI_CHECK(item.width.isValue(), "仍是数值尺寸");
    PLUGINXX_UI_CHECK_EQ(item.width.value, 0.0, "负值按 0");
    PLUGINXX_UI_CHECK(!report.warnings.empty(), "记了一条提示");
}

PLUGINXX_UI_TEST(尺寸的三种形态) {
    const Item a = pluginxx::ui::parseBlock(Json::parse(R"({"kind":"Gap","size":12})"));
    PLUGINXX_UI_CHECK(a.size.isValue(), "数值");
    PLUGINXX_UI_CHECK_EQ(a.size.value, 12.0, "数值大小");

    const Item b = pluginxx::ui::parseBlock(Json::parse(R"({"kind":"Gap","size":"auto"})"));
    PLUGINXX_UI_CHECK(b.size.isAuto(), "auto");

    const Item c = pluginxx::ui::parseBlock(
        Json::parse(R"({"kind":"Gap","size":{"percent":40}})")
    );
    PLUGINXX_UI_CHECK(c.size.isPercent(), "percent");
    PLUGINXX_UI_CHECK_EQ(c.size.value, 40.0, "percent 大小");

    // 缺省 = auto（客户端用 caps.gap 兜底）
    const Item d = pluginxx::ui::parseBlock(Json::parse(R"({"kind":"Gap"})"));
    PLUGINXX_UI_CHECK(d.size.isAuto(), "缺省 auto");
}

PLUGINXX_UI_TEST(文本取值支持键与命名占位) {
    const Item item = pluginxx::ui::parseBlock(Json::parse(
        R"({"kind":"Text","text":{"key":"demo.total","fallback":"共 {n} 项","args":{"n":3}}})"
    ));
    PLUGINXX_UI_CHECK_EQ(item.text.key, std::string("demo.total"), "键");
    PLUGINXX_UI_CHECK_EQ(item.text.resolve(), std::string("共 3 项"), "缺键时用 fallback 并替换占位");
    const auto lookup = [](const std::string_view key) {
        return key == "demo.total" ? std::string("total {n}") : std::string();
    };
    PLUGINXX_UI_CHECK_EQ(item.text.resolve(lookup), std::string("total 3"), "命中语言表");
}

PLUGINXX_UI_TEST(动作的四种形态) {
    const auto actionOf = [](const char* text) {
        const std::string source =
            std::string(R"({"kind":"Button","label":"x","action":)") + text + "}";
        return pluginxx::ui::parseBlock(Json::parse(source)).action;
    };
    const Action shortForm = actionOf(R"("openSettings")");
    PLUGINXX_UI_CHECK(shortForm.kind == Action::Kind::Dispatch, "字符串短写 = dispatch");
    PLUGINXX_UI_CHECK_EQ(shortForm.name, std::string("openSettings"), "动作名");

    const Action route = actionOf(R"({"kind":"route","route":"ext://demo/settings"})");
    PLUGINXX_UI_CHECK(route.kind == Action::Kind::Route, "route");
    PLUGINXX_UI_CHECK_EQ(route.route, std::string("ext://demo/settings"), "跳转目标");

    const Action command =
        actionOf(R"({"kind":"command","name":"musicxx.player.play","args":{"x":1}})");
    PLUGINXX_UI_CHECK(command.kind == Action::Kind::Command, "command");
    PLUGINXX_UI_CHECK_EQ(command.argsJson, std::string(R"({"x":1})"), "参数按原文本携带");

    const Action none = actionOf(R"({"kind":"none"})");
    PLUGINXX_UI_CHECK(none.empty(), "none 是空动作");
}

PLUGINXX_UI_TEST(动作解析器可直接用) {
    // 块字段与客户端扩展点（UI 项的 data.action）共用同一个解析器
    const Action shortForm = pluginxx::ui::parseAction(Json("openSettings"));
    PLUGINXX_UI_CHECK(shortForm.kind == Action::Kind::Dispatch, "字符串短写 = dispatch");
    PLUGINXX_UI_CHECK_EQ(shortForm.name, std::string("openSettings"), "动作名");

    const Action route = pluginxx::ui::parseAction(
        Json::parse(R"({"kind":"ROUTE","route":"ext://demo/card"})"));
    PLUGINXX_UI_CHECK(route.kind == Action::Kind::Route, "kind 忽略大小写");
    PLUGINXX_UI_CHECK_EQ(route.route, std::string("ext://demo/card"), "跳转地址");

    const Action none = pluginxx::ui::parseAction(Json::parse(R"({"kind":"none"})"));
    PLUGINXX_UI_CHECK(none.empty(), "none 是空动作");
    PLUGINXX_UI_CHECK(pluginxx::ui::parseAction(Json::parse(R"({"kind":"unknown"})")).empty(),
                      "未知 kind 取 none");
    PLUGINXX_UI_CHECK(pluginxx::ui::parseAction(Json(3)).empty(), "非法取值是空动作");

    // 序列化：空动作输出 null，其余可往返
    PLUGINXX_UI_CHECK(pluginxx::ui::dumpAction(none).is_null(), "空动作输出 null");
    const Action again =
        pluginxx::ui::parseAction(pluginxx::ui::dumpAction(route));
    PLUGINXX_UI_CHECK_EQ(again.route, route.route, "往返保留地址");
}

PLUGINXX_UI_TEST(解析与序列化往返稳定) {
    const std::string text = pluginxx_ui_test::readFixture("core.json");
    PLUGINXX_UI_CHECK(!text.empty(), "core.json 存在");
    const Json first  = Json::parse(text);
    const Json dumped = pluginxx::ui::dumpDocument(pluginxx::ui::parseDocument(first));
    const Json second = pluginxx::ui::dumpDocument(pluginxx::ui::parseDocument(dumped));
    PLUGINXX_UI_CHECK_EQ(dumped.dump(), second.dump(), "dump(parse(dump(parse(x)))) 稳定");
}

PLUGINXX_UI_TEST(超过数量上限时截断) {
    Json array = Json::array();
    for (int i = 0; i < 600; ++i) {
        array.push_back(Json::object({{"kind", "Text"}, {"text", "x"}}));
    }
    ParseReport report;
    const auto  items = pluginxx::ui::parseBlocks(array, {}, &report);
    PLUGINXX_UI_CHECK_EQ(items.size(), pluginxx::ui::gen::kMaxItems, "按上限截断");
    PLUGINXX_UI_CHECK(report.truncated, "标记为截断");
}

PLUGINXX_UI_TEST(超过层级上限时丢弃更深子块) {
    // 造一段比 maxDepth 更深的嵌套
    Json node = Json::object({{"kind", "Text"}, {"text", "最深处"}});
    for (int i = 0; i < pluginxx::ui::gen::kMaxDepth + 4; ++i) {
        Json wrapper = Json::object({{"kind", "Column"}});
        Json children = Json::array();
        children.push_back(node);
        wrapper["children"] = children;
        node                = wrapper;
    }
    ParseReport report;
    const Item  item = pluginxx::ui::parseBlock(node, {}, &report);
    PLUGINXX_UI_CHECK(report.truncated, "标记为截断");
    const pluginxx::ui::Item* cursor = &item;
    int                       depth  = 0;
    while (!cursor->children.empty()) {
        cursor = &cursor->children.front();
        ++depth;
        // 顶层块算第 1 层：最深块正好落在上限上
        PLUGINXX_UI_CHECK(depth <= pluginxx::ui::gen::kMaxDepth, "层级不超过上限");
    }
}

PLUGINXX_UI_TEST(能力段往返) {
    const pluginxx::ui::Capabilities full = pluginxx::ui::fullCapabilities();
    const Json                     json = pluginxx::ui::capabilitiesToJson(full);
    PLUGINXX_UI_CHECK_EQ(static_cast<int>(json["apiVersion"].get<double>()), full.apiVersion, "版本");
    PLUGINXX_UI_CHECK_EQ(json["kind"].get<std::string>(), std::string("gui"), "渲染类型");
    const pluginxx::ui::Capabilities back = pluginxx::ui::capabilitiesFromJson(json);
    PLUGINXX_UI_CHECK_EQ(back.blocks.size(), full.blocks.size(), "组件数与上报一致");
    PLUGINXX_UI_CHECK(back.supportsBlock("Text"), "支持 Text");
    PLUGINXX_UI_CHECK_EQ(back.gap, full.gap, "默认行距");

    const pluginxx::ui::Capabilities minimal = pluginxx::ui::minimalCapabilities();
    const Json                     minJson  = pluginxx::ui::capabilitiesToJson(minimal);
    const pluginxx::ui::Capabilities minBack  = pluginxx::ui::capabilitiesFromJson(minJson);
    PLUGINXX_UI_CHECK_EQ(minBack.blocks.size(), static_cast<std::size_t>(1), "最小能力只有 Text");
    PLUGINXX_UI_CHECK(!minBack.percent, "最小能力不支持 percent");
}
