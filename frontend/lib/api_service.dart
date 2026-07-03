// api_service.dart - Service to communicate with the FastAPI backend

import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class ApiService {
  // Use localhost for local API server, or 10.0.2.2 for Android Emulator
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    } else if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    } else {
      return 'http://127.0.0.1:8000';
    }
  }

  /// Fetch the current simulated vehicle state and user profiles
  static Future<Map<String, dynamic>> getVehicleStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/status'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching vehicle status: $e');
      rethrow;
    }
  }

  /// Send a text chat message to the Co-Pilot
  static Future<Map<String, dynamic>> sendChatMessage(
      String message, List<Map<String, String>> chatHistory) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'message': message,
          'chat_history': chatHistory,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to send message: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in chat request: $e');
      rethrow;
    }
  }

  /// Update a sensor value manually in the simulator
  static Future<Map<String, dynamic>> updateSensorState(String key, dynamic value) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/status/update'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'key': key,
          'value': value,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to update sensor: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating sensor state: $e');
      rethrow;
    }
  }

  /// Speak text offline using the host TTS system
  static Future<bool> speakOffline(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/speak'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'text': text}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error triggering backend TTS: $e');
      return false;
    }
  }
}
