import fs from 'node:fs';
import path from 'node:path';

const debuggingPort = Number(process.env.CDP_PORT ?? 9250);
const baseUrl = process.env.AUDIT_URL ?? 'http://127.0.0.1:9020';
const evidenceDir = path.resolve('docs/mobile-ui-p2');
fs.mkdirSync(evidenceDir, { recursive: true });

const targets = await (await fetch(`http://127.0.0.1:${debuggingPort}/json/list`)).json();
const target = targets.find(
  (item) => item.type === 'page' && item.url.startsWith(baseUrl),
);
if (!target) throw new Error(`No audit page found at ${baseUrl}`);

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener('open', resolve, { once: true });
  socket.addEventListener('error', reject, { once: true });
});

let nextId = 0;
const pending = new Map();
const browserErrors = [];
socket.addEventListener('message', (event) => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(message.error.message));
    else resolve(message);
    return;
  }
  if (message.method === 'Runtime.exceptionThrown') {
    browserErrors.push(message.params.exceptionDetails.text);
  }
  if (message.method === 'Log.entryAdded' && message.params.entry.level === 'error') {
    browserErrors.push(message.params.entry.text);
  }
});

const send = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const id = ++nextId;
    pending.set(id, { resolve, reject });
    socket.send(JSON.stringify({ id, method, params }));
  });
const wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
const evaluate = async (expression) => {
  const response = await send('Runtime.evaluate', {
    expression,
    returnByValue: true,
  });
  if (response.result.exceptionDetails) {
    throw new Error(response.result.exceptionDetails.text);
  }
  return response.result.result.value;
};

await send('Runtime.enable');
await send('Log.enable');
await send('Network.enable');
await send('Network.setCacheDisabled', { cacheDisabled: true });
await send('Network.setBypassServiceWorker', { bypass: true });

async function setViewport(width, height) {
  await send('Emulation.setDeviceMetricsOverride', {
    width,
    height,
    deviceScaleFactor: 1,
    mobile: true,
    screenWidth: width,
    screenHeight: height,
  });
}

async function navigate(route, width = 390, height = 844) {
  await send('Page.navigate', { url: `${baseUrl}${route}` });
  await wait(3000);
  let viewport;
  for (let attempt = 0; attempt < 5; attempt++) {
    await setViewport(width, height);
    await wait(300);
    viewport = await evaluate('({width:innerWidth,height:innerHeight})');
    if (viewport.width === width && viewport.height === height) break;
  }
  if (viewport.width !== width || viewport.height !== height) {
    throw new Error(`Viewport did not settle at ${width}x${height}: ${JSON.stringify(viewport)}`);
  }
  await evaluate('document.querySelector("flt-semantics-placeholder")?.click()');
  const accessibility = await send('Accessibility.getFullAXTree');
  const nodes = accessibility.result.nodes;
  const names = [...new Set(nodes.map((node) => node.name?.value).filter(Boolean))];
  const selectedTab = nodes.find(
    (node) =>
      node.role?.value === 'tab' &&
      node.properties?.some(
        (property) => property.name === 'selected' && property.value?.value,
      ),
  )?.name?.value;
  return {
    names,
    selectedTab,
    state: await evaluate(
      '({url:location.pathname+location.search,width:innerWidth,height:innerHeight})',
    ),
  };
}

async function capture(route, filename, expected, width = 390, height = 844) {
  const page = await navigate(route, width, height);
  const absent = expected.filter((text) => !page.names.some((name) => name.includes(text)));
  if (absent.length > 0) {
    throw new Error(
      `${route} missing visible content: ${absent.join(', ')}; ` +
      `viewport=${JSON.stringify(page.state)}; names=${page.names.slice(0, 24).join(' | ')}`,
    );
  }
  const screenshot = await send('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
    captureBeyondViewport: false,
  });
  fs.writeFileSync(
    path.join(evidenceDir, `${filename}.png`),
    Buffer.from(screenshot.result.data, 'base64'),
  );
  return { file: `${filename}.png`, ...page.state, selectedTab: page.selectedTab };
}

async function clickSemantics(text) {
  const rect = await evaluate(`(() => {
    const element = [...document.querySelectorAll('flt-semantics[role]')]
      .find((item) => {
        const label = (item.getAttribute('aria-label') || item.innerText)
          .trim().replace(/\\s+/g, ' ');
        return label === ${JSON.stringify(text)};
      });
    if (!element) return null;
    const bounds = element.getBoundingClientRect();
    return [bounds.x + bounds.width / 2, bounds.y + bounds.height / 2];
  })()`);
  if (!rect) throw new Error(`Semantic control not found: ${text}`);
  await send('Input.dispatchMouseEvent', {
    type: 'mousePressed', x: rect[0], y: rect[1], button: 'left', clickCount: 1,
  });
  await send('Input.dispatchMouseEvent', {
    type: 'mouseReleased', x: rect[0], y: rect[1], button: 'left', clickCount: 1,
  });
  await wait(700);
}

async function visibleNames() {
  await evaluate('document.querySelector("flt-semantics-placeholder")?.click()');
  const response = await send('Accessibility.getFullAXTree');
  return [...new Set(response.result.nodes.map((node) => node.name?.value).filter(Boolean))];
}

const evidence = [];
evidence.push(await capture('/?app=1', 'overview-390', ['Net worth', 'Cash balances']));
evidence.push(await capture('/transactions?app=1', 'transactions-390', ['8 of 8 transactions', 'Filters']));
evidence.push(await capture('/accounts?app=1', 'accounts-390', ['Cash Accounts', 'Assets & Liabilities']));
evidence.push(await capture('/analysis?app=1', 'analysis-trends-390', ['Net worth (USD)', 'Account history']));
await clickSemantics('Categories');
const categoriesNames = await visibleNames();
if (!categoriesNames.some((name) => name.includes('Spending by Category'))) {
  throw new Error('Analysis Categories view did not render.');
}
const categoriesShot = await send('Page.captureScreenshot', {
  format: 'png',
  fromSurface: true,
  captureBeyondViewport: false,
});
fs.writeFileSync(
  path.join(evidenceDir, 'analysis-categories-390.png'),
  Buffer.from(categoriesShot.result.data, 'base64'),
);
evidence.push({ file: 'analysis-categories-390.png', content: 'Categories view' });
await clickSemantics('All tags');
const tagSheetNames = await visibleNames();
if (!tagSheetNames.includes('Filter categories by tag') || !tagSheetNames.includes('Boston')) {
  throw new Error('Tag filter did not expose its title and CSV tag.');
}
const tagSheetScreenshot = await send('Page.captureScreenshot', {
  format: 'png',
  fromSurface: true,
  captureBeyondViewport: false,
});
fs.writeFileSync(
  path.join(evidenceDir, 'analysis-tag-filter-390.png'),
  Buffer.from(tagSheetScreenshot.result.data, 'base64'),
);
evidence.push({ file: 'analysis-tag-filter-390.png', content: 'All tags and Boston selection' });
await clickSemantics('Boston');
const filteredNames = await visibleNames();
if (!filteredNames.includes('Boston')) throw new Error('Selected tag was not retained in the toolbar.');

await navigate('/analysis?app=1');
await clickSemantics('Choose Net Worth Period More');
const periodNames = await visibleNames();
if (!periodNames.includes('All history') || !periodNames.includes('5 years')) {
  throw new Error('The period chooser did not expose all historical ranges.');
}
const periodScreenshot = await send('Page.captureScreenshot', {
  format: 'png',
  fromSurface: true,
  captureBeyondViewport: false,
});
fs.writeFileSync(
  path.join(evidenceDir, 'analysis-period-chooser-390.png'),
  Buffer.from(periodScreenshot.result.data, 'base64'),
);
evidence.push({ file: 'analysis-period-chooser-390.png', content: 'Seven period presets' });

await navigate('/analysis?app=1');
await clickSemantics('Categories');
for (let index = 0; index < 3; index++) {
  await send('Input.dispatchMouseEvent', {
    type: 'mouseWheel', x: 280, y: 650, deltaY: 450, deltaX: 0,
  });
  await wait(300);
}
const allocationRect = await evaluate(`(() => {
  const element = [...document.querySelectorAll('flt-semantics[role="button"]')]
    .find((item) => item.innerText.includes('Add Income Allocation'));
  if (!element) return null;
  const bounds = element.getBoundingClientRect();
  return [bounds.x + bounds.width / 2, bounds.y + bounds.height / 2, bounds.y, bounds.bottom];
})()`);
if (!allocationRect || allocationRect[2] < 0 || allocationRect[3] > 844) {
  throw new Error('Income allocation action was not brought into view.');
}
await send('Input.dispatchMouseEvent', {
  type: 'mousePressed', x: allocationRect[0], y: allocationRect[1], button: 'left', clickCount: 1,
});
await send('Input.dispatchMouseEvent', {
  type: 'mouseReleased', x: allocationRect[0], y: allocationRect[1], button: 'left', clickCount: 1,
});
await wait(1000);
const allocationNames = await visibleNames();
for (const text of ['Close', 'Expected amount', 'Save']) {
  if (!allocationNames.some((name) => name.includes(text))) {
    throw new Error(`Income allocation entry is missing: ${text}`);
  }
}
const allocationScreenshot = await send('Page.captureScreenshot', {
  format: 'png',
  fromSurface: true,
  captureBeyondViewport: false,
});
fs.writeFileSync(
  path.join(evidenceDir, 'income-allocation-390.png'),
  Buffer.from(allocationScreenshot.result.data, 'base64'),
);
evidence.push({ file: 'income-allocation-390.png', content: 'Adaptive allocation entry' });
evidence.push(
  await capture('/milestones?app=1&milestones=progress', 'milestones-progress-390', [
    'Last month average',
    'First milestone achieved',
    'Earned milestones',
  ]),
);
evidence.push(
  await capture('/milestones?app=1&milestones=celebration', 'milestones-celebration-390', [
    'You did it!',
    'A strong financial foundation',
  ]),
);
evidence.push(await capture('/?app=1', 'overview-320', ['Net worth', 'Cash balances'], 320, 740));
evidence.push(
  await capture('/transactions?app=1', 'transactions-320', ['8 of 8 transactions', 'Filters'], 320, 740),
);
evidence.push(await capture('/?app=1', 'overview-1280', ['Net worth', 'Cash balances'], 1280, 900));
evidence.push(
  await capture('/transactions?app=1', 'transactions-1280', ['8 of 8 transactions', 'Type All Types'], 1280, 900),
);
evidence.push(
  await capture('/analysis?app=1', 'analysis-trends-1280', ['Net worth (USD)', 'Account history'], 1280, 900),
);
await navigate('/transactions?app=1', 320, 740);
await send('Input.dispatchMouseEvent', {
  type: 'mouseWheel', x: 160, y: 450, deltaY: 350, deltaX: 0,
});
await wait(500);
const transferNames = await visibleNames();
if (!transferNames.some((name) => name.includes('From · Chase Checking')) ||
    !transferNames.some((name) => name.includes('To · Chase Freedom Rise'))) {
  throw new Error('Scrolled transfer row did not expose both labeled legs.');
}
const transferScreenshot = await send('Page.captureScreenshot', {
  format: 'png',
  fromSurface: true,
  captureBeyondViewport: false,
});
fs.writeFileSync(
  path.join(evidenceDir, 'transaction-transfer-320.png'),
  Buffer.from(transferScreenshot.result.data, 'base64'),
);
evidence.push({ file: 'transaction-transfer-320.png', content: 'Both transfer legs' });
const transferRect = await evaluate(`(() => {
  const element = [...document.querySelectorAll('flt-semantics[role="button"]')]
    .find((item) => item.innerText.includes('Credit Payment'));
  if (!element) return null;
  const bounds = element.getBoundingClientRect();
  return [bounds.x + bounds.width / 2, bounds.y + bounds.height / 2];
})()`);
if (!transferRect) throw new Error('Credit Payment row semantics target not found.');
await send('Input.dispatchMouseEvent', {
  type: 'mousePressed', x: transferRect[0], y: transferRect[1], button: 'left', clickCount: 1,
});
await send('Input.dispatchMouseEvent', {
  type: 'mouseReleased', x: transferRect[0], y: transferRect[1], button: 'left', clickCount: 1,
});
await wait(900);
const detailsNames = await visibleNames();
for (const text of ['Source', 'Destination', 'Chase Checking · -$ 380.00', 'Chase Freedom Rise · +$ 380.00']) {
  if (!detailsNames.some((name) => name.includes(text))) {
    throw new Error(`Transfer details are missing: ${text}`);
  }
}
const detailsScreenshot = await send('Page.captureScreenshot', {
  format: 'png',
  fromSurface: true,
  captureBeyondViewport: false,
});
fs.writeFileSync(
  path.join(evidenceDir, 'transaction-details-320.png'),
  Buffer.from(detailsScreenshot.result.data, 'base64'),
);
evidence.push({ file: 'transaction-details-320.png', content: 'Signed source/destination detail values' });

const directRoutes = [
  ['/analysis?app=1', 'Net worth (USD)', 'Analysis'],
  ['/accounts?app=1', 'Cash Accounts', 'Accounts'],
  ['/milestones?app=1', 'Add named milestones', 'More More'],
  ['/transactions?app=1', '8 of 8 transactions', 'Activity'],
  ['/prefix/analysis?app=1', 'Net worth (USD)', 'Analysis'],
];
const directResults = [];
for (const [route, visibleText, selectedTab] of directRoutes) {
  const page = await navigate(route);
  if (!page.names.some((name) => name.includes(visibleText))) {
    throw new Error(`Direct route ${route} did not show ${visibleText}.`);
  }
  if (page.selectedTab !== selectedTab) {
    throw new Error(`Direct route ${route} selected ${page.selectedTab}, expected ${selectedTab}.`);
  }
  directResults.push({ route, visibleText, selectedTab: page.selectedTab });
}
await navigate('/prefix/analysis?app=1');
await clickSemantics('Activity');
const prefixedNavigationUrl = await evaluate('location.pathname+location.search');
if (prefixedNavigationUrl !== '/prefix/transactions?app=1') {
  throw new Error(`Deployment-prefix navigation lost its prefix: ${prefixedNavigationUrl}`);
}

const refreshed = await navigate('/analysis?app=1');
await send('Page.reload', { ignoreCache: true });
await wait(3000);
const afterRefresh = await navigate('/analysis?app=1');
if (!afterRefresh.names.some((name) => name.includes('Net worth (USD)'))) {
  throw new Error('Refresh lost the direct Analysis destination.');
}

await navigate('/?app=1');
await clickSemantics('Activity');
const activityUrl = await evaluate('location.pathname+location.search');
await clickSemantics('Accounts');
const accountsUrl = await evaluate('location.pathname+location.search');
await evaluate('history.back()');
await wait(1000);
const backUrl = await evaluate('location.pathname+location.search');
const backNames = await visibleNames();
await evaluate('history.forward()');
await wait(1000);
const forwardUrl = await evaluate('location.pathname+location.search');
const forwardNames = await visibleNames();
if (activityUrl !== '/transactions?app=1' || accountsUrl !== '/accounts?app=1' ||
    backUrl !== activityUrl || !backNames.some((name) => name.includes('8 of 8 transactions')) ||
    forwardUrl !== accountsUrl || !forwardNames.some((name) => name.includes('Cash Accounts'))) {
  throw new Error('Browser Back/Forward did not restore the matching section and URL.');
}

const beforeMore = await evaluate('location.pathname+location.search');
await clickSemantics('More More');
await send('Input.dispatchMouseEvent', {
  type: 'mousePressed', x: 8, y: 300, button: 'left', clickCount: 1,
});
await send('Input.dispatchMouseEvent', {
  type: 'mouseReleased', x: 8, y: 300, button: 'left', clickCount: 1,
});
await wait(700);
const afterMore = await evaluate('location.pathname+location.search');
if (beforeMore !== afterMore) throw new Error('Dismissing More changed the route.');

if (browserErrors.length > 0) {
  throw new Error(`Browser protocol/runtime errors:\n${browserErrors.join('\n')}`);
}

console.log(
  JSON.stringify(
    {
      evidence,
      directRoutes: directResults,
      prefixedNavigationUrl,
      refresh: { url: afterRefresh.state.url, selectedTab: afterRefresh.selectedTab },
      history: { activityUrl, accountsUrl, backUrl, forwardUrl },
      moreDismissal: { before: beforeMore, after: afterMore },
      browserErrors,
      viewport: refreshed.state,
    },
    null,
    2,
  ),
);
socket.close();
