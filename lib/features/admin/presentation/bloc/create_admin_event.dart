part of 'create_admin_bloc.dart';

abstract class CreateAdminEvent extends Equatable {
  const CreateAdminEvent();

  @override
  List<Object?> get props => [];
}

class LoadOrganizationsRequested extends CreateAdminEvent {}

class LoadCompaniesForOrgRequested extends CreateAdminEvent {
  final String organizationUID;

  const LoadCompaniesForOrgRequested({required this.organizationUID});

  @override
  List<Object?> get props => [organizationUID];
}

class CreateAdminSubmitted extends CreateAdminEvent {
  final String phoneNumber;
  final String email;
  final String displayName;
  final String role;
  final String organizationUID;
  final String? companyUID;
  final String? companyName;
  final String? jobTitle;

  const CreateAdminSubmitted({
    required this.phoneNumber,
    required this.email,
    required this.displayName,
    this.role = 'company-admin',
    this.organizationUID = '',
    this.companyUID,
    this.companyName,
    this.jobTitle,
  });

  @override
  List<Object?> get props => [
    phoneNumber,
    email,
    displayName,
    role,
    organizationUID,
    companyUID,
    companyName,
    jobTitle,
  ];
}
