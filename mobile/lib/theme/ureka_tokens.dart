import 'package:flutter/material.dart';

abstract final class USpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  static const EdgeInsets cardPadding = EdgeInsets.all(14);
}

abstract final class URadii {
  static const double sm = 6;
  static const double md = 8;
  static const double card = 10;
  static const double xl = 14;
  static const double full = 999;
}

abstract final class UDurations {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
}
