import 'dart:async';

import 'package:pluginxx_ui/pluginxx_ui.dart';
import 'package:test/test.dart';

class _FakeTransport implements ContentTransport {
  final StreamController<ContentChange> controller =
      StreamController<ContentChange>.broadcast();
  final List<ContentRequest> requests = <ContentRequest>[];

  /// 非空时请求挂起，等测试放行
  Completer<void>? gate;

  @override
  Stream<ContentChange> get changes => controller.stream;

  @override
  Future<void> requestContent(ContentRequest request) async {
    requests.add(request);
    final Completer<void>? g = gate;
    if (null != g) {
      await g.future;
    }
  }

  void emit(ContentChange change) => controller.add(change);
}

class _FakeVariables implements VariableReader {
  final Map<String, Object?> values = <String, Object?>{};
  final Map<String, List<void Function()>> watchers =
      <String, List<void Function()>>{};

  @override
  Object? read(String id, SlotScope? scope) {
    if (id.startsWith('scope:')) {
      return scope?.read(id);
    }
    return values[id];
  }

  @override
  void watch(String id, void Function() onChange) {
    watchers.putIfAbsent(id, () => <void Function()>[]).add(onChange);
  }

  @override
  void unwatch(String id, void Function() onChange) {
    watchers[id]?.remove(onChange);
  }

  void set(String id, Object? value) {
    values[id] = value;
    for (final void Function() callback in List<void Function()>.of(
      watchers[id] ?? const <void Function()>[],
    )) {
      callback();
    }
  }
}

/// 内容结果里的 JSON：一份最简单的界面
Map<String, Object?> _doc(String text) => <String, Object?>{
  'blocks': <Object?>[
    <String, Object?>{'kind': 'Text', 'text': text},
  ],
};

void main() {
  group('内容运行时', () {
    late SlotCatalogue slots;
    late _FakeTransport transport;
    late _FakeVariables variables;
    late ContentHub hub;

    setUp(() {
      slots = SlotCatalogue(
        specs: <SlotSpec>[
          const SlotSpec(id: 'slot.insert', kind: SlotKind.insert),
          const SlotSpec(id: 'slot.replace', kind: SlotKind.replace),
          const SlotSpec(id: 'slot.select', kind: SlotKind.selectable),
        ],
      );
      transport = _FakeTransport();
      variables = _FakeVariables();
      hub = ContentHub(
        slots: slots,
        variables: variables,
        transport: transport,
        log: (String message) {},
      );
    });

    tearDown(() {
      hub.dispose();
      transport.controller.close();
    });

    test('激活即请求一次，结果进缓存，多份按 order 排', () async {
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row2',
            plugin: 'a',
            id: 'row2',
            order: 20,
            seq: 2,
          ),
        ),
      );
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row1',
            plugin: 'a',
            id: 'row1',
            order: 10,
            seq: 1,
          ),
        ),
      );
      final SlotScope scope = hub.activate('slot.insert');
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests.length, 2);
      expect(
        <String>[for (final ContentRequest r in transport.requests) r.itemId],
        containsAll(<String>['plugin.a.row1', 'plugin.a.row2']),
      );

      transport.emit(
        ContentResultChange(
          slot: 'slot.insert',
          itemId: 'plugin.a.row2',
          rev: 1,
          json: <String, Object?>{
            'blocks': <Object?>[
              <String, Object?>{'kind': 'Text', 'text': '第二行'},
            ],
          },
        ),
      );
      transport.emit(
        ContentResultChange(
          slot: 'slot.insert',
          itemId: 'plugin.a.row1',
          rev: 1,
          json: <String, Object?>{
            'blocks': <Object?>[
              <String, Object?>{'kind': 'Text', 'text': '第一行'},
            ],
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final List<ContentEntry> entries = hub.contentsOf('slot.insert');
      expect(<String>[for (final ContentEntry e in entries) e.id], <String>['row1', 'row2']);
      final UiDocument? document = hub.renderDocument(entries.first, scope);
      expect(document, isNotNull);
      expect(document!.blocks.first.text.fallback, '第一行');
      scope.dispose();
    });

    test('执行期间变量变了几次，只补一次最新 context', () async {
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row',
            plugin: 'a',
            id: 'row',
            deps: <String>['musicxx.song.name'],
          ),
        ),
      );
      variables.set('musicxx.song.name', '第一首');
      final Completer<void> gate = Completer<void>();
      transport.gate = gate;
      final SlotScope scope = hub.activate('slot.insert');
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests.length, 1);
      expect(transport.requests.first.context['musicxx.song.name'], '第一首');

      // 在途期间变三次
      variables.set('musicxx.song.name', '第二首');
      variables.set('musicxx.song.name', '第三首');
      variables.set('musicxx.song.name', '第四首');
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests.length, 1, reason: '在途时不再发新请求');

      // 放行：执行完立刻补一次，用最新那份
      transport.gate = null;
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests.length, 2);
      expect(transport.requests.last.context['musicxx.song.name'], '第四首');
      scope.dispose();
    });

    test('失败保留上一次有效内容，成功后清掉原因', () async {
      const ContentRegistration reg = ContentRegistration(
        slot: 'slot.insert',
        itemId: 'plugin.a.row',
        plugin: 'a',
        id: 'row',
      );
      transport.emit(const ContentRegistered(reg));
      final SlotScope scope = hub.activate('slot.insert');
      await Future<void>.delayed(Duration.zero);
      transport.emit(
        ContentResultChange(slot: 'slot.insert', itemId: reg.itemId, rev: 1, json: _doc('好的')),
      );
      await Future<void>.delayed(Duration.zero);
      transport.emit(
        ContentResultChange(
          slot: 'slot.insert',
          itemId: 'plugin.a.row',
          rev: 2,
          error: '生成函数抛异常',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      ContentEntry entry = hub.contentsOf('slot.insert').single;
      expect(entry.hasContent, isTrue);
      expect(entry.lastError, '生成函数抛异常');
      expect(entry.rev, 1);

      transport.emit(
        ContentResultChange(slot: 'slot.insert', itemId: reg.itemId, rev: 3, json: _doc('又好了')),
      );
      await Future<void>.delayed(Duration.zero);
      entry = hub.contentsOf('slot.insert').single;
      expect(entry.lastError, isNull);
      expect(entry.rev, 3);
      scope.dispose();
    });

    test('过期的 rev 丢掉', () async {
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row',
            plugin: 'a',
            id: 'row',
          ),
        ),
      );
      final SlotScope scope = hub.activate('slot.insert');
      await Future<void>.delayed(Duration.zero);
      transport.emit(
        ContentResultChange(
          slot: 'slot.insert',
          itemId: 'plugin.a.row',
          rev: 5,
          json: <String, Object?>{'blocks': <Object?>[]},
        ),
      );
      transport.emit(
        ContentResultChange(
          slot: 'slot.insert',
          itemId: 'plugin.a.row',
          rev: 4,
          json: <String, Object?>{'blocks': <Object?>[]},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(hub.contentsOf('slot.insert').single.rev, 5);
      scope.dispose();
    });

    test('按 id 要求刷新只影响指定那一条', () async {
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row1',
            plugin: 'a',
            id: 'row1',
          ),
        ),
      );
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row2',
            plugin: 'a',
            id: 'row2',
          ),
        ),
      );
      final SlotScope scope = hub.activate('slot.insert');
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests.length, 2);
      hub.requestUpdate('slot.insert', <String>['row2'], 'a');
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests.length, 3);
      expect(transport.requests.last.id, 'row2');
      scope.dispose();
    });

    test('replace 只请求生效那份（order 最小）', () async {
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.replace',
            itemId: 'plugin.a.late',
            plugin: 'a',
            id: 'late',
            order: 20,
          ),
        ),
      );
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.replace',
            itemId: 'plugin.a.first',
            plugin: 'a',
            id: 'first',
            order: 10,
          ),
        ),
      );
      // 注册事件是异步投递的：等它们进注册表再激活
      await Future<void>.delayed(Duration.zero);
      final SlotScope scope = hub.activate('slot.replace');
      await Future<void>.delayed(Duration.zero);
      expect(<String>[for (final ContentRequest r in transport.requests) r.id], <String>['first']);
      expect(hub.contentsOf('slot.replace').length, 1);
      scope.dispose();
    });

    test('selectable 只渲染选中那份', () async {
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.select',
            itemId: 'plugin.a.s1',
            plugin: 'a',
            id: 's1',
          ),
        ),
      );
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.select',
            itemId: 'plugin.a.s2',
            plugin: 'a',
            id: 's2',
          ),
        ),
      );
      final SlotScope scope = hub.activate('slot.select');
      await Future<void>.delayed(Duration.zero);
      expect(hub.contentsOf('slot.select'), isEmpty, reason: '还没选');

      hub.setSelected('slot.select', 's2');
      await Future<void>.delayed(Duration.zero);
      expect(<String>[for (final ContentEntry e in hub.contentsOf('slot.select')) e.id], <String>['s2']);
      expect(<String>[for (final ContentRequest r in transport.requests) r.id], <String>['s2']);
      scope.dispose();
    });

    test('嵌套：深度上限与循环都返回不可用的作用域', () {
      const SlotSpec pluginSlot = SlotSpec(
        id: 'plugin.a.ui.nested',
        kind: SlotKind.insert,
        owner: 'a',
      );
      slots.put(pluginSlot);
      final SlotScope root = hub.activate('slot.insert');
      final SlotScope child = hub.activate('plugin.a.ui.nested', parent: root);
      expect(child.valid, isTrue);
      final SlotScope again = hub.activate('plugin.a.ui.nested', parent: child);
      expect(again.valid, isFalse, reason: '祖先链里已经有了');
      // 深度：root(1) → nested(2) → l2(3) → l3(4) → l4(5) 不合法
      SlotScope deep = child;
      slots.put(
        const SlotSpec(id: 'plugin.a.ui.l2', kind: SlotKind.insert, owner: 'a'),
      );
      slots.put(
        const SlotSpec(id: 'plugin.a.ui.l3', kind: SlotKind.insert, owner: 'a'),
      );
      slots.put(
        const SlotSpec(id: 'plugin.a.ui.l4', kind: SlotKind.insert, owner: 'a'),
      );
      for (int i = 2; i <= 3; i++) {
        deep = hub.activate('plugin.a.ui.l$i', parent: deep);
        expect(deep.valid, isTrue, reason: '第 $i 层（深度 ${deep.depth}）');
      }
      final SlotScope tooDeep = hub.activate('plugin.a.ui.l4', parent: deep);
      expect(tooDeep.valid, isFalse);
      expect(tooDeep.depth, 5);
      root.dispose();
      child.dispose();
    });

    test('作用域变量通过作用域链读，嵌套也能读到外层的', () async {
      slots.put(
        const SlotSpec(
          id: 'plugin.a.ui.inner',
          kind: SlotKind.insert,
          owner: 'a',
        ),
      );
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row',
            plugin: 'a',
            id: 'row',
            deps: <String>['scope:musicxx.songlist.name', 'scope:musicxx.slot.args'],
          ),
        ),
      );
      final SlotScope root = hub.activate(
        'slot.insert',
        values: <String, Object?>{'scope:musicxx.songlist.name': '我的歌单'},
      );
      final SlotScope inner = hub.activate(
        'plugin.a.ui.inner',
        parent: root,
        args: <String, Object?>{'rowId': 'abc'},
      );
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'plugin.a.ui.inner',
            itemId: 'plugin.b.extra',
            plugin: 'b',
            id: 'extra',
            deps: <String>['scope:musicxx.songlist.name', 'scope:musicxx.slot.args'],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final ContentRequest request = transport.requests.last;
      expect(request.itemId, 'plugin.b.extra');
      expect(request.context['scope:musicxx.songlist.name'], '我的歌单');
      expect(
        request.context['scope:musicxx.slot.args'],
        <String, Object?>{'rowId': 'abc'},
      );
      root.dispose();
      inner.dispose();
    });

    test('变量变化：重渲染用新值，并且再请求一次结构', () async {
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row',
            plugin: 'a',
            id: 'row',
            deps: <String>['musicxx.song.name'],
          ),
        ),
      );
      variables.set('musicxx.song.name', '第一首');
      final SlotScope scope = hub.activate('slot.insert');
      await Future<void>.delayed(Duration.zero);
      transport.emit(
        ContentResultChange(
          slot: 'slot.insert',
          itemId: 'plugin.a.row',
          rev: 1,
          json: <String, Object?>{
            'blocks': <Object?>[
              <String, Object?>{
                'kind': 'Text',
                'text': '{musicxx.song.name}',
              },
            ],
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      ContentEntry entry = hub.contentsOf('slot.insert').single;
      expect(hub.renderDocument(entry, scope)!.blocks.first.text.fallback, '第一首');

      variables.set('musicxx.song.name', '第二首');
      await Future<void>.delayed(Duration.zero);
      entry = hub.contentsOf('slot.insert').single;
      expect(entry.rev, 1, reason: '变量变化不改 rev');
      expect(hub.renderDocument(entry, scope)!.blocks.first.text.fallback, '第二首');
      expect(transport.requests.length, 2, reason: '同时请求了一次新的结构');
      expect(transport.requests.last.context['musicxx.song.name'], '第二首');
      scope.dispose();
    });

    test('注销一条内容不影响同槽位的其它内容', () async {
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row1',
            plugin: 'a',
            id: 'row1',
          ),
        ),
      );
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row2',
            plugin: 'a',
            id: 'row2',
          ),
        ),
      );
      final SlotScope scope = hub.activate('slot.insert');
      await Future<void>.delayed(Duration.zero);
      transport.emit(
        ContentResultChange(
          slot: 'slot.insert',
          itemId: 'plugin.a.row1',
          rev: 1,
          json: <String, Object?>{'blocks': <Object?>[]},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      transport.emit(
        const ContentUnregistered(slot: 'slot.insert', itemId: 'plugin.a.row1'),
      );
      await Future<void>.delayed(Duration.zero);
      final List<ContentEntry> entries = hub.contentsOf('slot.insert');
      expect(entries.length, 1);
      expect(entries.single.id, 'row2');
      scope.dispose();
    });

    test('插件卸载清掉它的内容与槽位', () async {
      transport.emit(
        const SlotDeclared(
          SlotSpec(id: 'plugin.a.ui.nested', kind: SlotKind.insert, owner: 'a'),
        ),
      );
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row',
            plugin: 'a',
            id: 'row',
          ),
        ),
      );
      final SlotScope scope = hub.activate('slot.insert');
      await Future<void>.delayed(Duration.zero);
      transport.emit(const PluginDetached('a'));
      await Future<void>.delayed(Duration.zero);
      expect(hub.contentsOf('slot.insert'), isEmpty);
      expect(slots.contains('plugin.a.ui.nested'), isFalse);
      scope.dispose();
    });

    test('取消激活保留缓存，重新激活复用', () async {
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row',
            plugin: 'a',
            id: 'row',
          ),
        ),
      );
      final SlotScope first = hub.activate('slot.insert');
      await Future<void>.delayed(Duration.zero);
      transport.emit(
        ContentResultChange(
          slot: 'slot.insert',
          itemId: 'plugin.a.row',
          rev: 1,
          json: <String, Object?>{'blocks': <Object?>[]},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      first.dispose();
      expect(hub.isActive('slot.insert'), isFalse);
      expect(hub.contentsOf('slot.insert').single.hasContent, isTrue);
      final SlotScope second = hub.activate('slot.insert');
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests.length, 2, reason: '激活总是请求一次');
      second.dispose();
    });

    test('页面背景按路由取舍：写了路由的优先，同一优先级最新注册的生效', () async {
      slots.put(
        const SlotSpec(id: 'slot.bg', kind: SlotKind.pageBackground),
      );
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.bg',
            itemId: 'plugin.a.all',
            plugin: 'a',
            id: 'all',
            seq: 1,
          ),
        ),
      );
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.bg',
            itemId: 'plugin.a.songs',
            plugin: 'a',
            id: 'songs',
            seq: 2,
          ),
        ),
      );
      hub.setBackgroundRoutes('plugin.a.all', <String>[]);
      hub.setBackgroundRoutes('plugin.a.songs', <String>['/songs']);
      hub.setRoute('slot.bg', '/songs');
      final SlotScope scope = hub.activate('slot.bg');
      await Future<void>.delayed(Duration.zero);
      expect(hub.contentsOf('slot.bg').single.id, 'songs');
      hub.setRoute('slot.bg', '/setting');
      expect(hub.contentsOf('slot.bg').single.id, 'all');
      scope.dispose();
    });

    test('只关心指定内容：只请求那一份，其它那份的变量不订阅', () async {
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row1',
            plugin: 'a',
            id: 'row1',
            deps: <String>['musicxx.player.title'],
            seq: 1,
          ),
        ),
      );
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row2',
            plugin: 'a',
            id: 'row2',
            deps: <String>['musicxx.player.artist'],
            seq: 2,
          ),
        ),
      );
      final SlotScope scope = hub.activate(
        'slot.insert',
        ids: <String>['row2'],
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        <String>[for (final ContentRequest r in transport.requests) r.itemId],
        <String>['plugin.a.row2'],
      );
      expect(
        hub.registrationsOf('slot.insert').length,
        2,
        reason: '注册表照样有两份，只是没请求另一份',
      );
      expect(scope.onlyIds, <String>{'row2'});

      final int before = transport.requests.length;
      variables.set('musicxx.player.title', '别的歌');
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests.length, before, reason: '没要的那一份的变量不订阅');

      variables.set('musicxx.player.artist', '新歌手');
      await Future<void>.delayed(Duration.zero);
      expect(
        <String>[
          for (final ContentRequest r in transport.requests.skip(before))
            r.itemId,
        ],
        <String>['plugin.a.row2'],
      );
      scope.dispose();
    });

    test('同一个槽位先后两个挂载点各要一份：两份都会被请求', () async {
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row1',
            plugin: 'a',
            id: 'row1',
            seq: 1,
          ),
        ),
      );
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row2',
            plugin: 'a',
            id: 'row2',
            seq: 2,
          ),
        ),
      );
      final SlotScope first = hub.activate(
        'slot.insert',
        ids: <String>['row1'],
      );
      await Future<void>.delayed(Duration.zero);
      final SlotScope second = hub.activate(
        'slot.insert',
        ids: <String>['row2'],
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        <String>[for (final ContentRequest r in transport.requests) r.itemId],
        containsAll(<String>['plugin.a.row1', 'plugin.a.row2']),
      );
      first.dispose();
      second.dispose();
    });

    test('退订只退自己订阅过的变量，别的槽位还在用的照旧收到通知', () async {
      slots.put(const SlotSpec(id: 'slot.other', kind: SlotKind.insert));
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row',
            plugin: 'a',
            id: 'row',
            deps: <String>['musicxx.player.title'],
          ),
        ),
      );
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.other',
            itemId: 'plugin.a.other',
            plugin: 'a',
            id: 'other',
            deps: <String>['musicxx.player.title'],
          ),
        ),
      );
      final SlotScope first = hub.activate('slot.insert');
      final SlotScope second = hub.activate('slot.other');
      await Future<void>.delayed(Duration.zero);

      first.dispose();
      final int before = transport.requests.length;
      variables.set('musicxx.player.title', '第一首');
      await Future<void>.delayed(Duration.zero);
      expect(
        <String>[
          for (final ContentRequest r in transport.requests.skip(before))
            r.itemId,
        ],
        <String>['plugin.a.other'],
        reason: '同一个变量别的槽位还在用，退订不能把它撤掉',
      );

      second.dispose();
      final int after = transport.requests.length;
      variables.set('musicxx.player.title', '第二首');
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests.length, after, reason: '都取消激活了，不再订阅变量');
    });

    test('entryOf / registrationOf 按 id 取，title 与 depict 原样保留', () async {
      transport.emit(
        const ContentRegistered(
          ContentRegistration(
            slot: 'slot.insert',
            itemId: 'plugin.a.row',
            plugin: 'a',
            id: 'row',
            title: '歌曲信息',
            depict: '在歌曲操作里加一行',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(hub.registrationOf('slot.insert', 'row')?.title, '歌曲信息');
      expect(
        hub.registrationOf('slot.insert', 'row')?.depict,
        '在歌曲操作里加一行',
      );
      expect(hub.registrationOf('slot.insert', 'nope'), isNull);
      expect(hub.entryOf('slot.insert', 'row')?.itemId, 'plugin.a.row');
      expect(hub.entryOf('slot.insert', 'nope'), isNull);
    });
  });
}

