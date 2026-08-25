import 'package:couple_chat_app/src/features/travel_map/presentation/travel_map_page.dart';
import 'package:flutter/material.dart';

class TravelCityDetailPage extends StatelessWidget {
  const TravelCityDetailPage({required this.cityId, super.key});

  final String cityId;

  @override
  Widget build(BuildContext context) {
    return TravelMapPage(initialCityId: cityId);
  }
}
