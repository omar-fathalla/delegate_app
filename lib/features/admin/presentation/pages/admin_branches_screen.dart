import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/branch_model.dart';

class AdminBranchesScreen extends StatelessWidget {
  const AdminBranchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('branches').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.errorGeneral));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.store_mall_directory_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.branches,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final branch = BranchModel.fromFirestore(doc);

              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.withValues(alpha: 0.1),
                    child: const Icon(Icons.store, color: Colors.blue),
                  ),
                  title: Text(
                    branch.branchName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${branch.latitude.toStringAsFixed(4)}, ${branch.longitude.toStringAsFixed(4)}\nRadius: ${branch.geofenceRadius}m',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.qr_code, color: Colors.grey),
                  onTap: () {
                    // Navigate to BranchDetailsScreen (to be created)
                    context.push('/admin/branch-details', extra: branch);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
