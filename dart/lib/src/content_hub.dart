// 内容运行时：槽位的激活、依赖订阅、串行刷新、缓存与渲染前的绑定
//
// 一条内容 = 插件为某个槽位生成的一份界面 JSON（`{json, data}`）。渲染路径**只读缓存**，
// 永不同步调用、也不同步等待插件：
//
// ```
// 插件注册内容(槽位, 内容 id, deps, order)
//   → 客户端把注册表交给 ContentHub（applyChange）
// 槽位被挂载 → activate()：订阅 deps → 请求一次内容（带 context）
//   → 客户端把它变成插件框架的调用，结果经 changes 回来 → 写缓存
// 挂载点：读缓存 → 绑定变量 → 解析 → 适配 → 渲染（不碰插件）
//     变量变化：立刻重新绑定（refresh），同时按"串行 + 只保留最新"请求插件重生成
// ```
//
// 库不渲染、不认识 Flutter：渲染器与被渲染的模型之间的分界是 [ContentPipeline]。
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'adapt.dart';
import 'bind.dart';
import 'capabilities.dart';
import 'model.dart';
import 'parse.dart';
import 'slot.dart';

// ==================== 内容模型 ====================

/// 一条内容的注册（插件声明的那一半：槽位、id、依赖、排序）
class ContentRegistration {
  const ContentRegistration({
    required this.slot,
    required this.itemId,
    required this.plugin,
    required this.id,
    this.deps = const <String>[],
    this.order = 0,
    this.minIntervalMs = 0,
    this.seq = 0,
  });

  /// 槽位 id
  final String slot;

  /// 内容全名 `plugin.<插件id>.<内容 id>`
  final String itemId;

  /// 属主插件 id
  final String plugin;

  /// 插件自己起的短 id（同一个插件在同一个槽位上可以有多份）
  final String id;

  /// 依赖的变量 id（只有这些被订阅、也只有这些进 `context`）
  final List<String> deps;

  /// 排序权重（小者靠前）
  final int order;

  /// 插件要求的最短刷新间隔（毫秒；0 = 不按时间节流）
  final int minIntervalMs;

  /// 注册顺序（同 `order` 时按它排）
  final int seq;

  @override
  String toString() => 'ContentRegistration($slot, $itemId, order=$order)';
}

/// 缓存里的一条内容
class ContentEntry {
  const ContentEntry({
    required this.slot,
    required this.itemId,
    required this.plugin,
    required this.id,
    required this.order,
    required this.rev,
    this.json,
    this.data,
    this.updatedAt,
    this.lastError,
    this.bytes = 0,
    this.seq = 0,
  });

  final String slot;
  final String itemId;
  final String plugin;
  final String id;
  final int order;

  /// 框架给的单调版本（只接受更大的值，过期结果直接丢掉）
  final int rev;

  /// 生成函数给的原始 JSON（绑定前）
  final Object? json;

  /// 生成函数给的附加数据（第一版只保存，留给以后做局部更新）
  final Object? data;

  final DateTime? updatedAt;

  /// 最近一次失败原因（成功后清空）
  final String? lastError;

  /// 原始 JSON 的字节数（自省用）
  final int bytes;

  /// 注册顺序
  final int seq;

  bool get hasContent => null != json;

  ContentEntry copyWith({
    int? rev,
    Object? json,
    Object? data,
    DateTime? updatedAt,
    String? lastError,
    bool clearError = false,
    int? bytes,
    int? order,
    int? seq,
  }) => ContentEntry(
    slot: slot,
    itemId: itemId,
    plugin: plugin,
    id: id,
    order: order ?? this.order,
    rev: rev ?? this.rev,
    json: null == json ? this.json : json,
    data: null == data ? this.data : data,
    updatedAt: updatedAt ?? this.updatedAt,
    lastError: clearError ? null : (lastError ?? this.lastError),
    bytes: bytes ?? this.bytes,
    seq: seq ?? this.seq,
  );

  @override
  String toString() =>
      'ContentEntry($slot, $id, rev=$rev${null == lastError ? '' : ', $lastError'})';
}

// ==================== 传输与变量（客户端实现） ====================

/// 一次内容请求
class ContentRequest {
  const ContentRequest({
    required this.slot,
    required this.itemId,
    required this.plugin,
    required this.id,
    required this.context,
  });

  final String slot;
  final String itemId;
  final String plugin;
  final String id;

  /// 声明的依赖变量 → 当前值
  final Map<String, Object?> context;

  @override
  String toString() => 'ContentRequest($itemId)';
}

/// 内容变化（客户端把插件框架的事件翻译成这些）
sealed class ContentChange {
  const ContentChange();
}

/// 插件注册（或重新注册）了一条内容
class ContentRegistered extends ContentChange {
  const ContentRegistered(this.registration);

  final ContentRegistration registration;
}

/// 插件注销了一条内容
class ContentUnregistered extends ContentChange {
  const ContentUnregistered({required this.slot, required this.itemId});

  final String slot;
  final String itemId;
}

/// 一次生成的结果（成功或失败）
class ContentResultChange extends ContentChange {
  const ContentResultChange({
    required this.slot,
    required this.itemId,
    required this.rev,
    this.json,
    this.data,
    this.error,
  });

  final String slot;
  final String itemId;
  final int rev;
  final Object? json;
  final Object? data;
  final String? error;
}

/// 插件声明了一个槽位
class SlotDeclared extends ContentChange {
  const SlotDeclared(this.spec);

  final SlotSpec spec;
}

/// 插件撤销了一个槽位（引用它的 `UISlot` 画 fallback）
class SlotRevoked extends ContentChange {
  const SlotRevoked(this.slot);

  final String slot;
}

/// 某个插件的内容与槽位全部失效（停用 / 卸载 / 关闭总开关）
class PluginDetached extends ContentChange {
  const PluginDetached(this.plugin);

  final String plugin;
}

/// 全部失效
class AllDetached extends ContentChange {
  const AllDetached();
}

/// 内容传输：客户端接插件框架
abstract interface class ContentTransport {
  /// 内容结果 / 注册变化 / 槽位变化
  Stream<ContentChange> get changes;

  /// 让插件生成一份内容（结果经 [changes] 回来）
  ///
  /// 返回的 Future 只表示"这次请求结束了"（成功、失败都算），`ContentHub` 用它来判定
  /// 串行刷新（同一份内容最多一个在途请求）。
  Future<void> requestContent(ContentRequest request);
}

/// 变量读取：客户端提供取值与变化通知
///
/// 作用域变量（`scope:*`）由 [SlotScope] 自己给（读 [SlotScope.read]，它会沿作用域链找），
/// 客户端只要把全局变量（`musicxx.*`）与插件广播（`plugin.*`）接上即可。
abstract interface class VariableReader {
  Object? read(String id, SlotScope? scope);

  /// 订阅一个变量的变化（同一变量多次订阅要能正确计数）
  void watch(String id, void Function() onChange);

  void unwatch(String id, void Function() onChange);
}

/// 原始 JSON → 可渲染文档（客户端可替换：加自己的包装解析、统计等）
abstract interface class ContentPipeline {
  UiDocument? render({
    required Object? json,
    required Map<String, Object?> values,
    required SlotScope scope,
    required List<String> missing,
  });
}

/// 默认的渲染管线：绑定变量 → 解析 → 适配
class DefaultContentPipeline implements ContentPipeline {
  const DefaultContentPipeline({this.capabilities, this.parseProblems});

  /// 客户端能力（不传就不做适配，返回解析后的模型）
  final PluginCapabilities? capabilities;

  /// 解析提示的出口（客户端可以接到日志）
  final void Function(List<String> warnings)? parseProblems;

  @override
  UiDocument? render({
    required Object? json,
    required Map<String, Object?> values,
    required SlotScope scope,
    required List<String> missing,
  }) {
    if (null == json) {
      return null;
    }
    final BindResult bound = bindVariables(json, values);
    missing.addAll(bound.missing);
    final ParseReport report = ParseReport();
    final UiDocument doc = parseDocument(bound.value, report: report);
    if (report.warnings.isNotEmpty) {
      parseProblems?.call(<String>[...report.warnings]);
    }
    final PluginCapabilities? caps = capabilities;
    if (null == caps) {
      return doc;
    }
    return adaptDocument(doc, caps);
  }
}

// ==================== 作用域 ====================

/// 槽位作用域：一次激活的句柄
///
/// - [args]：外层内容通过 `UISlot.args` 传进来的上下文（`scope:musicxx.slot.args`）；
/// - [values]：客户端在这个槽位上填的作用域变量（例如歌单页的歌单信息）；
/// - [parent]：嵌套时的外层作用域（作用域变量按链继承）；
/// - [depth]：嵌套深度（应用预留的槽位是 1）；
/// - [ancestors]：祖先槽位链（防止循环）。
class SlotScope {
  SlotScope._({
    required this.slot,
    required this.args,
    required this.values,
    required this.parent,
    required this.depth,
    required this.ancestors,
    ContentHub? hub,
    bool valid = true,
  }) : _hub = hub,
       _valid = valid;

  final String slot;
  final Map<String, Object?> args;
  final Map<String, Object?> values;
  final SlotScope? parent;
  final int depth;
  final Set<String> ancestors;

  final ContentHub? _hub;
  final bool _valid;

  /// 这个作用域能不能用（深度超限 / 循环时是 false：调用方画 fallback）
  bool get valid => _valid;

  bool get isNested => null != parent;

  /// 读一个作用域变量（沿作用域链往上找）
  Object? read(String id) {
    if (id == scopeSlotArgs) {
      return args;
    }
    for (SlotScope? scope = this; null != scope; scope = scope.parent) {
      if (scope.values.containsKey(id)) {
        return scope.values[id];
      }
    }
    return null;
  }

  /// `scope:musicxx.slot.args`：外层内容传给这个嵌套槽位的上下文
  static const String scopeSlotArgs = 'scope:musicxx.slot.args';

  bool _disposed = false;

  /// 结束这次激活（挂载点 dispose 时调用；重复调用安全）
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _hub?._deactivate(this);
  }

  @override
  String toString() => 'SlotScope($slot, depth=$depth${_valid ? '' : ', invalid'})';
}

// ==================== 运行时 ====================

/// 内容运行时：缓存、激活、依赖订阅、串行刷新、排序与记忆化
///
/// 线程模型：全部在 Dart 侧单线程里跑；同一个槽位的两个挂载点共享同一份缓存。
class ContentHub {
  ContentHub({
    required this.slots,
    required this.variables,
    required this.transport,
    ContentPipeline? pipeline,
    this.maxNesting = 4,
    void Function(String message)? log,
  }) : pipeline = pipeline ?? const DefaultContentPipeline(),
       _log = log {
    _subscription = transport.changes.listen(applyChange);
    slots.addListener(_onSlotsChanged);
  }

  final SlotCatalogue slots;
  final VariableReader variables;
  final ContentTransport transport;
  final ContentPipeline pipeline;

  /// 嵌套深度上限（应用预留的槽位算第 1 层）
  final int maxNesting;

  final void Function(String message)? _log;

  /// 槽位 → (内容全名 → 注册)
  final Map<String, Map<String, ContentRegistration>> _registry =
      <String, Map<String, ContentRegistration>>{};

  /// 槽位 → (内容全名 → 缓存)
  final Map<String, Map<String, ContentEntry>> _cache =
      <String, Map<String, ContentEntry>>{};

  /// 内容全名 → 在途请求状态
  final Map<String, _InFlight> _inflight = <String, _InFlight>{};

  /// 槽位 → 当前激活的作用域（后挂载的排在后面；请求用最后一个）
  final Map<String, List<SlotScope>> _active = <String, List<SlotScope>>{};

  /// 槽位 → 变化监听
  final Map<String, List<void Function()>> _slotListeners =
      <String, List<void Function()>>{};

  /// 变量 → 订阅者计数（多个内容依赖同一变量时只订阅一次）
  final Map<String, int> _watchCount = <String, int>{};
  final Map<String, void Function()> _watchCallbacks =
      <String, void Function()>{};

  /// 渲染记忆化：(内容全名) → 上一份文档与它的指纹
  final Map<String, _RenderedDocument> _rendered = <String, _RenderedDocument>{};

  /// `selectable` 槽位当前选中的内容 id（客户端在用户换样式时设置）
  final Map<String, String?> _selected = <String, String?>{};

  /// `pageBackground` 槽位当前所在路由（客户端在页面切换时设置）
  final Map<String, String> _routeOf = <String, String>{};

  /// 插件声明的槽位属主（撤销时用）
  final Map<String, String> _slotOwner = <String, String>{};

  StreamSubscription<ContentChange>? _subscription;
  bool _disposed = false;

  /// 全部内容的结果条数（自省 / 测试用）
  int get cachedEntryCount =>
      _cache.values.fold<int>(0, (int sum, Map<String, ContentEntry> m) => sum + m.length);

  /// 最近一次请求的字节数与耗时统计（自省用）
  final Map<String, int> requestCount = <String, int>{};

  // ---------- 查询 ----------

  /// 某个槽位上的内容（按 order 与注册顺序排好）
  ///
  /// `insert` 返回全部；`replace` 只返回生效的那一份（`order` 最小）；`selectable` 只返回
  /// 选中的那一份；`pageBackground` 返回当前路由命中的那一份。没有缓存的内容也会占位
  /// （`hasContent` 为 false），挂载点据此决定画不画内置界面。
  List<ContentEntry> contentsOf(String slot) {
    final Map<String, ContentEntry>? cached = _cache[slot];
    final Map<String, ContentRegistration>? registered = _registry[slot];
    final List<ContentEntry> list = <ContentEntry>[];
    if (null != registered) {
      for (final ContentRegistration reg in registered.values) {
        final ContentEntry? entry = cached?[reg.itemId];
        if (null != entry) {
          list.add(entry);
        } else {
          list.add(
            ContentEntry(
              slot: slot,
              itemId: reg.itemId,
              plugin: reg.plugin,
              id: reg.id,
              order: reg.order,
              rev: 0,
              seq: reg.seq,
            ),
          );
        }
      }
    }
    list.sort((ContentEntry a, ContentEntry b) {
      if (a.order != b.order) {
        return a.order.compareTo(b.order);
      }
      return a.seq.compareTo(b.seq);
    });
    final SlotSpec? spec = slots[slot];
    switch (spec?.kind) {
      case SlotKind.replace:
        return list.isEmpty ? list : <ContentEntry>[list.first];
      case SlotKind.selectable:
        final String? selected = _selected[slot];
        if (null == selected) {
          return const <ContentEntry>[];
        }
        return <ContentEntry>[
          for (final ContentEntry entry in list)
            if (entry.id == selected) entry,
        ];
      case SlotKind.pageBackground:
        final String route = _routeOf[slot] ?? '';
        return <ContentEntry>[
          if (_backgroundFor(list, route) case final ContentEntry entry)
            entry,
        ];
      case SlotKind.item:
      case SlotKind.insert:
      case SlotKind.page:
      case SlotKind.overlay:
      case null:
        return list;
    }
  }

  /// 页面背景的取舍：写了这个路由的优先于"所有页面"，同一优先级里**最新注册的生效**
  ContentEntry? _backgroundFor(List<ContentEntry> list, String route) {
    ContentEntry? matched;
    ContentEntry? fallback;
    for (final ContentEntry entry in list) {
      final Object? routes = _routesOf(entry.itemId);
      if (routes is List && routes.isNotEmpty) {
        if (routes.contains(route)) {
          matched = entry; // 后面注册的（顺序靠后）覆盖前面的
        }
      } else {
        fallback = entry;
      }
    }
    return matched ?? fallback;
  }

  Object? _routesOf(String itemId) => _routeMap[itemId];

  /// 页面背景项声明的路由（客户端注册内容时一起告诉 hub）
  final Map<String, Object?> _routeMap = <String, Object?>{};

  /// 设置一个页面背景内容适用的路由（空 = 所有普通页面）
  void setBackgroundRoutes(String itemId, List<String> routes) {
    _routeMap[itemId] = routes;
  }

  /// 设置某个槽位当前所在的页面路由（页面切换时调用）
  void setRoute(String slot, String route) {
    if (_routeOf[slot] == route) {
      return;
    }
    _routeOf[slot] = route;
    _invalidateSlotMemo(slot);
    _notifySlot(slot);
  }

  /// 设置可选样式槽位当前选中的内容 id
  void setSelected(String slot, String? contentId) {
    if (_selected[slot] == contentId) {
      return;
    }
    _selected[slot] = contentId;
    _invalidateSlotMemo(slot);
    _notifySlot(slot);
    if (_isActive(slot)) {
      _requestSlot(slot, onlyEffective: true);
    }
  }

  /// 某个槽位的缓存与注册（自省用）
  List<ContentRegistration> registrationsOf(String slot) =>
      _registry[slot]?.values.toList(growable: false) ?? const <ContentRegistration>[];

  /// 是否正在激活
  bool _isActive(String slot) => (_active[slot]?.isNotEmpty ?? false);

  bool isActive(String slot) => _isActive(slot);

  // ---------- 激活 ----------

  /// 激活一个槽位（挂载点 `initState` 时调用，返回的句柄 `dispose` 时取消激活）
  ///
  /// [parent] 非空表示这是 `UISlot` 渲染出来的嵌套槽位：作用域按链继承，同时做深度与循环检查
  /// （不合法时返回 `valid == false` 的句柄，调用方画 fallback）。
  SlotScope activate(
    String slot, {
    SlotScope? parent,
    Map<String, Object?> args = const <String, Object?>{},
    Map<String, Object?> values = const <String, Object?>{},
  }) {
    final SlotSpec? spec = slots[slot];
    if (null == parent && null == spec) {
      _log?.call('激活了未声明的槽位 `$slot`（按 insert 处理）');
    }
    final int depth = null == parent ? 1 : parent.depth + 1;
    final Set<String> ancestors = <String>{
      if (null != parent) ...parent.ancestors,
      if (null != parent) parent.slot,
    };
    bool valid = true;
    if (null != parent) {
      if (!parent.valid || depth > maxNesting) {
        valid = false;
        _log?.call('嵌套槽位 `$slot` 超过深度上限 $maxNesting，画 fallback');
      } else if (ancestors.contains(slot)) {
        valid = false;
        _log?.call('嵌套槽位 `$slot` 出现循环（${ancestors.join(' > ')}），画 fallback');
      } else if (null != spec && !spec.nestable) {
        valid = false;
        _log?.call('槽位 `$slot` 是 ${spec.kind.name}，不能嵌在界面里，画 fallback');
      }
    }
    final SlotScope scope = SlotScope._(
      slot: slot,
      args: args,
      values: values,
      parent: parent,
      depth: depth,
      ancestors: ancestors,
      hub: this,
      valid: valid,
    );
    if (!valid) {
      return scope;
    }
    final List<SlotScope> list = _active.putIfAbsent(slot, () => <SlotScope>[]);
    list.add(scope);
    if (list.length == 1) {
      _subscribeSlot(slot);
      // 激活总是请求一次：保证结构是最新的（显式请求，不受"同一 context 不发"限制）
      _requestSlot(slot, force: true);
    }
    return scope;
  }

  void _deactivate(SlotScope scope) {
    final List<SlotScope>? list = _active[scope.slot];
    if (null == list) {
      return;
    }
    list.remove(scope);
    if (list.isEmpty) {
      _active.remove(scope.slot);
      _unsubscribeSlot(scope.slot);
      // 取消激活保留缓存
    }
  }

  // ---------- 依赖订阅 ----------

  void _subscribeSlot(String slot) {
    final Map<String, ContentRegistration>? registered = _registry[slot];
    if (null == registered) {
      return;
    }
    for (final ContentRegistration reg in registered.values) {
      for (final String dep in reg.deps) {
        if (dep.startsWith('scope:') || dep.startsWith('plugin.')) {
          // 作用域变量由作用域自己给（激活时就有了），插件变量要订阅广播
          if (!dep.startsWith('plugin.')) {
            continue;
          }
        }
        _watchVariable(dep, slot);
      }
    }
  }

  void _unsubscribeSlot(String slot) {
    final Map<String, ContentRegistration>? registered = _registry[slot];
    if (null == registered) {
      return;
    }
    final Set<String> stillNeeded = <String>{};
    for (final MapEntry<String, Map<String, ContentRegistration>> entry in _registry.entries) {
      if (entry.key == slot || !_isActive(entry.key)) {
        continue;
      }
      for (final ContentRegistration reg in entry.value.values) {
        stillNeeded.addAll(reg.deps);
      }
    }
    for (final ContentRegistration reg in registered.values) {
      for (final String dep in reg.deps) {
        if (stillNeeded.contains(dep)) {
          continue;
        }
        _unwatchVariable(dep, slot);
      }
    }
  }

  void _watchVariable(String id, String slot) {
    final int count = (_watchCount[id] ?? 0) + 1;
    _watchCount[id] = count;
    if (count > 1) {
      return;
    }
    void onChange() => _onVariableChanged(id);
    _watchCallbacks[id] = onChange;
    variables.watch(id, onChange);
  }

  void _unwatchVariable(String id, String slot) {
    final int count = (_watchCount[id] ?? 0) - 1;
    if (count > 0) {
      _watchCount[id] = count;
      return;
    }
    _watchCount.remove(id);
    final void Function()? callback = _watchCallbacks.remove(id);
    if (null != callback) {
      variables.unwatch(id, callback);
    }
  }

  void _onVariableChanged(String id) {
    // 1) 先让绑定立刻拿到新值（用户马上看到数值 / 文案变了）
    for (final MapEntry<String, List<SlotScope>> entry in _active.entries) {
      final Set<String> deps = _depsOf(entry.key);
      if (!deps.contains(id)) {
        continue;
      }
      _invalidateSlotMemo(entry.key);
      _notifySlot(entry.key);
      // 2) 再让插件有机会改结构（串行 + 只保留最新）
      _requestSlot(entry.key);
    }
  }

  Set<String> _depsOf(String slot) {
    final Set<String> out = <String>{};
    final Map<String, ContentRegistration>? registered = _registry[slot];
    if (null == registered) {
      return out;
    }
    for (final ContentRegistration reg in registered.values) {
      out.addAll(reg.deps);
    }
    return out;
  }

  // ---------- 请求 ----------

  /// 显式要求刷新（插件调 `musicxx.ui.slot.update`，或客户端自己要重取）
  ///
  /// [ids] 是插件自己的内容短 id；不传 = 这个槽位上本插件的全部内容。
  /// 显式的刷新**总会发**（即使 context 与上一次相同），不受"同一份 context 不重复请求"限制。
  void requestUpdate(String slot, [List<String>? ids, String? plugin]) {
    _requestSlot(slot, ids: ids, plugin: plugin, force: true);
  }

  void _requestSlot(
    String slot, {
    List<String>? ids,
    String? plugin,
    bool onlyEffective = false,
    bool force = false,
  }) {
    final Map<String, ContentRegistration>? registered = _registry[slot];
    if (null == registered) {
      return;
    }
    final List<ContentEntry> effective = onlyEffective
        ? contentsOf(slot)
        : <ContentEntry>[];
    final Set<String> allowed = <String>{
      for (final ContentEntry entry in effective) entry.itemId,
    };
    for (final ContentRegistration reg in registered.values) {
      if (null != ids && !ids.contains(reg.id)) {
        continue;
      }
      if (null != plugin && reg.plugin != plugin) {
        continue;
      }
      if (onlyEffective && allowed.isNotEmpty && !allowed.contains(reg.itemId)) {
        continue;
      }
      if (!_shouldRequest(reg)) {
        continue;
      }
      _requestOne(reg, force: force);
    }
  }

  /// 只请求"会用得上"的内容：`replace` 只请求生效那份、`selectable` 只请求选中那份
  bool _shouldRequest(ContentRegistration reg) {
    final SlotSpec? spec = slots[reg.slot];
    switch (spec?.kind) {
      case SlotKind.selectable:
        return _selected[reg.slot] == reg.id;
      case SlotKind.replace:
        final List<ContentEntry> list = contentsOf(reg.slot);
        return list.isNotEmpty && list.first.itemId == reg.itemId;
      case SlotKind.item:
        return false;
      default:
        return true;
    }
  }

  void _requestOne(ContentRegistration reg, {bool force = false}) {
    final Map<String, Object?> context = _contextOf(reg);
    final _InFlight state = _inflight.putIfAbsent(reg.itemId, () => _InFlight());
    if (state.running) {
      // 在途：只记下最新一份 context（覆盖之前待发的值）
      state.pending = context;
      state.pendingForce = force || state.pendingForce;
      return;
    }
    if (!force && _sameContext(state.last, context)) {
      return;
    }
    _send(reg, context, state, force: force);
  }

  Future<void> _send(
    ContentRegistration reg,
    Map<String, Object?> context,
    _InFlight state, {
    bool force = false,
  }) async {
    state.running = true;
    state.last = context;
    state.pending = null;
    state.pendingForce = false;
    requestCount[reg.itemId] = (requestCount[reg.itemId] ?? 0) + 1;
    try {
      await transport.requestContent(
        ContentRequest(
          slot: reg.slot,
          itemId: reg.itemId,
          plugin: reg.plugin,
          id: reg.id,
          context: context,
        ),
      );
    } catch (error) {
      _log?.call('请求内容失败：${reg.itemId}（$error）');
    } finally {
      state.running = false;
    }
    if (_disposed) {
      return;
    }
    final Map<String, Object?>? pending = state.pending;
    final bool pendingForce = state.pendingForce;
    state.pending = null;
    state.pendingForce = false;
    if (null == pending) {
      return;
    }
    if (!pendingForce && _sameContext(context, pending)) {
      return;
    }
    if (reg.minIntervalMs > 0) {
      final int wait = reg.minIntervalMs;
      await Future<void>.delayed(Duration(milliseconds: wait));
      if (_disposed) {
        return;
      }
    }
    // 执行期间变了几次都只补一次，用最新那份 context
    final Map<String, Object?> latest = state.pending ?? pending;
    final bool latestForce = state.pendingForce || pendingForce;
    state.pending = null;
    state.pendingForce = false;
    if (!latestForce && _sameContext(state.last, latest)) {
      return;
    }
    final Map<String, ContentRegistration>? registered = _registry[reg.slot];
    final ContentRegistration? current = registered?[reg.itemId];
    if (null == current) {
      return;
    }
    await _send(current, latest, state, force: latestForce);
  }

  Map<String, Object?> _contextOf(ContentRegistration reg) {
    final SlotScope? scope = _scopeOf(reg.slot);
    final Map<String, Object?> context = <String, Object?>{};
    for (final String dep in reg.deps) {
      context[dep] = variables.read(dep, scope);
    }
    return context;
  }

  SlotScope? _scopeOf(String slot) {
    final List<SlotScope>? list = _active[slot];
    return (null == list || list.isEmpty) ? null : list.last;
  }

  static bool _sameContext(Map<String, Object?>? a, Map<String, Object?>? b) {
    if (identical(a, b)) {
      return true;
    }
    if (null == a || null == b) {
      return false;
    }
    return _signatureOf(a) == _signatureOf(b);
  }

  static String _signatureOf(Map<String, Object?> values) {
    final List<String> keys = values.keys.toList()..sort();
    try {
      return jsonEncode(<String, Object?>{
        for (final String key in keys) key: values[key],
      });
    } catch (_) {
      return keys.map((String key) => '$key=${values[key]}').join('|');
    }
  }

  // ---------- 渲染 ----------

  /// 把一条内容变成可渲染的文档（绑定 + 解析 + 适配，按 `(rev, 变量值)` 记忆化）
  ///
  /// 变量变了只重算绑定与适配，**不再请求插件**；没有内容时返回 null（调用方画 fallback）。
  UiDocument? renderDocument(ContentEntry entry, SlotScope scope) {
    final Object? json = entry.json;
    if (!entry.hasContent || null == json) {
      return null;
    }
    final ContentRegistration? reg = _registry[entry.slot]?[entry.itemId];
    final Map<String, Object?> values = _valuesFor(reg, entry, scope);
    final String fingerprint = '${entry.rev}|${_signatureOf(values)}';
    final _RenderedDocument? cached = _rendered[entry.itemId];
    if (null != cached && cached.fingerprint == fingerprint) {
      return cached.document;
    }
    final List<String> missing = <String>[];
    UiDocument? document;
    try {
      document = pipeline.render(
        json: json,
        values: values,
        scope: scope,
        missing: missing,
      );
    } catch (error) {
      _log?.call('内容解析失败：${entry.itemId}（$error）');
      return cached?.document;
    }
    if (missing.isNotEmpty) {
      _log?.call('内容 ${entry.itemId} 缺变量：${missing.join(', ')}');
    }
    _rendered[entry.itemId] = _RenderedDocument(fingerprint, document);
    return document;
  }

  Map<String, Object?> _valuesFor(
    ContentRegistration? reg,
    ContentEntry entry,
    SlotScope scope,
  ) {
    final Map<String, Object?> values = <String, Object?>{};
    final List<String> deps = reg?.deps ?? const <String>[];
    for (final String dep in deps) {
      values[dep] = variables.read(dep, scope);
    }
    return values;
  }

  /// 一条内容当前这套变量值（自省 / 排障用）
  Map<String, Object?> valuesOf(ContentEntry entry, SlotScope? scope) {
    final ContentRegistration? reg = _registry[entry.slot]?[entry.itemId];
    return _valuesFor(reg, entry, scope ?? _scopeOf(entry.slot) ?? _emptyScope);
  }

  late final SlotScope _emptyScope = SlotScope._(
    slot: '',
    args: const <String, Object?>{},
    values: const <String, Object?>{},
    parent: null,
    depth: 0,
    ancestors: const <String>{},
  );

  void _invalidateSlotMemo(String slot) {
    final Set<String> ids = <String>{
      ...?_registry[slot]?.keys,
      ...?_cache[slot]?.keys,
    };
    for (final String id in ids) {
      _rendered.remove(id);
    }
  }

  // ---------- 变化 ----------

  /// 处理一条变化（传输层把插件框架的事件交过来）
  void applyChange(ContentChange change) {
    switch (change) {
      case ContentRegistered(:final ContentRegistration registration):
        _applyRegistered(registration);
      case ContentUnregistered(:final String slot, :final String itemId):
        _registry[slot]?.remove(itemId);
        _cache[slot]?.remove(itemId);
        _rendered.remove(itemId);
        _inflight.remove(itemId);
        _notifySlot(slot);
      case ContentResultChange():
        _applyResult(change);
      case SlotDeclared(:final SlotSpec spec):
        slots.put(spec);
        if (spec.owner.isNotEmpty) {
          _slotOwner[spec.id] = spec.owner;
        }
      case SlotRevoked(:final String slot):
        _dropSlotContents(slot);
        slots.remove(slot);
        _slotOwner.remove(slot);
      case PluginDetached(:final String plugin):
        _detachPlugin(plugin);
      case AllDetached():
        _detachAll();
    }
  }

  void _applyRegistered(ContentRegistration reg) {
    final Map<String, ContentRegistration> map = _registry.putIfAbsent(
      reg.slot,
      () => <String, ContentRegistration>{},
    );
    final ContentRegistration? previous = map[reg.itemId];
    map[reg.itemId] = reg;
    if (null != previous) {
      // 覆盖这一条：deps / order 都换了，内容等下一次请求或推送
      if (previous.order != reg.order || previous.itemId == reg.itemId) {
        _cache[reg.slot]?.putIfAbsent(
          reg.itemId,
          () => ContentEntry(
            slot: reg.slot,
            itemId: reg.itemId,
            plugin: reg.plugin,
            id: reg.id,
            order: reg.order,
            rev: 0,
            seq: reg.seq,
          ),
        );
      }
      _rendered.remove(reg.itemId);
    }
    if (_isActive(reg.slot)) {
      if (map.length == 1) {
        _subscribeSlot(reg.slot);
      } else {
        for (final String dep in reg.deps) {
          if (dep.startsWith('plugin.')) {
            _watchVariable(dep, reg.slot);
          }
        }
      }
      if (_shouldRequest(reg)) {
        _requestOne(reg, force: true);
      }
    }
    _notifySlot(reg.slot);
  }

  void _applyResult(ContentChange change) {
    final ContentResultChange result = change as ContentResultChange;
    final Map<String, ContentEntry> cached = _cache.putIfAbsent(
      result.slot,
      () => <String, ContentEntry>{},
    );
    final ContentEntry? previous = cached[result.itemId];
    final ContentRegistration? reg = _registry[result.slot]?[result.itemId];
    final String error = result.error ?? '';
    if (error.isNotEmpty) {
      // 失败：保留上一次有效内容，只记原因（同一内容成功后清空）
      final ContentEntry entry = (previous ??
              ContentEntry(
                slot: result.slot,
                itemId: result.itemId,
                plugin: reg?.plugin ?? '',
                id: reg?.id ?? '',
                order: reg?.order ?? 0,
                rev: result.rev,
              ))
          .copyWith(lastError: error);
      cached[result.itemId] = entry;
      _log?.call('生成内容失败：${result.itemId}（$error）');
      _notifySlot(result.slot);
      return;
    }
    if (null != previous && result.rev < previous.rev) {
      // 过期结果：丢掉
      return;
    }
    final ContentEntry entry = ContentEntry(
      slot: result.slot,
      itemId: result.itemId,
      plugin: reg?.plugin ?? '',
      id: reg?.id ?? '',
      order: reg?.order ?? 0,
      rev: result.rev,
      json: result.json,
      data: result.data,
      updatedAt: DateTime.now(),
      bytes: _bytesOf(result.json),
      seq: reg?.seq ?? 0,
    );
    cached[result.itemId] = entry;
    _rendered.remove(result.itemId);
    _notifySlot(result.slot);
  }

  static int _bytesOf(Object? json) {
    if (null == json) {
      return 0;
    }
    try {
      return utf8.encode(jsonEncode(json)).length;
    } catch (_) {
      return 0;
    }
  }

  void _dropSlotContents(String slot) {
    _registry.remove(slot);
    _cache.remove(slot);
    for (final String id in _rendered.keys.toList()) {
      if (id.startsWith('plugin.') && _registry.isEmpty) {
        _rendered.remove(id);
      }
    }
    _rendered.removeWhere((String id, _) => !_registry.values.any(
      (Map<String, ContentRegistration> map) => map.containsKey(id),
    ));
    _selected.remove(slot);
    _notifySlot(slot);
  }

  void _detachPlugin(String plugin) {
    final List<String> slotIds = <String>[
      for (final MapEntry<String, Map<String, ContentRegistration>> entry in _registry.entries)
        if (entry.value.values.any((ContentRegistration reg) => reg.plugin == plugin))
          entry.key,
    ];
    for (final String slot in slotIds) {
      _registry[slot]?.removeWhere((String _, ContentRegistration reg) => reg.plugin == plugin);
      _cache[slot]?.removeWhere((String _, ContentEntry entry) => entry.plugin == plugin);
      if (_registry[slot]?.isEmpty ?? false) {
        _registry.remove(slot);
        _cache.remove(slot);
      }
      _notifySlot(slot);
    }
    _rendered.removeWhere((String id, _) => id.startsWith('plugin.$plugin.'));
    _inflight.removeWhere((String id, _) => id.startsWith('plugin.$plugin.'));
    slots.removeOwnedBy(plugin);
    _slotOwner.removeWhere((String _, String owner) => owner == plugin);
    for (final String id in _watchCount.keys.toList()) {
      if (id.startsWith('plugin.$plugin.')) {
        _unwatchVariable(id, '');
      }
    }
  }

  void _detachAll() {
    final Set<String> slotIds = <String>{..._registry.keys, ..._cache.keys};
    _registry.clear();
    _cache.clear();
    _rendered.clear();
    _inflight.clear();
    _selected.clear();
    for (final String id in _watchCount.keys.toList()) {
      _unwatchVariable(id, '');
    }
    for (final String slot in slotIds) {
      _notifySlot(slot);
    }
    slots.removeOwnedBy('');
    for (final SlotSpec spec in slots.pluginDeclared.toList()) {
      slots.remove(spec.id);
    }
    _slotOwner.clear();
  }

  void _onSlotsChanged() {
    // 槽位表变了：引用它的内容重画（UISlot 会画 fallback）
    for (final String slot in _active.keys.toList()) {
      _notifySlot(slot);
    }
  }

  // ---------- 监听 ----------

  void addSlotListener(String slot, void Function() listener) {
    _slotListeners.putIfAbsent(slot, () => <void Function()>[]).add(listener);
  }

  void removeSlotListener(String slot, void Function() listener) {
    _slotListeners[slot]?.remove(listener);
  }

  void _notifySlot(String slot) {
    final List<void Function()>? listeners = _slotListeners[slot];
    if (null == listeners) {
      return;
    }
    for (final void Function() listener in List<void Function()>.of(listeners)) {
      listener();
    }
  }

  /// 释放（客户端关掉『拟声++』或退出时调用）
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
    slots.removeListener(_onSlotsChanged);
    for (final MapEntry<String, void Function()> entry in _watchCallbacks.entries) {
      variables.unwatch(entry.key, entry.value);
    }
    _watchCallbacks.clear();
    _watchCount.clear();
    _registry.clear();
    _cache.clear();
    _rendered.clear();
    _inflight.clear();
    _active.clear();
    _slotListeners.clear();
  }
}

/// 一条内容的在途请求状态
class _InFlight {
  bool running = false;

  /// 在途请求用的 context
  Map<String, Object?>? last;

  /// 待发的 context（只保留最新一份）
  Map<String, Object?>? pending;

  /// 待发的那一次是不是显式刷新（显式刷新不受"同一份 context 不发"限制）
  bool pendingForce = false;
}

/// 渲染记忆化的条目
class _RenderedDocument {
  const _RenderedDocument(this.fingerprint, this.document);

  final String fingerprint;
  final UiDocument? document;
}

/// 计算一个槽位里最大的 `order`（自省 / 测试用）
int maxOrderOf(Iterable<ContentEntry> entries) => entries.fold<int>(
  0,
  (int value, ContentEntry entry) => math.max(value, entry.order),
);
