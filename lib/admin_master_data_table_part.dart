part of 'admin_master_data_screen.dart';

/// Shared list + CRUD for [MasterDataListPanel] and [MasterDataListModalSheet].
/// Avoids [GlobalKey] on the modal path (fixes `_dependents.isEmpty` when swiping the sheet closed).
mixin MasterDataListContentMixin<T extends StatefulWidget> on State<T> {
  String get masterDataStepId;
  MasterTableConfig get masterDataConfig;
  double get masterDataListBottomPadding;

  bool get _rowColour => _showColourCode(masterDataStepId);
  bool get _rowCategory => _showCategory(masterDataStepId);

  List<_MasterRow> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void openAdd() => _openEditor();

  Future<void> refreshList() async => _fetch();

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Supabase.instance.client
          .from(masterDataConfig.tableName)
          .select()
          .order('created_at', ascending: true);
      final list = (data as List<dynamic>)
          .map((e) => _MasterRow.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (mounted) {
        setState(() {
          _rows = list;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Master data fetch error: $e');
      if (mounted) {
        setState(() {
          _error = 'Could not load data. Check permissions and table name.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openEditor({_MasterRow? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _MasterDataEditorSheet(
        config: masterDataConfig,
        stepId: masterDataStepId,
        existing: existing,
        onSave: ({
          required BuildContext sheetContext,
          required String? existingId,
          required String value,
          required String colourCode,
          required String category,
        }) =>
            _saveRowValues(
          context: sheetContext,
          existingId: existingId,
          value: value,
          colourCode: colourCode,
          category: category,
        ),
      ),
    );

    if (saved == true && mounted) await _fetch();
  }

  Future<bool> _saveRowValues({
    required BuildContext context,
    required String? existingId,
    required String value,
    required String colourCode,
    required String category,
  }) async {
    final v = value.trim();
    if (v.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a ${masterDataConfig.title.toLowerCase()} value')),
      );
      return false;
    }

    if (_rowColour) {
      final hex = colourCode.trim().toUpperCase();
      if (hex.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a colour code (HEX)')));
        return false;
      }
      if (!_hexPattern.hasMatch(hex)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid HEX color code (e.g., #FF5733 or #F53)')),
        );
        return false;
      }
    }

    if (_rowCategory && category.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a category')));
      return false;
    }

    final payload = <String, dynamic>{'value': v};
    if (_rowColour) {
      payload['colour_code'] = colourCode.trim().toUpperCase();
    }
    if (_rowCategory) {
      payload['category'] = category.trim();
    }

    try {
      if (existingId != null) {
        await Supabase.instance.client.from(masterDataConfig.tableName).update(payload).eq('id', existingId);
      } else {
        await Supabase.instance.client.from(masterDataConfig.tableName).insert(payload);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(existingId != null ? 'Updated successfully' : 'Added successfully')),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Master data save error: $e');
      if (e is PostgrestException && e.code == '23505') {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('This ${masterDataConfig.title.toLowerCase()} value already exists')),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save: ${e is PostgrestException ? e.message : e}')),
          );
        }
      }
      return false;
    }
  }

  Future<void> _confirmDelete(_MasterRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${masterDataConfig.title} value'),
        content: Text('Are you sure you want to delete "${row.value}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await Supabase.instance.client.from(masterDataConfig.tableName).delete().eq('id', row.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
        await _fetch();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  Widget buildMasterDataListBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AdminHomeScreen.brandPurple));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    return RefreshIndicator(
      color: AdminHomeScreen.brandPurple,
      onRefresh: _fetch,
      child: _rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                Icon(Icons.inbox_outlined, size: 56, color: Colors.black.withValues(alpha: 0.2)),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'No ${masterDataConfig.title.toLowerCase()} values yet. Tap "${masterDataConfig.addButtonText}" to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black.withValues(alpha: 0.5), height: 1.4),
                  ),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 8, 16, masterDataListBottomPadding),
              itemCount: _rows.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final row = _rows[index];
                final swatch = _tryParseHex(row.colourCode);
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openEditor(existing: row),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${index + 1}.',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.black.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_rowCategory && (row.category ?? '').isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      row.category!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AdminHomeScreen.brandPurple.withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ),
                                Text(
                                  row.value,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E1E1E),
                                  ),
                                ),
                                if (_rowColour) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      if (swatch != null)
                                        Container(
                                          width: 28,
                                          height: 28,
                                          margin: const EdgeInsets.only(right: 8),
                                          decoration: BoxDecoration(
                                            color: swatch,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.black12),
                                          ),
                                        ),
                                      Text(
                                        row.colourCode ?? '—',
                                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.edit_outlined, color: AdminHomeScreen.brandPurple.withValues(alpha: 0.85)),
                            onPressed: () => _openEditor(existing: row),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
                            onPressed: () => _confirmDelete(row),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Add/edit form in its own [State] so [TextEditingController]s are disposed with the route
/// (avoids `_dependents.isEmpty` when swiping nested bottom sheets closed).
class _MasterDataEditorSheet extends StatefulWidget {
  const _MasterDataEditorSheet({
    required this.config,
    required this.stepId,
    this.existing,
    required this.onSave,
  });

  final MasterTableConfig config;
  final String stepId;
  final _MasterRow? existing;
  final Future<bool> Function({
    required BuildContext sheetContext,
    required String? existingId,
    required String value,
    required String colourCode,
    required String category,
  }) onSave;

  @override
  State<_MasterDataEditorSheet> createState() => _MasterDataEditorSheetState();
}

class _MasterDataEditorSheetState extends State<_MasterDataEditorSheet> {
  late final TextEditingController _valueCtrl;
  late final TextEditingController _colourCtrl;
  late final TextEditingController _categoryCtrl;
  late final ScrollController _scrollCtrl;

  bool get _rowColour => _showColourCode(widget.stepId);
  bool get _rowCategory => _showCategory(widget.stepId);
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _valueCtrl = TextEditingController(text: widget.existing?.value ?? '');
    _colourCtrl = TextEditingController(text: widget.existing?.colourCode ?? '');
    _categoryCtrl = TextEditingController(text: widget.existing?.category ?? '');
    _scrollCtrl = ScrollController();
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    _colourCtrl.dispose();
    _categoryCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final ok = await widget.onSave(
      sheetContext: context,
      existingId: widget.existing?.id,
      value: _valueCtrl.text,
      colourCode: _colourCtrl.text,
      category: _categoryCtrl.text,
    );
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        primary: false,
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isEdit ? 'Edit ${widget.config.title}' : widget.config.dialogTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _isEdit
                  ? 'Update the ${widget.config.title.toLowerCase()} value below.'
                  : widget.config.dialogDescription,
              style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 20),
            if (_rowCategory) ...[
              TextField(
                controller: _categoryCtrl,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  hintText: 'Enter category',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _valueCtrl,
              decoration: InputDecoration(
                labelText: '${widget.config.title} value',
                hintText: widget.config.inputPlaceholder,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_rowColour) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _colourCtrl,
                decoration: const InputDecoration(
                  labelText: 'Colour code (HEX)',
                  hintText: '#FF5733 or #F53',
                  border: OutlineInputBorder(),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[#A-Fa-f0-9]')),
                  LengthLimitingTextInputFormatter(7),
                ],
                onChanged: (v) {
                  if (v.isNotEmpty && !v.startsWith('#')) {
                    _colourCtrl.text = '#$v';
                    _colourCtrl.selection = TextSelection.collapsed(offset: _colourCtrl.text.length);
                  }
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Enter a valid HEX color code (e.g., #FF5733 or #F53)',
                style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45)),
              ),
              if (_tryParseHex(_colourCtrl.text) != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _tryParseHex(_colourCtrl.text),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AdminHomeScreen.brandPurple,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _handleSave,
              child: Text(_isEdit ? 'Update' : 'Save'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
