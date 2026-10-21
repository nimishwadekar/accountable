import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../theme/design_tokens.dart';

IconData categoryIcon(Category category) {
  final text = '${category.id} ${category.name}'.toLowerCase();
  if (_contains(text, ['dining', 'restaurant', 'food', 'meal'])) return Icons.restaurant;
  if (_contains(text, ['groceries'])) return Icons.eco;
  if (_contains(text, ['shopping', 'clothing'])) return Icons.shopping_bag;
  if (_contains(text, ['personal', 'beauty'])) return Icons.spa;
  if (_contains(text, ['nightlife', 'bar', 'drinks', 'alcohol'])) return Icons.wine_bar;
  if (_contains(text, ['gifts', 'gift'])) return Icons.card_giftcard;
  if (_contains(text, ['travel'])) return Icons.directions_car;
  if (_contains(text, ['transport', 'fuel', 'car'])) return Icons.train;
  if (_contains(text, ['health', 'medical', 'dental'])) return Icons.health_and_safety;
  if (_contains(text, ['housing', 'rent', 'home'])) return Icons.home;
  if (_contains(text, ['bills', 'bill'])) return Icons.note_alt;
  if (_contains(text, ['utilities', 'internet', 'phone'])) return Icons.receipt_long;
  if (_contains(text, ['entertainment', 'leisure', 'hobby'])) return Icons.movie;
  if (_contains(text, ['education', 'school', 'course'])) return Icons.school;
  if (_contains(text, ['tax', 'government', 'fee'])) return Icons.account_balance;
  return Icons.category_outlined;
}

Color categoryColor(Category category) {
  final text = '${category.id} ${category.name}'.toLowerCase();
  if (_contains(text, ['dining', 'restaurant', 'food', 'meal'])) return const Color(0xFFE76F51);
  if (_contains(text, ['groceries'])) return const Color(0xFF4CAF50);
  if (_contains(text, ['shopping', 'clothing'])) return const Color(0xFF7B61FF);
  if (_contains(text, ['personal', 'beauty'])) return const Color(0xFFE07A5F);
  if (_contains(text, ['nightlife', 'bar', 'drinks', 'alcohol'])) return const Color(0xFF9B5DE5);
  if (_contains(text, ['gifts', 'gift'])) return const Color(0xFFE63946);
  if (_contains(text, ['travel'])) return const Color(0xFF2A9D8F);
  if (_contains(text, ['transport', 'fuel', 'car'])) return const Color(0xFF277DA1);
  if (_contains(text, ['health', 'medical', 'dental'])) return const Color(0xFFD1495B);
  if (_contains(text, ['housing', 'rent', 'home'])) return const Color(0xFF457B9D);
  if (_contains(text, ['bills', 'bill'])) return const Color(0xFF8D99AE);
  if (_contains(text, ['utilities', 'internet', 'phone'])) return const Color(0xFFF4A261);
  if (_contains(text, ['entertainment', 'leisure', 'hobby'])) return const Color(0xFF6A4C93);
  if (_contains(text, ['education', 'school', 'course'])) return const Color(0xFF277DA1);
  if (_contains(text, ['tax', 'government', 'fee'])) return const Color(0xFF606C38);
  return AppColors.teal;
}

bool _contains(String text, List<String> terms) => terms.any(text.contains);
