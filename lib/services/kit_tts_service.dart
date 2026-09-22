import 'package:flutter_tts/flutter_tts.dart';

/// 分貨格位語音播報（掃碼成功後唸「第 N 櫃」）
class KitTtsService {
  KitTtsService() {
    _ready = _init();
  }

  final FlutterTts _tts = FlutterTts();
  late final Future<void> _ready;

  Future<void> _init() async {
    try {
      final languages = await _tts.getLanguages;
      final list = languages is List
          ? languages.map((e) => '$e'.toLowerCase()).toList()
          : <String>[];
      if (list.any((l) => l.contains('zh-tw') || l.contains('zh_tw'))) {
        await _tts.setLanguage('zh-TW');
      } else if (list.any((l) => l.contains('zh-cn') || l.contains('zh_cn'))) {
        await _tts.setLanguage('zh-CN');
      } else {
        await _tts.setLanguage('zh-TW');
      }
      // Android：0.5 約為正常語速；略快一點方便連續掃碼
      await _tts.setSpeechRate(0.55);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(false);
    } catch (_) {
      // 裝置無 TTS 引擎時靜默略過
    }
  }

  /// 將 0001 / 01 / 1 正規成可唸的數字
  static String normalizeKitNumber(String kit) {
    final digits = kit.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    return '${int.parse(digits)}';
  }

  Future<void> speakKit(String kit) async {
    final n = normalizeKitNumber(kit);
    if (n.isEmpty) return;
    try {
      await _ready;
      await _tts.stop();
      await _tts.speak('第$n櫃');
    } catch (_) {}
  }

  Future<void> speakKitCompleted(String kit) async {
    final n = normalizeKitNumber(kit);
    if (n.isEmpty) return;
    try {
      await _ready;
      await _tts.stop();
      await _tts.speak('第$n櫃已完成');
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
