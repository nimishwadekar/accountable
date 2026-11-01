// Screenshot/geometry baseline only. This does not change the application UI.
import fs from 'node:fs';
import path from 'node:path';

const baseUrl = process.env.AUDIT_URL ?? 'http://127.0.0.1:9030';
const port = process.env.CDP_PORT ?? '9260';
const output = path.resolve(process.env.EVIDENCE_DIR ?? 'docs/mobile-ui-p3-audit');
const deviceScaleFactor = Number(process.env.AUDIT_DPR ?? '1');
fs.mkdirSync(output, { recursive: true });
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) => item.type === 'page' && item.url.startsWith(baseUrl));
if (!target) throw new Error('Open the isolated CSV audit app first.');
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener('open', resolve, { once: true });
  socket.addEventListener('error', reject, { once: true });
});
let serial = 0;
const pending = new Map();
const errors = [];
socket.addEventListener('message', ({ data }) => {
  const message = JSON.parse(data);
  if (pending.has(message.id)) {
    const { resolve, reject, timer } = pending.get(message.id);
    clearTimeout(timer);
    pending.delete(message.id);
    if (message.error) reject(new Error(message.error.message));
    else resolve(message.result);
  } else if (message.method === 'Runtime.exceptionThrown') {
    errors.push(message.params.exceptionDetails.text);
  } else if (message.method === 'Log.entryAdded' && message.params.entry.level === 'error') {
    errors.push(message.params.entry.text);
  }
});
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const id = ++serial;
  const timer = setTimeout(() => {
    pending.delete(id);
    reject(new Error(`CDP timeout: ${method}`));
  }, 20000);
  pending.set(id, { resolve, reject, timer });
  socket.send(JSON.stringify({ id, method, params }));
});
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const evaluate = async (expression) => {
  const result = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
  return result.result.value;
};
await send('Runtime.enable');
await send('Log.enable');
await send('Network.enable');
await send('Network.setCacheDisabled', { cacheDisabled: true });
await send('Network.setBypassServiceWorker', { bypass: true });
await send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 1 });

async function viewport(width, height) {
  await send('Emulation.setDeviceMetricsOverride', {
    width, height, deviceScaleFactor, mobile: true, screenWidth: width, screenHeight: height,
  });
  await wait(400);
  const actual = await evaluate('({width:innerWidth,height:innerHeight})');
  if (actual.width !== width || actual.height !== height) throw new Error('Incorrect audit viewport.');
}
async function enableSemantics() {
  await evaluate('document.querySelector("flt-semantics-placeholder")?.click()');
  await wait(250);
}
async function navigate(route, width = 390, height = 844) {
  await send('Page.navigate', { url: `${baseUrl}${route}` });
  await wait(2400);
  await viewport(width, height);
  await enableSemantics();
}
async function click(text, { includes = false, last = false, role = null } = {}) {
  const rect = await evaluate(`(() => {
    const matches = [...document.querySelectorAll('flt-semantics[role]')].filter((element) => {
      if (!['button', 'tab', 'checkbox', 'switch', 'combobox', 'radio'].includes(element.getAttribute('role'))) return false;
      if (${JSON.stringify(role)} && element.getAttribute('role') !== ${JSON.stringify(role)}) return false;
      const text = (element.getAttribute('aria-label') || element.innerText).trim().replace(/\\s+/g, ' ');
      const rect = element.getBoundingClientRect();
      return rect.bottom > 0 && rect.top < innerHeight &&
        ${includes ? `text.includes(${JSON.stringify(text)})` : `text === ${JSON.stringify(text)}`};
    });
    const element = matches[${last ? 'matches.length - 1' : '0'}];
    if (!element) return null;
    const rect = element.getBoundingClientRect();
    return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
  })()`);
  if (!rect) throw new Error(`Control not found: ${text}`);
  await tap(rect.x, rect.y);
}
async function tap(x, y) {
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
  await wait(650);
}
async function scroll(deltaY, x = 280, y = 600) {
  await send('Input.dispatchMouseEvent', { type: 'mouseWheel', x, y, deltaY, deltaX: 0 });
  await wait(450);
}

const reportPath = path.join(output, 'measurements.json');
const records = fs.existsSync(reportPath)
  ? JSON.parse(fs.readFileSync(reportPath, 'utf8')).records
  : [];
async function capture(name, expected = []) {
  await enableSemantics();
  const tree = await send('Accessibility.getFullAXTree');
  const names = [...new Set(tree.nodes.map((node) => node.name?.value).filter(Boolean))];
  for (const text of expected) {
    if (!names.some((name) => name.includes(text))) throw new Error(`${name}: missing ${text}`);
  }
  const state = await evaluate(`({
    url:location.pathname+location.search,width:innerWidth,height:innerHeight,
    controls:[...document.querySelectorAll('flt-semantics')].filter((element) =>
      element.hasAttribute('role') || !element.querySelector('flt-semantics')
    ).map((element) => {
      const rect = element.getBoundingClientRect();
      return {
        role:element.getAttribute('role'),
        text:(element.getAttribute('aria-label') || element.innerText).trim().replace(/\\s+/g,' ').slice(0,240),
        x:rect.x,y:rect.y,width:rect.width,height:rect.height,
      };
    }).filter((element) => element.text && element.height > 0)
  })`);
  const shot = await send('Page.captureScreenshot', { format: 'png', fromSurface: true, captureBeyondViewport: false });
  fs.writeFileSync(path.join(output, `${name}.png`), Buffer.from(shot.data, 'base64'));
  const existing = records.findIndex((record) => record.name === name);
  if (existing >= 0) records.splice(existing, 1);
  records.push({ name, ...state, names });
  fs.writeFileSync(reportPath, JSON.stringify({ records, errors }, null, 2) + '\n');
  console.log(`${name}: ${state.width}x${state.height} ${state.url}`);
}

try {
  if (process.env.AUDIT_MODE === 'populated') {
    await navigate('/?app=1');
    const original = await evaluate('localStorage.getItem("accountable.local_dataset")');
    if (!original) throw new Error('CSV audit storage was not initialized.');
    try {
      await evaluate(`(() => {
        const tables = JSON.parse(JSON.parse(localStorage.getItem('accountable.local_dataset')));
        const now = new Date();
        const timestamp = now.toISOString();
        const date = (year, month, day) => new Date(Date.UTC(year, month, day)).toISOString().slice(0,10);
        const csv = (rows) => rows.map((row) => row.map((cell) =>
          '"' + String(cell).replaceAll('"', '""') + '"'
        ).join(',')).join('\\n');
        const year = now.getUTCFullYear(), month = now.getUTCMonth();
        const history = [['net_worth_id','net_worth_date','amount','retrieved_at']];
        for (let offset = -1; offset <= 0; offset++) {
          const days = offset === 0 ? now.getUTCDate() - 1 : new Date(Date.UTC(year,month,0)).getUTCDate();
          for (let day = 1; day <= days; day++) {
            const label = date(year,month+offset,day);
            history.push([label+'-density',label,offset === -1 ? 12500 : 15750,timestamp]);
          }
        }
        tables['test_sheets/DailyNetWorth.csv'] = csv(history);
        tables['test_sheets/TransactionTemplates.csv'] = csv([
          ['template_id','name','transaction_type','date','description','category','tag','source_account_id','source_amount','dest_account_id','dest_amount','created_at','updated_at','is_favorite'],
          ['density-lunch','Weekday lunch','expense','','Lunch','food_drink','boston','chase_checking','','','',timestamp,timestamp,'TRUE'],
          ['density-transfer','International savings transfer','transfer','','Savings','general','','chase_checking','','sbi_nro','',timestamp,timestamp,'FALSE'],
          ['density-salary','Monthly salary','income','','Salary','salary','','','','chase_checking','',timestamp,timestamp,'FALSE'],
        ]);
        tables['test_sheets/IncomeAllocations.csv'] = csv([
          ['allocation_id','name','income_category_id','income_account_id','transfer_category_id','expected_amount_per_income','start_date','end_date','created_at','updated_at'],
          ['density-emergency','Emergency savings allocation','salary','chase_checking','general','400',date(year,month,1),'',timestamp,timestamp],
        ]);
        localStorage.setItem('accountable.local_dataset',JSON.stringify(JSON.stringify(tables)));
      })()`);
      await navigate('/analysis?app=1');
      await capture('analysis-summary-populated-390', ['15,750.00']);
      await navigate('/analysis?app=1', 320, 740);
      await capture('analysis-summary-populated-320', ['15,750.00']);
      await navigate('/transactions?app=1');
      await click('Add transaction');
      await capture('template-browser-populated-390', ['Weekday lunch']);
      await navigate('/analysis?app=1');
      await click('Categories');
      await scroll(900);
      await capture('analysis-allocation-populated-390', ['Emergency savings allocation']);
    } finally {
      await evaluate(`localStorage.setItem('accountable.local_dataset',${JSON.stringify(original)})`);
    }
  } else if (process.env.AUDIT_MODE === 'analysis-ranges') {
    await navigate('/analysis?app=1', 430, 932);
    await capture('analysis-ranges-430', [
      '1M', '3M', '6M', 'YTD', '1Y', '5Y', 'MAX',
    ]);
    await navigate('/analysis?app=1', 320, 740);
    await capture('analysis-ranges-320', [
      '1M', '3M', '6M', 'YTD', '1Y', '5Y', 'MAX',
    ]);
  } else if (process.env.AUDIT_MODE === 'p4-retina-mobile') {
    await navigate('/settings?app=1', 430, 628);
    const originalScale = await evaluate('localStorage.getItem("flutter.text_scale")');
    try {
      await evaluate('localStorage.removeItem("flutter.text_scale")');
      await navigate('/transactions?app=1', 430, 628);
      await capture('activity-default-430-dpr2');
    } finally {
      await evaluate(originalScale === null
        ? 'localStorage.removeItem("flutter.text_scale")'
        : `localStorage.setItem('flutter.text_scale',${JSON.stringify(originalScale)})`);
    }
  } else if (process.env.AUDIT_MODE === 'p4-enlarged-mobile') {
    await navigate('/settings?app=1', 430, 628);
    const originalScale = await evaluate('localStorage.getItem("flutter.text_scale")');
    try {
      await evaluate('localStorage.setItem("flutter.text_scale","1.5")');
      await navigate('/transactions?app=1', 430, 628);
      await capture('activity-app150-430-dpr2');
    } finally {
      await evaluate(originalScale === null
        ? 'localStorage.removeItem("flutter.text_scale")'
        : `localStorage.setItem('flutter.text_scale',${JSON.stringify(originalScale)})`);
    }
  } else if (process.env.AUDIT_MODE === 'rows') {
    for (const [width, height] of [[320, 740], [360, 800], [390, 844], [430, 932]]) {
      await navigate('/accounts?app=1', width, height);
      await capture(`accounts-${width}`, ['Cash Accounts', 'Add valuation']);
      await navigate('/analysis?app=1', width, height);
      await capture(`analysis-summary-${width}`, ['Net worth (USD)']);
      await navigate('/transactions?app=1', width, height);
      await capture(`activity-${width}`, ['Transactions', 'Add transaction']);
    }
    await navigate('/transactions?app=1', 320, 740);
    await scroll(350, 160, 450);
    await capture('activity-transfer-320', [
      'Credit Payment',
      'From · Chase Checking',
      'To · Chase Freedom Rise',
    ]);
    await navigate('/transactions?app=1', 390, 844);
    await click('Show balances');
    await scroll(300, 195, 450);
    await capture('activity-transfer-balances-390', [
      'Credit Payment',
      'Balance: $ 1,550.00',
      'Balance: $ -85.00',
    ]);
  } else if (process.env.AUDIT_MODE === 'desktop') {
    for (const [route, name, expected] of [
      ['/transactions?app=1', 'activity-1280', ['Transactions']],
      ['/accounts?app=1', 'accounts-1280', ['Cash Accounts', 'Assets & Liabilities']],
      ['/analysis?app=1', 'analysis-trends-1280', ['Net worth (USD)', 'Account history']],
      ['/milestones?app=1&milestones=progress', 'milestones-progress-1280', ['Earned milestones']],
    ]) {
      await navigate(route, 1280, 900);
      await capture(name, expected);
    }
  } else if (process.env.AUDIT_MODE === 'enlarged') {
    await navigate('/settings?app=1');
    const originalScale = await evaluate('localStorage.getItem("flutter.text_scale")');
    try {
      await evaluate('localStorage.setItem("flutter.text_scale","1.5")');
      await navigate('/analysis?app=1');
      await capture('analysis-summary-app150-390', ['Net worth (USD)']);
      await navigate('/transactions?app=1');
      await capture('activity-app150-390', ['Transactions']);
      await navigate('/transactions?app=1', 860, 1255);
      await capture('activity-app150-860', ['Transactions']);
      await navigate('/analysis?app=1');
      await click('Categories');
      await capture('analysis-categories-app150-390', ['Spending by Category']);
    } finally {
      await evaluate(originalScale === null
        ? 'localStorage.removeItem("flutter.text_scale")'
        : `localStorage.setItem('flutter.text_scale',${JSON.stringify(originalScale)})`);
    }
    await navigate('/analysis?app=1', 390, 520);
    await click('Categories');
    await capture('analysis-categories-short-390', ['Spending by Category']);
    await navigate('/transactions?app=1', 390, 520);
    await capture('activity-short-390', ['Add transaction']);
  } else if (process.env.AUDIT_MODE === 'inspect') {
    await capture(process.env.CAPTURE_NAME ?? 'inspection');
    console.log(await evaluate('Object.keys(localStorage)'));
  } else {
    if (!['flows', 'extras'].includes(process.env.AUDIT_MODE)) {
      for (const [width, height] of [[320, 740], [360, 800], [390, 844], [430, 932]]) {
        await navigate('/analysis?app=1', width, height);
        await capture(`analysis-summary-${width}`, ['Net worth (USD)']);
        await navigate('/transactions?app=1', width, height);
        await capture(`activity-${width}`, ['Transactions']);
        if (width === 390 || width === 320) {
          await click('Show balances');
          await scroll(300, width / 2, 450);
          await capture(`activity-balances-${width}`, ['Balance:', 'Credit Payment']);
        }
        await navigate('/accounts?app=1', width, height);
        await capture(`accounts-${width}`, ['Cash Accounts']);
      }
    }
    if (process.env.AUDIT_MODE !== 'extras') {
      await navigate('/analysis?app=1');
      await capture('analysis-trends-390', ['Net worth (USD)']);
      await scroll(400);
      await capture('analysis-account-history-390', ['Account history']);
      await navigate('/analysis?app=1');
      await click('Categories');
      await capture('analysis-categories-390', ['Spending by Category']);
      await scroll(650);
      await capture('analysis-income-390', ['Income by Category']);
      await click('Add Income Allocation', { includes: true });
      await capture('income-allocation-390', ['Expected amount', 'Save']);

      await navigate('/transactions?app=1');
      await click('Filters');
      await capture('filters-390', ['Type', 'Account']);
      await navigate('/transactions?app=1');
      await click('Add transaction');
      await capture('template-browser-empty-390', ['New Transaction']);
      await click('New Transaction');
      await capture('type-chooser-390', ['Expense', 'Transfer']);
      await click('Expense');
      await capture('expense-form-390', ['Description', 'Amount']);
      await navigate('/transactions?app=1');
      await click('Add transaction');
      await click('New Transaction');
      await click('Transfer');
      await capture('transfer-form-390', ['Source', 'Destination']);

      await navigate('/accounts?app=1');
      await click('Add valuation');
      await capture('valuation-390', ['Add Daily Valuations']);
    }
    await navigate('/settings?app=1');
    await capture('settings-390', ['App text size']);
    await click('Accounts', { role: 'button' });
    await capture('display-accounts-390', ['Show Chase Checking in app']);

    await navigate('/milestones?app=1');
    await capture('milestones-empty-390', ['Add named milestones']);
    await navigate('/milestones?app=1&milestones=progress');
    await capture('milestones-progress-390', ['Earned milestones']);
    await navigate('/milestones?app=1&milestones=celebration');
    await capture('milestones-celebration-390', ['You did it!']);
  }
  if (errors.length) throw new Error(errors.join('\n'));
} finally {
  socket.close();
}
