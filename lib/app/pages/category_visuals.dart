import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../theme/design_tokens.dart';

class CategoryVisual {
  const CategoryVisual({
    required this.terms,
    required this.icon,
    required this.color,
  });

  final List<String> terms;
  final IconData icon;
  final Color color;
}

const _categoryVisuals = <CategoryVisual>[
  CategoryVisual(
    terms: ['dining', 'restaurant', 'food', 'meal'],
    icon: Icons.restaurant,
    color: Color(0xFFE76F51),
  ),
  CategoryVisual(
    terms: ['groceries'],
    icon: Icons.eco,
    color: Color(0xFF4CAF50),
  ),
  CategoryVisual(
    terms: ['shopping', 'clothing'],
    icon: Icons.shopping_bag,
    color: Color(0xFF7B61FF),
  ),
  CategoryVisual(
    terms: ['personal', 'beauty'],
    icon: Icons.spa,
    color: Color(0xFFE07A5F),
  ),
  CategoryVisual(
    terms: ['nightlife', 'bar', 'drinks', 'alcohol'],
    icon: Icons.wine_bar,
    color: Color(0xFF9B5DE5),
  ),
  CategoryVisual(
    terms: ['gifts', 'gift'],
    icon: Icons.card_giftcard,
    color: Color(0xFFE63946),
  ),
  CategoryVisual(
    terms: ['travel'],
    icon: Icons.directions_car,
    color: Color(0xFF2A9D8F),
  ),
  CategoryVisual(
    terms: ['transport', 'fuel', 'car'],
    icon: Icons.train,
    color: Color(0xFF277DA1),
  ),
  CategoryVisual(
    terms: ['health', 'medical', 'dental'],
    icon: Icons.health_and_safety,
    color: Color(0xFFD1495B),
  ),
  CategoryVisual(
    terms: ['housing', 'rent', 'home'],
    icon: Icons.home,
    color: Color(0xFF457B9D),
  ),
  CategoryVisual(
    terms: ['bills', 'bill'],
    icon: Icons.note_alt,
    color: Color(0xFF8D99AE),
  ),
  CategoryVisual(
    terms: ['utilities', 'internet', 'phone'],
    icon: Icons.receipt_long,
    color: Color(0xFFF4A261),
  ),
  CategoryVisual(
    terms: ['entertainment', 'leisure', 'hobby'],
    icon: Icons.movie,
    color: Color(0xFF6A4C93),
  ),
  CategoryVisual(
    terms: ['education', 'school', 'course'],
    icon: Icons.school,
    color: Color(0xFF277DA1),
  ),
  CategoryVisual(
    terms: ['tax', 'government', 'fee'],
    icon: Icons.account_balance,
    color: Color(0xFF606C38),
  ),
];

IconData categoryIcon(Category category) => _visualFor(category).icon;

Color categoryColor(Category category) => _visualFor(category).color;

CategoryVisual _visualFor(Category category) {
  final text = '${category.id} ${category.name}'.toLowerCase();
  return _categoryVisuals.firstWhere(
    (visual) => visual.terms.any(text.contains),
    orElse: () => const CategoryVisual(
      terms: [],
      icon: Icons.category_outlined,
      color: AppColors.teal,
    ),
  );
}
