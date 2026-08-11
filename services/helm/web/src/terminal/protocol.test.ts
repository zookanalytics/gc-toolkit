import { describe, expect, it } from 'vitest';

import {
  ClientCommand,
  MIN_SIZE,
  clampSize,
  decodeServerMessage,
  encodeHandshake,
  encodeInput,
  encodeResize,
} from './protocol';

const decoder = new TextDecoder();
const encoder = new TextEncoder();

const commandOf = (frame: Uint8Array) => String.fromCharCode(frame[0]);
const bodyOf = (frame: Uint8Array) => decoder.decode(frame.subarray(1));

function serverFrame(command: string, payload: string): Uint8Array {
  const body = encoder.encode(payload);
  const frame = new Uint8Array(body.length + 1);
  frame[0] = command.charCodeAt(0);
  frame.set(body, 1);
  return frame;
}

describe('clampSize', () => {
  it('leaves a comfortable size alone', () => {
    expect(clampSize({ columns: 120, rows: 40 })).toEqual({ columns: 120, rows: 40 });
  });

  it('raises a cramped size to the floor', () => {
    expect(clampSize({ columns: 10, rows: 3 })).toEqual(MIN_SIZE);
  });

  it('floors fractional cell counts', () => {
    expect(clampSize({ columns: 100.9, rows: 30.9 })).toEqual({ columns: 100, rows: 30 });
  });

  it('falls back to the floor for non-finite input', () => {
    expect(clampSize({ columns: Number.NaN, rows: Number.POSITIVE_INFINITY })).toEqual(MIN_SIZE);
  });
});

describe('encodeHandshake', () => {
  it('is bare JSON with no command byte, as ttyd expects first', () => {
    const frame = encodeHandshake('tok', { columns: 100, rows: 30 });
    expect(JSON.parse(decoder.decode(frame))).toEqual({
      AuthToken: 'tok',
      columns: 100,
      rows: 30,
    });
  });

  it('clamps the reported size', () => {
    const frame = encodeHandshake('', { columns: 4, rows: 2 });
    expect(JSON.parse(decoder.decode(frame))).toEqual({
      AuthToken: '',
      columns: MIN_SIZE.columns,
      rows: MIN_SIZE.rows,
    });
  });
});

describe('encodeInput', () => {
  it('prefixes the INPUT command byte', () => {
    const frame = encodeInput('ls\r');
    expect(commandOf(frame)).toBe(ClientCommand.INPUT);
    expect(bodyOf(frame)).toBe('ls\r');
  });

  it('carries multi-byte input without corrupting it', () => {
    const frame = encodeInput('é→🙂');
    expect(bodyOf(frame)).toBe('é→🙂');
  });

  it('encodes an empty keystroke as the command byte alone', () => {
    expect(encodeInput('')).toEqual(new Uint8Array([ClientCommand.INPUT.charCodeAt(0)]));
  });
});

describe('encodeResize', () => {
  it('prefixes the RESIZE_TERMINAL command byte and clamps', () => {
    const frame = encodeResize({ columns: 40, rows: 10 });
    expect(commandOf(frame)).toBe(ClientCommand.RESIZE_TERMINAL);
    expect(JSON.parse(bodyOf(frame))).toEqual(MIN_SIZE);
  });
});

describe('decodeServerMessage', () => {
  it('decodes OUTPUT', () => {
    expect(decodeServerMessage(serverFrame('0', 'hello'))).toEqual({
      type: 'output',
      data: 'hello',
    });
  });

  it('decodes a window title', () => {
    expect(decodeServerMessage(serverFrame('1', 'mayor'))).toEqual({
      type: 'title',
      title: 'mayor',
    });
  });

  it('decodes preferences as JSON', () => {
    expect(decodeServerMessage(serverFrame('2', '{"fontSize":13}'))).toEqual({
      type: 'preferences',
      preferences: { fontSize: 13 },
    });
  });

  it('accepts an ArrayBuffer as well as a view', () => {
    const frame = serverFrame('0', 'hi');
    expect(decodeServerMessage(frame.buffer as ArrayBuffer)).toEqual({ type: 'output', data: 'hi' });
  });

  it('preserves multi-byte output', () => {
    expect(decodeServerMessage(serverFrame('0', '▍ é'))).toEqual({ type: 'output', data: '▍ é' });
  });

  it('ignores an unknown command instead of failing the session', () => {
    expect(decodeServerMessage(serverFrame('9', 'whatever'))).toEqual({
      type: 'unknown',
      command: '9',
    });
    expect(decodeServerMessage(serverFrame('2', 'not json'))).toEqual({
      type: 'unknown',
      command: '2',
    });
  });

  it('returns null for an empty frame', () => {
    expect(decodeServerMessage(new Uint8Array())).toBeNull();
  });
});
