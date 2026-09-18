import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';

class ManageOrganizationsPage extends StatefulWidget {
  const ManageOrganizationsPage({super.key});

  @override
  State<ManageOrganizationsPage> createState() => _ManageOrganizationsPageState();
}

class _ManageOrganizationsPageState extends State<ManageOrganizationsPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddOrganizationDialog() {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final addressController = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.add_business_rounded, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'إضافة منظمة / سلسلة جديدة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم المنظمة / السلسلة التجارية *',
                          hintText: 'مثال: مؤسسة زهران، بيت الجملة...',
                          prefixIcon: Icon(Icons.corporate_fare_rounded),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'يرجى إدخال اسم المنظمة' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: codeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'كود المنظمة التعريفي *',
                          hintText: 'مثال: ZAHRAN, GOMLEH...',
                          prefixIcon: Icon(Icons.tag_rounded),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'يرجى إدخال كود المنظمة' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressController,
                        decoration: const InputDecoration(
                          labelText: 'العنوان / المركز الرئيسي',
                          hintText: 'مثال: الإسكندرية، سموحة...',
                          prefixIcon: Icon(Icons.location_on_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setStateDialog(() => isSaving = true);

                          final name = nameController.text.trim();
                          final code = codeController.text.trim().toUpperCase();
                          final address = addressController.text.trim();

                          try {
                            final orgRef =
                                FirebaseFirestore.instance.collection('organizations').doc();
                            await orgRef.set({
                              'organizationUID': orgRef.id,
                              'uid': orgRef.id,
                              'name': name,
                              'title': name,
                              'code': code,
                              'address': address,
                              'isActive': true,
                              'createdAt': FieldValue.serverTimestamp(),
                            });

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              AppSnackBar.showSuccess(
                                context,
                                'تمت إضافة منظمة "$name" بنجاح، وستظهر الآن لجميع المشرفين!',
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              setStateDialog(() => isSaving = false);
                              AppSnackBar.showError(ctx, 'فشل إنشاء المنظمة: $e');
                            }
                          }
                        },
                  child: isSaving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                        )
                      : const Text('حفظ المنظمة'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'إدارة المنظمات والسلاسل التجارية',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'البحث عن منظمة أو سلسلة...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
            ),
          ),

          // Organizations Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('organizations').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('خطأ في تحميل المنظمات: ${snapshot.error}'),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                var filtered = docs.map((d) {
                  final data = d.data() as Map<String, dynamic>;
                  data['docId'] = d.id;
                  return data;
                }).toList();

                if (_searchQuery.isNotEmpty) {
                  filtered = filtered.where((org) {
                    final name = (org['name'] ?? org['title'] ?? '').toString().toLowerCase();
                    final code = (org['code'] ?? '').toString().toLowerCase();
                    return name.contains(_searchQuery) || code.contains(_searchQuery);
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'لا توجد منظمات مسجلة حتى الآن.',
                      style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final org = filtered[index];
                    final name = org['name'] ?? org['title'] ?? 'بدون اسم';
                    final code = org['code'] ?? '';
                    final isActive = org['isActive'] != false;

                    return Card(
                      elevation: 0.5,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        leading: CircleAvatar(
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.primary,
                          child: const Icon(Icons.corporate_fare_rounded),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                        ),
                        subtitle: Text(
                          code.isNotEmpty ? 'الكود: $code' : 'منظمة مسجلة',
                          style: TextStyle(fontSize: 12, color: colorScheme.outline),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isActive
                                ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isActive ? 'نشطة' : 'غير نشطة',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddOrganizationDialog,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text(
          'إضافة منظمة / سلسلة جديدة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
