import 'package:pluginxx_ui/pluginxx_ui.dart';
import 'package:test/test.dart';

void main() {
  group('槽位表', () {
    test('查表、插件声明与撤销', () {
      final SlotCatalogue catalogue = SlotCatalogue(
        specs: const <SlotSpec>[
          SlotSpec(id: 'musicxx.ui.playing.lyric.top', kind: SlotKind.insert),
          SlotSpec(
            id: 'musicxx.ui.playing.background',
            kind: SlotKind.selectable,
            variables: <String>['scope:musicxx.slot.colorMain'],
          ),
        ],
      );
      expect(catalogue['musicxx.ui.playing.lyric.top']?.kind, SlotKind.insert);
      expect(
        catalogue['musicxx.ui.playing.background']?.hasVariable(
          'scope:musicxx.slot.colorMain',
        ),
        isTrue,
      );

      int notified = 0;
      void listener() => notified++;
      catalogue.addListener(listener);
      catalogue.put(
        const SlotSpec(
          id: 'plugin.a.ui.toolbar',
          kind: SlotKind.insert,
          owner: 'a',
        ),
      );
      expect(notified, 1);
      expect(catalogue.pluginDeclared.length, 1);
      expect(catalogue.remove('plugin.a.ui.toolbar'), isTrue);
      expect(notified, 2);
      catalogue.removeListener(listener);

      catalogue.put(
        const SlotSpec(id: 'plugin.a.ui.x', kind: SlotKind.replace, owner: 'a'),
      );
      catalogue.put(
        const SlotSpec(id: 'plugin.a.ui.y', kind: SlotKind.insert, owner: 'a'),
      );
      catalogue.removeOwnedBy('a');
      expect(catalogue.contains('plugin.a.ui.x'), isFalse);
      expect(catalogue.contains('plugin.a.ui.y'), isFalse);
    });

    test('只有 insert / replace 能嵌进界面', () {
      const SlotSpec insert = SlotSpec(id: 'a', kind: SlotKind.insert);
      const SlotSpec replace = SlotSpec(id: 'b', kind: SlotKind.replace);
      const SlotSpec page = SlotSpec(id: 'c', kind: SlotKind.page);
      const SlotSpec select = SlotSpec(id: 'd', kind: SlotKind.selectable);
      expect(insert.nestable, isTrue);
      expect(replace.nestable, isTrue);
      expect(page.nestable, isFalse);
      expect(select.nestable, isFalse);
    });

    test('形态名解析忽略大小写', () {
      expect(slotKindOf('Insert'), SlotKind.insert);
      expect(slotKindOf('pagebackground'), SlotKind.pageBackground);
      expect(slotKindOf('nope'), isNull);
    });
  });

  group('可选样式的候选与选择', () {
    test('按内置优先、order 与注册顺序排', () {
      final SlotChoice choice = SlotChoice(slot: 's');
      choice.put(
        const SlotChoiceEntry(id: 'plugin.a.x', order: 20, seq: 2),
      );
      choice.put(
        const SlotChoiceEntry(id: 'plugin.a.y', order: 10, seq: 3),
      );
      choice.put(
        const SlotChoiceEntry(id: 'musicxx.circle', builtin: true, order: 99),
      );
      expect(
        <String>[for (final SlotChoiceEntry e in choice.entries) e.id],
        <String>['musicxx.circle', 'plugin.a.y', 'plugin.a.x'],
      );
    });

    test('换选择记下上一个；撤销选中项回到默认', () {
      final SlotChoice choice = SlotChoice(slot: 's');
      choice.put(const SlotChoiceEntry(id: 'a'));
      choice.put(const SlotChoiceEntry(id: 'b'));
      choice.select('a');
      expect(choice.current, 'a');
      choice.select('b');
      expect(choice.previous, 'a');
      expect(choice.selectPrevious(), isTrue);
      expect(choice.current, 'a');
      expect(choice.previous, isNull);

      choice.select('b');
      choice.remove('b');
      expect(choice.current, isNull);
      expect(choice.previous, 'b');
      expect(choice.hasValidCurrent, isTrue);
      // 被撤销的候选不在了，"交还控制权"也回不去
      expect(choice.selectPrevious(), isFalse);
      expect(choice.current, isNull);
    });
  });

  group('UISlot 块', () {
    test('解析 slot / args / fallback，并往返', () {
      final ItemData item = parseBlock(<String, Object?>{
        'kind': 'UISlot',
        'slot': 'playing.lyric.top',
        'args': <String, Object?>{'rowId': 'abc'},
        'fallback': <String, Object?>{'kind': 'Text', 'text': '（没有内容）'},
      });
      expect(item.kind, 'UISlot');
      expect(item.slot, 'playing.lyric.top');
      expect(item.slotArgs, <String, Object?>{'rowId': 'abc'});
      expect(item.slotFallback?.kind, 'Text');
      expect(item.slotFallback?.text.fallback, '（没有内容）');

      final Map<String, Object?> dumped = dumpItem(item);
      expect(dumped['slot'], 'playing.lyric.top');
      expect(dumped['args'], <String, Object?>{'rowId': 'abc'});
      expect(
        (dumped['fallback']! as Map<String, Object?>)['text'],
        '（没有内容）',
      );
    });

    test('没有 slot 时记一条提示但不抛异常', () {
      final ParseReport report = ParseReport();
      final ItemData item = parseBlock(
        <String, Object?>{'kind': 'UISlot'},
        report: report,
      );
      expect(item.slot, isEmpty);
      expect(report.warnings.join(' '), contains('slot'));
    });

    test('不适配时就地跳过（fallback 由纯文本渲染）', () {
      final ItemData item = parseBlock(<String, Object?>{
        'kind': 'UISlot',
        'slot': 'musicxx.ui.playing.lyric.top',
        'fallback': <String, Object?>{'kind': 'Text', 'text': '（没有内容）'},
      });
      final List<ItemData> adapted = adaptBlocks(
        <ItemData>[item],
        PluginCapabilities.minimal(),
      );
      expect(adapted.length, 1);
      expect(adapted.first.text.fallback, '（没有内容）');
    });
  });
}
