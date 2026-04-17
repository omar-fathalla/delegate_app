part of 'profile_bloc.dart';

abstract class ProfileEvent extends Equatable {
  const ProfileEvent();

  @override
  List<Object> get props => [];
}

class LoadProfile extends ProfileEvent {
  final String uid;
  final String? organizationUID;
  final String? companyUID;

  const LoadProfile({
    required this.uid,
    this.organizationUID,
    this.companyUID,
  });

  @override
  List<Object> get props => [
        uid,
        if (organizationUID != null) organizationUID!,
        if (companyUID != null) companyUID!,
      ];
}
