// kit 展开（Dart 绑定）
import 'package:pluginxx_ui/pluginxx_ui.dart';
import 'package:test/test.dart';

PluginCapabilities capsWithout(List<String> remove) {
  final PluginCapabilities caps = PluginCapabilities.full();
  return PluginCapabilities(
    kind: caps.kind,
    blocks: <String>[
      for (final String name in caps.blocks)
        if (!remove.any((String r) => r.toLowerCase() == name.toLowerCase())) name,
    ],
    controls: caps.controls,
    cell: caps.cell,
    gap: caps.gap,
    percent: caps.percent,
    aspect: caps.aspect,
    limits: caps.limits,
  );
}

void main() {
  test('kit 列表行按参数装配', () {
    final Map<String, Object?> row = listRow(title: '切歌次数', trailing: '3');
    expect(row['kind'], 'Block');
    expect(row['variant'], 'inset');
    final List<Object?> children = (row['children']! as List);
    expect(children.length, 1);
    final Map<String, Object?> line = (children[0] as Map).cast<String, Object?>();
    expect(line['kind'], 'Row');
    expect(line['cross'], 'center');
    final List<Object?> lineChildren = line['children']! as List;
    expect(lineChildren.length, 2);
    final Map<String, Object?> left = (lineChildren[0] as Map).cast<String, Object?>();
    expect(left['kind'], 'Expanded');
    final Map<String, Object?> trailing = (lineChildren[1] as Map).cast<String, Object?>();
    expect(trailing['text'], '3');
  });

  test('kit 缺省参数让节点退掉', () {
    final Map<String, Object?> row = listRow(title: '只有标题');
    final List<Object?> lineChildren =
        (((row['children']! as List)[0]) as Map)['children']! as List;
    expect(lineChildren.length, 1, reason: '没有右侧文本');
    final Map<String, Object?> column = (lineChildren[0] as Map).cast<String, Object?>();
    expect(column['kind'], 'Expanded');
    final List<Object?> columnChildren = column['children']! as List;
    final Map<String, Object?> inner =
        (columnChildren[0] as Map).cast<String, Object?>();
    expect(inner['kind'], 'Column');
    expect((inner['children']! as List).length, 1, reason: '没有副标题');
  });

  test('kit 列表映射生成等宽按钮', () {
    final Map<String, Object?> row = actionsRow(
      buttons: <Object?>[
        <String, Object?>{'kind': 'Button', 'label': '保存', 'action': 'apply'},
        <String, Object?>{'kind': 'Button', 'label': '取消', 'action': 'cancel'},
      ],
    );
    expect(row['kind'], 'Row');
    final List<Object?> children = row['children']! as List;
    expect(children.length, 2);
    for (final Object? child in children) {
      final Map<String, Object?> expanded = (child! as Map).cast<String, Object?>();
      expect(expanded['kind'], 'Expanded');
      expect(((expanded['children']! as List)[0] as Map)['kind'], 'Button');
    }
  });

  test('kit 按目标选择变体', () {
    final Map<String, Object?> iconNode =
        icon(name: 'play', glyph: '▶', env: PluginCapabilities.full());
    expect(iconNode['kind'], 'Icon');

    final Map<String, Object?> textNode =
        icon(name: 'play', glyph: '▶', env: capsWithout(<String>['Icon']));
    expect(textNode['kind'], 'Text');
    expect(textNode['text'], '▶');

    final Map<String, Object?> neutral = icon(name: 'play', glyph: '▶');
    expect(neutral['kind'], 'Icon');
  });

  test('kit 默认留白交给客户端', () {
    final Map<String, Object?> gapNode = gap();
    expect(gapNode['kind'], 'Gap');
    expect(gapNode.containsKey('size'), isFalse, reason: '缺省不写死尺寸');
    expect(gap(size: 24)['size'], 24);
  });

  test('kit 展开结果可以直接解析', () {
    final Map<String, Object?> row = listRow(title: '标题', subtitle: '副标题');
    final ItemData parsed = parseBlock(row);
    expect(parsed.known, isTrue);
    expect(parsed.kind, 'Block');
    expect(parsed.children.length, 1);
  });

  test('kit 按格换算', () {
    expect(cols(2), 16);
    expect(rows(3), 60);
    final PluginCapabilities caps = PluginCapabilities.full();
    final PluginCapabilities custom = PluginCapabilities(
      kind: caps.kind,
      blocks: caps.blocks,
      controls: caps.controls,
      cell: const CellSize(width: 10, height: 24),
    );
    expect(cols(2, env: custom), 20);
    expect(rows(2, env: custom), 48);
  });
}
