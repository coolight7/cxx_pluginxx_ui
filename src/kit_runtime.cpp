// kit 模板展开（与 Dart/JS 两份绑定语义一致）
#include "pluginxx/ui/kit_runtime.h"

#include "pluginxx/ui/parse.h"

#include <cstddef>
#include <string>
#include <string_view>

namespace pluginxx {
namespace ui {
namespace detail {

namespace {

using utilxx_base::Json;

/// 值是否存在（null 与空字符串视为"没有给"）
bool present(const Json& value) {
    if (value.is_null()) {
        return false;
    }
    if (value.is_string()) {
        return !value.get_string_view().empty();
    }
    return true;
}

/// `$require` 的判空规则：null、空字符串、空数组都算"空"
bool isEmptyValue(const Json& value) {
    if (!present(value)) {
        return true;
    }
    return value.is_array() && value.size() == 0;
}

/// 参数值 → 文本（字符串插值用；规则与 item.cpp 的占位替换一致）
std::string stringify(const Json& value) {
    if (value.is_null()) {
        return {};
    }
    if (value.is_string()) {
        return std::string(value.get_string_view());
    }
    if (value.is_bool()) {
        return value.get<bool>() ? "true" : "false";
    }
    if (value.is_number()) {
        return formatNumber(value.get<double>());
    }
    return value.dump();
}

std::string interpolate(const std::string_view text, const Json& values) {
    std::string out;
    out.reserve(text.size());
    for (std::size_t i = 0; i < text.size();) {
        if (text[i] == '$' && i + 1 < text.size() && text[i + 1] == '{') {
            const std::size_t end = text.find('}', i + 2);
            if (end != std::string_view::npos) {
                const std::string_view name = text.substr(i + 2, end - i - 2);
                Json                 value;
                if (values.contains(name)) {
                    value = values[name];
                }
                out.append(stringify(value));
                i = end + 1;
                continue;
            }
        }
        out.push_back(text[i++]);
    }
    return out;
}

/// 变体选择：第一个 `requires` 全部被 env 支持的变体生效；env 为空时用第一个无条件变体
Json pickVariant(const Json& kitDef, const Capabilities* env) {
    const Json& variants = kitDef["variants"];
    if (!variants.is_array() || variants.size() == 0) {
        return Json();
    }
    // 目标未知（没有 env）：用第一个变体（插件作者认为最合适的那一个）
    if (env == nullptr) {
        return variants[0]["template"];
    }
    const Json* fallback = nullptr;
    for (const Json& variant : variants) {
        const Json& required = variant["requires"];
        if (!required.is_array() || required.size() == 0) {
            if (fallback == nullptr) {
                fallback = &variant;
            }
            continue;
        }
        bool ok = true;
        for (const Json& need : required) {
            if (!need.is_string() || !env->supportsBlock(need.get_string_view())) {
                ok = false;
                break;
            }
        }
        if (ok) {
            return variant["template"];
        }
    }
    if (fallback != nullptr) {
        return (*fallback)["template"];
    }
    return variants[0]["template"];
}

Json expandNode(const Json& node, const Json& values, const Capabilities* env);

/// `$map`：把列表参数逐项展开（当前项以 `$item` 提供给 wrap 模板）
Json expandMap(const Json& node, const Json& values, const Capabilities* env) {
    Json out = Json::array();
    if (!node.is_object() || !node.contains("$map")) {
        const Json single = expandNode(node, values, env);
        if (!single.is_null()) {
            out.push_back(single);
        }
        return out;
    }
    const std::string_view param = node["$map"].is_string() ? node["$map"].get_string_view()
                                                            : std::string_view{};
    if (param.empty() || !values.contains(param) || !values[param].is_array()) {
        return out;
    }
    for (const Json& element : values[param]) {
        Json scope = Json::object();
        for (const auto& kv : values.items()) {
            scope[std::string(kv.first)] = kv.second;
        }
        scope["item"] = element;
        const Json expanded = expandNode(node["wrap"], scope, env);
        if (!expanded.is_null()) {
            out.push_back(expanded);
        }
    }
    return out;
}

Json expandNode(const Json& node, const Json& values, const Capabilities* env) {
    if (node.is_string()) {
        const std::string_view text = node.get_string_view();
        if (text.size() > 1 && text[0] == '$' && text.find('{') == std::string_view::npos) {
            const std::string_view name = text.substr(1);
            return values.contains(name) ? values[name] : Json();
        }
        if (text.find("${") != std::string_view::npos) {
            return Json(interpolate(text, values));
        }
        return node;
    }
    if (node.is_array()) {
        Json out = Json::array();
        for (const Json& element : node) {
            const Json expanded = expandMap(element, values, env);
            for (const Json& item : expanded) {
                out.push_back(item);
            }
        }
        return out;
    }
    if (!node.is_object()) {
        return node;
    }
    if (node.contains("$map")) {
        return expandMap(node, values, env);
    }
    if (node.contains("$require")) {
        const Json& require   = node["$require"];
        const std::string_view param = require.is_string() ? require.get_string_view()
                                                           : std::string_view{};
        Json value;
        if (!param.empty() && values.contains(param)) {
            value = values[param];
        }
        if (isEmptyValue(value)) {
            return Json();
        }
    }
    Json out = Json::object();
    for (const auto& kv : node.items()) {
        if (kv.first == "$require") {
            continue;
        }
        const Json child = expandNode(kv.second, values, env);
        if (child.is_null()) {
            continue;
        }
        out[std::string(kv.first)] = child;
    }
    return out;
}

} // namespace

Json expandKitTemplate(const Json& templateNode, const Json& values, const Capabilities* env) {
    return expandNode(templateNode, values, env);
}

Item expandKit(const std::string_view name, const Json& params, const Capabilities* env,
               const KitTemplateLookup lookup) {
    if (lookup == nullptr) {
        return {};
    }
    const Json definition = lookup(name);
    if (!definition.is_object()) {
        return {};
    }
    Json values = definition["params"].is_object() ? definition["params"] : Json::object();
    if (params.is_object()) {
        for (const auto& kv : params.items()) {
            values[std::string(kv.first)] = kv.second;
        }
    }
    const Json templateNode = pickVariant(definition, env);
    if (!templateNode.is_object()) {
        return {};
    }
    const Json result = expandNode(templateNode, values, env);
    if (!result.is_object()) {
        return {};
    }
    return parseBlock(result);
}

} // namespace detail
} // namespace ui
} // namespace pluginxx
