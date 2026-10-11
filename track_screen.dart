import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'sidebar.dart';

// --- DESIGN TOKENS (same palette as dashboard and inbox) ---
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

class UserDetails {
  final String name;
  final String office;

  UserDetails({required this.name, required this.office});
}

class TrackScreen extends StatefulWidget {
  final String? initialDocId;

  const TrackScreen({super.key, this.initialDocId});

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String? _selectedDocId;

  // Cache resolved user details (name + office) to prevent re-fetching Firestore docs
  final Map<String, Future<UserDetails>> _userCache = {};

  @override
  void initState() {
    super.initState();
    _selectedDocId = widget.initialDocId;
  }

  // Detect if attachment URL corresponds to an image file
  bool _isImageUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final path = url.toLowerCase();
    return path.contains('.jpg') ||
        path.contains('.jpeg') ||
        path.contains('.png') ||
        path.contains('.webp') ||
        path.contains('.gif') ||
        path.contains('image%2f');
  }

  Future<UserDetails> _getUserDetails(String? uid) {
    if (uid == null || uid.isEmpty) {
      return Future.value(UserDetails(name: 'N/A', office: ''));
    }

    return _userCache.putIfAbsent(uid, () async {
      try {
        final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final data = doc.data();
        final name = (data?['name'] as String?) ??
            (data?['userName'] as String?) ??
            uid;
        final office = (data?['officeName'] as String?) ??
            (data?['office'] as String?) ??
            '';
        return UserDetails(
          name: name.trim().isNotEmpty ? name : uid,
          office: office.trim(),
        );
      } catch (_) {
        return UserDetails(name: uid, office: '');
      }
    });
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    final dt = timestamp.toDate();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day.toString().padLeft(2, '0')}, ${dt.year} $hour:$minute $period';
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
        return _C.green;
      case 'rejected':
        return _C.red;
      case 'pending':
        return const Color(0xFFB7791F);
      default:
        return _C.blue;
    }
  }

  Color _getStatusTint(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
        return const Color(0xFFE6F5EE);
      case 'rejected':
        return const Color(0xFFFBEAEA);
      case 'pending':
        return const Color(0xFFFCF3DC);
      default:
        return const Color(0xFFE8F0FE);
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
        return Icons.check_rounded;
      case 'rejected':
        return Icons.close_rounded;
      case 'pending':
        return Icons.schedule_rounded;
      default:
        return Icons.alt_route_rounded;
    }
  }

  String _statusLabel(String? status) {
    final s = (status ?? 'pending');
    if (s.isEmpty) return 'Pending';
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  Widget _statusChip(String? status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _getStatusTint(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: _getStatusColor(status),
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Helper method to open document URL
  Future<void> _openFileUrl(BuildContext context, String? fileUrl) async {
    if (fileUrl == null || fileUrl.trim().isEmpty) {
      _snack(context, 'No file attachment URL available for this document.');
      return;
    }

    final Uri? uri = Uri.tryParse(fileUrl);
    if (uri != null) {
      try {
        final launched =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && context.mounted) {
          _snack(context, 'Could not open file URL.');
        }
      } catch (e) {
        if (context.mounted) {
          _snack(context, 'Error opening file: $e');
        }
      }
    }
  }

  Widget _infoBlock(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: _C.muted)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _C.paper,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(value,
              style: const TextStyle(fontSize: 13, color: _C.text, height: 1.4)),
        ),
      ],
    );
  }

  Widget _participantRow(
      {required String label,
        required UserDetails user,
        required Color color,
        required Color tint}) {
    final initial = user.name.trim().isNotEmpty
        ? user.name.trim()[0].toUpperCase()
        : '?';

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Center(
            child: Text(initial,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 11, color: _C.faint)),
              Text(
                user.name,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: _C.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (user.office.isNotEmpty)
                Text(
                  user.office,
                  style: const TextStyle(fontSize: 11, color: _C.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  // Quick View Modal
  void _showQuickViewModal(BuildContext context, Map<String, dynamic> docData) {
    final title = docData['title'] ??
        docData['document_title'] ??
        docData['fileName'] ??
        docData['filename'] ??
        'Untitled Document';
    final description = (docData['description']?.toString().isNotEmpty == true)
        ? docData['description'].toString()
        : 'No description provided.';
    final remarks = (docData['remarks']?.toString().isNotEmpty == true)
        ? docData['remarks'].toString()
        : 'No active remarks.';
    final fileName =
        docData['fileName'] ?? docData['filename'] ?? 'Attachment link';
    final fileUrl = (docData['fileUrl'] ??
        docData['downloadUrl'] ??
        docData['url'] ??
        docData['file_url']) as String?;
    final status = (docData['status'] as String?) ?? 'pending';
    final dueDate = (docData['dueDate'] ?? docData['due_date'])?.toString();
    final uploaderId = (docData['uploaderId'] ??
        docData['uploader_id'] ??
        docData['senderId']) as String?;
    final recipientId =
    (docData['recipientId'] ?? docData['receiver_user_id']) as String?;
    final createdAt =
    (docData['createdAt'] ?? docData['updatedAt']) as Timestamp?;
    final hasFile = fileUrl != null && fileUrl.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _C.line,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
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
                                child: const Icon(Icons.description_outlined,
                                    color: _C.blue, size: 24),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title.toString(),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: _C.ink,
                                        letterSpacing: -0.3,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    _statusChip(status),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Attachment card
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _openFileUrl(ctx, fileUrl),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: hasFile
                                      ? const Color(0xFFF1F6FE)
                                      : _C.paper,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: hasFile
                                        ? const Color(0xFFCFE0FB)
                                        : _C.line,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          _isImageUrl(fileUrl)
                                              ? Icons.image_outlined
                                              : Icons.attach_file_rounded,
                                          color: hasFile ? _C.blue : _C.muted,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                fileName.toString(),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: hasFile
                                                      ? _C.ink
                                                      : _C.text,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                hasFile
                                                    ? (_isImageUrl(fileUrl)
                                                    ? 'Tap to open the full image'
                                                    : 'Tap to open the file')
                                                    : 'No file attached',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: hasFile
                                                      ? _C.blue
                                                      : _C.faint,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (hasFile)
                                          const Icon(Icons.open_in_new_rounded,
                                              color: _C.blue, size: 18),
                                      ],
                                    ),

                                    // Inline image preview
                                    if (_isImageUrl(fileUrl)) ...[
                                      const SizedBox(height: 12),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          fileUrl!,
                                          height: 190,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          loadingBuilder:
                                              (context, child, progress) {
                                            if (progress == null) return child;
                                            return const SizedBox(
                                              height: 100,
                                              child: Center(
                                                child: CircularProgressIndicator(
                                                    strokeWidth: 2),
                                              ),
                                            );
                                          },
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            return Container(
                                              height: 64,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                BorderRadius.circular(12),
                                              ),
                                              alignment: Alignment.center,
                                              child: const Text(
                                                'Unable to load image preview',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: _C.muted),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          _infoBlock('Description', description),
                          const SizedBox(height: 16),
                          _infoBlock('Current remarks', remarks),
                          const SizedBox(height: 20),

                          // Participants
                          FutureBuilder<List<UserDetails>>(
                            future: Future.wait([
                              _getUserDetails(uploaderId),
                              _getUserDetails(recipientId),
                            ]),
                            builder: (context, snapshot) {
                              final uploader = snapshot.data?[0] ??
                                  UserDetails(
                                      name: uploaderId ?? 'System', office: '');
                              final recipient = snapshot.data?[1] ??
                                  UserDetails(
                                      name: recipientId ?? 'N/A',
                                      office: docData['destinationOffice'] ?? '');

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _C.line),
                                ),
                                child: Column(
                                  children: [
                                    _participantRow(
                                      label: 'Uploaded by',
                                      user: uploader,
                                      color: _C.blue,
                                      tint: const Color(0xFFE8F0FE),
                                    ),
                                    const Padding(
                                      padding:
                                      EdgeInsets.symmetric(vertical: 10),
                                      child: Divider(height: 1, color: _C.line),
                                    ),
                                    _participantRow(
                                      label: 'Assigned to',
                                      user: recipient,
                                      color: _C.green,
                                      tint: const Color(0xFFE6F5EE),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),

                          // Dates
                          Row(
                            children: [
                              const Icon(Icons.event_note_outlined,
                                  size: 16, color: _C.muted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Created ${_formatTimestamp(createdAt)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: _C.muted),
                                ),
                              ),
                              if (dueDate != null && dueDate.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFBEAEA),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Due $dueDate',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _C.red,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),

                  // Pinned action buttons
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12, top: 4),
                      child: Row(
                        children: [
                          if (hasFile) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 50),
                                  foregroundColor: _C.blue,
                                  side: const BorderSide(color: _C.blue),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                ),
                                onPressed: () => _openFileUrl(ctx, fileUrl),
                                icon: const Icon(Icons.open_in_new_rounded,
                                    size: 18),
                                label: Text(
                                  _isImageUrl(fileUrl)
                                      ? 'View image'
                                      : 'Open file',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 50),
                                backgroundColor: _C.ink,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close',
                                  style:
                                  TextStyle(fontWeight: FontWeight.w700)),
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
    );
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to track documents.')),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _C.paper,
      drawer: const Sidebar(currentPage: 'track.php'),
      body: Column(
        children: [
          _buildHeader(currentUserId),

          // Timeline area
          Expanded(
            child: _selectedDocId == null
                ? _buildPickPrompt()
                : _buildTimelineArea(),
          ),
        ],
      ),
    );
  }

  // ---------- HEADER + DOCUMENT PICKER ----------

  Widget _buildHeader(String currentUserId) {
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
                    const Text(
                      'Track status',
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
                      'See where a document has been and where it is now',
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
          const SizedBox(height: 18),

          // Document selection dropdown
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('documents')
                .where(
              Filter.or(
                Filter('senderId', isEqualTo: currentUserId),
                Filter('sender_id', isEqualTo: currentUserId),
                Filter('recipientId', isEqualTo: currentUserId),
                Filter('receiver_user_id', isEqualTo: currentUserId),
                Filter('uploaderId', isEqualTo: currentUserId),
                Filter('uploader_id', isEqualTo: currentUserId),
              ),
            )
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    color: Colors.white,
                  ),
                );
              }

              if (snapshot.hasError) {
                return Text(
                  'Could not load documents: ${snapshot.error}',
                  style: const TextStyle(color: Color(0xFFFFB4B4), fontSize: 12),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border:
                    Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: Text(
                    'No documents to track yet.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13),
                  ),
                );
              }

              final docIds = docs.map((d) => d.id).toList();
              if (_selectedDocId != null && !docIds.contains(_selectedDocId)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _selectedDocId = null;
                    });
                  }
                });
              }

              return DropdownButtonFormField<String>(
                value: docIds.contains(_selectedDocId) ? _selectedDocId : null,
                hint: const Text('Choose a document'),
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: _C.muted),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 20, color: _C.faint),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  fillColor: Colors.white,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final title = data['title'] ??
                      data['document_title'] ??
                      data['fileName'] ??
                      data['filename'] ??
                      doc.id;
                  return DropdownMenuItem<String>(
                    value: doc.id,
                    child: Text(title.toString(), overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedDocId = val;
                  });
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPickPrompt() {
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
              child: const Icon(Icons.alt_route_rounded,
                  color: _C.blue, size: 34),
            ),
            const SizedBox(height: 18),
            const Text(
              'Pick a document to follow',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _C.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose one above to see every step it has gone through.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _C.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- TIMELINE ----------

  Widget _buildTimelineArea() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('documents')
          .doc(_selectedDocId)
          .snapshots(),
      builder: (context, docSnapshot) {
        if (docSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!docSnapshot.hasData || !docSnapshot.data!.exists) {
          return const Center(
            child: Text('The selected document no longer exists.',
                style: TextStyle(color: _C.muted)),
          );
        }

        final docData = docSnapshot.data!.data() as Map<String, dynamic>;
        final docTitle =
        (docData['title'] ?? docData['fileName'] ?? 'Document details')
            .toString();
        final currentStatus = (docData['status'] as String?) ?? 'pending';

        return Column(
          children: [
            // Summary bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _C.line),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _getStatusTint(currentStatus),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_getStatusIcon(currentStatus),
                          color: _getStatusColor(currentStatus), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            docTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: _C.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _statusChip(currentStatus),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFE8F0FE),
                        foregroundColor: _C.blue,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _showQuickViewModal(context, docData),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('Details',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Timeline stream
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('documents')
                    .doc(_selectedDocId)
                    .collection('history')
                    .snapshots(),
                builder: (context, historySnapshot) {
                  final List<Map<String, dynamic>> rawLogs = [];

                  // 1. Gather historical logs
                  if (historySnapshot.hasData &&
                      historySnapshot.data!.docs.isNotEmpty) {
                    for (var logDoc in historySnapshot.data!.docs) {
                      rawLogs.add(Map<String, dynamic>.from(
                          logDoc.data() as Map<String, dynamic>));
                    }
                  }

                  // 2. Current top-level document snapshot
                  final docStatus = (docData['status'] as String?) ?? 'pending';
                  final docUpdatedAt = (docData['updatedAt'] as Timestamp?) ??
                      (docData['createdAt'] as Timestamp?);
                  final docSender = (docData['uploaderId'] ??
                      docData['uploader_id'] ??
                      docData['senderId'] ??
                      docData['sender_id']) as String?;
                  final docReceiver = (docData['recipientId'] ??
                      docData['receiver_user_id']) as String?;
                  final docOffice = (docData['destinationOffice'] ??
                      docData['senderOffice'] ??
                      '') as String?;
                  final docRemarks =
                  (docData['remarks'] as String?)?.trim().isNotEmpty == true
                      ? docData['remarks'] as String
                      : 'Document status: ${docStatus.toUpperCase()}';

                  final topLog = {
                    'status': docStatus,
                    'movedAt': docUpdatedAt,
                    'senderId': docSender,
                    'receiverId': docReceiver,
                    'destinationOffice': docOffice,
                    'remarks': docRemarks,
                  };

                  if (rawLogs.isEmpty) {
                    rawLogs.add(topLog);
                  } else {
                    final lastReceiver =
                        rawLogs.last['receiverId'] ?? rawLogs.last['recipientId'];
                    final lastStatus = rawLogs.last['status'];

                    if (lastStatus != docStatus || lastReceiver != docReceiver) {
                      rawLogs.add(topLog);
                    }
                  }

                  // 3. Sort chronologically ASCENDING (Oldest -> Newest)
                  rawLogs.sort((a, b) {
                    final aTime = (a['movedAt'] ?? a['createdAt']) as Timestamp?;
                    final bTime = (b['movedAt'] ?? b['createdAt']) as Timestamp?;
                    if (aTime == null || bTime == null) return 0;
                    return aTime.compareTo(bTime);
                  });

                  // 4. Sequential Chaining: User1 -> User2 -> User3
                  String? previousRecipientId;

                  for (int i = 0; i < rawLogs.length; i++) {
                    final log = rawLogs[i];
                    final currentReceiver = (log['receiverId'] ??
                        log['recipientId'] ??
                        log['receiver_user_id']) as String?;

                    String? currentSender = (log['senderId'] ??
                        log['uploaderId'] ??
                        log['uploader_id'] ??
                        log['sender_id']) as String?;

                    if (i > 0 &&
                        previousRecipientId != null &&
                        previousRecipientId.isNotEmpty) {
                      currentSender = previousRecipientId;
                    }

                    log['chainedSenderId'] = currentSender;
                    log['chainedReceiverId'] = currentReceiver ?? currentSender;

                    if (currentReceiver != null && currentReceiver.isNotEmpty) {
                      previousRecipientId = currentReceiver;
                    }
                  }

                  // 5. Reverse list so latest activity is at top
                  final displayLogs = rawLogs.reversed.toList();

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    itemCount: displayLogs.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14, left: 2),
                          child: Text(
                            displayLogs.length == 1
                                ? '1 step so far'
                                : '${displayLogs.length} steps so far, newest first',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _C.muted,
                            ),
                          ),
                        );
                      }

                      final i = index - 1;
                      return _buildTimelineItem(
                        log: displayLogs[i],
                        isFirst: i == 0,
                        isLast: i == displayLogs.length - 1,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimelineItem({
    required Map<String, dynamic> log,
    required bool isFirst,
    required bool isLast,
  }) {
    final status = (log['status'] as String?) ?? 'pending';
    final remarks = (log['remarks'] as String?)?.trim().isNotEmpty == true
        ? log['remarks'] as String
        : 'No remarks recorded.';
    final movedAt = log['movedAt'] as Timestamp?;

    final senderId = log['chainedSenderId'] as String?;
    final receiverId = log['chainedReceiverId'] as String?;
    final fallbackOffice =
        (log['destinationOffice'] as String?) ?? (log['office'] as String?) ?? '';

    final statusColor = _getStatusColor(status);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline rail
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isFirst ? statusColor : _getStatusTint(status),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isFirst ? Colors.white : statusColor.withValues(alpha: 0.4),
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
                  child: Icon(
                    _getStatusIcon(status),
                    size: 16,
                    color: isFirst ? Colors.white : statusColor,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: _C.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isFirst ? const Color(0xFFBFD3F7) : _C.line,
                  width: isFirst ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _statusChip(status),
                      Flexible(
                        child: Text(
                          _formatTimestamp(movedAt),
                          style: const TextStyle(
                              fontSize: 11,
                              color: _C.muted,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // From / To
                  FutureBuilder<List<UserDetails>>(
                    future: Future.wait([
                      _getUserDetails(senderId),
                      _getUserDetails(receiverId),
                    ]),
                    builder: (context, userSnapshot) {
                      final sender = userSnapshot.data?[0] ??
                          UserDetails(name: senderId ?? 'System', office: '');
                      final receiver = userSnapshot.data?[1] ??
                          UserDetails(
                              name: receiverId ?? 'N/A', office: fallbackOffice);

                      final receiverWithOffice = receiver.office.isNotEmpty
                          ? receiver
                          : UserDetails(
                          name: receiver.name, office: fallbackOffice);

                      return Column(
                        children: [
                          _participantRow(
                            label: 'From',
                            user: sender,
                            color: _C.blue,
                            tint: const Color(0xFFE8F0FE),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 2,
                                height: 14,
                                color: _C.line,
                              ),
                            ),
                          ),
                          _participantRow(
                            label: 'To',
                            user: receiverWithOffice,
                            color: _C.green,
                            tint: const Color(0xFFE6F5EE),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),

                  // Remarks
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _C.paper,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.format_quote_rounded,
                            size: 18, color: _C.faint),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            remarks,
                            style: const TextStyle(
                                fontSize: 12.5, color: _C.text, height: 1.4),
                          ),
                        ),
                      ],
                    ),
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