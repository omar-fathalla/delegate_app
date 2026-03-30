import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PaginationListView extends StatefulWidget {
  const PaginationListView({super.key});

  @override
  State<PaginationListView> createState() => _PaginationListViewState();
}

class _PaginationListViewState extends State<PaginationListView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Initial fetch
    context.read<ExamplePaginationBloc>().add(LoadFirstBatchRequested());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom) {
      context.read<ExamplePaginationBloc>().add(LoadNextBatchRequested());
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    // Load next batch when user is within 10% of the bottom
    return currentScroll >= (maxScroll * 0.9);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ExamplePaginationBloc, PaginationState>(
      builder: (context, state) {
        if (state.isLoading && state.items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.errorMessage != null && state.items.isEmpty) {
          return Center(child: Text(state.errorMessage!));
        }

        if (state.items.isEmpty) {
          return const Center(child: Text("No items found"));
        }

        return ListView.builder(
          controller: _scrollController,
          itemCount: state.hasReachedMax ? state.items.length : state.items.length + 1,
          itemBuilder: (context, index) {
            // Check if we reached the loading indicator at the bottom
            if (index >= state.items.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final item = state.items[index];
            return ListTile(
              title: Text("Item ${item.title}"),
              // Your custom list item widget here
            );
          },
        );
      },
    );
  }
}
