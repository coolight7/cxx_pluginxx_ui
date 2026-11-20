// 槽位模型：一个渲染位置、它的形态、可用的作用域变量，以及"可选样式槽位"的选择
//
// 槽位（slot）是客户端预留（或插件自己声明）的渲染位置；挂在槽位上的一份界面叫内容
// （content，见 content_hub.dart）。这一层只描述"有哪些位置、怎么用"，不含项目业务。
import 'model.dart' show TextValue;

/// 槽位的使用方式
enum SlotKind {
  /// 声明项：出现在客户端自己的列表里，没有界面树（入口 / 菜单项 / 音效）
  item,

  /// 插入：一个位置可以有多份内容，按 `order` 排
  insert,

  /// 替换：只认一份内容（`order` 最小的那一条），没有内容时客户端画内置界面
  replace,

  /// 可选样式：候选声明 + 用户选择，只渲染选中那一份
  selectable,

  /// 普通页面背景：按路由自动生效
  pageBackground,

  /// 插件页面：插件自己发起（地址里带内容 id）
  page,

  /// 插件浮层：插件自己发起
  overlay,
}

/// 名字 → 形态（大小写不敏感；不认识返回 null）
SlotKind? slotKindOf(String name) {
  for (final SlotKind kind in SlotKind.values) {
    if (kind.name.toLowerCase() == name.toLowerCase()) {
      return kind;
    }
  }
  return null;
}

/// 一个槽位的声明
class SlotSpec {
  const SlotSpec({
    required this.id,
    required this.kind,
    this.variables = const <String>[],
    this.routes = const <String>[],
    this.owner = '',
    this.label = '',
  });

  /// 槽位 id（应用预留 `musicxx.ui.*`；插件声明 `plugin.<插件id>.ui.*`）
  final String id;
  final SlotKind kind;

  /// 这个槽位可用的作用域变量 id（`scope:*`）
  final List<String> variables;

  /// `pageBackground` 适用的页面路由（空 = 所有普通页面）
  final List<String> routes;

  /// 插件声明的槽位：属主插件 id；应用预留为空
  final String owner;

  /// 中文叫法（错误提示与自省用）
  final String label;

  bool get isPluginDeclared => owner.isNotEmpty;

  /// 能不能被 `UISlot` 嵌进界面里
  ///
  /// 只有 `insert` / `replace` 有意义：`selectable` / `pageBackground` / `page` / `overlay`
  /// 需要页面级位置或用户选择。
  bool get nestable => kind == SlotKind.insert || kind == SlotKind.replace;

  /// 有没有这个作用域变量
  bool hasVariable(String id) => variables.contains(id);

  SlotSpec copyWith({
    SlotKind? kind,
    List<String>? variables,
    List<String>? routes,
    String? owner,
    String? label,
  }) => SlotSpec(
    id: id,
    kind: kind ?? this.kind,
    variables: variables ?? this.variables,
    routes: routes ?? this.routes,
    owner: owner ?? this.owner,
    label: label ?? this.label,
  );

  @override
  String toString() => 'SlotSpec($id, ${kind.name}${owner.isEmpty ? '' : ', $owner'})';
}

/// 槽位表：客户端预留的槽位 + 运行期插件声明的槽位
///
/// 只做查表与变更通知，不关心内容。插件槽位在插件停用 / 卸载时由调用方移除。
class SlotCatalogue {
  SlotCatalogue({Iterable<SlotSpec> specs = const <SlotSpec>[]}) {
    for (final SlotSpec spec in specs) {
      _specs[spec.id] = spec;
    }
  }

  final Map<String, SlotSpec> _specs = <String, SlotSpec>{};

  /// 槽位表变化（声明 / 撤销）：内容是"这个槽位现在能用了吗"的订阅入口
  final List<void Function()> _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  SlotSpec? operator [](String id) => _specs[id];

  bool contains(String id) => _specs.containsKey(id);

  List<SlotSpec> get all => _specs.values.toList(growable: false);

  Iterable<SlotSpec> get pluginDeclared =>
      _specs.values.where((SlotSpec spec) => spec.isPluginDeclared);

  /// 新增 / 覆盖一个槽位（覆盖时不发通知：内容注册表自己会跟着事件走）
  void put(SlotSpec spec) {
    final bool isNew = !_specs.containsKey(spec.id);
    _specs[spec.id] = spec;
    if (isNew) {
      _notify();
    }
  }

  /// 撤销一个槽位（插件停用 / 卸载 → 引用它的内容一起失效）
  bool remove(String id) {
    if (null == _specs.remove(id)) {
      return false;
    }
    _notify();
    return true;
  }

  /// 撤销某个插件声明的全部槽位
  ///
  /// 空的 [pluginId] 不做事：应用预留的槽位 `owner` 也是空串，传空串会把它们一起删掉。
  void removeOwnedBy(String pluginId) {
    if (pluginId.isEmpty) {
      return;
    }
    final List<String> owned = <String>[
      for (final SlotSpec spec in _specs.values)
        if (spec.owner == pluginId) spec.id,
    ];
    if (owned.isEmpty) {
      return;
    }
    for (final String id in owned) {
      _specs.remove(id);
    }
    _notify();
  }

  void _notify() {
    for (final void Function() listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }
}

/// 可选样式槽位里的一个候选
class SlotChoiceEntry {
  const SlotChoiceEntry({
    required this.id,
    this.title = const TextValue(),
    this.depict = '',
    this.builtin = false,
    this.order = 0,
    this.seq = 0,
  });

  /// 候选 id（内置候选是 `musicxx.<名字>`，插件候选是内容的短 id）
  final String id;
  final TextValue title;

  /// 一句话说明（设置页的副标题）
  final String depict;

  /// 是不是客户端自带的候选
  final bool builtin;

  /// 插件给的排序权重（内置候选按客户端自己的顺序）
  final int order;

  /// 注册顺序（同 `order` 时按它排）
  final int seq;

  @override
  String toString() => 'SlotChoiceEntry($id${builtin ? ', builtin' : ''})';
}

/// 可选样式槽位（背景 / 歌曲图 / 动效）的候选与当前选择
///
/// 只放模型与规则：候选怎么来的、选择存哪里（设置项）都由客户端决定。
class SlotChoice {
  SlotChoice({required this.slot, String? current}) : _current = current;

  /// 槽位 id
  final String slot;

  final Map<String, SlotChoiceEntry> _entries = <String, SlotChoiceEntry>{};

  String? _current;

  /// 上一个选择（"交还控制权"用它）
  String? _previous;

  /// 当前选中的候选 id（`null` = 用客户端默认）
  String? get current => _current;

  /// 上一个选择
  String? get previous => _previous;

  /// 全部候选（内置在前，插件按 `order` 与注册顺序排）
  List<SlotChoiceEntry> get entries {
    final List<SlotChoiceEntry> list = _entries.values.toList();
    list.sort((SlotChoiceEntry a, SlotChoiceEntry b) {
      if (a.builtin != b.builtin) {
        return a.builtin ? -1 : 1;
      }
      if (a.order != b.order) {
        return a.order.compareTo(b.order);
      }
      return a.seq.compareTo(b.seq);
    });
    return list;
  }

  SlotChoiceEntry? entryOf(String id) => _entries[id];

  /// 加一个候选（同 id 覆盖）
  void put(SlotChoiceEntry entry) => _entries[entry.id] = entry;

  bool remove(String id) {
    if (null == _entries.remove(id)) {
      return false;
    }
    // 选中的被撤掉：回到客户端默认，但记下它曾经被选过
    if (_current == id) {
      _previous = id;
      _current = null;
    }
    return true;
  }

  /// 换一个（记下上一个选择，供"交还控制权"）
  void select(String? id) {
    if (id == _current) {
      return;
    }
    _previous = _current;
    _current = id;
  }

  /// 回到上一个选择（没有上一个时不动，返回 false）
  bool selectPrevious() {
    final String? previous = _previous;
    if (null == previous || !_entries.containsKey(previous)) {
      return false;
    }
    _current = previous;
    _previous = null;
    return true;
  }

  /// 当前选中的那一份能不能用（插件卸载后它不在了）
  bool get hasValidCurrent => null == _current || _entries.containsKey(_current!);
}
