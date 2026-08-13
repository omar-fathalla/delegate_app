import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';

class EditPermissionBranchesDialog extends StatefulWidget {
  final PhotoPermission permission;
  final Function(List<String> branchIds, List<String> branchNames) onSave;

  const EditPermissionBranchesDialog({
    super.key,
    required this.permission,
    required this.onSave,
  });

  @override
  State<EditPermissionBranchesDialog> createState() => _EditPermissionBranchesDialogState();
}

class _EditPermissionBranchesDialogState extends State<EditPermissionBranchesDialog> {
  final List<String> _selectedBranchIds = [];
  final List<String> _selectedBranchNames = [];
  bool _isLoading = true;
  List<DocumentSnapshot> _allBranches = [];

  @override
  void initState() {
    super.initState();
    _selectedBranchIds.addAll(widget.permission.branchIds);
    _selectedBranchNames.addAll(widget.permission.branchNames);
    _fetchBranches();
  }

  Future<void> _fetchBranches() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.permission.organizationUID)
          .collection('companies')
          .doc(widget.permission.companyUID)
          .collection('branches')
          .get();
      if (mounted) {
        setState(() {
          _allBranches = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل الفروع المعتمدة', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _allBranches.isEmpty
                ? const Text('لا توجد فروع مسجلة لهذه الشركة.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _allBranches.length,
                    itemBuilder: (context, index) {
                      final doc = _allBranches[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final branchId = doc.id;
                      final branchName = data['branchName'] as String? ?? 'بدون اسم';

                      final isSelected = _selectedBranchIds.contains(branchId);

                      return CheckboxListTile(
                        title: Text(branchName),
                        value: isSelected,
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              _selectedBranchIds.add(branchId);
                              _selectedBranchNames.add(branchName);
                            } else {
                              final removeIndex = _selectedBranchIds.indexOf(branchId);
                              if (removeIndex != -1) {
                                _selectedBranchIds.removeAt(removeIndex);
                                _selectedBranchNames.removeAt(removeIndex);
                              }
                            }
                          });
                        },
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _selectedBranchIds.isEmpty
              ? null
              : () {
                  widget.onSave(_selectedBranchIds, _selectedBranchNames);
                  Navigator.pop(context);
                },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
