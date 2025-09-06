import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class BrowseToursScreen extends StatefulWidget {
  const BrowseToursScreen({super.key});

  @override
  State<BrowseToursScreen> createState() => _BrowseToursScreenState();
}

class _BrowseToursScreenState extends State<BrowseToursScreen> {
  List<dynamic> tours = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchTours();
  }

  Future<void> fetchTours() async {
    // IMPORTANT: 10.0.2.2 is the special IP address the Android emulator
    // uses to connect to the host machine (your Windows PC).
    final url = Uri.parse('http://10.0.2.2:8000/tours');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          tours = jsonDecode(response.body);
          isLoading = false;
        });
      } else {
         setState(() {
          errorMessage = 'Failed to load tours. Status code: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to connect to the server. Make sure your Python server is running.';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Tours'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!, textAlign: TextAlign.center))
              : ListView.builder(
                  itemCount: tours.length,
                  itemBuilder: (context, index) {
                    final tour = tours[index];
                    return ListTile(
                      title: Text(tour['name']),
                    );
                  },
                ),
    );
  }
}
