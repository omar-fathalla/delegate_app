import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import 'package:delegate_app/core/services/firestore_session_subscriptions.dart';

/// Live `users/{uid}` document bound to [FirestoreSessionSubscriptions].
///
/// [StreamBuilder] is not enough: its subscription is only cancelled in
/// dispose, which can run after [FirebaseAuth.signOut] and produce a
/// PERMISSION_DENIED on `users/{id}` (~3s after logout on M31 at 040ea9b).
/// Registering here lets AuthBloc cancel the listen *before* signOut.
class SessionUserDocBuilder extends StatefulWidget {
  const SessionUserDocBuilder({
    super.key,
    required this.uid,
    required this.subscriptionKey,
    required this.builder,
    this.firestore,
  });

  final String uid;
  final String subscriptionKey;
  final FirebaseFirestore? firestore;
  final Widget Function(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>>? snapshot,
  )
  builder;

  @override
  State<SessionUserDocBuilder> createState() => _SessionUserDocBuilderState();
}

class _SessionUserDocBuilderState extends State<SessionUserDocBuilder> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  DocumentSnapshot<Map<String, dynamic>>? _snap;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(SessionUserDocBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.subscriptionKey != widget.subscriptionKey ||
        oldWidget.firestore != widget.firestore) {
      _attach();
    }
  }

  void _attach() {
    final key = widget.subscriptionKey;
    unawaited(FirestoreSessionSubscriptions.instance.cancel(key));
    _sub = null;
    if (widget.uid.isEmpty) return;
    final fs = widget.firestore ?? FirebaseFirestore.instance;
    _sub = fs.collection('users').doc(widget.uid).snapshots().listen((doc) {
      if (!mounted) return;
      setState(() => _snap = doc);
    }, onError: (_) {});
    FirestoreSessionSubscriptions.instance.register(key, _sub!);
  }

  @override
  void dispose() {
    unawaited(
      FirestoreSessionSubscriptions.instance.cancel(widget.subscriptionKey),
    );
    _sub = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _snap);
}
