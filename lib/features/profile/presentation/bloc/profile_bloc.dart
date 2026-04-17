import 'package:bloc/bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/domain/usecases/get_delegate_profile.dart';
import 'package:equatable/equatable.dart';

part 'profile_event.dart';
part 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final GetDelegateProfile getDelegateProfile;

  ProfileBloc({required this.getDelegateProfile}) : super(ProfileInitial()) {
    on<LoadProfile>(_onLoadProfile);
  }

  Future<void> _onLoadProfile(
    LoadProfile event,
    Emitter<ProfileState> emit,
  ) async {
    emit(ProfileLoading());
    final result = await getDelegateProfile(
      GetDelegateProfileParams(
        uid: event.uid,
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
      ),
    );
    result.fold(
      (failure) => emit(ProfileError(message: failure.message)),
      (delegate) => emit(ProfileLoaded(delegate: delegate)),
    );
  }
}
