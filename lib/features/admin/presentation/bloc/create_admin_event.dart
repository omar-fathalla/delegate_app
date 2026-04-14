part of 'create_admin_bloc.dart';

abstract class CreateAdminEvent extends Equatable {
  const CreateAdminEvent();

  @override
  List<Object?> get props => [];
}

class LoadOrganizationsRequested extends CreateAdminEvent {}

class CreateAdminSubmitted extends CreateAdminEvent {
  final String phoneNumber;
  final String email;
  final String displayName;
  final String role;
  final String organizationUID;

  const CreateAdminSubmitted({
    required this.phoneNumber,
    required this.email,
    required this.displayName,
    this.role = 'company-admin',
    this.organizationUID = '',
  });

  @override
  List<Object?> get props => [
    phoneNumber,
    email,
    displayName,
    role,
    organizationUID,
  ];
}
