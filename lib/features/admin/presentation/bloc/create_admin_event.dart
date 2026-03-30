part of 'create_admin_bloc.dart';

abstract class CreateAdminEvent extends Equatable {
  const CreateAdminEvent();

  @override
  List<Object?> get props => [];
}

class CreateAdminSubmitted extends CreateAdminEvent {
  final String phoneNumber;
  final String email;
  final String displayName;

  const CreateAdminSubmitted({
    required this.phoneNumber,
    required this.email,
    required this.displayName,
  });

  @override
  List<Object?> get props => [phoneNumber, email, displayName];
}
