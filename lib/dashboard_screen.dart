import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'sidebar.dart';
import 'upload_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  late TextEditingController _nameController;
  late TextEditingController _positionController;
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String userName = "Loading...";
  String officeName = "Loading...";
  String position = "";
  bool _isUpdating = false;

  // Receiver name lookup cache
  final Map<String, Future<String>> _receiverNameCache = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _positionController = TextEditingController();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _positionController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Fetch current user & office details from Firestore
  Future<void> _loadUserProfile() async {
    if (_currentUser == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .get();

    if (doc.exists && mounted) {
      final data = doc.data()!;
      setState(() {
        userName = data['name'] ?? data['userName'] ?? 'User';
        officeName = data['officeName'] ?? data['office'] ?? 'General Office';
        position = data['position'] ?? 'Staff';
        _nameController.text = userName;
        _positionController.text = position;
      });
    }
  }

  // Resolve Receiver Name from user collection or cache
  Future<String> _getReceiverName(String? uid, Map<String, dynamic> docData) {
    // If name is already embedded in the document
    final embeddedName = docData['recipientName'] ?? docData['receiverName'] ?? docData['receiver'];
    if (embeddedName != null && embeddedName.toString().trim().isNotEmpty) {
      return Future.value(embeddedName.toString());
    }

    if (uid == null || uid.isEmpty) return Future.value('N/A');

    return _receiverNameCache.putIfAbsent(uid, () async {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final name = doc.data()?['name'] as String?;
        return (name != null && name.trim().isNotEmpty) ? name : uid;
      } catch (_) {
        return uid;
      }
    });
  }

  // Update profile details in Firestore and Firebase Auth
  Future<void> _updateProfile() async {
    if (_currentUser == null) return;

    setState(() => _isUpdating = true);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .update({
        'name': _nameController.text.trim(),
        'position': _positionController.text.trim(),
      });

      if (_passwordController.text.isNotEmpty) {
        if (_passwordController.text == _confirmPasswordController.text) {
          await _currentUser!.updatePassword(_passwordController.text.trim());
        } else {
          throw Exception('Passwords do not match');
        }
      }

      setState(() {
        userName = _nameController.text.trim();
        position = _positionController.text.trim();
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account updated successfully!'),
          backgroundColor: Color(0xFF2563EB),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view dashboard.')),
      );
    }

    final currentUserId = _currentUser!.uid;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: StreamBuilder<QuerySnapshot>(
        // Stream for Sidebar Notification Count (Incoming + Sender Status Updates)
        stream: FirebaseFirestore.instance.collection('documents').snapshots(),
        builder: (context, notifSnapshot) {
          int incomingCount = 0;
          int senderActionCount = 0;

          if (notifSnapshot.hasData) {
            for (var doc in notifSnapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final isArchived = data['isArchived'] == true;
              final status = (data['status'] ?? '').toString().toLowerCase();

              if (!isArchived) {
                // Incoming docs pending for this user
                final recipientId = data['recipientId'] ?? data['receiver_user_id'];
                if (recipientId == currentUserId && status == 'pending') {
                  incomingCount++;
                }

                // Sent docs updated (approved/rejected) not seen by sender
                final senderId = data['senderId'] ?? data['uploaderId'];
                final seenBySender = data['seenBySender'] ?? false;
                if (senderId == currentUserId && (status == 'approved' || status == 'rejected') && !seenBySender) {
                  senderActionCount++;
                }
              }
            }
          }

          return Sidebar(
            currentPage: 'dashboard.php',
            notificationCount: incomingCount + senderActionCount,
          );
        },
      ),
      endDrawer: _buildProfileDrawer(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadUserProfile,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Bar
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu, size: 26, color: Color(0xFF0F172A)),
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hello, $userName!',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.business, size: 12, color: Color(0xFF2563EB)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  officeName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                      child: Stack(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2563EB),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Color(0xFF1D4ED8),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.settings, size: 10, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Notifications Stream
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('documents').snapshots(),
                  builder: (context, notifSnapshot) {
                    int incomingCount = 0;
                    int senderActionCount = 0;

                    if (notifSnapshot.hasData) {
                      for (var doc in notifSnapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final isArchived = data['isArchived'] == true;
                        final status = (data['status'] ?? '').toString().toLowerCase();

                        if (!isArchived) {
                          final recipientId = data['recipientId'] ?? data['receiver_user_id'];
                          if (recipientId == currentUserId && status == 'pending') {
                            incomingCount++;
                          }

                          final senderId = data['senderId'] ?? data['uploaderId'];
                          final seenBySender = data['seenBySender'] ?? false;
                          if (senderId == currentUserId && (status == 'approved' || status == 'rejected') && !seenBySender) {
                            senderActionCount++;
                          }
                        }
                      }
                    }

                    if (incomingCount == 0 && senderActionCount == 0) {
                      return const SizedBox.shrink();
                    }

                    return Column(
                      children: [
                        if (incomingCount > 0)
                          _buildNotifBanner(
                            icon: Icons.move_to_inbox,
                            iconColor: const Color(0xFFD97706),
                            bgColor: const Color(0xFFFFFBEB),
                            borderColor: const Color(0xFFF59E0B),
                            textColor: const Color(0xFF92400E),
                            text: 'You have $incomingCount docs to process. ',
                            actionText: 'View Inbox',
                          ),
                        if (senderActionCount > 0)
                          _buildNotifBanner(
                            icon: Icons.notifications_active_outlined,
                            iconColor: const Color(0xFF2563EB),
                            bgColor: const Color(0xFFEFF6FF),
                            borderColor: const Color(0xFF3B82F6),
                            textColor: const Color(0xFF1E40AF),
                            text: '$senderActionCount documents were updated. ',
                            actionText: 'Check Status',
                          ),
                        const SizedBox(height: 10),
                      ],
                    );
                  },
                ),

                // Stats Grid (Filtered for uploader/sender)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('documents')
                      .where(
                    Filter.or(
                      Filter('senderId', isEqualTo: currentUserId),
                      Filter('uploaderId', isEqualTo: currentUserId),
                    ),
                  )
                      .snapshots(),
                  builder: (context, snapshot) {
                    int total = 0;
                    int pending = 0;
                    int approved = 0;
                    int rejected = 0;

                    if (snapshot.hasData) {
                      for (var doc in snapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final isArchived = data['isArchived'] == true;

                        if (!isArchived) {
                          total++;
                          final status = (data['status'] ?? '').toString().toLowerCase();
                          if (status == 'pending') pending++;
                          if (status == 'approved') approved++;
                          if (status == 'rejected') rejected++;
                        }
                      }
                    }

                    return GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.45,
                      children: [
                        _buildStatCard('ACTIVE SENT', total, const Color(0xFF2563EB)),
                        _buildStatCard('PENDING', pending, const Color(0xFFEAB308)),
                        _buildStatCard('APPROVED', approved, const Color(0xFF22C55E)),
                        _buildStatCard('REJECTED', rejected, const Color(0xFFEF4444)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Upload Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const UploadScreen()),
                      );
                    },
                    icon: const Icon(Icons.upload_file_outlined, color: Colors.white),
                    label: const Text(
                      'Upload New Document',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Recent Activity Card (Top 5 Uploads by User)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Recent Activity',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            TextButton(
                              onPressed: () {},
                              style: TextButton.styleFrom(padding: EdgeInsets.zero),
                              child: const Text(
                                'View All',
                                style: TextStyle(
                                  color: Color(0xFF2563EB),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('documents')
                            .where(
                          Filter.or(
                            Filter('senderId', isEqualTo: currentUserId),
                            Filter('uploaderId', isEqualTo: currentUserId),
                          ),
                        )
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('No recent activity recorded.', style: TextStyle(color: Colors.grey)),
                            );
                          }

                          // Filter out archived documents and sort by createdAt DESC
                          final userDocs = snapshot.data!.docs.where((d) {
                            final data = d.data() as Map<String, dynamic>;
                            return data['isArchived'] != true;
                          }).toList();

                          userDocs.sort((a, b) {
                            final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                            final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                            if (aTime == null || bTime == null) return 0;
                            return bTime.compareTo(aTime);
                          });

                          final recentDocs = userDocs.take(5).toList();

                          if (recentDocs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('No recent activity recorded.', style: TextStyle(color: Colors.grey)),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            itemCount: recentDocs.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final docData = recentDocs[index].data() as Map<String, dynamic>;
                              final receiverUid = (docData['recipientId'] ?? docData['receiver_user_id']) as String?;

                              return FutureBuilder<String>(
                                future: _getReceiverName(receiverUid, docData),
                                builder: (context, nameSnapshot) {
                                  final receiverName = nameSnapshot.data ?? 'Loading...';
                                  return _buildDocRow(docData, receiverName);
                                },
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, int value, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF94A3B8),
                ),
              ),
              Container(width: 8, height: 8, decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle)),
            ],
          ),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifBanner({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
    required String text,
    required String actionText,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(color: textColor, fontSize: 12),
                children: [
                  TextSpan(text: text),
                  TextSpan(
                    text: actionText,
                    style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocRow(Map<String, dynamic> doc, String receiverName) {
    final status = (doc['status'] ?? 'pending').toString();
    Color badgeBg;
    Color badgeText;

    switch (status.toLowerCase()) {
      case 'approved':
        badgeBg = const Color(0xFFDCFCE7);
        badgeText = const Color(0xFF15803D);
        break;
      case 'rejected':
        badgeBg = const Color(0xFFFFE4E6);
        badgeText = const Color(0xFFBE123C);
        break;
      default:
        badgeBg = const Color(0xFFFEF3C7);
        badgeText = const Color(0xFFB45309);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.article_outlined, color: Color(0xFF2563EB), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc['title'] ?? doc['document_title'] ?? doc['filename'] ?? 'Untitled Document',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF334155),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Receiver: $receiverName',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(
                color: badgeText,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Account Settings',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: const Color(0xFF2563EB),
                            child: Text(
                              userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                              style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text('CHANGE PHOTO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildDrawerLabel('FULL NAME'),
                    TextField(
                      controller: _nameController,
                      decoration: _drawerInputDecoration('Full Name'),
                    ),
                    const SizedBox(height: 12),
                    _buildDrawerLabel('POSITION'),
                    TextField(
                      controller: _positionController,
                      decoration: _drawerInputDecoration('Position'),
                    ),
                    const SizedBox(height: 16),
                    _buildDrawerLabel('E-SIGNATURE'),
                    Container(
                      height: 80,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.draw, color: Color(0xFF94A3B8)),
                          Text('Upload Signature Image', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDrawerLabel('SECURITY'),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: _drawerInputDecoration('New Password'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      decoration: _drawerInputDecoration('Confirm Password'),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isUpdating ? null : _updateProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isUpdating
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                            : const Text('Update Account', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4.0),
        child: Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
        ),
      ),
    );
  }

  InputDecoration _drawerInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      fillColor: const Color(0xFFF8FAFC),
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    );
  }
}