import 'package:flutter/material.dart';

/// One shared messenger so alerts can be shown from anywhere in the app.
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
