import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'sidebar.dart';
import 'track_screen.dart';

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
  String _searchQuery = '';
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
        return const Color(0xFF10B981);
      case 'in progress':
      case 'forwarded':
        return const Color(0xFF3B82F6);
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'rejected':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
    }
  }

  // --- ARCHIVE CONFIRMATION DIALOG ---
  void _showArchiveDialog(TrackedDocument doc) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            "Archive Document",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Text(
            "Are you sure you want to archive '${doc.title.isNotEmpty ? doc.title : doc.filename}'? It will be removed from your active list.",
            style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel", style: TextStyle(color: Color(0xFF64748B))),
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
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("Archive"),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                "Edit Pending Document",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      enabled: !isSaving,
                      decoration: InputDecoration(
                        labelText: "Document Title",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // FILE REPLACEMENT SELECTOR
                    const Text(
                      "Attached Document File",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file_outlined, color: Color(0xFF2563EB)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedFile != null
                                      ? selectedFile!.name
                                      : (doc.filename.isNotEmpty ? doc.filename : "No file attached"),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  selectedFile != null
                                      ? "New file selected"
                                      : "Current uploaded file",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: selectedFile != null ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
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
                            label: Text(selectedFile == null ? "Replace" : "Change"),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    TextField(
                      controller: filenameController,
                      enabled: !isSaving,
                      decoration: InputDecoration(
                        labelText: "Display File Name",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),

                    if (isSaving) ...[
                      const SizedBox(height: 18),
                      const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text("Uploading file & saving changes...", style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: isSaving
                  ? []
                  : [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel", style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: () async {
                    setDialogState(() => isSaving = true);

                    try {
                      String newFileUrl = doc.fileUrl;

                      // 1. Upload new file if replaced
                      if (selectedFile != null) {
                        final storageRef = FirebaseStorage.instance
                            .ref()
                            .child('documents/${doc.id}/${selectedFile!.name}');

                        // file_picker v12: no more `.bytes` field populated via
                        // withData: true. Read bytes on demand instead — this
                        // works on web (where .path is null) and everywhere else.
                        final bytes = await selectedFile!.readAsBytes();
                        await storageRef.putData(bytes);

                        newFileUrl = await storageRef.getDownloadURL();
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
                          const SnackBar(content: Text("Document updated successfully!")),
                        );
                      }
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Failed to update document: $e")),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Save Changes"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const Sidebar(currentPage: 'docu_list.php'),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFF8FAFC),
            child: Row(
              children: [
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu, color: Color(0xFF1E293B), size: 24),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "My Sent Documents",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Manage uploaded files & routing status",
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0xFFCBD5E1),
                  child: Icon(Icons.person, color: Colors.white, size: 24),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Search title or filename...",
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                ),
              ),
            ),
          ),

          // Firestore Documents List Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('documents')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text("Error loading documents"));
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.folder_open, size: 48, color: Color(0xFF94A3B8)),
                        SizedBox(height: 12),
                        Text(
                          "No sent documents found.",
                          style: TextStyle(fontSize: 14, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: userDocs.length,
                  itemBuilder: (context, index) {
                    final doc = userDocs[index];
                    final statusColor = _getStatusColor(doc.status);

                    // EDIT RULE: Can only edit if status is strictly 'pending'
                    final bool isEditable = doc.status.toLowerCase() == 'pending';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Color(0xFFEFF6FF),
                                  child: Icon(Icons.article_rounded, color: Color(0xFF2563EB), size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        doc.title.isNotEmpty ? doc.title : doc.filename,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "File: ${doc.filename}",
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: statusColor.withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    doc.status.toUpperCase(),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12.0),
                              child: Divider(color: Color(0xFFF1F5F9), height: 1),
                            ),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      const Icon(Icons.person_outline, size: 16, color: Color(0xFF64748B)),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: FirebaseUserText(
                                          userId: doc.holderUserId,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1E293B),
                                          ),
                                        ),
                                      ),
                                      FirebaseOfficeText(
                                        officeId: doc.officeId,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF1D4ED8),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                Row(
                                  children: [
                                    // CONDITIONAL EDIT / LOCK BUTTON
                                    if (isEditable)
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, color: Color(0xFF2563EB), size: 20),
                                        tooltip: "Edit Document",
                                        onPressed: () => _showEditDialog(doc),
                                      )
                                    else
                                      const Tooltip(
                                        message: "Locked: Document has been processed or forwarded",
                                        child: Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: Icon(Icons.lock_outline, color: Color(0xFF94A3B8), size: 20),
                                        ),
                                      ),

                                    // ARCHIVE BUTTON
                                    IconButton(
                                      icon: const Icon(Icons.archive_outlined, color: Color(0xFFD97706), size: 20),
                                      tooltip: "Archive Document",
                                      onPressed: () => _showArchiveDialog(doc),
                                    ),

                                    const SizedBox(width: 2),

                                    TextButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => const TrackScreen(),
                                          ),
                                        );
                                      },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        backgroundColor: const Color(0xFFF1F5F9),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      icon: const Icon(Icons.alt_route_rounded, size: 16, color: Color(0xFF1E40AF)),
                                      label: const Text(
                                        "Track",
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
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