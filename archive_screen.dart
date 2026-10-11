import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sidebar.dart';
import 'docu_list_screen.dart'; // Imports TrackedDocument, FirebaseUserText, FirebaseOfficeText

// --- DESIGN TOKENS (same palette as dashboard, inbox, track and docu list) ---
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

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
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

  // --- RESTORE DOCUMENT DIALOG ---
  void _showRestoreDialog(TrackedDocument doc) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.undo_rounded, color: _C.blue, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Restore Document?",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: _C.ink,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          content: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _C.paper,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "This will move '${doc.title.isNotEmpty ? doc.title : doc.filename}' back to your active tracking list.",
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
                  'isArchived': false,
                  'restoredAt': FieldValue.serverTimestamp(),
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text("Document restored back to Tracking list"),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              child: const Text("Yes, Restore", style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
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
                      "Document Archive",
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
                      "View documents you have moved to storage",
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
              hintText: "Search by title, filename, or ID...",
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
      drawer: const Sidebar(currentPage: 'archive.php'),
      body: Column(
        children: [
          _buildHeader(),

          // StreamBuilder for Archived Documents
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('documents')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text("Error loading archive",
                        style: TextStyle(color: _C.muted)),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allDocs = snapshot.data!.docs
                    .map((d) => TrackedDocument.fromFirestore(d))
                    .toList();

                // Filter explicitly archived documents for current user
                final archivedDocs = allDocs.where((doc) {
                  final isMyDoc = currentUserId.isEmpty || doc.uploaderId == currentUserId;
                  final isArchived = doc.isArchived == true;
                  final titleMatch = doc.title.toLowerCase().contains(_searchQuery);
                  final fileMatch = doc.filename.toLowerCase().contains(_searchQuery);
                  final idMatch = doc.id.toLowerCase().contains(_searchQuery);

                  return isMyDoc && isArchived && (titleMatch || fileMatch || idMatch);
                }).toList();

                if (archivedDocs.isEmpty) {
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
                            child: const Icon(Icons.inventory_2_outlined,
                                color: _C.blue, size: 34),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            "Archive is empty.",
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
                  itemCount: archivedDocs.length,
                  itemBuilder: (context, index) {
                    final doc = archivedDocs[index];
                    final statusColor = _getStatusColor(doc.status);

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
                                  color: const Color(0xFFFCF3DC),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(Icons.archive_rounded,
                                    color: _C.amber, size: 22),
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
                                      "File: ${doc.filename} | ID: #${doc.id}",
                                      style: const TextStyle(fontSize: 11, color: _C.muted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
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
                                  const SizedBox(height: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _C.ink,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      "ARCHIVED",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ],
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

                          // RESTORE BUTTON
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _showRestoreDialog(doc),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 40),
                                foregroundColor: _C.blue,
                                side: const BorderSide(color: _C.blue),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.undo_rounded, size: 16),
                              label: const Text(
                                "Restore",
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
        ],
      ),
    );
  }
}