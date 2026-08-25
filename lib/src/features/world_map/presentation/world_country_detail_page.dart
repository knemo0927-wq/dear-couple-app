import 'package:couple_chat_app/src/features/world_map/presentation/world_map_page.dart';
import 'package:flutter/material.dart';

class WorldCountryDetailPage extends StatelessWidget {
  const WorldCountryDetailPage({required this.countryCode, super.key});

  final String countryCode;

  @override
  Widget build(BuildContext context) {
    return WorldMapPage(initialCountryCode: countryCode);
  }
}
