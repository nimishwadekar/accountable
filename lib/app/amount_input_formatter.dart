import 'package:flutter/services.dart';

/// Adds thousands separators to the integer part of a typed amount while
/// keeping the caret anchored to the same position in the unformatted text.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }

    final ungrouped = newValue.text.replaceAll(',', '');
    final formatted = _formatIntegerPart(ungrouped);
    if (formatted == newValue.text) return newValue;

    int mapOffset(int offset) {
      if (offset < 0) return offset;
      final boundedOffset = offset.clamp(0, newValue.text.length);
      final logicalOffset = newValue.text
          .substring(0, boundedOffset)
          .replaceAll(',', '')
          .length;
      return _offsetForLogicalPosition(formatted, logicalOffset);
    }

    final selection = newValue.selection;
    final mappedSelection = selection.isValid
        ? TextSelection(
            baseOffset: mapOffset(selection.baseOffset),
            extentOffset: mapOffset(selection.extentOffset),
            affinity: selection.affinity,
            isDirectional: selection.isDirectional,
          )
        : TextSelection.collapsed(offset: formatted.length);

    return TextEditingValue(
      text: formatted,
      selection: mappedSelection,
      composing: TextRange.empty,
    );
  }

  String _formatIntegerPart(String value) {
    final decimalIndex = value.indexOf('.');
    final integerPart = decimalIndex < 0
        ? value
        : value.substring(0, decimalIndex);
    final suffix = decimalIndex < 0 ? '' : value.substring(decimalIndex);
    final sign = integerPart.startsWith('-') ? '-' : '';
    final unsigned = sign.isEmpty ? integerPart : integerPart.substring(1);
    final grouped = unsigned.replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$sign$grouped$suffix';
  }

  int _offsetForLogicalPosition(String text, int logicalPosition) {
    if (logicalPosition <= 0) return 0;
    var logicalOffset = 0;
    for (var index = 0; index < text.length; index++) {
      if (text[index] != ',') logicalOffset++;
      if (logicalOffset == logicalPosition) return index + 1;
    }
    return text.length;
  }
}
