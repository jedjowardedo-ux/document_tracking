import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'sidebar.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  String _activeFilter = 'all'; // 'all' or 'overdue'

  // Dynamic user & office cache to mirror PHP table JOINs
  final Map<String, Future<Map<String, String>>> _uploaderCache = {};

  String _getTodayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  bool _isOverdue(String? dueDate) {
    if (dueDate == null || dueDate.trim().isEmpty) return false;
    final today = _getTodayString();
    return dueDate.compareTo(today) < 0;
  }

  // Resolve uploader name & sender office (joins user & office collection data)
  Future<Map<String, String>> _getUploaderDetails(
      String? uploaderId, Map<String, dynamic> docData) {
    // Return embedded fields if present
    final embeddedName = docData['uploaderName'] ?? docData['senderName'];
    final embeddedOffice = docData['senderOffice'] ?? docData['destinationOffice'];

    if (uploaderId == null || uploaderId.isEmpty) {
      return Future.value({
        'name': embeddedName ?? 'Unknown Sender',
        'office': embeddedOffice ?? 'General Office',
      });
    }

    return _uploaderCache.putIfAbsent(uploaderId, () async {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uploaderId)
            .get();

        if (userDoc.exists) {
          final uData = userDoc.data()!;
          final name = uData['name'] ?? uData['userName'] ?? 'Unknown Sender';
          final office = uData['officeName'] ?? uData['office'] ?? 'General Office';
          return {'name': name.toString(), 'office': office.toString()};
        }
      } catch (_) {}

      return {
        'name': embeddedName ?? 'Unknown Sender',
        'office': embeddedOffice ?? 'General Office',
      };
    });
  }

  // --- ACTIONS ---

  Future<void> _processAction(String docId, String newStatus) async {
    final label = newStatus.isEmpty
        ? newStatus
        : newStatus[0].toUpperCase() + newStatus.substring(1);
    final isApprove = newStatus == 'approved';

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Action',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to mark this document as $label?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isApprove
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.collection('documents').doc(docId).update({
        'status': newStatus,
        'seenBySender': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Document successfully $label.'),
          backgroundColor:
          isApprove ? const Color(0xFF16A34A) : const Color(0xFFEF4444),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error updating document: $e'),
            backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  void _showDetailsDialog(
      Map<String, dynamic> data, String uploaderName, String senderOffice) {
    final title = data['title'] ??
        data['document_title'] ??
        data['filename'] ??
        data['fileName'] ??
        'Untitled Document';
    final description = (data['description']?.toString().isNotEmpty == true)
        ? data['description']
        : 'No description provided.';
    final remarks = (data['remarks']?.toString().isNotEmpty == true)
        ? data['remarks']
        : 'No remarks provided.';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.description, color: Color(0xFF2563EB)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('DESCRIPTION',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF64748B))),
              const SizedBox(height: 4),
              Text(description,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B))),
              const SizedBox(height: 12),
              const Text('REMARKS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF64748B))),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(remarks,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.person, size: 16, color: Color(0xFF2563EB)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Sender: $uploaderName',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.business, size: 16, color: Color(0xFF9333EA)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Office: $senderOffice',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openForwardModal(String docId) {
    String? forwardOffice;
    String? forwardUserId;
    String? forwardUserName;
    final remarksController = TextEditingController();
    PlatformFile? newFile;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (bottomCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(bottomCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Forward & Update Document',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),

                    // Target Office Dropdown (Fetched from Firestore 'offices' collection)
                    const Text('Target Office *',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('offices')
                          .orderBy('office_name', descending: false)
                          .snapshots(),
                      builder: (context, officeSnapshot) {
                        List<String> officeOptions = [
                          'College of Engineering',
                          'College of Arts & Sciences',
                          'Human Resource Management',
                          'Finance & Accounting',
                          'Registrar Office',
                          'IT & Technical Support',
                        ];

                        if (officeSnapshot.hasData &&
                            officeSnapshot.data!.docs.isNotEmpty) {
                          officeOptions = officeSnapshot.data!.docs.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return (data['office_name'] ??
                                data['name'] ??
                                'Office')
                                .toString();
                          }).toList();
                        }

                        return DropdownButtonFormField<String>(
                          value: forwardOffice,
                          hint: const Text('Select Office...'),
                          decoration: _inputDecoration(''),
                          items: officeOptions
                              .map((o) => DropdownMenuItem(
                              value: o, child: Text(o)))
                              .toList(),
                          onChanged: (val) {
                            setModalState(() {
                              forwardOffice = val;
                              forwardUserId = null;
                              forwardUserName = null;
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // Recipient Dropdown
                    const Text('Recipient *',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const LinearProgressIndicator();
                        }

                        final users = snapshot.data!.docs;
                        final currentUid = _currentUser?.uid;

                        // Filter out current user and optionally match selected office
                        final filteredUsers = users.where((u) {
                          if (u.id == currentUid) return false;
                          if (forwardOffice == null) return true;
                          final data = u.data() as Map<String, dynamic>;
                          final uOffice =
                              data['officeName'] ?? data['office'];
                          return uOffice == forwardOffice;
                        }).toList();

                        return DropdownButtonFormField<String>(
                          value: forwardUserId,
                          hint: Text(filteredUsers.isEmpty
                              ? 'No recipient found for this office'
                              : 'Select Person...'),
                          decoration: _inputDecoration(''),
                          items: filteredUsers.map((u) {
                            final data = u.data() as Map<String, dynamic>;
                            final name =
                                data['userName'] ?? data['name'] ?? 'User';
                            return DropdownMenuItem<String>(
                                value: u.id, child: Text(name));
                          }).toList(),
                          onChanged: filteredUsers.isEmpty
                              ? null
                              : (val) {
                            setModalState(() {
                              forwardUserId = val;
                              if (val != null) {
                                final selectedDoc = filteredUsers
                                    .firstWhere((u) => u.id == val);
                                final data = selectedDoc.data()
                                as Map<String, dynamic>;
                                forwardUserName = data['userName'] ??
                                    data['name'] ??
                                    'User';
                              }
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // Remarks
                    const Text('Forwarding Remarks',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: remarksController,
                      maxLines: 2,
                      decoration:
                      _inputDecoration('Add routing instructions...'),
                    ),
                    const SizedBox(height: 12),

                    // Optional Replacement File
                    OutlinedButton.icon(
                      onPressed: () async {
                        final files = await FilePicker.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: [
                            'pdf',
                            'doc',
                            'docx',
                            'jpg',
                            'jpeg',
                            'png'
                          ],
                        );
                        if (files.isNotEmpty) {
                          setModalState(() => newFile = files.first);
                        }
                      },
                      icon: const Icon(Icons.attach_file, size: 18),
                      label: Text(newFile == null
                          ? 'Update File (Optional)'
                          : newFile!.name),
                    ),
                    const SizedBox(height: 20),

                    // Forward Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          if (forwardUserId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Please select a recipient to forward.')),
                            );
                            return;
                          }

                          final updatePayload = <String, dynamic>{
                            'recipientId': forwardUserId,
                            'receiver_user_id': forwardUserId,
                            'recipientName': forwardUserName,
                            'destinationOffice': forwardOffice,
                            'remarks': remarksController.text.trim(),
                            'status': 'pending',
                            'updatedAt': FieldValue.serverTimestamp(),
                          };

                          if (newFile != null) {
                            final fileBytes = await newFile!.readAsBytes();
                            if (fileBytes.length > 500000) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'File exceeds 500 KB size limit.')),
                              );
                              return;
                            }
                            updatePayload['fileData'] =
                                base64Encode(fileBytes);
                            updatePayload['fileName'] = newFile!.name;
                            updatePayload['filename'] = newFile!.name;
                            updatePayload['fileExtension'] = newFile!.extension;
                          }

                          await FirebaseFirestore.instance
                              .collection('documents')
                              .doc(docId)
                              .update(updatePayload);

                          if (!mounted) return;
                          Navigator.pop(bottomCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Document successfully forwarded!'),
                              backgroundColor: Color(0xFF16A34A),
                            ),
                          );
                        },
                        child: const Text('Forward Now',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view inbox.')),
      );
    }

    final currentUserId = _currentUser!.uid;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('documents').snapshots(),
        builder: (context, notifSnapshot) {
          int count = 0;
          if (notifSnapshot.hasData) {
            for (var doc in notifSnapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final isArchived = data['isArchived'] == true;
              final status = (data['status'] ?? '').toString().toLowerCase();

              if (!isArchived) {
                final recipientId =
                    data['recipientId'] ?? data['receiver_user_id'];
                if (recipientId == currentUserId && status == 'pending') {
                  count++;
                }

                final senderId = data['senderId'] ?? data['uploaderId'];
                final seenBySender = data['seenBySender'] ?? false;
                if (senderId == currentUserId &&
                    (status == 'approved' || status == 'rejected') &&
                    !seenBySender) {
                  count++;
                }
              }
            }
          }

          return Sidebar(
            currentPage: 'inbox.php',
            notificationCount: count,
          );
        },
      ),
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
                        Text('Incoming Documents',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A))),
                        Text('Review, forward, or route incoming files',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Filter Tabs (All / Overdue)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _activeFilter = 'all'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _activeFilter == 'all'
                                ? const Color(0xFF1E3A8A)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'ALL',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: _activeFilter == 'all'
                                  ? Colors.white
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _activeFilter = 'overdue'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _activeFilter == 'overdue'
                                ? const Color(0xFFB91C1C)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.schedule,
                                  size: 14,
                                  color: _activeFilter == 'overdue'
                                      ? Colors.white
                                      : const Color(0xFFB91C1C)),
                              const SizedBox(width: 4),
                              Text(
                                'OVERDUE',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: _activeFilter == 'overdue'
                                      ? Colors.white
                                      : const Color(0xFFB91C1C),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Document List View
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('documents')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text('Inbox is empty.',
                          style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF64748B))),
                    );
                  }

                  // Match backend logic: receiver_user_id == user_id AND status == 'pending' AND is_archived == FALSE
                  var docs = snapshot.data!.docs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final recipientId =
                        data['recipientId'] ?? data['receiver_user_id'];
                    final status =
                    (data['status'] ?? '').toString().toLowerCase();
                    final isArchived = data['isArchived'] == true;

                    return recipientId == currentUserId &&
                        status == 'pending' &&
                        !isArchived;
                  }).toList();

                  // Client-side overdue filter
                  if (_activeFilter == 'overdue') {
                    docs = docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final dueDate =
                          data['dueDate'] ?? data['due_date'] as String?;
                      return _isOverdue(dueDate);
                    }).toList();
                  }

                  // Order by updatedAt DESC
                  docs.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final aTime = (aData['updatedAt'] ?? aData['createdAt'])
                    as Timestamp?;
                    final bTime = (bData['updatedAt'] ?? bData['createdAt'])
                    as Timestamp?;
                    if (aTime == null || bTime == null) return 0;
                    return bTime.compareTo(aTime);
                  });

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        _activeFilter == 'overdue'
                            ? 'No overdue documents found.'
                            : 'Inbox is empty.',
                        style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Color(0xFF64748B)),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final uploaderId = (data['uploaderId'] ??
                          data['senderId'] ??
                          data['uploader_id']) as String?;

                      final title = data['title'] ??
                          data['document_title'] ??
                          data['filename'] ??
                          data['fileName'] ??
                          'Untitled Document';
                      final dueDate = (data['dueDate'] ?? data['due_date'])
                      as String?;
                      final late = _isOverdue(dueDate);

                      return FutureBuilder<Map<String, String>>(
                        future: _getUploaderDetails(uploaderId, data),
                        builder: (context, detailsSnapshot) {
                          final uploaderName = detailsSnapshot.data?['name'] ??
                              data['senderName'] ??
                              'Loading...';
                          final senderOffice =
                              detailsSnapshot.data?['office'] ??
                                  data['destinationOffice'] ??
                                  'General Office';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: late
                                  ? const Color(0xFFFEF2F2)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: late
                                      ? const Color(0xFFFCA5A5)
                                      : const Color(0xFFE2E8F0)),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 4,
                                    offset: Offset(0, 2))
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor:
                                        const Color(0xFFDBEAFE),
                                        child: Text(
                                          uploaderName.isNotEmpty
                                              ? uploaderName[0].toUpperCase()
                                              : 'U',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1E40AF)),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(uploaderName,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: Color(0xFF0F172A))),
                                            Text(senderOffice,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF2563EB),
                                                    fontWeight:
                                                    FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                      if (late)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                              color: const Color(0xFFEF4444),
                                              borderRadius:
                                              BorderRadius.circular(20)),
                                          child: const Text('OVERDUE',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight:
                                                  FontWeight.bold)),
                                        )
                                      else if (dueDate != null &&
                                          dueDate.isNotEmpty)
                                        Text('Due: $dueDate',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF64748B))),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: Color(0xFF0F172A))),
                                  if (data['description'] != null &&
                                      data['description']
                                          .toString()
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      data['description'],
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF475569)),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  const Divider(
                                      height: 1, color: Color(0xFFE2E8F0)),
                                  const SizedBox(height: 8),

                                  // Actions Row
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.info_outline,
                                            color: Color(0xFF64748B)),
                                        onPressed: () => _showDetailsDialog(
                                            data, uploaderName, senderOffice),
                                        tooltip: 'Details',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.share,
                                            color: Color(0xFFD97706)),
                                        onPressed: () =>
                                            _openForwardModal(doc.id),
                                        tooltip: 'Forward',
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.check_circle_outline,
                                            color: Color(0xFF16A34A)),
                                        onPressed: () => _processAction(
                                            doc.id, 'approved'),
                                        tooltip: 'Approve',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.cancel_outlined,
                                            color: Color(0xFFDC2626)),
                                        onPressed: () => _processAction(
                                            doc.id, 'rejected'),
                                        tooltip: 'Reject',
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      fillColor: Colors.white,
      filled: true,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
          const BorderSide(color: Color(0xFF2563EB), width: 1.5)),
    );
  }
}