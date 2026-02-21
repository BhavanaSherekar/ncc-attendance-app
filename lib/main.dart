import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;

late List<CameraDescription> cameras;

// 🔴 CHANGE THIS TO YOUR MAC MINI IP
const String SERVER = "http://192.168.1.39:8000";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

/* ================= HOME PAGE ================= */

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("NCC Attendance App")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              child: const Text("Take Attendance"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AttendancePage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              child: const Text("View Cadets"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CadetsPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/* ================= ATTENDANCE PAGE ================= */

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  CameraController? controller;

  CameraDescription? backCamera;
  CameraDescription? frontCamera;
  bool usingFrontCamera = false;

  String statusText = "Ready";

  @override
  void initState() {
    super.initState();

    // Detect cameras safely
    for (var cam in cameras) {
      if (cam.lensDirection == CameraLensDirection.back) {
        backCamera = cam;
      }
      if (cam.lensDirection == CameraLensDirection.front) {
        frontCamera = cam;
      }
    }

    // Start with back camera
    startCamera(backCamera ?? cameras.first);
  }

  Future<void> startCamera(CameraDescription camera) async {
    await controller?.dispose();

    controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller!.initialize();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> markAttendance() async {
    try {
      setState(() {
        statusText = "Processing...";
      });

      final image = await controller!.takePicture();

      var request = http.MultipartRequest(
        "POST",
        Uri.parse("$SERVER/mark-attendance"),
      );

      request.files.add(
        await http.MultipartFile.fromPath("file", image.path),
      );

      final response = await request.send();
      final result = await response.stream.bytesToString();

      final data = json.decode(result);

      setState(() {
        if (data["status"] == "success") {
          statusText = "✅ ${data["name"]} marked present";
        } else {
          statusText = "⚠ ${data["message"] ?? "Unknown person"}";
        }
      });
    } catch (e) {
      setState(() {
        statusText = "❌ Server not reachable";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Take Attendance"),
        actions: [
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () async {
              if (frontCamera == null) return;

              usingFrontCamera = !usingFrontCamera;

              await startCamera(
                usingFrontCamera ? frontCamera! : backCamera!,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: CameraPreview(controller!)),
          const SizedBox(height: 10),
          Text(
            statusText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: markAttendance,
                child: const Text("Mark Attendance"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close Camera"),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}

/* ================= VIEW CADETS PAGE ================= */

class CadetsPage extends StatefulWidget {
  const CadetsPage({super.key});

  @override
  State<CadetsPage> createState() => _CadetsPageState();
}

class _CadetsPageState extends State<CadetsPage> {
  Map<String, dynamic> cadets = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadCadets();
  }

  Future<void> loadCadets() async {
    try {
      final response =
          await http.get(Uri.parse("$SERVER/session-attendance"));

      if (response.statusCode == 200) {
        setState(() {
          cadets = json.decode(response.body);
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Present Cadets (Session)")),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : cadets.isEmpty
              ? const Center(child: Text("No attendance marked yet"))
              : RefreshIndicator(
                  onRefresh: loadCadets,
                  child: ListView(
                    children: cadets.entries.map((entry) {
                      return ListTile(
                        leading: const Icon(Icons.check_circle,
                            color: Colors.green),
                        title: Text(entry.key),
                        subtitle: Text("Time: ${entry.value}"),
                      );
                    }).toList(),
                  ),
                ),
    );
  }
}