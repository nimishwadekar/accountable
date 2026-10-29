// Maps Chrome Performance trace call sites from a local profile build back to Dart.
// Usage: node tool/map_profile_trace.mjs TRACE.json build/web/main.dart.js.map
import { readFile } from 'node:fs/promises';

const [tracePath, mapPath] = process.argv.slice(2);
if (tracePath == null || mapPath == null) {
  throw new Error('Usage: node tool/map_profile_trace.mjs TRACE.json MAIN.dart.js.map');
}

const trace = JSON.parse(await readFile(tracePath, 'utf8'));
const sourceMap = JSON.parse(await readFile(mapPath, 'utf8'));
const targets = new Map();
const isCpuProfile = Array.isArray(trace.nodes) && Array.isArray(trace.samples);
const cpuSelfTime = new Map();
const cpuInclusiveTime = new Map();
if (isCpuProfile) {
  for (var index = 0; index < trace.samples.length; index++) {
    const nodeId = trace.samples[index];
    cpuSelfTime.set(
      nodeId,
      (cpuSelfTime.get(nodeId) ?? 0) + (trace.timeDeltas[index] ?? 0),
    );
  }
  const parentByNode = new Map();
  for (const node of trace.nodes) {
    for (const child of node.children ?? []) parentByNode.set(child, node.id);
  }
  for (var index = 0; index < trace.samples.length; index++) {
    const delta = trace.timeDeltas[index] ?? 0;
    var nodeId = trace.samples[index];
    while (nodeId != null) {
      cpuInclusiveTime.set(
        nodeId,
        (cpuInclusiveTime.get(nodeId) ?? 0) + delta,
      );
      nodeId = parentByNode.get(nodeId);
    }
  }
}
const inputEvents = isCpuProfile
  ? trace.nodes.map((node) => ({
      name: node.callFrame?.functionName || '(anonymous)',
      dur: cpuSelfTime.get(node.id) ?? 0,
      inclusiveDur: cpuInclusiveTime.get(node.id) ?? 0,
      args: { data: node.callFrame },
    }))
  : (trace.traceEvents ?? []);
for (const event of inputEvents) {
  const frame = event.args?.data;
  if (
    frame?.url?.endsWith('/main.dart.js') !== true ||
    !Number.isInteger(frame.lineNumber) ||
    !Number.isInteger(frame.columnNumber)
  ) {
    continue;
  }
  const key = `${frame.lineNumber}:${frame.columnNumber}`;
  const entries = targets.get(key) ?? [];
  entries.push(event);
  targets.set(key, entries);
}

const positions = [...targets.keys()]
  .map((key) => {
    const [line, column] = key.split(':').map(Number);
    return { key, line, column };
  })
  .sort((a, b) => a.line - b.line || a.column - b.column);
const byLine = new Map();
for (const position of positions) {
  const columns = byLine.get(position.line) ?? [];
  columns.push(position);
  byLine.set(position.line, columns);
}

const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function decodeVlq(segment, start) {
  var result = 0;
  var shift = 0;
  var cursor = start;
  var continuation;
  do {
    const digit = alphabet.indexOf(segment[cursor++]);
    if (digit < 0) throw new Error('Invalid source-map VLQ digit.');
    continuation = (digit & 32) !== 0;
    result += (digit & 31) << shift;
    shift += 5;
  } while (continuation);
  const negative = (result & 1) !== 0;
  const value = result >> 1;
  return { value: negative ? -value : value, cursor };
}

const mappings = sourceMap.mappings.split(';');
var sourceIndex = 0;
var originalLine = 0;
var originalColumn = 0;
var nameIndex = 0;
const mapped = new Map();
const lastTargetLine = positions.at(-1)?.line ?? -1;

for (var generatedLine = 0; generatedLine <= lastTargetLine; generatedLine++) {
  var generatedColumn = 0;
  var lastMapping = null;
  const requests = byLine.get(generatedLine) ?? [];
  var requestIndex = 0;
  for (const segment of (mappings[generatedLine] ?? '').split(',')) {
    if (segment === '') continue;
    var cursor = 0;
    const generatedDelta = decodeVlq(segment, cursor);
    generatedColumn += generatedDelta.value;
    cursor = generatedDelta.cursor;
    if (cursor === segment.length) {
      lastMapping = null;
    } else {
      sourceIndex += decodeVlq(segment, cursor).value;
      cursor = decodeVlq(segment, cursor).cursor;
      originalLine += decodeVlq(segment, cursor).value;
      cursor = decodeVlq(segment, cursor).cursor;
      originalColumn += decodeVlq(segment, cursor).value;
      cursor = decodeVlq(segment, cursor).cursor;
      if (cursor < segment.length) {
        nameIndex += decodeVlq(segment, cursor).value;
      }
      lastMapping = {
        source: sourceMap.sources[sourceIndex],
        line: originalLine + 1,
        column: originalColumn + 1,
        name: sourceMap.names[nameIndex] ?? null,
      };
    }
    while (
      requestIndex < requests.length &&
      requests[requestIndex].column < generatedColumn
    ) {
      mapped.set(requests[requestIndex++].key, lastMapping);
    }
  }
  while (requestIndex < requests.length) {
    mapped.set(requests[requestIndex++].key, lastMapping);
  }
}

const result = [];
for (const [key, events] of targets) {
  const location = mapped.get(key);
  if (location == null) continue;
  for (const event of events) {
    result.push({
      event: event.name,
      durationMs: Number(((event.dur ?? 0) / 1000).toFixed(3)),
      ...(isCpuProfile
        ? { inclusiveMs: Number((event.inclusiveDur / 1000).toFixed(3)) }
        : {}),
      generated: key,
      ...location,
    });
  }
}
result.sort((a, b) =>
  isCpuProfile
    ? b.inclusiveMs - a.inclusiveMs
    : b.durationMs - a.durationMs,
);
console.log(JSON.stringify(result.slice(0, 40), null, 2));
if (isCpuProfile) {
  const appFrames = result.filter((entry) =>
    /(?:tool\/performance_profile_app\.dart|lib\/app\/pages\/|lib\/features\/analysis\/)/.test(
      entry.source,
    ),
  );
  console.log('Mapped app frames:');
  console.log(JSON.stringify(appFrames.slice(0, 40), null, 2));
}
