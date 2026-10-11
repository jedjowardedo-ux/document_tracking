import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'sidebar.dart';

// --- DESIGN TOKENS (same palette as dashboard, inbox, track, docu list, archive) ---
class _C {
  static const ink = Color(0xFF0B1B3A);
  static const inkSoft = Color(0xFF14337A);
  static const blue = Color(0xFF2563EB);
  static const paper = Color(0xFFF5F7FB);
  static const line = Color(0xFFE3E8F0);
  static const text = Color(0xFF1E293B);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);
  static const green = Color(0xFF1F9D63);
  static const red = Color(0xFFD64545);
  static const amber = Color(0xFFD99A1E);
}

// --- FIELD NAMES (taken from your upload screen) ---
class _F {
  static const recipientId = 'recipientId'; // documents (current holder) + history
  static const uploaderId = 'uploaderId'; // documents
  static const senderId = 'senderId'; // history
}

enum RegistryType { incoming, outgoing, filing, logs }

// --- DATA MODELS ---
class RegistryRecord {
  final String id;
  final String title;
  final String originOffice;
  final String senderOffice;
  final String destinationOffice;
  final String receiverName;
  final String uploaderName;
  final String senderName;
  final String status;
  final String? folderId;
  final String? folderName;
  final String? folderLocation;
  final DateTime? createdAt;
  final DateTime? interactionDate;
  final String? timeReleased;
  final int? docNumber;

  RegistryRecord({
    required this.id,
    required this.title,
    this.originOffice = 'Main Office',
    this.senderOffice = 'N/A',
    this.destinationOffice = 'Registry',
    this.receiverName = 'N/A',
    this.uploaderName = 'Staff',
    this.senderName = 'Staff',
    this.status = 'pending',
    this.folderId,
    this.folderName,
    this.folderLocation,
    this.createdAt,
    this.interactionDate,
    this.timeReleased,
    this.docNumber,
  });

  // Shown in the "Doc No." column: #0001, #0002... (falls back to the id for old documents)
  String get docNo => docNumber != null
      ? '#${docNumber.toString().padLeft(4, '0')}'
      : '#$id';

  factory RegistryRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return RegistryRecord(
      id: doc.id,
      title: (data['title'] ?? data['document_title'] ?? 'Untitled Document')
          .toString(),
      destinationOffice:
      (data['destinationOffice'] ?? 'Registry').toString(),
      receiverName: (data['recipientName'] ?? 'N/A').toString(),
      uploaderName: (data['senderName'] ?? 'Staff').toString(),
      senderName: (data['senderName'] ?? 'Staff').toString(),
      status: (data['status'] ?? 'pending').toString(),
      folderId: (data['folderId'] ?? data['folder_id'])?.toString(),
      createdAt: ts(data['createdAt']),
      interactionDate: ts(data['updatedAt']) ?? ts(data['createdAt']),
      docNumber: (data['docNumber'] as num?)?.toInt(),
    );
  }
}

class FolderItem {
  final String id;
  final String name;

  FolderItem({required this.id, required this.name});

  factory FolderItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FolderItem(
      id: doc.id,
      name: data['folder_name'] ?? 'Unnamed Folder',
    );
  }
}

class HistoryStep {
  final String status;
  final String senderName;
  final String officeName;
  final String movedAt;

  HistoryStep({
    required this.status,
    required this.senderName,
    required this.officeName,
    required this.movedAt,
  });
}

// --- MAIN RECORDS SCREEN ---
class RecordsScreen extends StatefulWidget {
  final String? folderId;
  final String? folderName;

  const RecordsScreen({
    super.key,
    this.folderId,
    this.folderName,
  });

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  RegistryType _currentType = RegistryType.incoming;
  String _searchQuery = '';
  int _currentPage = 1;
  final int _itemsPerPage = 5;
  String? _activeFolderId;
  String? _activeFolderName;

  late Stream<List<RegistryRecord>> _recordsStream;

  // Small caches so the same user/folder isn't re-read for every row
  final Map<String, Map<String, dynamic>> _userCache = {};
  final Map<String, Map<String, dynamic>> _folderCache = {};

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _activeFolderId = widget.folderId;
    _activeFolderName = widget.folderName;
    _recordsStream = _buildStream(_currentType);
  }

  // ---------- DATA (mirrors the conditions in records.php) ----------

  DateTime? _ts(dynamic v) => v is Timestamp ? v.toDate() : null;

  Future<Map<String, dynamic>> _lookup(
      String collection,
      String? id,
      Map<String, Map<String, dynamic>> cache,
      ) async {
    if (id == null || id.isEmpty) return {};
    final cached = cache[id];
    if (cached != null) return cached;
    final snap =
    await FirebaseFirestore.instance.collection(collection).doc(id).get();
    final data = snap.data() ?? <String, dynamic>{};
    cache[id] = data;
    return data;
  }

  String? _nameOf(Map<String, dynamic> u) {
    final n = (u['name'] ?? u['userName'])?.toString().trim();
    return (n == null || n.isEmpty) ? null : n;
  }

  String? _officeOf(Map<String, dynamic> u) {
    final o = u['officeName']?.toString().trim();
    return (o == null || o.isEmpty) ? null : o;
  }

  // Builds one table row. [h] is the history step for Outgoing/Logs rows.
  Future<RegistryRecord> _toRecord(
      String docId,
      Map<String, dynamic> d,
      RegistryType type, {
        Map<String, dynamic>? h,
      }) async {
    final senderId = (h?['senderId'] ?? d['senderId'])?.toString();
    final recipientId = (h?['recipientId'] ?? d['recipientId'])?.toString();
    final uploaderId = (d['uploaderId'] ?? d['senderId'])?.toString();
    final folderId = (d['folderId'] ?? d['folder_id'])?.toString();

    final sender = await _lookup('users', senderId, _userCache);
    final uploader = await _lookup('users', uploaderId, _userCache);
    final recipient = await _lookup('users', recipientId, _userCache);
    final folder = await _lookup('folders', folderId, _folderCache);

    final moved =
        _ts(h?['movedAt']) ?? _ts(d['updatedAt']) ?? _ts(d['createdAt']);

    // PHP: Outgoing shows the uploader's office, Incoming/Logs the sender's
    final originOffice = type == RegistryType.outgoing
        ? _officeOf(uploader)
        : _officeOf(sender);

    return RegistryRecord(
      id: docId,
      title: (d['title'] ?? d['document_title'] ?? 'Untitled Document')
          .toString(),
      originOffice: originOffice ?? 'Main Office',
      senderOffice: _officeOf(sender) ?? 'N/A',
      destinationOffice:
      (h?['destinationOffice'] ?? d['destinationOffice'] ?? 'Registry')
          .toString(),
      receiverName:
      _nameOf(recipient) ?? d['recipientName']?.toString() ?? 'N/A',
      uploaderName:
      _nameOf(uploader) ?? d['senderName']?.toString() ?? 'Staff',
      senderName: _nameOf(sender) ?? d['senderName']?.toString() ?? 'Staff',
      status: (d['status'] ?? 'pending').toString(),
      folderId: folderId,
      folderName: (folder['folderName'] ??
          folder['folder_name'] ??
          d['folderName'] ??
          'Unassigned')
          .toString(),
      folderLocation: (folder['location'] ??
          folder['folderLocation'] ??
          folder['folder_location'] ??
          'Vault-A')
          .toString(),
      createdAt: _ts(d['createdAt']),
      interactionDate: moved,
      timeReleased: moved != null ? DateFormat('hh:mm a').format(moved) : 'N/A',
      docNumber: (d['docNumber'] as num?)?.toInt(),
    );
  }

  Future<List<RegistryRecord>> _fromDocs(
      QuerySnapshot<Map<String, dynamic>> snap,
      RegistryType type,
      ) {
    return Future.wait(snap.docs.map((d) => _toRecord(d.id, d.data(), type)));
  }

  Stream<List<RegistryRecord>> _buildStream(RegistryType type) {
    final uid = _uid;
    if (uid == null) return Stream.value(<RegistryRecord>[]);
    final docs = FirebaseFirestore.instance.collection('documents');

    switch (type) {
      case RegistryType.incoming:
      // PHP: latest step is addressed to me, status != approved
        return docs
            .where(_F.recipientId, isEqualTo: uid)
            .snapshots()
            .asyncMap((s) => _fromDocs(s, type));

      case RegistryType.filing:
      // PHP: (receiver = me OR uploader = me) AND approved
        return docs
            .where(Filter.or(
          Filter(_F.recipientId, isEqualTo: uid),
          Filter(_F.uploaderId, isEqualTo: uid),
        ))
            .snapshots()
            .asyncMap((s) => _fromDocs(s, type));

      case RegistryType.outgoing:
      // PHP: history.sender = me AND status IN (forwarded, uploaded).
      // Your upload screen saves the first step as 'pending', so it counts too.
        return _historyStream(
          type: type,
          field: _F.senderId,
          uid: uid,
          allowedStatuses: const ['forwarded', 'uploaded', 'pending'],
        );

      case RegistryType.logs:
      // PHP: history.receiver = me (every status)
        return _historyStream(
          type: type,
          field: _F.recipientId,
          uid: uid,
        );
    }
  }

  Stream<List<RegistryRecord>> _historyStream({
    required RegistryType type,
    required String field,
    required String uid,
    List<String>? allowedStatuses,
  }) {
    return FirebaseFirestore.instance
        .collection('documents')
        .snapshots()
        .asyncMap((snap) async {
      final perDoc = await Future.wait(snap.docs.map((d) async {
        // Query inside ONE document's history: no special index needed
        final steps = await d.reference
            .collection('history')
            .where(field, isEqualTo: uid)
            .get();

        final matching = steps.docs.where((h) {
          if (allowedStatuses == null) return true;
          final s = (h.data()['status'] ?? '').toString().toLowerCase();
          return allowedStatuses.contains(s);
        }).toList();

        return Future.wait(
          matching.map((h) => _toRecord(d.id, d.data(), type, h: h.data())),
        );
      }));

      return perDoc.expand((r) => r).toList();
    });
  }

  // Trail dialog data: one entry per history step, newest first
  Stream<List<HistoryStep>> _trailStream(String docId) {
    return FirebaseFirestore.instance
        .collection('documents')
        .doc(docId)
        .collection('history')
        .orderBy('movedAt', descending: true)
        .snapshots()
        .asyncMap((snap) => Future.wait(snap.docs.map((doc) async {
      final data = doc.data();
      final u = await _lookup(
          'users', data['senderId']?.toString(), _userCache);
      final date = _ts(data['movedAt']);
      return HistoryStep(
        status: (data['status'] ?? 'pending').toString(),
        senderName: _nameOf(u) ?? 'Staff',
        officeName:
        (data['destinationOffice'] ?? 'Registry').toString(),
        movedAt: date != null
            ? DateFormat('MMM dd, yyyy • hh:mm a').format(date)
            : 'N/A',
      );
    })));
  }

  String _formatDate(DateTime? date, {String format = 'MM/dd/yyyy'}) {
    if (date == null) return 'N/A';
    return DateFormat(format).format(date);
  }

  // ---------- UI HELPERS (styling only) ----------

  String _tabLabel(RegistryType type) {
    final n = type.name;
    return n[0].toUpperCase() + n.substring(1);
  }

  void _styledSnack(BuildContext ctx, String message, {Color? color}) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _dialogTitle(
      IconData icon, Color color, Color tint, String title, String subtitle,
      {Widget? trailing}) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _C.ink,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: subtitle.toLowerCase().contains('cannot') ? _C.red : _C.muted,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  ButtonStyle _cancelStyle() => OutlinedButton.styleFrom(
    minimumSize: const Size(0, 46),
    foregroundColor: _C.muted,
    side: const BorderSide(color: _C.line),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );

  ButtonStyle _primaryStyle(Color bg) => ElevatedButton.styleFrom(
    minimumSize: const Size(0, 46),
    backgroundColor: bg,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );

  Widget _statusPill(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // Deletes the document and its 'history' subcollection together
  Future<void> _deleteDocument(String docId) async {
    final db = FirebaseFirestore.instance;
    final docRef = db.collection('documents').doc(docId);

    try {
      final history = await docRef.collection('history').get();

      final batch = db.batch();
      for (final h in history.docs) {
        batch.delete(h.reference);
      }
      batch.delete(docRef);
      await batch.commit();

      if (mounted) {
        _styledSnack(context, "Document deleted successfully.", color: _C.green);
      }
    } catch (e) {
      if (mounted) {
        _styledSnack(context, "Failed to delete document: $e", color: _C.red);
      }
    }
  }

  // Confirmation dialog before deleting
  void _confirmDelete(String docId, String title) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          title: _dialogTitle(
            Icons.delete_outline_rounded,
            _C.red,
            const Color(0xFFFBEAEA),
            "Delete document?",
            "This action cannot be undone",
          ),
          content: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _C.paper,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "\"$title\" and its document trail will be permanently removed.",
              style: const TextStyle(fontSize: 13, color: _C.text, height: 1.4),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          actions: [
            OutlinedButton(
              style: _cancelStyle(),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel",
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              style: _primaryStyle(_C.red),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _deleteDocument(docId);
              },
              child: const Text("Delete",
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }

  // Dialog to assign/move document to a folder
  void _openMoveModal(String docId) {
    String? selectedFolderId;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              title: _dialogTitle(
                Icons.drive_file_move_outlined,
                _C.blue,
                const Color(0xFFE8F0FE),
                "Move to folder",
                "Relocate document within registry",
              ),
              content: StreamBuilder<QuerySnapshot>(
                stream:
                FirebaseFirestore.instance.collection('folders').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 80,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final folders = snapshot.data!.docs
                      .map((d) => FolderItem.fromFirestore(d))
                      .toList();

                  return Container(
                    width: double.maxFinite,
                    padding: const EdgeInsets.only(top: 8),
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedFolderId,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: _C.muted),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _C.paper,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        hintText: "Select folder",
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _C.muted,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                          const BorderSide(color: _C.blue, width: 1.5),
                        ),
                      ),
                      items: folders.map((f) {
                        return DropdownMenuItem<String>(
                          value: f.id,
                          child: Text(
                            f.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: _C.text),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setModalState(() => selectedFolderId = val),
                    ),
                  );
                },
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              actions: [
                OutlinedButton(
                  style: _cancelStyle(),
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel",
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                ElevatedButton(
                  style: _primaryStyle(_C.ink),
                  onPressed: () async {
                    if (selectedFolderId == null) {
                      _styledSnack(context, "Please select a folder");
                      return;
                    }

                    Navigator.pop(dialogContext);

                    await FirebaseFirestore.instance
                        .collection('documents')
                        .doc(docId)
                        .update({'folderId': selectedFolderId});

                    if (mounted) {
                      _styledSnack(
                        this.context,
                        "Document moved and filed successfully!",
                        color: _C.green,
                      );
                    }
                  },
                  child: const Text("Move now",
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Dialog to view document timeline / audit trail
  void _openHistoryModal(String docId) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          title: _dialogTitle(
            Icons.alt_route_rounded,
            _C.blue,
            const Color(0xFFE8F0FE),
            "Document trail",
            "Every step this document has taken",
            trailing: IconButton(
              icon: const Icon(Icons.close_rounded, color: _C.faint),
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: StreamBuilder<List<HistoryStep>>(
              stream: _trailStream(docId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Could not load trail: ${snapshot.error}',
                      style: const TextStyle(color: _C.red, fontSize: 12),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text(
                      "No history trail found for this document.",
                      style: TextStyle(color: _C.muted, fontSize: 13),
                    ),
                  );
                }

                final steps = snapshot.data!;

                return ListView.builder(
                  itemCount: steps.length,
                  itemBuilder: (context, index) {
                    final step = steps[index];
                    Color statusColor;
                    Color statusTint;
                    IconData statusIcon;

                    switch (step.status.toLowerCase()) {
                      case 'approved':
                        statusColor = _C.green;
                        statusTint = const Color(0xFFE6F5EE);
                        statusIcon = Icons.check_rounded;
                        break;
                      case 'forwarded':
                        statusColor = _C.blue;
                        statusTint = const Color(0xFFE8F0FE);
                        statusIcon = Icons.share_rounded;
                        break;
                      case 'rejected':
                        statusColor = _C.red;
                        statusTint = const Color(0xFFFBEAEA);
                        statusIcon = Icons.close_rounded;
                        break;
                      default:
                        statusColor = _C.muted;
                        statusTint = const Color(0xFFF1F5F9);
                        statusIcon = Icons.info_outline_rounded;
                    }

                    final isFirst = index == 0;

                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isFirst ? statusColor : statusTint,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isFirst
                                        ? Colors.white
                                        : statusColor.withValues(alpha: 0.4),
                                    width: isFirst ? 3 : 1.5,
                                  ),
                                  boxShadow: isFirst
                                      ? [
                                    BoxShadow(
                                      color: statusColor.withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      spreadRadius: 1,
                                    )
                                  ]
                                      : null,
                                ),
                                child: Icon(statusIcon,
                                    color: isFirst ? Colors.white : statusColor,
                                    size: 16),
                              ),
                              if (index != steps.length - 1)
                                Expanded(
                                  child: Container(
                                    width: 2,
                                    margin:
                                    const EdgeInsets.symmetric(vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _C.line,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isFirst
                                      ? const Color(0xFFBFD3F7)
                                      : _C.line,
                                  width: isFirst ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${step.status.toUpperCase()} • ${step.movedAt}",
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: _C.faint,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    step.senderName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: _C.text,
                                    ),
                                  ),
                                  Text(
                                    step.officeName,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _C.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  // Record filtering logic based on selected tab and search input
  List<RegistryRecord> _filterRecords(List<RegistryRecord> allDocs) {
    final result = allDocs.where((doc) {
      final matchSearch = _searchQuery.isEmpty ||
          doc.title.toLowerCase().contains(_searchQuery) ||
          doc.id.toLowerCase().contains(_searchQuery) ||
          doc.docNo.toLowerCase().contains(_searchQuery) ||
          doc.originOffice.toLowerCase().contains(_searchQuery) ||
          doc.uploaderName.toLowerCase().contains(_searchQuery);

      if (!matchSearch) return false;

      switch (_currentType) {
        case RegistryType.incoming:
          return doc.status != 'approved';
        case RegistryType.filing:
          if (doc.status != 'approved') return false;
          return _activeFolderId != null
              ? doc.folderId == _activeFolderId
              : (doc.folderId == null || doc.folderId!.isEmpty);
        case RegistryType.outgoing:
        case RegistryType.logs:
          return true; // already limited to my history steps in the stream
      }
    }).toList();

    // PHP: ORDER BY moved_at / updated_at ASC (flip a and b for newest first)
    result.sort((a, b) => (a.interactionDate ?? DateTime(0))
        .compareTo(b.interactionDate ?? DateTime(0)));
    return result;
  }

  List<DataColumn> _getHeaders() {
    List<String> titles;
    switch (_currentType) {
      case RegistryType.outgoing:
        titles = [
          'Date Received', 'Doc No.', 'Office of Origin', 'Sender\'s Office',
          'Destination Office', 'Addressee', 'Document Title',
          'Responsible Person', 'Date Released', 'Time Released', 'Trail'
        ];
        break;
      case RegistryType.filing:
        titles = [
          'Date', 'Doc No.', 'Office of Origin', 'Document Title',
          'Responsible Person', 'Folder Name', 'Location', 'Trail'
        ];
        break;
      case RegistryType.logs:
      case RegistryType.incoming:
        titles = [
          'Date Received', 'Doc No.', 'Office of Origin', 'Document Title',
          'Responsible Person', 'Status', 'Trail'
        ];
        break;
    }

    return titles
        .map((t) => DataColumn(
      label: Text(
        t.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: _C.muted,
          letterSpacing: 0.6,
        ),
      ),
    ))
        .toList();
  }

  List<DataRow> _getRows(List<RegistryRecord> records) {
    const idStyle = TextStyle(color: _C.blue, fontWeight: FontWeight.w800);
    const titleStyle = TextStyle(fontWeight: FontWeight.w800, color: _C.ink);

    return records.map((row) {
      List<DataCell> cells = [];

      switch (_currentType) {
        case RegistryType.outgoing:
          cells = [
            DataCell(Text(_formatDate(row.createdAt, format: 'MMM dd, yyyy'))),
            DataCell(Text(row.docNo, style: idStyle)),
            DataCell(Text(row.originOffice)),
            DataCell(Text(row.senderOffice)),
            DataCell(Text(row.destinationOffice)),
            DataCell(Text(row.receiverName)),
            DataCell(Text(row.title, style: titleStyle)),
            DataCell(Text(row.uploaderName)),
            DataCell(Text(
                _formatDate(row.interactionDate, format: 'MMM dd, yyyy'))),
            DataCell(Text(row.timeReleased ?? 'N/A')),
          ];
          break;

        case RegistryType.filing:
          cells = [
            DataCell(Text(_formatDate(row.interactionDate))),
            DataCell(Text(row.docNo, style: idStyle)),
            DataCell(Text(row.originOffice)),
            DataCell(Text(row.title, style: titleStyle)),
            DataCell(Text(row.uploaderName)),
            DataCell(
              Row(
                children: [
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FE),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      row.folderName ?? 'Unassigned',
                      style: const TextStyle(
                        color: _C.blue,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 16, color: _C.faint),
                    onPressed: () => _openMoveModal(row.id),
                  ),
                ],
              ),
            ),
            DataCell(Text(
              row.folderLocation ?? 'Vault-A',
              style: const TextStyle(
                  color: _C.green, fontWeight: FontWeight.w700),
            )),
          ];
          break;

        case RegistryType.logs:
        case RegistryType.incoming:
          Color statusBg = _currentType == RegistryType.incoming
              ? const Color(0xFFFCF3DC)
              : (row.status == 'approved'
              ? const Color(0xFFE6F5EE)
              : const Color(0xFFE8F0FE));
          Color statusText = _currentType == RegistryType.incoming
              ? const Color(0xFFB7791F)
              : (row.status == 'approved' ? _C.green : _C.blue);

          cells = [
            DataCell(Text(_formatDate(row.interactionDate))),
            DataCell(Text(row.docNo, style: idStyle)),
            DataCell(Text(row.originOffice)),
            DataCell(Text(row.title, style: titleStyle)),
            DataCell(Text(row.senderName)),
            DataCell(_statusPill(row.status.toUpperCase(), statusBg, statusText)),
          ];
          break;
      }

      // Trail + Delete actions
      cells.add(
        DataCell(
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.ink,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _openHistoryModal(row.id),
                icon: const Icon(Icons.alt_route_rounded, size: 14),
                label: const Text(
                  "View trail",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              Material(
                color: const Color(0xFFFBEAEA),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _confirmDelete(row.id, row.title),
                  child: const Tooltip(
                    message: 'Delete document',
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(Icons.delete_outline_rounded,
                          size: 18, color: _C.red),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      return DataRow(cells: cells);
    }).toList();
  }

  Widget _headerActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      style: TextButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_C.ink, _C.inkSoft],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border:
                    Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: const Icon(Icons.menu_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeFolderId != null
                          ? (_activeFolderName ?? "Folder files")
                          : "Registry log sheets",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _activeFolderId != null
                          ? "Viewing files inside folder"
                          : "Official records registry system",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_currentType == RegistryType.filing &&
                  _activeFolderId != null)
                _headerActionButton(
                  icon: Icons.list_rounded,
                  label: "View all unfiled",
                  onPressed: () => setState(() {
                    _activeFolderId = null;
                    _activeFolderName = null;
                  }),
                ),
              _headerActionButton(
                icon: Icons.print_outlined,
                label: "Print log",
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text("Preparing document for print..."),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _C.paper,
      drawer: const Sidebar(currentPage: 'records.php'),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tab Navigation Bar
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: _C.line,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: RegistryType.values.map((type) {
                          final isSelected = _currentType == type;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _currentType = type;
                                _currentPage = 1;
                                _recordsStream = _buildStream(type);
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: isSelected
                                    ? [
                                  BoxShadow(
                                    color:
                                    Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                                    : [],
                              ),
                              child: Text(
                                _tabLabel(type),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? _C.ink : _C.muted,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Search Bar & Dynamic Counter
                  StreamBuilder<List<RegistryRecord>>(
                    stream: _recordsStream,
                    builder: (context, snapshot) {
                      List<RegistryRecord> filteredRecords = [];
                      if (snapshot.hasData) {
                        filteredRecords = _filterRecords(snapshot.data!);
                      }

                      final totalRecords = filteredRecords.length;
                      final totalPages = (totalRecords / _itemsPerPage).ceil();

                      // If a delete empties the current page, step back a page
                      if (_currentPage > 1 && _currentPage > totalPages) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() => _currentPage =
                            totalPages == 0 ? 1 : totalPages);
                          }
                        });
                      }

                      final startIndex = (_currentPage - 1) * _itemsPerPage;
                      final endIndex = startIndex + _itemsPerPage > totalRecords
                          ? totalRecords
                          : startIndex + _itemsPerPage;

                      final pageRecords = (startIndex < totalRecords)
                          ? filteredRecords.sublist(startIndex, endIndex)
                          : <RegistryRecord>[];

                      return Column(
                        children: [
                          if (snapshot.hasError)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'Could not load records: ${snapshot.error}',
                                style: const TextStyle(
                                    color: _C.red, fontSize: 12),
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  onChanged: (val) {
                                    setState(() {
                                      _searchQuery = val.toLowerCase();
                                      _currentPage = 1;
                                    });
                                  },
                                  style: const TextStyle(
                                      fontSize: 14, color: _C.text),
                                  decoration: InputDecoration(
                                    hintText: "Search registry records...",
                                    hintStyle: const TextStyle(
                                        fontSize: 14, color: _C.faint),
                                    prefixIcon: const Icon(Icons.search_rounded,
                                        size: 20, color: _C.faint),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 14),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide:
                                      const BorderSide(color: _C.line),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide:
                                      const BorderSide(color: _C.line),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                          color: _C.blue, width: 1.5),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: _C.ink,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      "${filteredRecords.length}",
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Container(
                                        height: 20,
                                        width: 1,
                                        color: Colors.white24),
                                    const SizedBox(width: 10),
                                    const Text(
                                      "Records\nfound",
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white70,
                                        height: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Table Display
                          Container(
                            width: double.infinity,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: _C.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    headingRowColor:
                                    WidgetStateProperty.all(_C.paper),
                                    headingRowHeight: 48,
                                    dividerThickness: 1,
                                    dataTextStyle: const TextStyle(
                                        fontSize: 12.5, color: _C.text),
                                    dataRowMinHeight: 56,
                                    dataRowMaxHeight: 64,
                                    horizontalMargin: 20,
                                    columnSpacing: 24,
                                    columns: _getHeaders(),
                                    rows: pageRecords.isEmpty
                                        ? [
                                      DataRow(
                                        cells: [
                                          DataCell(
                                            SizedBox(
                                              width: MediaQuery.of(context)
                                                  .size
                                                  .width,
                                              child: const Center(
                                                child: Padding(
                                                  padding:
                                                  EdgeInsets.symmetric(
                                                      vertical: 32),
                                                  child: Text(
                                                    "No records found in this section.",
                                                    style: TextStyle(
                                                      color: _C.muted,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          ...List.generate(
                                            _getHeaders().length - 1,
                                                (_) => const DataCell(
                                                SizedBox.shrink()),
                                          )
                                        ],
                                      )
                                    ]
                                        : _getRows(pageRecords),
                                  ),
                                ),

                                // Pagination Controls
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: const BoxDecoration(
                                    color: _C.paper,
                                    border: Border(
                                        top: BorderSide(color: _C.line)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Page $_currentPage of ${totalPages == 0 ? 1 : totalPages}",
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _C.muted,
                                        ),
                                      ),
                                      Flexible(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          reverse: true,
                                          child: Row(
                                            children: List.generate(
                                              totalPages == 0 ? 1 : totalPages,
                                                  (index) {
                                                final pageNum = index + 1;
                                                final isCurrentPage =
                                                    pageNum == _currentPage;
                                                return Padding(
                                                  padding:
                                                  const EdgeInsets.only(
                                                      left: 6.0),
                                                  child: InkWell(
                                                    onTap: () => setState(() =>
                                                    _currentPage = pageNum),
                                                    borderRadius:
                                                    BorderRadius.circular(10),
                                                    child: Container(
                                                      width: 32,
                                                      height: 32,
                                                      alignment:
                                                      Alignment.center,
                                                      decoration: BoxDecoration(
                                                        color: isCurrentPage
                                                            ? _C.ink
                                                            : Colors.white,
                                                        borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                        border: Border.all(
                                                          color: isCurrentPage
                                                              ? _C.ink
                                                              : _C.line,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        "$pageNum",
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                          FontWeight.w700,
                                                          color: isCurrentPage
                                                              ? Colors.white
                                                              : _C.muted,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}