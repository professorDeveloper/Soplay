import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riasdxd/core/subtitles/subtitle_parser.dart';

void main() {
  test('empty-bodied cue mid-file no longer truncates the rest', () {
    const srt = '1\n00:00:01,000 --> 00:00:02,000\nOne\n\n'
        '2\n00:00:03,000 --> 00:00:04,000\n\n'
        '3\n00:00:05,000 --> 00:00:06,000\nThree\n';
    final r = parseSubtitleText(srt);
    expect(r.isSuccess, true);
    expect(r.captions.map((c) => c.text).toList(), ['One', 'Three']);
  });

  test('double blank lines survive', () {
    const srt = '1\n00:00:01,000 --> 00:00:02,000\nOne\n\n\n'
        '2\n00:00:03,000 --> 00:00:04,000\nTwo\n\n\n'
        '3\n00:00:05,000 --> 00:00:06,000\nThree\n';
    expect(parseSubtitleText(srt).captions.length, 3);
  });

  test('single-digit hours and coordinate junk', () {
    const srt = '1\n0:00:01,000 --> 0:00:02,000  X1:100 X2:600 Y1:20 Y2:50\n'
        'Hello\n\n'
        '2\n0:00:03,5 --> 0:00:04,500\nWorld\n';
    final r = parseSubtitleText(srt);
    expect(r.captions.length, 2);
    expect(r.captions[0].start, const Duration(seconds: 1));
    expect(r.captions[1].start, const Duration(seconds: 3, milliseconds: 500));
  });

  test('cues come back sorted by start', () {
    const srt = '1\n00:00:09,000 --> 00:00:10,000\nLate\n\n'
        '2\n00:00:01,000 --> 00:00:02,000\nEarly\n';
    final r = parseSubtitleText(srt);
    expect(r.captions.first.text, 'Early');
  });

  test('CRLF tolerated', () {
    const srt = '1\r\n00:00:01,000 --> 00:00:02,000\r\nOne\r\n\r\n';
    expect(parseSubtitleText(srt).captions.length, 1);
  });

  test('cp1251 Cyrillic decodes to real text', () {
    final bytes = <int>[];
    bytes.addAll(utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n'));
    // 'Привет' in cp1251.
    bytes.addAll([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2]);
    bytes.addAll(utf8.encode('\n\n'));
    final r = parseSubtitleBytes(bytes);
    expect(r.captions.single.text, 'Привет');
  });

  test('utf8 still wins when valid', () {
    final bytes = utf8.encode(
      '1\n00:00:01,000 --> 00:00:02,000\nПривет\n\n',
    );
    expect(parseSubtitleBytes(bytes).captions.single.text, 'Привет');
  });

  test('ASS dialogue converts instead of throwing', () {
    const ass = '[Script Info]\nTitle: x\n\n[Events]\n'
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
        r'Dialogue: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,{\an8}Hello, world'
        '\n';
    final r = parseSubtitleText(ass);
    expect(r.isSuccess, true);
    expect(r.captions.single.text, 'Hello, world');
    expect(r.captions.single.end,
        const Duration(seconds: 3, milliseconds: 500));
  });

  test('VTT body is not fed to the SRT parser', () {
    const vtt = 'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHi\n';
    final r = parseSubtitleText(vtt);
    expect(r.isSuccess, true);
  });

  test('html / zip / empty all fail explicitly', () {
    expect(parseSubtitleText('<!DOCTYPE html><html><body>no</body></html>')
        .failure, SubtitleParseFailure.html);
    expect(parseSubtitleBytes([0x50, 0x4B, 0x03, 0x04, 0x00]).failure,
        SubtitleParseFailure.archive);
    expect(parseSubtitleBytes(const []).failure, SubtitleParseFailure.empty);
    expect(parseSubtitleText('just some prose').failure,
        SubtitleParseFailure.unsupportedFormat);
  });

  test('gzip is unwrapped', () {
    final raw = utf8.encode('1\n00:00:01,000 --> 00:00:02,000\nOne\n\n');
    final gz = gzipEncodeForTest(raw);
    expect(parseSubtitleBytes(gz).captions.single.text, 'One');
  });
}

List<int> gzipEncodeForTest(List<int> bytes) => gzip.encode(bytes);
