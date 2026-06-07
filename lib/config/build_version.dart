import 'build_info.g.dart';

const _buildDateFromEnv = String.fromEnvironment('BUILD_DATE', defaultValue: '');
const _buildSeqFromEnv = String.fromEnvironment('BUILD_SEQ', defaultValue: '');

String _normalizedBuildDate() {
  final digits = _buildDateFromEnv.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 8) return digits;
  return kGeneratedBuildDate;
}

String _normalizedBuildSeq() {
  final digits = _buildSeqFromEnv.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return kGeneratedBuildSeq;
  final value = int.tryParse(digits);
  if (value == null || value <= 0) return kGeneratedBuildSeq;
  return value.toString().padLeft(2, '0');
}

/// Display version baked in at compile time, e.g. 20250607_01.
String get appBuildVersion =>
    '${_normalizedBuildDate()}_${_normalizedBuildSeq()}';
