import 'package:pluginxx_ui/pluginxx_ui.dart';
import 'package:test/test.dart';

void main() {
  group('尺寸换算', () {
    test('数值直接给出；auto 用 fallback', () {
      expect(resolveSize(const SizeValue.value(24)).value, 24);
      expect(resolveSize(SizeValue.autoValue, fallback: 8).value, 8);
      expect(resolveSize(SizeValue.autoValue).isAuto, isTrue);
    });

    test('percent 按可用空间换算，无界时用 fallback', () {
      final ResolvedSize half = resolveSize(
        const SizeValue.percent(50),
        available: 200,
      );
      expect(half.value, 100);
      expect(half.fromPercent, isTrue);
      expect(resolveSize(const SizeValue.percent(50), fallback: 12).value, 12);
    });

    test('值表达式的结果按 u 或 percent 解释', () {
      final SizeValue expr = SizeValue.expr(<String, Object?>{'kind': 'const', 'value': 30});
      expect(resolveSize(expr, expr: const ExprSize(30)).value, 30);
      expect(
        resolveSize(expr, available: 200, expr: const ExprSize(25, percent: true)).value,
        50,
      );
      expect(resolveSize(expr).isAuto, isTrue);
    });

    test('边距换算与字符格', () {
      final Edges scaled = resolveEdges(
        const Edges(left: 3, top: 4, right: 5, bottom: 6),
        convert: (double value) => value * 2,
      );
      expect(scaled.left, 6);
      expect(scaled.bottom, 12);

      final Edges cells = resolveEdgesInCells(
        const Edges(left: 9, top: 31, right: 0, bottom: 2),
      );
      expect(cells.left, 1); // 9 / 8 → 1 格
      expect(cells.top, 2); // 31 / 20 → 2 行
      expect(cells.right, 0);
      expect(cells.bottom, 0);

      expect(sizeInCells(4), 1); // 0.5 → 四舍五入 1
      expect(sizeInCells(1), 0);
      expect(sizeInCells(1, atLeastOne: true), 1);
    });
  });
}
