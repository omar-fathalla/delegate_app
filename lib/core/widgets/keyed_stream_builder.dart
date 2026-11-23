import 'package:flutter/widgets.dart';

/// A [StreamBuilder] that creates its stream once, not on every build
/// (TAS-90).
///
/// Writing `StreamBuilder(stream: query.snapshots())` inside `build()` makes
/// a new Firestore listener on every rebuild of the parent (a hover, a
/// `setState`, a keystroke), and each new listener reads the query again.
/// This widget calls [create] once when it is first inserted, keeps the
/// stream in its state, and calls [create] again only when [streamKey]
/// changes (compared with `==`, so a record such as
/// `('leave_requests', companyUID)` works as a key).
///
/// Put every input of the query (collection, company, organization, user)
/// in [streamKey], so a real change of input still re-subscribes.
///
/// When [create] throws (for example Firebase is not initialised in a widget
/// test), the builder receives the error as a snapshot error instead of the
/// build failing.
class KeyedStreamBuilder<T> extends StatefulWidget {
  const KeyedStreamBuilder({
    super.key,
    required this.streamKey,
    required this.create,
    required this.builder,
  });

  /// Identity of the stream's inputs. The stream is recreated only when this
  /// value changes.
  final Object? streamKey;

  /// Creates the stream. Called once per [streamKey].
  final Stream<T> Function() create;

  /// Same contract as [StreamBuilder.builder].
  final AsyncWidgetBuilder<T> builder;

  @override
  State<KeyedStreamBuilder<T>> createState() => _KeyedStreamBuilderState<T>();
}

class _KeyedStreamBuilderState<T> extends State<KeyedStreamBuilder<T>> {
  late Stream<T> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _createStream();
  }

  @override
  void didUpdateWidget(KeyedStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streamKey != oldWidget.streamKey) {
      _stream = _createStream();
    }
  }

  Stream<T> _createStream() {
    try {
      return widget.create();
    } catch (error, stackTrace) {
      return Stream<T>.error(error, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(stream: _stream, builder: widget.builder);
  }
}
