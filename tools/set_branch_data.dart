import 'package:material_ui/material_ui.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MaterialApp(home: BranchUpdaterScreen()));
}

class BranchUpdaterScreen extends StatefulWidget {
  const BranchUpdaterScreen({super.key});

  @override
  State<BranchUpdaterScreen> createState() => _BranchUpdaterScreenState();
}

class _BranchUpdaterScreenState extends State<BranchUpdaterScreen> {
  final dataSource = AttendanceRemoteDataSourceImpl(
    firestore: FirebaseFirestore.instance,
  );

  String _status = 'Ready';
  bool _isLoading = false;

  Future<void> _updateBranches() async {
    setState(() {
      _isLoading = true;
      _status = 'Updating...';
    });

    try {
      // 1. Smouha Branch (Alexandria)
      await dataSource.saveBranch(
        branchName: 'سموحة اختبار',
        latitude: 31.2267,
        longitude: 29.9575,
        geofenceRadius: 200,
      );

      // 2. Main Sea Branch
      await dataSource.saveBranch(
        branchName: 'الفرع البحري الرئيسي',
        latitude: 31.2001,
        longitude: 29.9187,
        geofenceRadius: 300,
      );

      setState(() {
        _status = 'Success! Branches updated in Firestore.';
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Branch Data Patcher')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on, size: 60, color: Colors.blue),
              const SizedBox(height: 20),
              Text(
                'This tool will update coordinates for:\n'
                '1. سموحة اختبار\n'
                '2. الفرع البحري الرئيسي',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 30),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: _updateBranches,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Update Firestore (In Firebase)'),
                ),
              const SizedBox(height: 20),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _status.contains('Error') ? Colors.red : Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
