import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'sidebar.dart';

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
        return const Color(0xFF16A34A);
      case 'rejected':
        return const Color(0xFFDC2626);
      case 'pending':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF2563EB);
    }
  }

  // Helper method to open document URL
  Future<void> _openFileUrl(BuildContext context, String? fileUrl) async {
    if (fileUrl == null || fileUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No file attachment URL available for this document.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final Uri? uri = Uri.tryParse(fileUrl);
    if (uri != null) {
      try {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open file URL.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error opening file: $e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  // Quick View Modal
  void _showQuickViewModal(BuildContext context, Map<String, dynamic> docData) {
    final title = docData['title'] ??
        docData['document_title'] ??
        docData['fileName'] ??
        docData['filename'] ??
        'Untitled Document';
    final description = (docData['description']?.toString().isNotEmpty == true)
        ? docData['description']
        : 'No description provided.';
    final remarks = (docData['remarks']?.toString().isNotEmpty == true)
        ? docData['remarks']
        : 'No active remarks.';
    final fileName = docData['fileName'] ?? docData['filename'] ?? 'Attachment Link';
    final fileUrl = (docData['fileUrl'] ?? docData['downloadUrl'] ?? docData['url'] ?? docData['file_url']) as String?;
    final status = (docData['status'] as String?) ?? 'pending';
    final dueDate = (docData['dueDate'] ?? docData['due_date']) as String?;
    final uploaderId = (docData['uploaderId'] ?? docData['uploader_id'] ?? docData['senderId']) as String?;
    final recipientId = (docData['recipientId'] ?? docData['receiver_user_id']) as String?;
    final createdAt = (docData['createdAt'] ?? docData['updatedAt']) as Timestamp?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.description, color: Color(0xFF2563EB), size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.w900, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 16),

                // Clickable File Attachment & Image Preview Card
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _openFileUrl(ctx, fileUrl),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: fileUrl != null ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: fileUrl != null ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isImageUrl(fileUrl) ? Icons.image : Icons.attach_file,
                                color: fileUrl != null ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fileName,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: fileUrl != null ? const Color(0xFF1E40AF) : const Color(0xFF334155),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      fileUrl != null
                                          ? (_isImageUrl(fileUrl)
                                          ? 'Tap to open full image'
                                          : 'Tap to view/open file')
                                          : 'No file attached',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: fileUrl != null ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (fileUrl != null)
                                const Icon(
                                  Icons.open_in_new,
                                  color: Color(0xFF2563EB),
                                  size: 18,
                                ),
                            ],
                          ),

                          // Inline Image Preview Component
                          if (_isImageUrl(fileUrl)) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                fileUrl!,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return const SizedBox(
                                    height: 100,
                                    child: Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    height: 60,
                                    color: const Color(0xFFF1F5F9),
                                    alignment: Alignment.center,
                                    child: const Text(
                                      'Unable to load image preview',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
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
                const SizedBox(height: 16),

                // Description
                const Text('DESCRIPTION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B))),
                const SizedBox(height: 16),

                // Current Remarks
                const Text('CURRENT REMARKS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(remarks, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
                ),
                const SizedBox(height: 16),

                // Participant Details
                FutureBuilder<List<UserDetails>>(
                  future: Future.wait([
                    _getUserDetails(uploaderId),
                    _getUserDetails(recipientId),
                  ]),
                  builder: (context, snapshot) {
                    final uploader = snapshot.data?[0] ?? UserDetails(name: uploaderId ?? 'System', office: '');
                    final recipient = snapshot.data?[1] ?? UserDetails(name: recipientId ?? 'N/A', office: docData['destinationOffice'] ?? '');

                    return Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 16, color: Color(0xFF2563EB)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Uploaded By: ${uploader.name} ${uploader.office.isNotEmpty ? "(${uploader.office})" : ""}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.assignment_ind_outlined, size: 16, color: Color(0xFF16A34A)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Assigned To: ${recipient.name} ${recipient.office.isNotEmpty ? "(${recipient.office})" : ""}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Dates Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Created: ${_formatTimestamp(createdAt)}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    if (dueDate != null && dueDate.isNotEmpty)
                      Text('Due Date: $dueDate', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                  ],
                ),
                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  children: [
                    if (fileUrl != null && fileUrl.isNotEmpty) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            side: const BorderSide(color: Color(0xFF2563EB)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _openFileUrl(ctx, fileUrl),
                          icon: const Icon(Icons.open_in_new, size: 18, color: Color(0xFF2563EB)),
                          label: Text(
                            _isImageUrl(fileUrl) ? 'View Image' : 'Open File',
                            style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          backgroundColor: const Color(0xFF0F172A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const Sidebar(currentPage: 'track.php'),
      body: SafeArea(
        child: Column(
          children: [
            // Header Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu, size: 26, color: Color(0xFF0F172A)),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Track Document Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                        Text('Real-time audit & routing timeline', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Document Selection Dropdown
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: StreamBuilder<QuerySnapshot>(
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
                    return const LinearProgressIndicator();
                  }

                  if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red));
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10)),
                      child: const Text('No active documents available to track.', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
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
                    hint: const Text('Select a Document to View Audit Trail...'),
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      fillColor: Colors.white,
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    ),
                    items: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final title = data['title'] ?? data['document_title'] ?? data['fileName'] ?? data['filename'] ?? doc.id;
                      return DropdownMenuItem<String>(
                        value: doc.id,
                        child: Text(title, overflow: TextOverflow.ellipsis),
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
            ),

            // Live Timeline Stream
            Expanded(
              child: _selectedDocId == null
                  ? const Center(
                child: Text(
                  'Select a document above to view history timeline.',
                  style: TextStyle(color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                ),
              )
                  : StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('documents').doc(_selectedDocId).snapshots(),
                builder: (context, docSnapshot) {
                  if (docSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!docSnapshot.hasData || !docSnapshot.data!.exists) {
                    return const Center(
                      child: Text('Selected document no longer exists.', style: TextStyle(color: Color(0xFF64748B))),
                    );
                  }

                  final docData = docSnapshot.data!.data() as Map<String, dynamic>;
                  final docTitle = docData['title'] ?? docData['fileName'] ?? 'Document Details';

                  return Column(
                    children: [
                      // Quick View Summary Action Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  docTitle,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  side: const BorderSide(color: Color(0xFF2563EB)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _showQuickViewModal(context, docData),
                                icon: const Icon(Icons.visibility_outlined, size: 16, color: Color(0xFF2563EB)),
                                label: const Text('Quick View', style: TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Timeline Stream
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('documents').doc(_selectedDocId).collection('history').snapshots(),
                          builder: (context, historySnapshot) {
                            final List<Map<String, dynamic>> rawLogs = [];

                            // 1. Gather historical logs
                            if (historySnapshot.hasData && historySnapshot.data!.docs.isNotEmpty) {
                              for (var logDoc in historySnapshot.data!.docs) {
                                rawLogs.add(Map<String, dynamic>.from(logDoc.data() as Map<String, dynamic>));
                              }
                            }

                            // 2. Current top-level document snapshot
                            final docStatus = (docData['status'] as String?) ?? 'pending';
                            final docUpdatedAt = (docData['updatedAt'] as Timestamp?) ?? (docData['createdAt'] as Timestamp?);
                            final docSender = (docData['uploaderId'] ?? docData['uploader_id'] ?? docData['senderId'] ?? docData['sender_id']) as String?;
                            final docReceiver = (docData['recipientId'] ?? docData['receiver_user_id']) as String?;
                            final docOffice = (docData['destinationOffice'] ?? docData['senderOffice'] ?? '') as String?;
                            final docRemarks = (docData['remarks'] as String?)?.trim().isNotEmpty == true ? docData['remarks'] as String : 'Document status: ${docStatus.toUpperCase()}';

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
                              final lastReceiver = rawLogs.last['receiverId'] ?? rawLogs.last['recipientId'];
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
                              final currentReceiver = (log['receiverId'] ?? log['recipientId'] ?? log['receiver_user_id']) as String?;

                              String? currentSender = (log['senderId'] ?? log['uploaderId'] ?? log['uploader_id'] ?? log['sender_id']) as String?;

                              if (i > 0 && previousRecipientId != null && previousRecipientId.isNotEmpty) {
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
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: displayLogs.length,
                              itemBuilder: (context, index) {
                                final log = displayLogs[index];
                                final status = (log['status'] as String?) ?? 'pending';
                                final remarks = (log['remarks'] as String?)?.trim().isNotEmpty == true ? log['remarks'] as String : 'No remarks recorded.';
                                final movedAt = log['movedAt'] as Timestamp?;

                                final senderId = log['chainedSenderId'] as String?;
                                final receiverId = log['chainedReceiverId'] as String?;
                                final fallbackOffice = (log['destinationOffice'] as String?) ?? (log['office'] as String?) ?? '';
                                final isFirst = index == 0;

                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Timeline Pillar
                                    Column(
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(status),
                                            shape: BoxShape.circle,
                                            boxShadow: isFirst ? [BoxShadow(color: _getStatusColor(status).withOpacity(0.4), blurRadius: 8, spreadRadius: 2)] : null,
                                          ),
                                          child: Icon(
                                            status == 'approved'
                                                ? Icons.check
                                                : status == 'rejected'
                                                ? Icons.close
                                                : Icons.alt_route,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                        if (index < displayLogs.length - 1)
                                          Container(
                                            width: 2,
                                            height: 110,
                                            color: const Color(0xFFCBD5E1),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 12),

                                    // Timeline Card Details
                                    Expanded(
                                      child: Container(
                                        margin: const EdgeInsets.only(bottom: 16),
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: isFirst ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0)),
                                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Status Header & Timestamp
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: _getStatusColor(status).withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    status.toUpperCase(),
                                                    style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.w900, fontSize: 10),
                                                  ),
                                                ),
                                                Text(
                                                  _formatTimestamp(movedAt),
                                                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),

                                            // Chained Sender (From) & Receiver (To)
                                            FutureBuilder<List<UserDetails>>(
                                              future: Future.wait([
                                                _getUserDetails(senderId),
                                                _getUserDetails(receiverId),
                                              ]),
                                              builder: (context, userSnapshot) {
                                                final sender = userSnapshot.data?[0] ?? UserDetails(name: senderId ?? 'System', office: '');
                                                final receiver = userSnapshot.data?[1] ?? UserDetails(name: receiverId ?? 'N/A', office: fallbackOffice);

                                                final senderOfficeText = sender.office.isNotEmpty ? ' (${sender.office})' : '';
                                                final receiverOfficeText = receiver.office.isNotEmpty ? ' (${receiver.office})' : (fallbackOffice.isNotEmpty ? ' ($fallbackOffice)' : '');

                                                return Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    // From (Current Sender)
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.north_east_rounded, size: 14, color: Color(0xFF2563EB)),
                                                        const SizedBox(width: 6),
                                                        Expanded(
                                                          child: Text.rich(
                                                            TextSpan(
                                                              children: [
                                                                const TextSpan(text: 'From: ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                                                                TextSpan(text: sender.name, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                                                TextSpan(text: senderOfficeText, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                                              ],
                                                            ),
                                                            style: const TextStyle(fontSize: 12),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),

                                                    // To (Next Recipient)
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.south_west_rounded, size: 14, color: Color(0xFF16A34A)),
                                                        const SizedBox(width: 6),
                                                        Expanded(
                                                          child: Text.rich(
                                                            TextSpan(
                                                              children: [
                                                                const TextSpan(text: 'To: ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                                                                TextSpan(text: receiver.name, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                                                TextSpan(text: receiverOfficeText, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                                              ],
                                                            ),
                                                            style: const TextStyle(fontSize: 12),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 8),

                                            // Remarks Section
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF8FAFC),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFF1F5F9)),
                                              ),
                                              child: Text(
                                                remarks,
                                                style: const TextStyle(fontSize: 11, color: Color(0xFF334155), height: 1.3),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}