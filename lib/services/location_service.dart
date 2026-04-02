import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LocationService {
  static Future<Position?> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  static Future<String> getAddressFromLatLng(double lat, double lng) async {
    try {
      // Dùng Nominatim (OpenStreetMap) - miễn phí, không cần API key
      final String url = 'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1&accept-language=vi';
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'FlutterApp/1.0'
      }).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final address = json['address'] as Map<String, dynamic>?;
        if (address != null) {
          // Xây dựng địa chỉ từ các thành phần
          final parts = <String>[];
          if (address['house_number'] != null) parts.add(address['house_number'].toString());
          if (address['road'] != null) parts.add(address['road'].toString());
          if (address['hamlet'] != null) parts.add(address['hamlet'].toString());
          if (address['village'] != null) parts.add(address['village'].toString());
          if (address['town'] != null) parts.add(address['town'].toString());
          if (address['city'] != null) parts.add(address['city'].toString());
          if (address['district'] != null) parts.add(address['district'].toString());
          if (address['county'] != null) parts.add(address['county'].toString());
          if (address['state'] != null) parts.add(address['state'].toString());
          if (address['country'] != null) parts.add(address['country'].toString());
          
          final result = parts.join(', ');
          if (result.isNotEmpty) return result;
        }
      }
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
    }
    return '$lat, $lng';
  }
}
