import 'package:flutter/material.dart';

class SearchableDropdownDialog extends StatefulWidget {
  final String title;
  final List<String> items;
  const SearchableDropdownDialog({super.key, required this.title, required this.items});
  @override
  State<SearchableDropdownDialog> createState() => _SearchableDropdownDialogState();
}

class _SearchableDropdownDialogState extends State<SearchableDropdownDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((e) => e.toLowerCase().contains(_query.toLowerCase())).toList();
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                return ListTile(
                  title: Text(filtered[i]),
                  onTap: () => Navigator.pop(context, filtered[i]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          )
        ],
      ),
    );
  }
}
