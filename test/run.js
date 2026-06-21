// ============================================================================
// FDE-ReLoop 測試（零相依，純 Node）
//   冒煙(smoke)：inline JS 語法、DOM 元素/事件接線、migration 與回滾配對
//   單元(unit) ：直接擷取 dealer_portal.html 內出貨的函式原始碼來測
//   整合(integration)：用假 DOM/假 DB 串接設備底價的關鍵流程
// 執行：npm test   （node test/run.js）
// ============================================================================
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(ROOT, 'dealer_portal.html'), 'utf8');

// ---- 迷你測試框架 ----
let pass = 0, fail = 0;
const fails = [];
function ok(cond, name) {
  if (cond) { pass++; }
  else { fail++; fails.push(name); console.log('  ✗ ' + name); }
}
function eq(a, b, name) { ok(JSON.stringify(a) === JSON.stringify(b), `${name}（期望 ${JSON.stringify(b)}，得到 ${JSON.stringify(a)}）`); }
function section(t) { console.log('\n▶ ' + t); }

// ---- 從 HTML 擷取 inline <script> ----
function inlineScripts(src) {
  return [...src.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)]
    .filter(m => !/\bsrc=/.test(m[1])).map(m => m[2]);
}

// ---- 精準函式擷取：跳過字串/樣板字面值/註解，正確配對大括號 ----
function extractFn(src, name) {
  const sig = new RegExp('(?:async\\s+)?function\\s+' + name + '\\s*\\(');
  const m = sig.exec(src);
  if (!m) throw new Error('找不到函式 ' + name);
  let i = src.indexOf('{', m.index);
  let depth = 0, j = i;
  let str = null;      // 目前字串引號字元或 null
  let tpl = [];        // 樣板字面值 ${} 巢狀深度堆疊
  let comment = null;  // 'line' | 'block' | null
  for (; j < src.length; j++) {
    const ch = src[j], prev = src[j - 1], next = src[j + 1];
    if (comment === 'line') { if (ch === '\n') comment = null; continue; }
    if (comment === 'block') { if (ch === '*' && next === '/') { comment = null; j++; } continue; }
    if (str) { if (ch === '\\') { j++; continue; } if (ch === str) str = null; continue; }
    if (tpl.length && tpl[tpl.length - 1] === 'intpl') {
      // 在 `...` 內，等待 ${
      if (ch === '\\') { j++; continue; }
      if (ch === '`') { tpl.pop(); continue; }
      if (ch === '$' && next === '{') { tpl.push('expr'); j++; depth++; continue; }
      continue;
    }
    if (ch === '/' && next === '/') { comment = 'line'; j++; continue; }
    if (ch === '/' && next === '*') { comment = 'block'; j++; continue; }
    if (ch === '"' || ch === "'") { str = ch; continue; }
    if (ch === '`') { tpl.push('intpl'); continue; }
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (tpl.length && tpl[tpl.length - 1] === 'expr') { tpl.pop(); continue; } // 結束 ${}，回到既有樣板字面值（不再 push）
      if (depth === 0) { j++; break; }
    }
  }
  return src.slice(m.index, j);
}

// 把擷取到的函式包進 sandbox：depNames 由呼叫端提供值，其餘自由變數需是 JS 內建
function buildFns(sources, depNames, depValues, returnExpr) {
  const factory = new Function(...depNames, sources.join('\n') + '\n; return (' + returnExpr + ');');
  return factory(...depValues);
}

// ============================================================================
section('冒煙：所有 inline script 語法正確');
const scripts = inlineScripts(html);
ok(scripts.length > 0, '至少有一段 inline script');
scripts.forEach((s, i) => {
  try { new Function(s); pass++; }
  catch (e) { fail++; fails.push(`script#${i} 語法`); console.log('  ✗ script#' + i + ' 語法：' + e.message); }
});

section('冒煙：底價功能用到的 DOM 元素 id 都存在');
['eq-floor-price', 'eq-floor-lock', 'eq-floor-status', 'eq-floor-hint', 'eq-floor-reminder',
 'eq-case-row', 'eq-case-no'].forEach(id => {
  ok(new RegExp(`id="${id}"`).test(html), `元素 #${id} 存在於 HTML`);
});

section('冒煙：事件處理器都對應到已定義函式');
const JS_KEYWORDS = new Set(['if', 'for', 'while', 'switch', 'return', 'function', 'do', 'else', 'try', 'catch', 'with', 'typeof', 'void', 'new', 'delete', 'await']);
const handlers = [...html.matchAll(/on(?:click|input|change)="\s*([a-zA-Z_]\w*)\s*\(/g)].map(m => m[1]);
const uniqHandlers = [...new Set(handlers)].filter(fn => !JS_KEYWORDS.has(fn));
uniqHandlers.forEach(fn => {
  const defined = new RegExp(`function\\s+${fn}\\s*\\(`).test(html)
    || new RegExp(`${fn}\\s*[:=]\\s*(async\\s*)?(function|\\()`).test(html)   // fn = function / fn: function / fn = (
    || new RegExp(`window\\.${fn}\\s*=`).test(html);
  ok(defined, `handler ${fn}() 有定義`);
});
// 新功能的關鍵 handler 必須在
['updateFloorReminder', 'approveFloorPrice', 'saveEquipment', 'openEquipmentForm'].forEach(fn => {
  ok(uniqHandlers.includes(fn) || new RegExp(`function\\s+${fn}`).test(html), `關鍵函式 ${fn} 有被接線/定義`);
});

section('冒煙：migration 與回滾腳本配對且內容合理');
const migDir = path.join(ROOT, 'supabase/migrations');
const rbDir = path.join(ROOT, 'supabase/rollback');
const migs = fs.readdirSync(migDir).filter(f => f.endsWith('.sql'));
migs.forEach(f => {
  const base = f.replace('.sql', '');
  ok(fs.existsSync(path.join(rbDir, base + '_down.sql')), `${f} 有對應回滾腳本`);
});
const floorMig = fs.readFileSync(path.join(migDir, '202606200001_equipment_floor_price.sql'), 'utf8');
ok(/ADD COLUMN IF NOT EXISTS floor_price\b/.test(floorMig), 'floor migration 有加 floor_price 欄位');
ok(/floor_price_status.*IN \('none', 'pending', 'approved'\)/s.test(floorMig), 'floor_price_status 有狀態約束');
const floorRb = fs.readFileSync(path.join(rbDir, '202606200001_equipment_floor_price_down.sql'), 'utf8');
ok(/DROP COLUMN IF EXISTS floor_price\b/.test(floorRb), 'floor 回滾有移除 floor_price 欄位');

// ============================================================================
section('單元：computeFloorPriceFields（底價狀態流轉）');
const computeFloorPriceFields = buildFns([extractFn(html, 'computeFloorPriceFields')], [], [], 'computeFloorPriceFields');
{
  const admin = computeFloorPriceFields('5000', true, 'u-admin', 'T');
  eq(admin.floor_price, 5000, 'admin 填→金額');
  eq(admin.floor_price_status, 'approved', 'admin 填→直接生效');
  eq(admin.floor_price_approved_by, 'u-admin', 'admin 填→approved_by=自己');

  const mgr = computeFloorPriceFields('3000', false, 'u-mgr', 'T');
  eq(mgr.floor_price_status, 'pending', '主管填→待審');
  eq(mgr.floor_price_approved_by, null, '主管填→尚無核可人');

  const empty = computeFloorPriceFields('', false, 'u-mgr', 'T');
  eq(empty.floor_price, null, '留空→null');
  eq(empty.floor_price_status, 'none', '留空→none');

  const emptyNull = computeFloorPriceFields(null, true, 'u-admin', 'T');
  eq(emptyNull.floor_price_status, 'none', 'null→none（即使是 admin）');
}

section('單元：floorPriceCell（清單底價顯示）');
const floorPriceCell = buildFns([extractFn(html, 'floorPriceCell')], [], [], 'floorPriceCell');
ok(floorPriceCell({ floor_price: null }).includes('—'), '未設→破折號');
ok(/生效/.test(floorPriceCell({ floor_price: 5000, floor_price_status: 'approved' })), 'approved→顯示生效');
ok(/待審/.test(floorPriceCell({ floor_price: 5000, floor_price_status: 'pending' })), 'pending→顯示待審');
ok(floorPriceCell({ floor_price: 12000, floor_price_status: 'approved' }).includes('12,000'), '金額有千分位');

section('單元：caseFinancialSummary（毛利彙總 + 權限把關）');
function makeCFS(perm, cases) {
  return buildFns(
    [extractFn(html, 'caseFinancialSummary')],
    ['hasPermission', 'casesCache'],
    [(k) => perm.includes(k), cases],
    'caseFinancialSummary'
  );
}
{
  const equips = [{ floor_price: 3000, floor_price_status: 'approved' }, { floor_price: 5000, floor_price_status: 'pending' }];
  // 無權限 → 空字串（看不到彙總）
  const noPerm = makeCFS([], [{ id: 'c1', estimate_price: 6000 }]);
  eq(noPerm('c1', equips), '', '無 view_case_financials→不顯示彙總');
  // 有權限、毛利為正（8000 ≥ 6000）
  const cfsPos = makeCFS(['view_case_financials'], [{ id: 'c1', estimate_price: 6000 }]);
  ok(/毛利/.test(cfsPos('c1', equips)), '加總≥總包價→顯示毛利');
  ok(cfsPos('c1', equips).includes('8,000'), '底價加總正確(3000+5000)');
  // 毛利為負（8000 < 10000）
  const cfsNeg = makeCFS(['view_case_financials'], [{ id: 'c1', estimate_price: 10000 }]);
  ok(/虧損/.test(cfsNeg('c1', equips)), '加總<總包價→顯示虧損');
  // formal_price 優先於 estimate_price
  const cfsFormal = makeCFS(['view_case_financials'], [{ id: 'c1', estimate_price: 1, formal_price: 10000 }]);
  ok(/正式報價/.test(cfsFormal('c1', equips)), '有 formal_price→以正式報價為基準');
  // 無任何總包價
  const cfsNoBase = makeCFS(['view_case_financials'], [{ id: 'c1' }]);
  ok(/無法計算/.test(cfsNoBase('c1', equips)), '無總包價→提示無法計算毛利');
}

// ============================================================================
section('整合：setupFloorPriceField + updateFloorReminder（假 DOM）');
function fakeEl() { return { value: '', style: {}, textContent: '', innerHTML: '', readOnly: false }; }
function makeFakeDoc(ids) {
  const map = {}; ids.forEach(id => map[id] = fakeEl());
  return { _map: map, getElementById: (id) => map[id] || (map[id] = fakeEl()) };
}
function makeFloorUI(perm, cases, equipCache, doc) {
  return buildFns(
    [extractFn(html, 'setupFloorPriceField'), extractFn(html, 'caseDisplayNo'), extractFn(html, 'updateFloorReminder')],
    ['hasPermission', 'casesCache', 'equipmentCache', 'document'],
    [(k) => perm.includes(k), cases, equipCache, doc],
    '({ setupFloorPriceField, updateFloorReminder })'
  );
}
{
  const ids = ['eq-floor-price', 'eq-floor-lock', 'eq-floor-hint', 'eq-floor-status', 'eq-case-row', 'eq-case-no', 'eq-floor-reminder'];
  // 業務（無 set_floor_price）→ 底價唯讀、顯示鎖
  const doc1 = makeFakeDoc(ids);
  const ui1 = makeFloorUI([], [{ id: 'c1', estimate_price: 6000 }], [], doc1);
  ui1.setupFloorPriceField({ id: 'e1', case_id: 'c1', floor_price: 3000, floor_price_status: 'approved' });
  eq(doc1._map['eq-floor-price'].readOnly, true, '業務→底價欄唯讀');
  ok(doc1._map['eq-floor-price'].value === 3000, '業務→仍看得到底價數字');
  ok(/生效/.test(doc1._map['eq-floor-status'].textContent), '狀態徽章顯示已生效');

  // 主管（有 set_floor_price）→ 可編輯
  const doc2 = makeFakeDoc(ids);
  const ui2 = makeFloorUI(['set_floor_price'], [{ id: 'c1', estimate_price: 6000 }], [], doc2);
  ui2.setupFloorPriceField({ id: 'e1', case_id: 'c1', floor_price: null, floor_price_status: 'none' });
  eq(doc2._map['eq-floor-price'].readOnly, false, '主管→底價欄可編輯');

  // 軟提醒：本案其他設備底價 2000 + 本台輸入 3000 = 5000 < 總包價 6000 → 虧損警示
  const doc3 = makeFakeDoc(ids);
  const cache = [{ id: 'e1', case_id: 'c1', floor_price: 2000 }, { id: 'e2', case_id: 'c1', floor_price: null }];
  const ui3 = makeFloorUI(['set_floor_price'], [{ id: 'c1', estimate_price: 6000 }], cache, doc3);
  ui3.setupFloorPriceField({ id: 'e2', case_id: 'c1', floor_price: null, floor_price_status: 'none' });
  doc3._map['eq-floor-price'].value = '3000';
  ui3.updateFloorReminder();
  ok(/虧損/.test(doc3._map['eq-floor-reminder'].innerHTML), '加總(2000+3000)<6000→提醒虧損');
  // 提高本台到 5000 → 加總 7000 ≥ 6000 → 毛利
  doc3._map['eq-floor-price'].value = '5000';
  ui3.updateFloorReminder();
  ok(/毛利/.test(doc3._map['eq-floor-reminder'].innerHTML), '加總(2000+5000)≥6000→顯示毛利');
}

section('整合：approveFloorPrice（假 DB；權限與狀態流轉）');
function makeApprove(perm, equipCache, captured, info) {
  return buildFns(
    [extractFn(html, 'approveFloorPrice')],
    ['hasPermission', 'getSupabase', 'equipmentCache', 'showToast', 'confirm', 'logActivity', 'currentDealerInfo', 'renderEquipmentList'],
    [
      (k) => perm.includes(k),
      () => ({ from: () => ({ update: (p) => { captured.payload = p; return { eq: async () => ({ error: null }) }; } }) }),
      equipCache,
      () => {}, () => true, () => {}, info, () => {},
    ],
    'approveFloorPrice'
  );
}
{
  // 無權限 → 不送出
  const cap0 = {};
  const noPerm = makeApprove([], [{ id: 'e1', device_name: 'A', floor_price: 5000, floor_price_status: 'pending' }], cap0, { id: 'admin' });
  await noPerm('e1');
  ok(!cap0.payload, '無 approve_floor_price→不執行更新');

  // 有權限 + pending → 更新為 approved
  const cap1 = {};
  const eqArr = [{ id: 'e1', device_name: 'A', floor_price: 5000, floor_price_status: 'pending' }];
  const yes = makeApprove(['approve_floor_price'], eqArr, cap1, { id: 'admin' });
  await yes('e1');
  ok(cap1.payload && cap1.payload.floor_price_status === 'approved', 'admin 核可→狀態 approved');
  eq(cap1.payload.floor_price_approved_by, 'admin', '核可人=admin');
  eq(eqArr[0].floor_price_status, 'approved', '本地快取同步更新');
}

// ============================================================================
console.log(`\n${'─'.repeat(48)}`);
if (fail === 0) { console.log(`✅ 全部通過：${pass} 項`); process.exit(0); }
else { console.log(`❌ 失敗 ${fail} 項 / 通過 ${pass} 項`); console.log('失敗清單：\n  - ' + fails.join('\n  - ')); process.exit(1); }
