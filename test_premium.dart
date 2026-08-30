import 'premium_utils.dart';
import 'package:flutter/material.dart';

void main() {
  final Map<String, dynamic> row = {
    'is_premium': true,
    'premium_expires_at': '2027-08-07T20:00:28.863+00:00'
  };
  print(isPremiumActive(row));
}
