// item.h 的小工具实现（文本占位替换、枚举归一化、数值格式化）
#include "pluginxx/ui/item.h"

#include <utilxx_base/json.h>

#include <cmath>
#include <cstdio>
#include <cstring>

namespace pluginxx {
namespace ui {
namespace detail {

namespace {

/// ASCII 小写（只处理 ASCII：组件名、枚举值、占位参数名都是 ASCII）
constexpr char lowerAscii(const char c) {
    return (c >= 'A' && c <= 'Z') ? static_cast<char>(c + 32) : c;
}

/// 值 → 文本（占位替换用；规则与 Dart/JS 两份绑定一致）
std::string stringifyArg(const utilxx_base::Json& value) {
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

/// `{name}` 里是否是合法参数名（字母/数字/下划线，且以字母开头）
bool isArgNameChar(const char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

} // namespace

bool iequals(const std::string_view a, const std::string_view b) {
    if (a.size() != b.size()) {
        return false;
    }
    for (std::size_t i = 0; i < a.size(); ++i) {
        if (lowerAscii(a[i]) != lowerAscii(b[i])) {
            return false;
        }
    }
    return true;
}

std::string_view
    enumNormalize(const std::string_view* values, const std::size_t count, const std::string_view v) {
    if (v.empty()) {
        return {};
    }
    for (std::size_t i = 0; i < count; ++i) {
        if (iequals(values[i], v)) {
            return values[i];
        }
    }
    return {};
}

bool enumContains(const std::string_view* values, const std::size_t count, const std::string_view v) {
    return !enumNormalize(values, count, v).empty();
}

std::string formatNumber(const double value) {
    if (!std::isfinite(value)) {
        return "0";
    }
    // 整数值直接按整数输出（两端一致：1.0 输出 "1"）
    if (value == std::floor(value) && std::fabs(value) < 1e15) {
        char buffer[32] = {};
        std::snprintf(buffer, sizeof(buffer), "%lld", static_cast<long long>(value));
        return buffer;
    }
    char buffer[64] = {};
    std::snprintf(buffer, sizeof(buffer), "%.2f", value);
    std::string out(buffer);
    // 去掉尾随 0 与小数点
    while (!out.empty() && out.back() == '0') {
        out.pop_back();
    }
    if (!out.empty() && out.back() == '.') {
        out.pop_back();
    }
    if (out == "-0") {
        return "0";
    }
    return out;
}

std::string applyTextArgs(const std::string_view text, const std::string_view argsJson) {
    if (text.empty() || argsJson.empty()) {
        return std::string(text);
    }
    utilxx_base::Json args;
    try {
        args = utilxx_base::Json::parse(argsJson);
    } catch (...) {
        return std::string(text);
    }
    if (!args.is_object()) {
        return std::string(text);
    }

    std::string out;
    out.reserve(text.size());
    for (std::size_t i = 0; i < text.size();) {
        if (text[i] != '{') {
            out.push_back(text[i++]);
            continue;
        }
        // 找到匹配的 '}'，中间必须是合法参数名
        const std::size_t begin = i + 1;
        std::size_t       end   = begin;
        while (end < text.size() && isArgNameChar(text[end])) {
            ++end;
        }
        const bool wellFormed = end > begin && end < text.size() && text[end] == '}';
        if (!wellFormed) {
            out.push_back(text[i++]);
            continue;
        }
        const std::string_view name = text.substr(begin, end - begin);
        if (!args.contains(name)) {
            // 没有这个参数：原样保留（插件能看出占位没被替换）
            out.append(text.substr(i, end - i + 1));
        } else {
            out.append(stringifyArg(args[name]));
        }
        i = end + 1;
    }
    return out;
}

} // namespace detail
} // namespace ui
} // namespace pluginxx
