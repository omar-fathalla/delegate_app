import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import '../bloc/branch_bloc.dart';

class AdminBranchesScreen extends StatelessWidget {
  final bool showAppBar;
  const AdminBranchesScreen({super.key, this.showAppBar = false});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<BranchBloc>()..add(BranchLoadRequested()),
      child: _AdminBranchesView(showAppBar: showAppBar),
    );
  }
}

class _AdminBranchesView extends StatelessWidget {
  final bool showAppBar;
  const _AdminBranchesView({this.showAppBar = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: showAppBar
          ? AppBar(
              title: Text(l10n.branches),
              centerTitle: true,
            )
          : null,
      body: BlocBuilder<BranchBloc, BranchState>(
        builder: (context, state) {
          if (state is BranchLoading || state is BranchInitial) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is BranchError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text(state.message, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () =>
                        context.read<BranchBloc>().add(BranchLoadRequested()),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            );
          }

          if (state is BranchLoaded) {
            if (state.branches.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.store_mall_directory_outlined,
                      size: 80,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.branches,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async =>
                  context.read<BranchBloc>().add(BranchLoadRequested()),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: state.branches.length,
                separatorBuilder: (context, i) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final branch = state.branches[index];

                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer,
                        child: Icon(Icons.store, color: colorScheme.primary),
                      ),
                      title: Text(
                        branch.branchName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${branch.latitude.toStringAsFixed(4)}, ${branch.longitude.toStringAsFixed(4)}\nRadius: ${branch.geofenceRadius}m',
                      ),
                      isThreeLine: true,
                      trailing: Icon(
                        Icons.qr_code,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onTap: () {
                        context
                            .push('/admin/branch-details', extra: branch)
                            .then((_) {
                              if (context.mounted) {
                                context.read<BranchBloc>().add(
                                  BranchLoadRequested(),
                                );
                              }
                            });
                      },
                    ),
                  );
                },
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}
