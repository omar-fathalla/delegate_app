import 'package:delegate_app/features/private_label/domain/entities/private_label_kpi.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_bloc.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_catalog_screen.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_screen.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_kpi_card.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_rest_day_sheet.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Compact Private Label KPI card for the marketer home dashboard.
///
/// Cache-first: renders the cached month instantly, then revalidates.
class PrivateLabelHomeCard extends StatelessWidget {
  final Delegate delegate;

  const PrivateLabelHomeCard({super.key, required this.delegate});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PrivateLabelBloc>(
      create: (_) => sl<PrivateLabelBloc>()
        ..add(PrivateLabelStarted(
          organizationUID: delegate.organizationUID,
          companyUID: delegate.companyUID,
          delegateUid: delegate.uid,
          delegateName: delegate.fullName,
          loadDetails: false,
        )),
      child: _HomeCardView(delegate: delegate),
    );
  }
}

class _HomeCardView extends StatelessWidget {
  final Delegate delegate;

  const _HomeCardView({required this.delegate});

  Future<void> _open(BuildContext context) async {
    final bloc = context.read<PrivateLabelBloc>();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PrivateLabelScreen(delegate: delegate)),
    );
    if (!bloc.isClosed) bloc.add(const PrivateLabelRefreshRequested());
  }

  Future<void> _openCatalog(BuildContext context) async {
    final bloc = context.read<PrivateLabelBloc>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrivateLabelCatalogScreen(delegate: delegate),
      ),
    );
    if (!bloc.isClosed) bloc.add(const PrivateLabelRefreshRequested());
  }

  Future<void> _rest(BuildContext context, {required bool cancel}) async {
    final bloc = context.read<PrivateLabelBloc>();
    final kpi = bloc.state.kpi;
    if (kpi == null) return;
    final ok = await confirmPrivateLabelRestDay(
      context: context,
      date: bloc.todayKey,
      remainingRestDays: kpi.remainingRestDays,
      restAllowance: kpi.restAllowance,
      cancel: cancel,
    );
    if (!ok) return;
    bloc.add(cancel
        ? PrivateLabelRestDayCancelled(bloc.todayKey)
        : PrivateLabelRestDayRequested(bloc.todayKey));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PrivateLabelBloc, PrivateLabelState>(
      buildWhen: (p, c) =>
          p.kpi != c.kpi ||
          p.isSyncing != c.isSyncing ||
          p.isUpdatingRest != c.isUpdatingRest ||
          p.pendingDrafts.length != c.pendingDrafts.length,
      builder: (context, state) {
        final kpi = state.kpi;
        final canEditRest = kpi != null &&
            kpi.todayStatus != PrivateLabelTodayStatus.outsideMonth &&
            !state.isUpdatingRest;
        return PrivateLabelKpiCard(
          kpi: kpi,
          compact: true,
          isLoading: kpi == null,
          isSyncing: state.isSyncing,
          pendingCount: state.pendingDrafts.length,
          onOpen: () => _open(context),
          onOpenCatalog: () => _openCatalog(context),
          catalogButtonLabel: 'الكتالوج',
          onRegisterRestToday: canEditRest && kpi.remainingRestDays > 0
              ? () => _rest(context, cancel: false)
              : null,
          onCancelRestToday: canEditRest ? () => _rest(context, cancel: true) : null,
        );
      },
    );
  }
}
