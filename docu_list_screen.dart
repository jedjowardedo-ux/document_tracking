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
// DATA MODEL
// ==========================================

class TrackedDocument {
  final String id;
  final String title;
  final String filename;
  final String fileUrl;
  final String uploaderId;   // ID of user who uploaded/created the doc
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

  factory TrackedDocument.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return TrackedDocument(
      id: doc.id,
      title: data['title'] ?? '',
      filename: data['filename'] ?? '',
      fileUrl: data['fileUrl'] ?? '',
      uploaderId: data['uploaderId'] ?? data['senderUserId'] ?? data['senderId'] ?? '',
      holderUserId: data['holderUserId'] ?? data['receiverId'] ?? '',
      officeId: data['officeId'] ?? data['receiverOfficeId'] ?? '',
      status: data['status'] ?? 'pending',
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isArchived: data['isArchived'] ?? false,
    );
  }
}

// ==========================================
// DYNAMIC FIREBASE RESOLVER WIDGETS
// ==========================================

class FirebaseUserText extends StatelessWidget {
  final String userId;
  final TextStyle style;

  const FirebaseUserText({super.key, required this.userId, required this.style});

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) {
      return Text("Unknown User", style: style);
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Text("...", style: style.copyWith(color: Colors.grey));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Text(userId, style: style);
        }
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final name = data?['name'] ?? data?['fullName'] ?? userId;
        return Text(name, style: style);
      },
    );
  }
}

class FirebaseOfficeText extends StatelessWidget {
  final String officeId;
  final TextStyle style;

  const FirebaseOfficeText({super.key, required this.officeId, required this.style});

  @override
  Widget build(BuildContext context) {
    if (officeId.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('offices').doc(officeId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Text("...", style: style.copyWith(color: Colors.grey));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Text(" ($officeId)", style: style);
        }
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final officeName = data?['name'] ?? data?['officeName'] ?? data?['code'] ?? officeId;
        return Text(" ($officeName)", style: style);
      },
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
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

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

  // Shared dialog styling helpers (UI only)
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
            "Archive Document",
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
              child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);

                await FirebaseFirestore.instance
                    .collection('documents')
                    .doc(doc.id)
                    .update({
                  'isArchived': true,
                  'archivedAt': FieldValue.serverTimestamp(),
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text("Document archived successfully"),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      action: SnackBarAction(
                        label: "Undo",
                        textColor: const Color(0xFF60A5FA),
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('documents')
                              .doc(doc.id)
                              .update({'isArchived': false});
                        },
                      ),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 46),
                backgroundColor: _C.ink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text("Archive", style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }

  // --- EDIT DIALOG WITH FILE REPLACEMENT & DATA MODIFICATION ---
  void _showEditDialog(TrackedDocument doc) {
    final titleController = TextEditingController(text: doc.title);
    final filenameController = TextEditingController(text: doc.filename);
    PlatformFile? selectedFile;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              title: _dialogTitle(
                Icons.edit_outlined,
                _C.blue,
                const Color(0xFFE8F0FE),
                "Edit Pending Document",
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      enabled: !isSaving,
                      decoration: _fieldDecoration("Document Title"),
                    ),
                    const SizedBox(height: 16),

                    // FILE REPLACEMENT SELECTOR
                    const Text(
                      "Attached Document File",
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: _C.muted),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selectedFile != null
                            ? const Color(0xFFE6F5EE)
                            : const Color(0xFFF1F6FE),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selectedFile != null
                              ? const Color(0xFFBFE6D2)
                              : const Color(0xFFCFE0FB),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.insert_drive_file_outlined,
                            color: selectedFile != null ? _C.green : _C.blue,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedFile != null
                                      ? selectedFile!.name
                                      : (doc.filename.isNotEmpty ? doc.filename : "No file attached"),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 13, color: _C.ink),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  selectedFile != null
                                      ? "New file selected"
                                      : "Current uploaded file",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: selectedFile != null ? _C.green : _C.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: isSaving
                                ? null
                                : () async {
                              // file_picker v12: pickFiles() returns List<PlatformFile>
                              // directly (no more FilePickerResult / FilePicker.platform).
                              final List<PlatformFile> files = await FilePicker.pickFiles();
                              if (files.isNotEmpty) {
                                setDialogState(() {
                                  selectedFile = files.first;
                                  filenameController.text = files.first.name;
                                });
                              }
                            },
                            icon: const Icon(Icons.upload_file, size: 16),
                            label: Text(
                              selectedFile == null ? "Replace" : "Change",
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: _C.blue,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: filenameController,
                      enabled: !isSaving,
                      decoration: _fieldDecoration("Display File Name"),
                    ),

                    if (isSaving) ...[
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
                            const Text("Uploading file & saving changes...",
                                style: TextStyle(fontSize: 12, color: _C.muted)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              actions: isSaving
                  ? []
                  : [
                OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    foregroundColor: _C.muted,
                    side: const BorderSide(color: _C.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    setDialogState(() => isSaving = true);

                    try {
                      String newFileUrl = doc.fileUrl;

                      // 1. Upload new file if replaced — via Cloudinary instead
                      // of Firebase Storage.
                      if (selectedFile != null) {
                        final bytes = await selectedFile!.readAsBytes();

                        final cloudinaryResponse = await _cloudinary.uploadFile(
                          CloudinaryFile.fromBytesData(
                            bytes,
                            identifier: selectedFile!.name,
                            resourceType: CloudinaryResourceType.Raw,
                          ),
                        );
                        newFileUrl = cloudinaryResponse.secureUrl;
                      }

                      // 2. Update Firestore Document Data
                      await FirebaseFirestore.instance
                          .collection('documents')
                          .doc(doc.id)
                          .update({
                        'title': titleController.text.trim(),
                        'filename': filenameController.text.trim(),
                        'fileUrl': newFileUrl,
                        'updatedAt': FieldValue.serverTimestamp(),
                      });

                      if (mounted) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text("Document updated successfully!"),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      }
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Failed to update document: $e"),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    backgroundColor: _C.ink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text("Save Changes", style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            );
          },
        );
      },
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
                      "My Sent Documents",
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
                      "Manage uploaded files & routing status",
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
            onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
            style: const TextStyle(fontSize: 14, color: _C.text),
            decoration: InputDecoration(
              hintText: "Search title or filename...",
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _C.paper,
      drawer: const Sidebar(currentPage: 'docu_list.php'),
      body: Column(
        children: [
          _buildHeader(),

          // Firestore Documents List Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('documents')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text("Error loading documents",
                        style: TextStyle(color: _C.muted)),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allDocs = snapshot.data!.docs
                    .map((d) => TrackedDocument.fromFirestore(d))
                    .toList();

                // Filter non-archived documents uploaded by user and matching search query
                final userDocs = allDocs.where((doc) {
                  final isMyDoc = currentUserId.isEmpty || doc.uploaderId == currentUserId;
                  final titleMatch = doc.title.toLowerCase().contains(_searchQuery);
                  final fileMatch = doc.filename.toLowerCase().contains(_searchQuery);
                  return isMyDoc && !doc.isArchived && (titleMatch || fileMatch);
                }).toList();

                if (userDocs.isEmpty) {
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
                            child: const Icon(Icons.folder_open_rounded,
                                color: _C.blue, size: 34),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            "No sent documents found.",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: _C.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  itemCount: userDocs.length,
                  itemBuilder: (context, index) {
                    final doc = userDocs[index];
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
                                child: const Icon(Icons.article_rounded,
                                    color: _C.blue, size: 22),
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
                                      "File: ${doc.filename}",
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
                                const Icon(Icons.person_outline_rounded,
                                    size: 18, color: _C.muted),
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
                                  tooltip: "Edit Document",
                                  onTap: () => _showEditDialog(doc),
                                )
                              else
                                _iconAction(
                                  icon: Icons.lock_outline_rounded,
                                  color: _C.faint,
                                  tint: _C.paper,
                                  tooltip: "Locked: Document has been processed or forwarded",
                                ),
                              const SizedBox(width: 8),

                              // ARCHIVE BUTTON
                              _iconAction(
                                icon: Icons.archive_outlined,
                                color: _C.amber,
                                tint: const Color(0xFFFCF3DC),
                                tooltip: "Archive Document",
                                onTap: () => _showArchiveDialog(doc),
                              ),
                              const SizedBox(width: 12),

                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const TrackScreen(),
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
                                    "Track",
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}