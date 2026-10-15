import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'sidebar.dart';
import 'track_screen.dart';

// Cloudinary config — cloud name + unsigned preset from the console.
final _cloudinary = CloudinaryPublic('nikh0hne', 'document_tracking_uploads', cache: false);

// --- DESIGN TOKENS (same palette as dashboard, inbox and track) ---
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

// ==========================================
// SHARED UI HELPERS
// ==========================================

InputDecoration _fieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 13, color: _C.muted),
    filled: true,
    fillColor: _C.paper,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _C.blue, width: 1.5),
    ),
  );
}

Widget _dialogTitle(IconData icon, Color color, Color tint, String text) {
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
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: _C.ink,
            letterSpacing: -0.2,
          ),
        ),
      ),
    ],
  );
}

void _snack(
    ScaffoldMessengerState messenger,
    String text, {
      bool error = false,
      SnackBarAction? action,
    }) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: error ? _C.red : null,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      action: action,
    ),
  );
}

// ==========================================
// DATA MODEL
// ==========================================

String _str(dynamic v) => v == null ? '' : v.toString();

class TrackedDocument {
  final String id;
  final String title;
  final String filename;
  final String fileUrl;
  final String uploaderId; // ID of user who uploaded/created the doc
  final String holderUserId; // Current holder
  final String officeId;
  final String status;
  final DateTime? dueDate;
  final DateTime createdAt;
  final bool isArchived;

  TrackedDocument({
    required this.id,
    required this.title,
    required this.filename,
    required this.fileUrl,
    required this.uploaderId,
    required this.holderUserId,
    required this.officeId,
    required this.status,
    this.dueDate,
    required this.createdAt,
    this.isArchived = false,
  });

  // Accepts typed and untyped snapshots, so every screen can call it
  factory TrackedDocument.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    // First non-empty value among several possible field names
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = _str(data[k]).trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final status = _str(data['status']).trim();

    return TrackedDocument(
      id: doc.id,
      title: _str(data['title']),
      filename: _str(data['filename']),
      fileUrl: _str(data['fileUrl']),
      uploaderId: pick(['uploaderId', 'senderUserId', 'senderId']),
      holderUserId: pick([
        'holderUserId',
        'receiverId',
        'receiver_id',
        'recipientId',
        'receiver_user_id',
      ]),
      officeId: pick(['officeId', 'receiverOfficeId']),
      status: status.isEmpty ? 'pending' : status,
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isArchived: data['isArchived'] == true,
    );
  }
}

// ==========================================
// DYNAMIC FIREBASE RESOLVER WIDGETS
// ==========================================

// The Future is created once per widget (not on every rebuild), so typing in
// the search box no longer re-reads the user / office for every card.
class FirebaseUserText extends StatefulWidget {
  final String userId;
  final TextStyle style;

  const FirebaseUserText({super.key, required this.userId, required this.style});

  @override
  State<FirebaseUserText> createState() => _FirebaseUserTextState();
}

class _FirebaseUserTextState extends State<FirebaseUserText> {
  Future<DocumentSnapshot<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FirebaseUserText old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _load();
  }

  void _load() {
    _future = widget.userId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    if (_future == null) return Text('Unknown User', style: style);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Text('...', style: style.copyWith(color: Colors.grey));
        }
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return Text(widget.userId, style: style, overflow: TextOverflow.ellipsis);
        }
        final data = snapshot.data!.data();
        final name = _str(data?['name']).isNotEmpty
            ? _str(data?['name'])
            : (_str(data?['fullName']).isNotEmpty
            ? _str(data?['fullName'])
            : widget.userId);
        return Text(name, style: style, overflow: TextOverflow.ellipsis);
      },
    );
  }
}

class FirebaseOfficeText extends StatefulWidget {
  final String officeId;
  final TextStyle style;

  const FirebaseOfficeText({super.key, required this.officeId, required this.style});

  @override
  State<FirebaseOfficeText> createState() => _FirebaseOfficeTextState();
}

class _FirebaseOfficeTextState extends State<FirebaseOfficeText> {
  Future<DocumentSnapshot<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FirebaseOfficeText old) {
    super.didUpdateWidget(old);
    if (old.officeId != widget.officeId) _load();
  }

  void _load() {
    _future = widget.officeId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('offices').doc(widget.officeId).get();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    if (_future == null) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Text('...', style: style.copyWith(color: Colors.grey));
        }
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return Text(' (${widget.officeId})',
              style: style, overflow: TextOverflow.ellipsis);
        }
        final data = snapshot.data!.data();
        String officeName = widget.officeId;
        for (final k in ['name', 'officeName', 'code']) {
          final v = _str(data?[k]);
          if (v.isNotEmpty) {
            officeName = v;
            break;
          }
        }
        return Text(' ($officeName)', style: style, overflow: TextOverflow.ellipsis);
      },
    );
  }
}

// ==========================================
// EDIT DIALOG (own State so its controllers are disposed properly)
// ==========================================

class _EditDocDialog extends StatefulWidget {
  final TrackedDocument doc;
  final ScaffoldMessengerState messenger;

  const _EditDocDialog({required this.doc, required this.messenger});

  @override
  State<_EditDocDialog> createState() => _EditDocDialogState();
}

class _EditDocDialogState extends State<_EditDocDialog> {
  late final TextEditingController _titleController =
  TextEditingController(text: widget.doc.title);
  late final TextEditingController _filenameController =
  TextEditingController(text: widget.doc.filename);

  PlatformFile? _selectedFile;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _filenameController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      // file_picker v12: pickFiles() returns List<PlatformFile> directly.
      final List<PlatformFile> files = await FilePicker.pickFiles();
      if (files.isEmpty || !mounted) return;
      setState(() {
        _selectedFile = files.first;
        _filenameController.text = files.first.name;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not pick the file: $e');
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    var filename = _filenameController.text.trim();

    if (title.isEmpty) {
      setState(() => _error = 'Document title cannot be empty.');
      return;
    }
    if (filename.isEmpty) {
      filename = _selectedFile?.name ?? widget.doc.filename;
    }

    // Grab these BEFORE any await / pop so no stale context is used later
    final navigator = Navigator.of(context);
    final messenger = widget.messenger;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      String newFileUrl = widget.doc.fileUrl;

      // 1. Upload the new file (Cloudinary) if one was picked
      if (_selectedFile != null) {
        final bytes = await _selectedFile!.readAsBytes();
        final res = await _cloudinary.uploadFile(
          CloudinaryFile.fromBytesData(
            bytes,
            identifier: _selectedFile!.name,
            resourceType: CloudinaryResourceType.Raw,
          ),
        );
        newFileUrl = res.secureUrl;
      }

      // 2. Update Firestore, re-checking the status inside a transaction so a
      //    document that was forwarded/approved meanwhile can't be overwritten
      final ref =
      FirebaseFirestore.instance.collection('documents').doc(widget.doc.id);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final status = _str(snap.data()?['status']).trim().toLowerCase();
        if (status.isNotEmpty && status != 'pending') {
          throw StateError(
              'This document has already been processed and can no longer be edited.');
        }
        tx.update(ref, {
          'title': title,
          'filename': filename,
          'fileUrl': newFileUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      navigator.pop();
      _snack(messenger, 'Document updated successfully!');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = e is StateError ? e.message : 'Failed to update document: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final hasNew = _selectedFile != null;

    // Block the Android back button while saving
    return PopScope(
      canPop: !_isSaving,
      child: AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        title: _dialogTitle(
          Icons.edit_outlined,
          _C.blue,
          const Color(0xFFE8F0FE),
          'Edit Pending Document',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                enabled: !_isSaving,
                decoration: _fieldDecoration('Document Title'),
              ),
              const SizedBox(height: 16),

              // FILE REPLACEMENT SELECTOR
              const Text(
                'Attached Document File',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12, color: _C.muted),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hasNew
                      ? const Color(0xFFE6F5EE)
                      : const Color(0xFFF1F6FE),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hasNew
                        ? const Color(0xFFBFE6D2)
                        : const Color(0xFFCFE0FB),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.insert_drive_file_outlined,
                      color: hasNew ? _C.green : _C.blue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasNew
                                ? _selectedFile!.name
                                : (doc.filename.isNotEmpty
                                ? doc.filename
                                : 'No file attached'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: _C.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            hasNew ? 'New file selected' : 'Current uploaded file',
                            style: TextStyle(
                              fontSize: 11,
                              color: hasNew ? _C.green : _C.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _isSaving ? null : _pickFile,
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: Text(
                        hasNew ? 'Change' : 'Replace',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _C.blue,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _filenameController,
                enabled: !_isSaving,
                decoration: _fieldDecoration('Display File Name'),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: _C.red),
                ),
              ],

              if (_isSaving) ...[
                const SizedBox(height: 18),
                Center(
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: const LinearProgressIndicator(
                          minHeight: 4,
                          backgroundColor: _C.line,
                          color: _C.blue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Uploading file & saving changes...',
                          style: TextStyle(fontSize: 12, color: _C.muted)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        actions: _isSaving
            ? []
            : [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 46),
              foregroundColor: _C.muted,
              side: const BorderSide(color: _C.line),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Cancel',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 46),
              backgroundColor: _C.ink,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Save Changes',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// MAIN DOCULIST SCREEN
// ==========================================

class DocuListScreen extends StatefulWidget {
  const DocuListScreen({super.key});

  @override
  State<DocuListScreen> createState() => _DocuListScreenState();
}

class _DocuListScreenState extends State<DocuListScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _searchQuery = '';

  late final String _currentUserId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _docsStream;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Only download MY documents (not the whole collection). The OR covers the
    // different field names older documents used for the uploader.
    // No orderBy here, so no composite index is needed; sorting is done below.
    if (_currentUserId.isNotEmpty) {
      _docsStream = FirebaseFirestore.instance
          .collection('documents')
          .where(Filter.or(
        Filter('uploaderId', isEqualTo: _currentUserId),
        Filter('senderUserId', isEqualTo: _currentUserId),
        Filter('senderId', isEqualTo: _currentUserId),
      ))
          .snapshots();
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
        return _C.green;
      case 'in progress':
      case 'forwarded':
        return _C.blue;
      case 'pending':
        return const Color(0xFFB7791F);
      case 'rejected':
        return _C.red;
      default:
        return _C.muted;
    }
  }

  Color _getStatusTint(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
        return const Color(0xFFE6F5EE);
      case 'in progress':
      case 'forwarded':
        return const Color(0xFFE8F0FE);
      case 'pending':
        return const Color(0xFFFCF3DC);
      case 'rejected':
        return const Color(0xFFFBEAEA);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  // --- ARCHIVE CONFIRMATION DIALOG ---
  void _showArchiveDialog(TrackedDocument doc) {
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
            Icons.archive_outlined,
            _C.amber,
            const Color(0xFFFCF3DC),
            'Archive Document',
          ),
          content: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _C.paper,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "Are you sure you want to archive '${doc.title.isNotEmpty ? doc.title : doc.filename}'? It will be removed from your active list.",
              style: const TextStyle(fontSize: 13, color: _C.text, height: 1.4),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 46),
                foregroundColor: _C.muted,
                side: const BorderSide(color: _C.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              onPressed: () async {
                // Grab the messenger first so no context is used after awaits
                final messenger = ScaffoldMessenger.of(context);
                final ref =
                FirebaseFirestore.instance.collection('documents').doc(doc.id);
                Navigator.pop(dialogContext);

                try {
                  await ref.update({
                    'isArchived': true,
                    'archivedAt': FieldValue.serverTimestamp(),
                  });

                  _snack(
                    messenger,
                    'Document archived successfully',
                    action: SnackBarAction(
                      label: 'Undo',
                      textColor: const Color(0xFF60A5FA),
                      onPressed: () async {
                        try {
                          await ref.update({
                            'isArchived': false,
                            'archivedAt': FieldValue.delete(),
                          });
                        } catch (e) {
                          _snack(messenger, 'Could not undo: $e', error: true);
                        }
                      },
                    ),
                  );
                } catch (e) {
                  _snack(messenger, 'Could not archive document: $e', error: true);
                }
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 46),
                backgroundColor: _C.ink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Archive', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }

  // --- EDIT DIALOG ---
  void _showEditDialog(TrackedDocument doc) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditDocDialog(doc: doc, messenger: messenger),
    );
  }

  // Small square icon button used in the card action row (UI only)
  Widget _iconAction({
    required IconData icon,
    required Color color,
    required Color tint,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tint,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: color, size: 20),
          ),
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
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: const Icon(Icons.menu_rounded, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My Sent Documents',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Manage uploaded files & routing status',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Search Bar
          TextField(
            onChanged: (value) =>
                setState(() => _searchQuery = value.trim().toLowerCase()),
            style: const TextStyle(fontSize: 14, color: _C.text),
            decoration: InputDecoration(
              hintText: 'Search title or filename...',
              hintStyle: const TextStyle(fontSize: 14, color: _C.faint),
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: _C.faint),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _centerMessage(IconData icon, String text, {Color? textColor}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F0FE),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _C.blue, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: textColor ?? _C.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(TrackedDocument doc) {
    final statusColor = _getStatusColor(doc.status);

    // EDIT RULE: Can only edit if status is strictly 'pending'
    final bool isEditable = doc.status.toLowerCase() == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _C.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.article_rounded, color: _C.blue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.title.isNotEmpty ? doc.title : doc.filename,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: _C.ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'File: ${doc.filename}',
                      style: const TextStyle(fontSize: 12, color: _C.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _getStatusTint(doc.status),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  doc.status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Holder strip
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _C.paper,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 18, color: _C.muted),
                const SizedBox(width: 8),
                Flexible(
                  child: FirebaseUserText(
                    userId: doc.holderUserId,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _C.text,
                    ),
                  ),
                ),
                Flexible(
                  child: FirebaseOfficeText(
                    officeId: doc.officeId,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _C.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Actions
          Row(
            children: [
              // CONDITIONAL EDIT / LOCK BUTTON
              if (isEditable)
                _iconAction(
                  icon: Icons.edit_outlined,
                  color: _C.blue,
                  tint: const Color(0xFFE8F0FE),
                  tooltip: 'Edit Document',
                  onTap: () => _showEditDialog(doc),
                )
              else
                _iconAction(
                  icon: Icons.lock_outline_rounded,
                  color: _C.faint,
                  tint: _C.paper,
                  tooltip: 'Locked: Document has been processed or forwarded',
                ),
              const SizedBox(width: 8),

              // ARCHIVE BUTTON
              _iconAction(
                icon: Icons.archive_outlined,
                color: _C.amber,
                tint: const Color(0xFFFCF3DC),
                tooltip: 'Archive Document',
                onTap: () => _showArchiveDialog(doc),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TrackScreen(initialDocId: doc.id),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    backgroundColor: _C.ink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.alt_route_rounded, size: 16),
                  label: const Text(
                    'Track',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    // Nobody logged in: show nothing instead of every user's documents
    if (_docsStream == null) {
      return _centerMessage(Icons.lock_outline_rounded, 'Please log in to see your documents.');
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _docsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error loading documents: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _C.red, fontSize: 12),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final userDocs = snapshot.data!.docs
            .map((d) => TrackedDocument.fromFirestore(d))
            .where((doc) {
          final titleMatch = doc.title.toLowerCase().contains(_searchQuery);
          final fileMatch = doc.filename.toLowerCase().contains(_searchQuery);
          return doc.uploaderId == _currentUserId &&
              !doc.isArchived &&
              (titleMatch || fileMatch);
        }).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first

        if (userDocs.isEmpty) {
          return _centerMessage(
              Icons.folder_open_rounded, 'No sent documents found.');
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          itemCount: userDocs.length,
          itemBuilder: (context, index) => _buildCard(userDocs[index]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _C.paper,
      drawer: const Sidebar(currentPage: 'docu_list.php'),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }
}