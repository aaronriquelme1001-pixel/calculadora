'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');

const source = fs.readFileSync(path.join(__dirname, '..', 'app.js'), 'utf8');

function loadProtocolFromApplication() {
  const marker = '  const AoooGProtocol = {';
  const start = source.indexOf(marker);
  assert.notEqual(start, -1, 'AoooGProtocol must exist in app.js');
  const equals = source.indexOf('=', start);
  const end = source.indexOf('\n  };', equals);
  assert.notEqual(end, -1, 'AoooGProtocol object must close');
  const literal = source.slice(equals + 1, end + 4).trim();
  return vm.runInNewContext('(' + literal + ')');
}

test('BLE protocol builds and parses a valid three-byte sensor frame', () => {
  const protocol = loadProtocolFromApplication();
  const payload = [0x10, 0x20, 0x30];
  const frame = protocol.buildFrame([0x78, 0x24, 0x15], 0x14, payload);
  assert.equal(frame[0], 0x0c);
  assert.equal(frame[1], 8);
  assert.deepEqual(Array.from(frame.slice(2, 5)), [0x78, 0x24, 0x15]);
  const parsed = protocol.parseFrame(frame);
  assert.ok(parsed);
  assert.deepEqual(Array.from(parsed.sensorId), [0x78, 0x24, 0x15]);
  assert.equal(parsed.cmd, 0x14);
  assert.deepEqual(Array.from(parsed.payload), payload);
});

test('BLE protocol rejects invalid CRC and malformed frame lengths', () => {
  const protocol = loadProtocolFromApplication();
  const frame = protocol.buildFrame([1, 2, 3], 0x1a, []);
  const corrupted = Uint8Array.from(frame);
  corrupted[corrupted.length - 1] ^= 0xff;
  assert.equal(protocol.parseFrame(corrupted), null);
  const badLength = Uint8Array.from(frame);
  badLength[1] += 1;
  assert.equal(protocol.parseFrame(badLength), null);
  assert.equal(protocol.parseFrame(new Uint8Array([0x0c, 0x01])), null);
});

test('calibration row serialization is little-endian and range-checked', () => {
  const protocol = loadProtocolFromApplication();
  const bytes = protocol.rowToBytes(249.2, 546, 5000);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  assert.ok(Math.abs(view.getFloat32(0, true) - 249.2) < 0.001);
  assert.equal(view.getUint16(4, true), 546);
  assert.equal(view.getUint16(6, true), 5000);
  assert.throws(() => protocol.rowToBytes(-1, 10, 10), /fuera de rango/);
  assert.throws(() => protocol.rowToBytes(10, 65536, 10), /fuera de rango/);
});

test('web discovery opens the browser chooser without restrictive advertisement filters', () => {
  const start = source.indexOf('  async function connectBleSensor() {');
  const end = source.indexOf('\n  async function disconnectBleSensor()', start);
  assert.notEqual(start, -1);
  assert.notEqual(end, -1);
  const connect = source.slice(start, end);
  assert.match(connect, /requestDevice\(\{[\s\S]*acceptAllDevices:\s*true/);
  assert.match(connect, /optionalServices:\s*\[AoooGProtocol\.SERVICE_UUID\]/);
  assert.doesNotMatch(connect, /filters\s*:/);
  assert.doesNotMatch(connect, /782415/);
});

test('web connection treats advertisement monitoring as optional and verifies ID with read-only 0x1A', () => {
  assert.match(source, /typeof device\.watchAdvertisements !== 'function'[\s\S]*?resolve\(null\)/);
  assert.doesNotMatch(source, /resolveSensorId\s*\(/);
  const start = source.indexOf('  async function connectBleSensor() {');
  const end = source.indexOf('\n  async function disconnectBleSensor()', start);
  const connect = source.slice(start, end);
  assert.match(connect, /await readOutputMode\(\)/);
  assert.match(connect, /ID real válido/);
  assert.match(connect, /\n\s*''\s*\n\s*\);/);
});

test('serial number conversion calculates 24-bit integer SN and parses decimal or hex sensor ID', () => {
  const protocol = loadProtocolFromApplication();

  // Conversion [0x0C, 0x52, 0x02] -> 807426
  assert.equal(protocol.sensorIdToSN([0x0c, 0x52, 0x02]), 807426);
  assert.equal(protocol.sensorIdToSN([0, 0, 0]), 0);
  assert.equal(protocol.sensorIdToSN([0xff, 0xff, 0xff]), 16777215);

  // Parse decimal Serial Number
  assert.deepEqual(Array.from(protocol.snToSensorId('807426')), [0x0c, 0x52, 0x02]);
  assert.deepEqual(Array.from(protocol.snToSensorId('SN: 807426')), [0x0c, 0x52, 0x02]);
  assert.deepEqual(Array.from(protocol.snToSensorId('ID: 807426')), [0x0c, 0x52, 0x02]);

  // Parse hex with colons/dashes
  assert.deepEqual(Array.from(protocol.snToSensorId('0C:52:02')), [0x0c, 0x52, 0x02]);
  assert.deepEqual(Array.from(protocol.snToSensorId('0c-52-02')), [0x0c, 0x52, 0x02]);
  assert.deepEqual(Array.from(protocol.snToSensorId('78:24:15')), [0x78, 0x24, 0x15]);

  // Parse hex with letters without separator
  assert.deepEqual(Array.from(protocol.snToSensorId('0c5202')), [0x0c, 0x52, 0x02]);
  assert.deepEqual(Array.from(protocol.snToSensorId('0BF04F')), [0x0b, 0xf0, 0x4f]);

  // Rejects invalid formats and zero
  assert.equal(protocol.snToSensorId('0'), null);
  assert.equal(protocol.snToSensorId('000000'), null);
  assert.equal(protocol.snToSensorId('00:00:00'), null);
  assert.equal(protocol.snToSensorId('invalid_id'), null);
  assert.equal(protocol.snToSensorId(''), null);
});

test('advertisement parser extracts sensor ID, SN, battery, frequency and temperature from AoooG and Universal manufacturer data', () => {
  const protocol = loadProtocolFromApplication();

  // Test AoooG format 0xFF43 (15 bytes)
  const aooogBuf = Buffer.alloc(15);
  aooogBuf[0] = 0x0c;
  aooogBuf[1] = 0x52;
  aooogBuf[2] = 0x02; // ID [0x0C, 0x52, 0x02] -> SN 807426
  // batteryCode: 715 -> ((715-500)*100)/220 = 98%
  aooogBuf[3] = (715 >> 8) & 0x0f;
  aooogBuf[4] = 715 & 0xff;
  // temperature: 20°C * 8 = 160
  aooogBuf.writeInt16BE(160, 5);
  // frequency: 546.2 Hz float32 LE
  aooogBuf.writeFloatLE(546.2, 7);
  // output: 249.2 L float32 LE
  aooogBuf.writeFloatLE(249.2, 11);

  const mockMapAoooG = new Map();
  mockMapAoooG.set(0xff43, aooogBuf);
  const parsedAoooG = protocol.parseAdvertisement(mockMapAoooG);
  assert.ok(parsedAoooG);
  assert.deepEqual(Array.from(parsedAoooG.id), [0x0c, 0x52, 0x02]);
  assert.equal(parsedAoooG.sn, 807426);
  assert.equal(parsedAoooG.battery, 98);
  assert.equal(parsedAoooG.temperature, 20);
  assert.ok(Math.abs(parsedAoooG.frequency - 546.2) < 0.01);
  assert.ok(Math.abs(parsedAoooG.output - 249.2) < 0.01);

  // Test Universal format 0xFFFF (24 bytes)
  const uniBuf = Buffer.alloc(24);
  uniBuf[0] = 0x3f; uniBuf[1] = 0x36; uniBuf[2] = 0xb4; uniBuf[5] = 0x5b;
  uniBuf[6] = 0x0c; uniBuf[7] = 0x52; uniBuf[8] = 0x02; // ID [0x0C, 0x52, 0x02] -> SN 807426
  uniBuf[14] = (546 >> 8) & 0xff; uniBuf[15] = 546 & 0xff; // freq 546 Hz
  uniBuf[18] = 0; uniBuf[19] = 100; // emptyFreq 100 Hz
  uniBuf[20] = 0; uniBuf[21] = 249; // output
  uniBuf[22] = 62; // temp: 62 - 40 = 22°C
  uniBuf[23] = 95; // battery 95%

  const mockMapUni = new Map();
  mockMapUni.set(0xffff, uniBuf);
  const parsedUni = protocol.parseAdvertisement(mockMapUni);
  assert.ok(parsedUni);
  assert.deepEqual(Array.from(parsedUni.id), [0x0c, 0x52, 0x02]);
  assert.equal(parsedUni.sn, 807426);
  assert.equal(parsedUni.battery, 95);
  assert.equal(parsedUni.temperature, 22);
  assert.equal(parsedUni.frequency, 546);
});


function loadApplicationFunction(name, nextName) {
  const start = source.indexOf(`  function ${name}(`);
  assert.notEqual(start, -1, `${name} must exist in app.js`);
  const end = source.indexOf(`  function ${nextName}(`, start);
  assert.notEqual(end, -1, `next function after ${name} must exist`);
  const declaration = source.slice(start, end).trim();
  return vm.runInNewContext('(' + declaration.replace(/^function /, 'function ') + ')');
}

function makeTelemetryPayload({ temp = 20, full = 5000, empty = 100, freq = 546.2, output = 249.2 } = {}) {
  const payload = new Uint8Array(22);
  const view = new DataView(payload.buffer);
  view.setUint16(0, 715, false);
  view.setInt16(2, temp * 8, false);
  view.setFloat32(6, full, true);
  view.setFloat32(10, empty, true);
  view.setFloat32(14, freq, true);
  view.setFloat32(18, output, true);
  return payload;
}

test('BLE credential parser converts exactly 16 hex characters to eight bytes without retaining text', () => {
  const parseCredential = loadApplicationFunction('parseBleCredential', 'isValidTelemetryFrame');
  assert.deepEqual(Array.from(parseCredential('0011223344556677')), [0, 17, 34, 51, 68, 85, 102, 119]);
  assert.deepEqual(Array.from(parseCredential('  aAbBcCdDeEfF0011  ')), [170, 187, 204, 221, 238, 255, 0, 17]);
  assert.equal(parseCredential('001122334455667'), null);
  assert.equal(parseCredential('00112233445566GG'), null);
  assert.equal(parseCredential(''), null);
});

test('only a complete, coherent 0x14 telemetry frame can establish an unknown sensor ID', () => {
  const isValidTelemetryFrame = loadApplicationFunction('isValidTelemetryFrame', 'extractSensorDataFromAdvertisement');
  const valid = { cmd: 0x14, sensorId: [0x0c, 0x52, 0x02], payload: makeTelemetryPayload() };
  assert.equal(isValidTelemetryFrame(valid), true);
  assert.equal(isValidTelemetryFrame({ ...valid, cmd: 0x12 }), false);
  assert.equal(isValidTelemetryFrame({ ...valid, payload: makeTelemetryPayload().slice(0, 21) }), false);
  assert.equal(isValidTelemetryFrame({ ...valid, sensorId: [0, 0, 0] }), false);
  assert.equal(isValidTelemetryFrame({ ...valid, payload: makeTelemetryPayload({ freq: NaN }) }), false);
  assert.equal(isValidTelemetryFrame({ ...valid, payload: makeTelemetryPayload({ freq: -1 }) }), false);
  assert.equal(isValidTelemetryFrame({ ...valid, payload: makeTelemetryPayload({ temp: 200 }) }), false);
});

test('notification handler cannot learn an ID from an arbitrary CRC-valid frame', () => {
  const start = source.indexOf('  function handleBleNotification(event) {');
  const end = source.indexOf('\n  // Búsqueda principal abierta', start);
  assert.ok(start >= 0 && end > start);
  const handler = source.slice(start, end);
  assert.match(handler, /!bleState\.sensorId && isValidTelemetryFrame\(parsed\)/);
  assert.doesNotMatch(handler, /if \(!bleState\.sensorId && parsed\.sensorId/);
  assert.match(handler, /if \(!sameSensorId\(parsed\.sensorId, bleState\.sensorId\)\) return/);
});

test('both visible discovery entry points use the unfiltered chooser as primary path', () => {
  const targetedStart = source.indexOf('  async function connectBleSensorTargeted() {');
  const targetedEnd = source.indexOf('\n  async function connectBleSensor() {', targetedStart);
  const targeted = source.slice(targetedStart, targetedEnd);
  assert.match(targeted, /return connectBleSensor\(\)/);
  assert.doesNotMatch(targeted, /manufacturerData|filters\s*:/);
  const connectStart = source.indexOf('  async function connectBleSensor() {');
  const connectEnd = source.indexOf('\n  async function disconnectBleSensor()', connectStart);
  const connect = source.slice(connectStart, connectEnd);
  assert.match(connect, /acceptAllDevices:\s*true/);
  assert.match(connect, /optionalServices:\s*\[AoooGProtocol\.SERVICE_UUID\]/);
});

test('authentication requires a positive 0x12 ACK and never logs the credential', () => {
  const start = source.indexOf('  async function authenticateBleSensor() {');
  const end = source.indexOf('\n  async function readBleSensorParameters()', start);
  const auth = source.slice(start, end);
  assert.match(auth, /parseBleCredential\(input\?\.value \|\| ''\)/);
  assert.match(auth, /sendBleCommand\(0x12, bytes, 6000\)/);
  assert.match(auth, /isSuccessAck\(response, 0x12\)/);
  assert.match(auth, /bleState\.isAuthenticated = false/);
  assert.doesNotMatch(auth, /console\.(log|info|debug).*credential/i);
});
