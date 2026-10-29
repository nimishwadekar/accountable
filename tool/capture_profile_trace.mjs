// Captures local Chrome Performance traces for performance_profile_app.dart.
// The harness contains generated data only and never contacts Google Sheets.
// Run after `flutter run --profile -d web-server --target=tool/performance_profile_app.dart --web-port=9000`:
// node tool/capture_profile_trace.mjs
import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const chromePath =
  process.env.CHROME_BIN ??
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const port = Number(process.env.CDP_PORT ?? 9229);
const root =
  process.env.PROFILE_OUTPUT_DIR ??
  path.join(os.tmpdir(), 'accountable-profile-traces');
const profileDirectory = path.join(root, 'chrome-user-data');
await mkdir(root, { recursive: true });
await mkdir(profileDirectory, { recursive: true });

const chrome = spawn(
  chromePath,
  [
    '--headless=new',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-background-networking',
    `--remote-debugging-port=${port}`,
    '--remote-allow-origins=*',
    `--user-data-dir=${profileDirectory}`,
    '--window-size=1440,1000',
    'about:blank',
  ],
  { stdio: 'ignore' },
);

const sleep = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
  return response.json();
}

async function waitForDebugger() {
  for (var attempt = 0; attempt < 100; attempt++) {
    try {
      return await fetchJson(`http://127.0.0.1:${port}/json/version`);
    } catch (_) {
      await sleep(100);
    }
  }
  throw new Error('Chrome remote debugging did not start.');
}

let socket;
try {
  await waitForDebugger();
  const targets = await fetchJson(`http://127.0.0.1:${port}/json/list`);
  const page = targets.find((target) => target.type === 'page');
  if (page == null) throw new Error('Chrome did not create a page target.');

  socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });

  let nextId = 0;
  const pending = new Map();
  let traceEvents = [];
  let traceComplete = null;
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id != null) {
      const callbacks = pending.get(message.id);
      if (callbacks == null) return;
      pending.delete(message.id);
      if (message.error != null) {
        callbacks.reject(new Error(message.error.message));
      } else {
        callbacks.resolve(message.result ?? {});
      }
      return;
    }
    if (message.method === 'Tracing.dataCollected') {
      traceEvents.push(...message.params.value);
    } else if (message.method === 'Tracing.tracingComplete') {
      traceComplete?.resolve();
    }
  });

  function command(method, params = {}) {
    const id = ++nextId;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      socket.send(JSON.stringify({ id, method, params }));
    });
  }

  const pageUrl = process.env.PROFILE_URL ?? 'http://127.0.0.1:9000';
  await command('Page.enable');
  await command('Runtime.enable');

  async function evaluate(expression) {
    const response = await command('Runtime.evaluate', {
      expression,
      returnByValue: true,
      awaitPromise: true,
    });
    return response.result?.value;
  }

  async function clickAt(x, y) {
    await command('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
    await command('Input.dispatchMouseEvent', {
      type: 'mousePressed',
      x,
      y,
      button: 'left',
      clickCount: 1,
    });
    await command('Input.dispatchMouseEvent', {
      type: 'mouseReleased',
      x,
      y,
      button: 'left',
      clickCount: 1,
    });
  }

  async function wheel(deltaY, count = 1) {
    for (var index = 0; index < count; index++) {
      await command('Input.dispatchMouseEvent', {
        type: 'mouseWheel',
        x: 720,
        y: 720,
        deltaX: 0,
        deltaY,
      });
      await sleep(16);
    }
  }

  async function waitForHarness() {
    for (var attempt = 0; attempt < 200; attempt++) {
      const ready = await evaluate(
        "document.readyState === 'complete' && !!document.querySelector('flt-glass-pane')",
      );
      if (ready) return;
      await sleep(100);
    }
    throw new Error('Flutter profile harness did not finish loading.');
  }

  async function startTrace() {
    traceEvents = [];
    traceComplete = {};
    traceComplete.promise = new Promise((resolve, reject) => {
      traceComplete.resolve = resolve;
      traceComplete.reject = reject;
    });
    await command('Tracing.start', {
      categories:
        'devtools.timeline,v8.execute,blink.user_timing,disabled-by-default-devtools.timeline,disabled-by-default-devtools.timeline.frame',
      options: 'sampling-frequency=10000',
      transferMode: 'ReportEvents',
    });
  }

  async function startCpuProfile() {
    await command('Profiler.enable');
    await command('Profiler.start');
  }

  async function stopCpuProfile(label, filename) {
    const { profile } = await command('Profiler.stop');
    await writeFile(path.join(root, `${filename}.cpu.json`), JSON.stringify(profile));
    const timeByNode = new Map();
    for (var index = 0; index < profile.samples.length; index++) {
      const nodeId = profile.samples[index];
      timeByNode.set(
        nodeId,
        (timeByNode.get(nodeId) ?? 0) + (profile.timeDeltas[index] ?? 0),
      );
    }
    const parentByNode = new Map();
    for (const node of profile.nodes) {
      for (const child of node.children ?? []) parentByNode.set(child, node.id);
    }
    const inclusiveTimeByNode = new Map();
    for (var sampleIndex = 0; sampleIndex < profile.samples.length; sampleIndex++) {
      const delta = profile.timeDeltas[sampleIndex] ?? 0;
      var nodeId = profile.samples[sampleIndex];
      while (nodeId != null) {
        inclusiveTimeByNode.set(
          nodeId,
          (inclusiveTimeByNode.get(nodeId) ?? 0) + delta,
        );
        nodeId = parentByNode.get(nodeId);
      }
    }
    const nodesById = new Map(profile.nodes.map((node) => [node.id, node]));
    const hotFunctions = [...inclusiveTimeByNode.entries()]
      .map(([id, microseconds]) => {
        const node = nodesById.get(id);
        const frame = node?.callFrame ?? {};
        return {
          function: frame.functionName || '(anonymous)',
          url: frame.url,
          line: frame.lineNumber,
          selfMs: (timeByNode.get(id) ?? 0) / 1000,
          inclusiveMs: microseconds / 1000,
        };
      })
      .filter((entry) => entry.url?.includes('main.dart.js'))
      .sort((a, b) => b.inclusiveMs - a.inclusiveMs)
      .slice(0, 25);
    console.log(`${label} CPU profile hot samples:`);
    console.log(JSON.stringify(hotFunctions, null, 2));
  }

  function summarize(events) {
    const tasks = events
      .filter((event) =>
        event.ph === 'X' &&
        (event.name === 'RunTask' ||
          event.name === 'FunctionCall' ||
          event.name === 'EvaluateScript' ||
          event.name === 'Layout' ||
          event.name === 'Paint'),
      )
      .map((event) => ({
        name: event.name,
        durationMs: (event.dur ?? 0) / 1000,
        category: event.cat,
      }));
    const runTasks = tasks.filter((event) => event.name === 'RunTask');
    const longTasks = runTasks
      .filter((event) => event.durationMs >= 16.7)
      .sort((a, b) => b.durationMs - a.durationMs);
    return {
      eventCount: events.length,
      runTaskCount: runTasks.length,
      longTaskCount: longTasks.length,
      longestRunTasksMs: longTasks.slice(0, 12).map((task) => task.durationMs),
      longestOtherEvents: tasks
        .filter((event) => event.name !== 'RunTask')
        .sort((a, b) => b.durationMs - a.durationMs)
        .slice(0, 10),
    };
  }

  async function stopTrace(name) {
    await command('Tracing.end');
    await traceComplete.promise;
    const filename = path.join(root, `${name}.json`);
    await writeFile(filename, JSON.stringify({ traceEvents }));
    console.log(`${name}: ${filename}`);
    console.log(JSON.stringify(summarize(traceEvents), null, 2));
  }

  await startCpuProfile();
  await startTrace();
  await command('Page.navigate', { url: pageUrl });
  await waitForHarness();
  await sleep(2000);
  const screenshot = await command('Page.captureScreenshot', {
    format: 'png',
    captureBeyondViewport: false,
  });
  await writeFile(
    path.join(root, 'profile-harness.png'),
    Buffer.from(screenshot.data, 'base64'),
  );
  await stopCpuProfile('Startup', '01-startup');
  await stopTrace('01-startup');

  await startCpuProfile();
  await startTrace();
  await wheel(600, 24);
  await sleep(500);
  await stopCpuProfile('Transactions scroll', '02-transactions-scroll-hidden');
  await stopTrace('02-transactions-scroll-hidden');

  await wheel(-1200, 12);
  await sleep(300);
  await startCpuProfile();
  await startTrace();
  await clickAt(240, 317); // Show balances
  await sleep(500);
  await stopCpuProfile('Show balances toggle', '03-show-balances-toggle');
  await stopTrace('03-show-balances-toggle');

  await startCpuProfile();
  await startTrace();
  await wheel(600, 24);
  await sleep(500);
  await stopCpuProfile(
    'Transactions scroll with balances visible',
    '04-transactions-scroll-balances-visible',
  );
  await stopTrace('04-transactions-scroll-balances-visible');

  await wheel(-1500, 12); // Return the scrollable list near its top.
  await sleep(300);
  await startCpuProfile();
  await startTrace();
  await clickAt(1080, 78); // Analysis tab.
  await sleep(2500);
  const analysisScreenshot = await command('Page.captureScreenshot', {
    format: 'png',
    captureBeyondViewport: false,
  });
  await writeFile(
    path.join(root, 'profile-analysis.png'),
    Buffer.from(analysisScreenshot.data, 'base64'),
  );
  await stopCpuProfile('Analysis initial render', '05-analysis-initial-render');
  await stopTrace('05-analysis-initial-render');

  await startCpuProfile();
  await startTrace();
  await clickAt(504, 609); // MAX net-worth range.
  await sleep(1200);
  const maxScreenshot = await command('Page.captureScreenshot', {
    format: 'png',
    captureBeyondViewport: false,
  });
  await writeFile(
    path.join(root, 'profile-analysis-max.png'),
    Buffer.from(maxScreenshot.data, 'base64'),
  );
  await stopCpuProfile('Analysis MAX range', '06-analysis-max-range');
  await stopTrace('06-analysis-max-range');

  await startCpuProfile();
  await startTrace();
  for (var point = 0; point < 20; point++) {
    await command('Input.dispatchMouseEvent', {
      type: 'mouseMoved',
      x: 190 + point * 54,
      y: 400,
    });
    await sleep(16);
  }
  await sleep(300);
  await stopCpuProfile('Analysis chart hover', '07-analysis-chart-hover');
  await stopTrace('07-analysis-chart-hover');

  await command('Page.close');
} finally {
  socket?.close();
  chrome.kill('SIGTERM');
}
