// JS kit 自检：骨架与 C++/Dart 两侧的 kit 测试用同一组参数与同一份期望，
// 保证三份绑定的展开语义不分叉。
//
// 用法：node tools/kit_js_test.js
'use strict';

require('../js/pluginxx_ui_kit.js');

const kit = globalThis.pluginxx.ui.kit;
let failures = 0;

function check(ok, message) {
  if (!ok) {
    failures += 1;
    console.error('  [FAIL] ' + message);
  }
}

function checkEqual(actual, expected, message) {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) {
    failures += 1;
    console.error('  [FAIL] ' + message + '\n    actual  : ' + a + '\n    expected: ' + b);
  }
}

// ---- 列表行：标题 + 右侧文字 ----
const row = kit.listRow({ title: '切歌次数', trailing: '3' });
check(row.kind === 'Block', 'listRow 外层是内容块');
check(row.variant === 'inset', 'listRow 用内嵌样式');
check(row.children.length === 1, 'listRow 只有一个子块');
const line = row.children[0];
check(line.kind === 'Row', 'listRow 的行');
check(line.cross === 'center', 'listRow 垂直居中');
check(line.children.length === 2, 'listRow 左侧 + 右侧');
check(line.children[0].kind === 'Expanded', 'listRow 左侧占满剩余');
check(line.children[1].text === '3', 'listRow 右侧文本');

// 缺省参数让节点退掉
const bare = kit.listRow({ title: '只有标题' });
check(bare.children[0].children.length === 1, '没有右侧文本');
check(bare.children[0].children[0].children[0].children.length === 1, '没有副标题');

// ---- 列表映射：一排等宽按钮 ----
const actions = kit.actionsRow({
  buttons: [
    { kind: 'Button', label: '保存', action: 'apply' },
    { kind: 'Button', label: '取消', action: 'cancel' },
  ],
});
check(actions.kind === 'Row', 'actionsRow 是一排');
check(actions.children.length === 2, 'actionsRow 两个等份');
check(actions.children[0].kind === 'Expanded', '每项占一等份');
check(actions.children[0].children[0].kind === 'Button', '里面是按钮');

// ---- 变体选择 ----
const caps = { blocks: ['Text', 'Gap', 'Badge', 'Block', 'Row', 'Expanded', 'Column', 'Divider'] };
check(kit.icon({ name: 'play', glyph: '▶' }, caps).kind === 'Text', '不支持 Icon 时退成文本');
check(kit.icon({ name: 'play', glyph: '▶' }, { blocks: ['Icon'] }).kind === 'Icon', '支持 Icon 时用它');
check(kit.icon({ name: 'play', glyph: '▶' }).kind === 'Icon', '目标未知时用第一个变体');

// ---- 默认留白交给客户端 ----
const gap = kit.gap();
check(gap.kind === 'Gap', 'gap 是留白块');
check(gap.size === undefined, '缺省不写死尺寸');
check(kit.gap({ size: 24 }).size === 24, '给了尺寸就用它');

// ---- 按格换算 ----
check(kit.cols(2) === 16, '默认格宽 8u');
check(kit.rows(3) === 60, '默认格高 20u');
check(kit.cols(2, { cell: { width: 10 } }) === 20, '客户端上报的格宽');

// ---- 组件表齐全 ----
for (const name of ['title', 'hint', 'text', 'badge', 'icon', 'gap', 'divider', 'button',
  'actionsRow', 'card', 'listRow', 'section', 'kv', 'table', 'tree', 'sparkline', 'progressRow']) {
  check(typeof kit[name] === 'function', 'kit 组件存在：' + name);
}

if (failures > 0) {
  console.error('kit JS 自检失败：' + failures + ' 条');
  process.exit(1);
}
console.log('kit JS 自检通过（kit 版本 ' + kit.kitVersion + '）');
