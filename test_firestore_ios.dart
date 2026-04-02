import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:delegate_app/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Firestore Test')),
        body: const FirestoreTest(),
      ),
    );
  }
}

class FirestoreTest extends StatefulWidget {
  const FirestoreTest({super.key});

  @override
  State<FirestoreTest> createState() => _FirestoreTestState();
}

class _FirestoreTestState extends State<FirestoreTest> {
  String _status = 'Not tested';
  String _authStatus = 'Not authenticated';
  List<String> _branches = [];

  Future<void> _testFirestore() async {
    try {
      setState(() {
        _status = 'Testing...';
        _authStatus = 'Checking auth...';
      });

      // 1. Check authentication
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(
          () => _authStatus = 'Not authenticated. Signing in anonymously...',
        );
        await FirebaseAuth.instance.signInAnonymously();
        setState(
          () => _authStatus =
              'Signed in anonymously: ${FirebaseAuth.instance.currentUser?.uid}',
        );
      } else {
        setState(
          () => _authStatus = 'Already authenticated: ${currentUser.uid}',
        );
      }

      // 2. Test Firestore
      final snapshot = await FirebaseFirestore.instance
          .collection('branches')
          .get()
          .timeout(const Duration(seconds: 10));

      setState(() {
        _status = 'Success! Found ${snapshot.docs.length} branches';
        _branches = snapshot.docs.map((doc) {
          final data = doc.data();
          return '${data['branchName'] ?? 'Unknown'} (${doc.id})';
        }).toList();
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            onPressed: _testFirestore,
            child: const Text('Test Firestore Connection'),
          ),
          const SizedBox(height: 20),
          Text('Auth Status: $_authStatus'),
          const SizedBox(height: 10),
          Text('Status: $_status'),
          const SizedBox(height: 20),
          if (_branches.isNotEmpty) ...[
            const Text(
              'Branches:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ..._branches.map((b) => Text('• $b')),
          ],
        ],
      ),
    );
  }
}
