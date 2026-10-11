import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// One row of the `offices` collection (mirrors the `office` table:
/// office_name + division).
class OfficeItem {
  final String id;
  final String name;
  final String division;
  final int sortOrder;

  OfficeItem({
    required this.id,
    required this.name,
    required this.division,
    required this.sortOrder,
  });

  factory OfficeItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return OfficeItem(
      id: doc.id,
      name: (data['office_name'] ?? data['name'] ?? data['officeName'] ?? '')
          .toString()
          .trim(),
      division: (data['division'] ?? 'Other').toString().trim(),
      sortOrder: (data['sort_order'] as num?)?.toInt() ?? 9999,
    );
  }
}

class OfficeService {
  /// Live list of offices, ordered by `sort_order` then name.
  static Stream<List<OfficeItem>> stream() {
    return FirebaseFirestore.instance
        .collection('offices')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => OfficeItem.fromFirestore(d))
          .where((o) => o.name.isNotEmpty)
          .toList();
      list.sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
      return list;
    });
  }
}

/// Searchable picker that loads offices from Firestore and groups them by
/// division. The selected value is the office NAME (same string your users
/// store in `officeName`), so the rest of the app keeps working unchanged.
class OfficeDropdownField extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? Function(String?)? validator;
  final InputDecoration decoration;
  final String hint;

  const OfficeDropdownField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.decoration,
    this.validator,
    this.hint = 'Select office...',
  });

  @override
  State<OfficeDropdownField> createState() => _OfficeDropdownFieldState();
}

class _OfficeDropdownFieldState extends State<OfficeDropdownField> {
  late final Stream<List<OfficeItem>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = OfficeService.stream();
  }

  Widget _message(String text, {Color color = const Color(0xFF94A3B8)}) {
    return InputDecorator(
      decoration: widget.decoration,
      child: Text(text, style: TextStyle(color: color, fontSize: 13)),
    );
  }

  Future<void> _openPicker(
      List<OfficeItem> offices,
      FormFieldState<String> field,
      ) async {
    FocusScope.of(context).unfocus();

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _OfficePickerSheet(
        offices: offices,
        selected: widget.value,
      ),
    );

    if (picked != null) {
      field.didChange(picked);
      widget.onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OfficeItem>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _message('Could not load offices: ${snapshot.error}',
              color: const Color(0xFFD64545));
        }
        if (!snapshot.hasData) {
          return _message('Loading offices...');
        }

        final offices = snapshot.data!;
        if (offices.isEmpty) {
          return _message('No offices found. Seed the offices collection first.');
        }

        final hasValue = offices.any((o) => o.name == widget.value);
        final current = hasValue ? widget.value : null;

        return FormField<String>(
          key: ValueKey('office_$current'),
          initialValue: current,
          validator: widget.validator,
          builder: (field) {
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openPicker(offices, field),
              child: InputDecorator(
                isEmpty: false,
                decoration: widget.decoration.copyWith(
                  errorText: field.errorText,
                  suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF64748B)),
                ),
                child: Text(
                  current ?? widget.hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: current == null ? 13 : 14,
                    color: current == null
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF1E293B),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Bottom sheet with a search box + division-grouped list.
class _OfficePickerSheet extends StatefulWidget {
  final List<OfficeItem> offices;
  final String? selected;

  const _OfficePickerSheet({required this.offices, required this.selected});

  @override
  State<_OfficePickerSheet> createState() => _OfficePickerSheetState();
}

class _OfficePickerSheetState extends State<_OfficePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = (media.size.height - media.viewInsets.bottom) * 0.85;

    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.offices
        : widget.offices
        .where((o) =>
    o.name.toLowerCase().contains(q) ||
        o.division.toLowerCase().contains(q))
        .toList();

    final children = <Widget>[];
    String? lastDivision;
    for (final o in filtered) {
      if (o.division != lastDivision) {
        lastDivision = o.division;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            o.division.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Color(0xFF2563EB),
            ),
          ),
        ));
      }

      final isSelected = o.name == widget.selected;
      children.add(ListTile(
        dense: true,
        title: Text(
          o.name,
          style: TextStyle(
            fontSize: 14,
            color: const Color(0xFF1E293B),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        trailing: isSelected
            ? const Icon(Icons.check, color: Color(0xFF2563EB), size: 20)
            : null,
        onTap: () => Navigator.pop(context, o.name),
      ));
    }

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search office or department...',
                  hintStyle:
                  const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                    const BorderSide(color: Color(0xFF2563EB), width: 2),
                  ),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                child: Text(
                  'No matching offices',
                  style: TextStyle(color: Color(0xFF94A3B8)),
                ),
              )
                  : ListView(children: children),
            ),
          ],
        ),
      ),
    );
  }
}