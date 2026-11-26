// TAS-90: streams are built once per input, not on every build().
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/widgets/keyed_stream_builder.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rebuilds [KeyedStreamBuilder] with a fresh `create` closure each time,
/// exactly like an inline `stream:` inside a parent's build().
class _Host extends StatefulWidget {
  const _Host({required this.firestore, required this.onCreate});

  final FakeFirebaseFirestore firestore;
  final VoidCallback onCreate;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String companyUID = 'comp1';
  int rebuilds = 0;

  void rebuild() => setState(() => rebuilds++);

  void switchCompany(String uid) => setState(() => companyUID = uid);

  @override
  Widget build(BuildContext context) {
    final company = companyUID;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: KeyedStreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        streamKey: ('leave_requests', company),
        create: () {
          widget.onCreate();
          return widget.firestore
              .collection('leave_requests')
              .where('companyUID', isEqualTo: company)
              .where('status', isEqualTo: 'pending')
              .snapshots();
        },
        builder: (context, snapshot) =>
            Text('count=${snapshot.data?.docs.length ?? 0}'),
      ),
    );
  }
}

void main() {
  late FakeFirebaseFirestore firestore;
  late int creates;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    creates = 0;
    for (final (company, status) in [
      ('comp1', 'pending'),
      ('comp1', 'pending'),
      ('comp1', 'approved'),
      ('comp2', 'pending'),
    ]) {
      await firestore.collection('leave_requests').add({
        'companyUID': company,
        'status': status,
      });
    }
  });

  testWidgets('parent rebuilds do not create a new stream', (tester) async {
    await tester.pumpWidget(
      _Host(firestore: firestore, onCreate: () => creates++),
    );
    await tester.pump();
    expect(find.text('count=2'), findsOneWidget);
    expect(creates, 1);

    final state = tester.state<_HostState>(find.byType(_Host));
    for (var i = 0; i < 5; i++) {
      state.rebuild();
      await tester.pump();
    }
    expect(state.rebuilds, 5);
    expect(creates, 1, reason: 'same inputs must reuse the stream');
    expect(find.text('count=2'), findsOneWidget);
  });

  testWidgets('the cached stream stays live', (tester) async {
    await tester.pumpWidget(
      _Host(firestore: firestore, onCreate: () => creates++),
    );
    await tester.pump();
    expect(find.text('count=2'), findsOneWidget);

    await firestore.collection('leave_requests').add({
      'companyUID': 'comp1',
      'status': 'pending',
    });
    await tester.pump();
    expect(find.text('count=3'), findsOneWidget);
    expect(creates, 1);
  });

  testWidgets('a new input key re-subscribes with the new filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Host(firestore: firestore, onCreate: () => creates++),
    );
    await tester.pump();
    expect(find.text('count=2'), findsOneWidget);

    tester.state<_HostState>(find.byType(_Host)).switchCompany('comp2');
    await tester.pump();
    await tester.pump();
    expect(creates, 2);
    // Company scoping holds: only comp2's pending request is counted.
    expect(find.text('count=1'), findsOneWidget);
  });

  testWidgets('a throwing create reaches the builder as an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: KeyedStreamBuilder<int>(
          streamKey: 'x',
          create: () => throw StateError('no Firebase app'),
          builder: (context, snapshot) =>
              Text(snapshot.hasError ? 'error' : 'waiting'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('error'), findsOneWidget);
  });
}
