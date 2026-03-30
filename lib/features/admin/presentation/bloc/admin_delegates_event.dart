import 'package:equatable/equatable.dart';

abstract class AdminDelegatesEvent extends Equatable {
  const AdminDelegatesEvent();

  @override
  List<Object> get props => [];
}

class LoadCompanyDelegates extends AdminDelegatesEvent {
  final String organizationUID;
  final String companyUID;

  const LoadCompanyDelegates({
    required this.organizationUID,
    required this.companyUID,
  });

  @override
  List<Object> get props => [organizationUID, companyUID];
}
