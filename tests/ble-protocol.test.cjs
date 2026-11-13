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
  assert.match(connect, /No se enviaron escrituras/);
  assert.match(connect, /'\s*'\s*\)/);
});
