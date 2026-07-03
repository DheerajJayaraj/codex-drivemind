// main.dart - DriveMind Edge AI Car Dashboard UI

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'api_service.dart';

void main() {
  runApp(const DriveMindApp());
}

class DriveMindApp extends StatelessWidget {
  const DriveMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DriveMind AI Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F121C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D1FF),
          secondary: Color(0xFF00FF85),
          surface: Color(0xFF161A26),
          error: Color(0xFFFF3B30),
        ),
        cardColor: const Color(0xFF161A26),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  // State variables for vehicle
  Map<String, dynamic> _vehicleState = {};
  Map<String, dynamic> _profiles = {};
  bool _isLoading = true;
  String _errorMsg = '';

  // Chat variables
  final List<Map<String, String>> _chatHistory = [];
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isWaitingForAI = false;

  // TTS & Speech-to-Text
  late FlutterTts _flutterTts;
  bool _isTtsEnabled = true;
  
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _speechText = '';

  // Timer for periodically fetching state updates (polling simulation)
  Timer? _statusTimer;

  // Animation controller for hazard lights flashing and music disk spinning
  late AnimationController _animationController;

  // Demo helper: quick command templates to trigger easy voice lines
  final List<String> _demoCommands = [
    "Hello",
    "Why is my battery warning light on?",
    "Why is my TPMS light on?",
    "Where is the cabin fuse box?",
    "I'm cold",
    "I'm hungry",
    "I'm sleepy",
    "Play my evening playlist",
    "Navigate home",
    "What have you learned about me?"
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();

    _initTts();
    _initSpeech();
    _fetchStatus();

    // Poll status every 2 seconds to capture state changes from the backend
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _fetchStatus();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _animationController.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initTts() {
    _flutterTts = FlutterTts();
    _flutterTts.setLanguage("en-US");
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setVolume(1.0);
    _flutterTts.setPitch(1.0);
  }

  void _initSpeech() async {
    _speech = stt.SpeechToText();
  }

  Future<void> _fetchStatus() async {
    try {
      final data = await ApiService.getVehicleStatus();
      if (mounted) {
        setState(() {
          _vehicleState = data['state'];
          _profiles = data['profiles'];
          _isLoading = false;
          _errorMsg = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Error communicating with DriveMind backend (FastAPI offline?).';
          _isLoading = false;
        });
      }
    }
  }

  void _speak(String text) async {
    if (!_isTtsEnabled) return;
    
    // First try standard FlutterTTS (client-side offline)
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      // If client-side fails, tell backend to speak on host system (FastAPI host computer)
      ApiService.speakOffline(text);
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    
    setState(() {
      _chatHistory.add({"role": "user", "content": text});
      _isWaitingForAI = true;
    });
    
    _chatController.clear();
    _scrollToBottom();

    // Call API
    try {
      final response = await ApiService.sendChatMessage(text, _chatHistory);
      
      setState(() {
        _chatHistory.add({
          "role": "assistant",
          "content": response['reply']
        });
        _vehicleState = response['state'];
        _isWaitingForAI = false;
      });

      _speak(response['reply']);
    } catch (e) {
      setState(() {
        _chatHistory.add({
          "role": "assistant",
          "content": "Sorry, I am unable to connect to the local model. Please verify Ollama is running."
        });
        _isWaitingForAI = false;
      });
    }
    
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) => print('onStatus: $val'),
        onError: (val) => print('onError: $val'),
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) => setState(() {
            _speechText = val.recognizedWords;
            _chatController.text = _speechText;
          }),
        );
      } else {
        // Speech recognition not available (e.g. Chrome permission or Windows setup)
        // Show a snackbar and allow simulated voice trigger
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition not available. Please type or use quick commands.')),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
      if (_chatController.text.isNotEmpty) {
        _sendMessage(_chatController.text);
      }
    }
  }

  // Simulator manipulation helper
  Future<void> _updateSensor(String key, dynamic value) async {
    try {
      final response = await ApiService.updateSensorState(key, value);
      setState(() {
        _vehicleState = response['state'];
      });
    } catch (e) {
      print('Sensor update failed: $e');
    }
  }

  // Predefined triggers to make the judge's demo extremely cool
  void _triggerScenario(String name) {
    if (name == "Sleepy Driver") {
      _updateSensor("driver_fatigue_hours", 2.5);
      _sendMessage("I'm feeling sleepy.");
    } else if (name == "Rainy Weather") {
      _updateSensor("is_rainy", true);
      _sendMessage("It's starting to rain quite heavily.");
    } else if (name == "Low Battery") {
      _updateSensor("battery_level", 8);
      _updateSensor("tpms_status", "Normal");
      _sendMessage("How is my battery looking?");
    } else if (name == "TPMS Error") {
      _updateSensor("tpms_status", "Malfunction");
      _updateSensor("tire_pressures", {"FL": 22, "FR": 34, "RL": 32, "RR": 32});
      _sendMessage("Why is my TPMS light on?");
    } else if (name == "Reset Simulator") {
      _updateSensor("driver_fatigue_hours", 0.0);
      _updateSensor("is_rainy", false);
      _updateSensor("battery_level", 45);
      _updateSensor("tpms_status", "Normal");
      _updateSensor("tire_pressures", {"FL": 34, "FR": 34, "RL": 32, "RR": 32});
      _updateSensor("windows_open", false);
      _updateSensor("hazard_lights", false);
      _updateSensor("music_playing", false);
      _updateSensor("music_track", "None");
      _updateSensor("current_route", "None");
      _updateSensor("ac_temp", 22.0);
      _updateSensor("drive_mode", "Comfort");
      setState(() {
        _chatHistory.clear();
      });
      _sendMessage("Hello, diagnostic reset completed.");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF00D1FF)),
              SizedBox(height: 20),
              Text('Starting DriveMind OS...', style: TextStyle(fontSize: 18, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (_errorMsg.isNotEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                Text(
                  _errorMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _fetchStatus,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00D1FF)),
                  child: const Text('Retry Connection'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final activeProfileName = _vehicleState['current_profile'] ?? 'Dad';
    final activeProfile = _profiles[activeProfileName] ?? {};

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // Left Pane - Co-Pilot Chat System (40% width)
            Expanded(
              flex: 4,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF0D0F18),
                  border: Border(right: BorderSide(color: Color(0xFF22283E), width: 1.5)),
                ),
                child: Column(
                  children: [
                    // Co-Pilot Header
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      color: const Color(0xFF131724),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00D1FF).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.blur_on_rounded, color: Color(0xFF00D1FF), size: 30),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DriveMind Co-Pilot',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5),
                              ),
                              Text(
                                'EDGE AI • OFFLINE ACTIVE',
                                style: TextStyle(color: Color(0xFF00FF85), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                              ),
                            ],
                          ),
                          const Spacer(),
                          // TTS Toggle Button
                          IconButton(
                            icon: Icon(
                              _isTtsEnabled ? Icons.volume_up : Icons.volume_off,
                              color: _isTtsEnabled ? const Color(0xFF00D1FF) : Colors.grey,
                            ),
                            onPressed: () {
                              setState(() {
                                _isTtsEnabled = !_isTtsEnabled;
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    // Quick Demo Commands Carousel (Helpful for rapid testing during live demo)
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      color: const Color(0xFF090A10),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _demoCommands.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: ActionChip(
                              label: Text(_demoCommands[index], style: const TextStyle(fontSize: 12, color: Colors.white70)),
                              backgroundColor: const Color(0xFF1A1F33),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              onPressed: () {
                                _sendMessage(_demoCommands[index]);
                              },
                            ),
                          );
                        },
                      ),
                    ),

                    // Chat History
                    Expanded(
                      child: _chatHistory.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16.0),
                              itemCount: _chatHistory.length,
                              itemBuilder: (context, index) {
                                final message = _chatHistory[index];
                                final isUser = message['role'] == 'user';
                                return _buildChatBubble(message['content'] ?? '', isUser);
                              },
                            ),
                    ),

                    // Typing Indicator
                    if (_isWaitingForAI)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00D1FF)),
                            ),
                            SizedBox(width: 12),
                            Text('DriveMind thinking...', style: TextStyle(color: Colors.white54, fontSize: 13, fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),

                    // Chat Input Bar
                    Container(
                      padding: const EdgeInsets.all(12.0),
                      color: const Color(0xFF131724),
                      child: Row(
                        children: [
                          // Voice button
                          GestureDetector(
                            onTap: _listen,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _isListening ? const Color(0xFFFF3B30) : const Color(0xFF1C2237),
                                shape: BoxShape.circle,
                                boxShadow: _isListening
                                    ? [BoxShadow(color: const Color(0xFFFF3B30).withOpacity(0.4), blurRadius: 10, spreadRadius: 2)]
                                    : [],
                              ),
                              child: Icon(
                                _isListening ? Icons.mic : Icons.mic_none_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Text Field
                          Expanded(
                            child: TextField(
                              controller: _chatController,
                              decoration: InputDecoration(
                                hintText: 'Ask or give a command...',
                                hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                filled: true,
                                fillColor: const Color(0xFF0D0F18),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (val) => _sendMessage(val),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Send button
                          IconButton(
                            icon: const Icon(Icons.send_rounded, color: Color(0xFF00D1FF)),
                            onPressed: () => _sendMessage(_chatController.text),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Right Pane - Simulated Car UI Infotainment Dashboard (60% width)
            Expanded(
              flex: 6,
              child: Column(
                children: [
                  // Upper dashboard - Stats Bar
                  _buildDashboardHeader(activeProfileName, activeProfile),

                  // Main Infotainment Widgets
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // First Row: Speedometer Battery Ring & Climate
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Speedometer & Battery Ring
                              Expanded(
                                flex: 5,
                                child: _buildEnergyAndSpeedWidget(),
                              ),
                              const SizedBox(width: 16),
                              // Climate Control
                              Expanded(
                                flex: 5,
                                child: _buildClimateControlWidget(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Second Row: TPMS & Music
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // TPMS status
                              Expanded(
                                flex: 5,
                                child: _buildTpmsWidget(),
                              ),
                              const SizedBox(width: 16),
                              // Music Player
                              Expanded(
                                flex: 5,
                                child: _buildMusicPlayerWidget(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Third Row: Emergency, Windows, Route
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Cabin States (Windows, Hazards, Wipers, Lights)
                              Expanded(
                                flex: 6,
                                child: _buildCabinStatesWidget(),
                              ),
                              const SizedBox(width: 16),
                              // Current Route Map display
                              Expanded(
                                flex: 4,
                                child: _buildNavigationWidget(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Dock - Driver Simulation Panel
                  _buildSimulatorControlDock(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_car_filled_outlined, size: 64, color: const Color(0xFF00D1FF).withOpacity(0.2)),
            const SizedBox(height: 16),
            const Text(
              'Welcome to DriveMind OS',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your Edge AI driving partner. Try saying "Hello" or select a quick query from the chips above.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white38),
            ),
            const SizedBox(height: 24),
            _buildDriverMemorySummary(),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverMemorySummary() {
    final activeProfileName = _vehicleState['current_profile'] ?? 'Dad';
    final activeProfile = _profiles[activeProfileName] ?? {};

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF22283E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_outlined, color: Color(0xFF00FF85), size: 20),
              const SizedBox(width: 8),
              Text(
                'Personal Memory ($activeProfileName)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF00FF85)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildMemoryRow('Seating memory', activeProfile['seat_position'] ?? 'Memory 1'),
          _buildMemoryRow('Pref AC Temp', '${activeProfile['preferred_temp']}°C'),
          _buildMemoryRow('Commute Timing', activeProfile['commute_time'] ?? 'None'),
          _buildMemoryRow('Preferred Mode', activeProfile['drive_mode'] ?? 'Comfort'),
          _buildMemoryRow('Favorite music', activeProfile['favorite_music'] ?? 'Acoustic Pop'),
          const SizedBox(height: 8),
          Text(
            'Habits: ${activeProfile['driving_habits'] ?? ''}',
            style: const TextStyle(fontSize: 11, color: Colors.white54, fontStyle: FontStyle.italic),
          )
        ],
      ),
    );
  }

  Widget _buildMemoryRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String text, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.28),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF00D1FF).withOpacity(0.15) : const Color(0xFF1A1F33),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isUser ? const Radius.circular(12) : const Radius.circular(0),
            bottomRight: isUser ? const Radius.circular(0) : const Radius.circular(12),
          ),
          border: Border.all(
            color: isUser ? const Color(0xFF00D1FF).withOpacity(0.4) : const Color(0xFF272F4C),
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.white.withOpacity(0.9),
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardHeader(String activeProfileName, Map<String, dynamic> activeProfile) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: const Color(0xFF131724),
      child: Row(
        children: [
          const Icon(Icons.drive_eta_rounded, color: Colors.white70, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TATA NEXON EV CO-DRIVE SYSTEM',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.0, color: Colors.white70),
              ),
              Row(
                children: [
                  const Text('DRIVE STATE: ', style: TextStyle(color: Colors.white30, fontSize: 10)),
                  Text(
                    _vehicleState['speed'] > 0 ? 'DRIVING (${_vehicleState['speed']} km/h)' : 'PARKED',
                    style: TextStyle(
                      color: _vehicleState['speed'] > 0 ? const Color(0xFF00FF85) : Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          // Driver memory state display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0F18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF22283E)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_circle, color: Color(0xFF00D1FF), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Driver: $activeProfileName (${activeProfile['seat_position']})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnergyAndSpeedWidget() {
    final battery = _vehicleState['battery_level'] ?? 0;
    final isLowBattery = battery <= 15;
    final driveMode = _vehicleState['drive_mode'] ?? 'Comfort';
    
    Color modeColor;
    if (driveMode == 'Sport') {
      modeColor = const Color(0xFFFF5252);
    } else if (driveMode == 'Eco') {
      modeColor = const Color(0xFF00FF85);
    } else {
      modeColor = const Color(0xFF00D1FF);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'VEHICLE RANGE & PROPULSION',
              style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Battery Gauge Ring
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        value: battery / 100.0,
                        backgroundColor: const Color(0xFF0F121C),
                        color: isLowBattery ? const Color(0xFFFF3B30) : const Color(0xFF00FF85),
                        strokeWidth: 8,
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          '$battery%',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isLowBattery ? const Color(0xFFFF3B30) : const Color(0xFF00FF85),
                          ),
                        ),
                        const Text('BATTERY', style: TextStyle(fontSize: 8, color: Colors.white54)),
                      ],
                    ),
                  ],
                ),
                // Speed & Drive Mode details
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${_vehicleState['speed']}',
                          style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(width: 4),
                        const Text('km/h', style: TextStyle(fontSize: 14, color: Colors.white30)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: modeColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: modeColor.withOpacity(0.4)),
                      ),
                      child: Text(
                        '$driveMode MODE',
                        style: TextStyle(color: modeColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Low battery alert box
            if (isLowBattery)
              Container(
                margin: const EdgeInsets.only(top: 12.0),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF3B30), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        battery <= 10 ? 'TORTOISE MODE: Speed capped at 40 km/h.' : 'Low battery warning. Co-Pilot suggests charging.',
                        style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    )
                  ],
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildClimateControlWidget() {
    final double acTemp = (_vehicleState['ac_temp'] ?? 22.0).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'CLIMATE ZONE CONTROL',
              style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Color(0xFF00D1FF), size: 28),
                  onPressed: () => _updateSensor('ac_temp', acTemp - 1.0),
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    Text(
                      '$acTemp°C',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const Text('AUTOMATIC A/C', style: TextStyle(fontSize: 9, color: Colors.white54, letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Color(0xFF00D1FF), size: 28),
                  onPressed: () => _updateSensor('ac_temp', acTemp + 1.0),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Icon(Icons.air_rounded, color: Colors.white54, size: 20),
                    const SizedBox(height: 4),
                    Text('FAN SPEED: ${_vehicleState['fan_speed'] ?? 3}', style: const TextStyle(fontSize: 9, color: Colors.white54)),
                  ],
                ),
                Column(
                  children: [
                    Icon(
                      _vehicleState['ac_temp'] < 20.0 ? Icons.ac_unit : Icons.wb_sunny_outlined,
                      color: _vehicleState['ac_temp'] < 20.0 ? const Color(0xFF00D1FF) : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(height: 4),
                    Text(_vehicleState['ac_temp'] < 20.0 ? 'COOLING' : 'HEATING', style: const TextStyle(fontSize: 9, color: Colors.white54)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTpmsWidget() {
    final status = _vehicleState['tpms_status'] ?? 'Normal';
    final pressures = _vehicleState['tire_pressures'] ?? {'FL': 34, 'FR': 34, 'RL': 32, 'RR': 32};
    final isWarn = status != 'Normal';

    return Card(
      color: isWarn ? const Color(0xFFFF9500).withOpacity(0.08) : const Color(0xFF161A26),
      shape: isWarn ? RoundedRectangleBorder(side: BorderSide(color: const Color(0xFFFF9500).withOpacity(0.4), width: 1.5), borderRadius: BorderRadius.circular(12)) : null,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TIRE PRESSURE SYSTEM (TPMS)',
                  style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isWarn ? const Color(0xFFFF9500).withOpacity(0.2) : const Color(0xFF00FF85).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: isWarn ? const Color(0xFFFF9500) : const Color(0xFF00FF85),
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTireIndicator('Front Left', pressures['FL'], pressures['FL'] < 26),
                    const SizedBox(height: 8),
                    _buildTireIndicator('Rear Left', pressures['RL'], pressures['RL'] < 26),
                  ],
                ),
                // Center graphic representation of car outline
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 50,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F121C),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24, width: 2),
                      ),
                    ),
                    if (isWarn)
                      // Flashing yellow warning icon
                      FadeTransition(
                        opacity: _animationController,
                        child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9500), size: 28),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildTireIndicator('Front Right', pressures['FR'], pressures['FR'] < 26),
                    const SizedBox(height: 8),
                    _buildTireIndicator('Rear Right', pressures['RR'], pressures['RR'] < 26),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTireIndicator(String label, dynamic val, bool alert) {
    return Column(
      crossAxisAlignment: label.contains('Left') ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.white38)),
        Text(
          '$val PSI',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: alert ? const Color(0xFFFF3B30) : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildMusicPlayerWidget() {
    final bool isPlaying = _vehicleState['music_playing'] ?? false;
    final trackName = _vehicleState['music_track'] ?? 'None';
    final playlistName = _vehicleState['music_playlist'] ?? 'None';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'CABIN AUDIO MEDIA SYSTEM',
              style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Disk visualizer spinning
                RotationTransition(
                  turns: isPlaying ? _animationController : const AlwaysStoppedAnimation(0),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0xFF131724), Color(0xFF00D1FF), Color(0xFF0F121C)],
                        stops: [0.1, 0.6, 1.0],
                      ),
                    ),
                    child: const Icon(Icons.music_note, color: Colors.white70, size: 20),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPlaying ? trackName : 'Audio Paused',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        isPlaying ? 'Playlist: $playlistName' : 'Select a playlist to start',
                        style: const TextStyle(color: Colors.white54, fontSize: 11, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    color: const Color(0xFF00D1FF),
                    size: 36,
                  ),
                  onPressed: () {
                    if (isPlaying) {
                      _updateSensor('music_playing', false);
                    } else {
                      _updateSensor('music_playing', true);
                      _updateSensor('music_track', 'Favorites Playlist');
                      _updateSensor('music_playlist', 'Favorites');
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCabinStatesWidget() {
    final win = _vehicleState['windows_open'] ?? false;
    final haz = _vehicleState['hazard_lights'] ?? false;
    final wipers = _vehicleState['wipers'] ?? 'Off';
    final rain = _vehicleState['is_rainy'] ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'CABIN CONTROLS & SECURITY',
              style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Windows control
                GestureDetector(
                  onTap: () => _updateSensor('windows_open', !win),
                  child: Column(
                    children: [
                      Icon(
                        win ? Icons.window_outlined : Icons.wb_iridescent_outlined,
                        color: win ? const Color(0xFF00D1FF) : Colors.white60,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(win ? 'WINDOWS OPEN' : 'WINDOWS CLOSED', style: const TextStyle(fontSize: 9, color: Colors.white54)),
                    ],
                  ),
                ),
                // Wipers (Auto triggers if rain)
                Column(
                  children: [
                    Icon(
                      wipers != 'Off' ? Icons.cyclone : Icons.water_drop_outlined,
                      color: rain ? const Color(0xFF00FF85) : Colors.white60,
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text('WIPERS: $wipers', style: const TextStyle(fontSize: 9, color: Colors.white54)),
                  ],
                ),
                // Hazard Light flasher
                GestureDetector(
                  onTap: () => _updateSensor('hazard_lights', !haz),
                  child: Column(
                    children: [
                      haz
                          ? FadeTransition(
                              opacity: _animationController,
                              child: const Icon(Icons.warning, color: Color(0xFFFF3B30), size: 24),
                            )
                          : const Icon(Icons.warning_amber_rounded, color: Colors.white60, size: 24),
                      const SizedBox(height: 4),
                      Text('HAZARDS', style: TextStyle(fontSize: 9, color: haz ? const Color(0xFFFF3B30) : Colors.white54, fontWeight: haz ? FontWeight.bold : FontWeight.normal)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationWidget() {
    final route = _vehicleState['current_route'] ?? 'None';
    final hasRoute = route != 'None';

    return Card(
      color: hasRoute ? const Color(0xFF00D1FF).withOpacity(0.05) : const Color(0xFF161A26),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'CO-PILOT ROUTE PLANNER',
              style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.navigation_outlined,
                  color: hasRoute ? const Color(0xFF00D1FF) : Colors.white24,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasRoute ? 'NAVIGATING TO:' : 'NO ACTIVE NAVIGATION',
                        style: TextStyle(color: hasRoute ? const Color(0xFF00D1FF) : Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        hasRoute ? route : 'Ask DriveMind to navigate',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulatorControlDock() {
    return Container(
      padding: const EdgeInsets.all(12.0),
      color: const Color(0xFF131724),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune, color: Colors.white30, size: 16),
              SizedBox(width: 8),
              Text(
                'TESTING CONSOLE - SIMULATE VEHICLE TRIPPERS',
                style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Profiles
              _buildCompactButton('Profile: Dad', () => _updateSensor('current_profile', 'Dad')),
              const SizedBox(width: 6),
              _buildCompactButton('Profile: Mom', () => _updateSensor('current_profile', 'Mom')),
              const SizedBox(width: 6),
              _buildCompactButton('Profile: Child', () => _updateSensor('current_profile', 'Child')),
              const VerticalDivider(color: Colors.white24, width: 20),
              // Scenario triggers
              _buildScenarioButton('Low Battery (8%)', const Color(0xFFFF3B30), () => _triggerScenario('Low Battery')),
              const SizedBox(width: 6),
              _buildScenarioButton('TPMS Alert (22 PSI)', const Color(0xFFFF9500), () => _triggerScenario('TPMS Error')),
              const SizedBox(width: 6),
              _buildScenarioButton('Rainy Weather', Colors.blue, () => _triggerScenario('Rainy Weather')),
              const SizedBox(width: 6),
              _buildScenarioButton('Sleepy Driver', Colors.deepPurple, () => _triggerScenario('Sleepy Driver')),
              const Spacer(),
              _buildScenarioButton('RESET SYSTEM', const Color(0xFF00FF85), () => _triggerScenario('Reset Simulator'), isOutline: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1C2237),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
    );
  }

  Widget _buildScenarioButton(String label, Color color, VoidCallback onPressed, {bool isOutline = false}) {
    if (isOutline) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.2),
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
