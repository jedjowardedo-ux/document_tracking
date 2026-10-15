import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'sidebar.dart';
import 'upload_screen.dart';
import 'records.dart';
import 'inbox_screen.dart';
import 'track_screen.dart';
import 'docu_list_screen.dart';

// --- DESIGN TOKENS ---
class _C {
  static const ink = Color(0xFF0B1B3A);
  static const inkSoft = Color(0xFF14337A);
  static const blue = Color(0xFF2563EB);
  static const paper = Color(0xFFF5F7FB);
  static const line = Color(0xFFE3E8F0);
  static const text = Color(0xFF1E293B);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);
  static const amber = Color(0xFFE0A526);
  static const green = Color(0xFF1F9D63);
  static const red = Color(0xFFD64545);
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // Same Cloudinary account as the upload screen
  final CloudinaryPublic _cloudinary = CloudinaryPublic(
    'nikh0hne',
    'document_tracking_uploads',
    cache: false,
  );

  late TextEditingController _nameController;
  late TextEditingController _positionController;
  final _currentPasswordController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String userName = "Loading...";
  String officeName = "Loading...";
  String position = "";
  String? photoUrl;
  String? signatureUrl;

  bool _isUpdating = false;
  bool _isChangingPassword = false;
  bool _uploadingPhoto = false;
  bool _uploadingSignature = false;
  bool _hidePasswords = true;

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
    _currentPasswordController.dispose();
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
      final photo = (data['photoUrl'] ?? '').toString().trim();
      final sig = (data['signatureUrl'] ?? '').toString().trim();
      setState(() {
        userName = data['name'] ?? data['userName'] ?? 'User';
        officeName = data['officeName'] ?? data['office'] ?? 'General Office';
        position = data['position'] ?? 'Staff';
        photoUrl = photo.isEmpty ? null : photo;
        signatureUrl = sig.isEmpty ? null : sig;
        _nameController.text = userName;
        _positionController.text = position;
      });
    }
  }

  // Resolve Receiver Name from user collection or cache
  Future<String> _getReceiverName(String? uid, Map<String, dynamic> docData) {
    final embeddedName =
        docData['recipientName'] ?? docData['receiverName'] ?? docData['receiver'];
    if (embeddedName != null && embeddedName.toString().trim().isNotEmpty) {
      return Future.value(embeddedName.toString());
    }

    if (uid == null || uid.isEmpty) return Future.value('N/A');

    return _receiverNameCache.putIfAbsent(uid, () async {
      try {
        final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final name = doc.data()?['name'] as String?;
        return (name != null && name.trim().isNotEmpty) ? name : uid;
      } catch (_) {
        return uid;
      }
    });
  }

  // ---------- ACCOUNT SETTINGS ----------

  void _snack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Save name + position
  Future<void> _updateProfile() async {
    if (_currentUser == null) return;

    final name = _nameController.text.trim();
    final pos = _positionController.text.trim();

    if (name.isEmpty) {
      _snack('Full name cannot be empty.', color: _C.red);
      return;
    }

    setState(() => _isUpdating = true);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .update({
        'name': name,
        'position': pos,
      });

      if (!mounted) return;
      setState(() {
        userName = name;
        position = pos;
      });

      Navigator.of(context).pop(); // close the drawer
      _snack('Profile updated successfully!', color: _C.blue);
    } catch (e) {
      _snack('Update failed: $e', color: _C.red);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // Pick an image and upload it to Cloudinary, then save the URL on the user.
  // isSignature = false -> photoUrl, true -> signatureUrl
  Future<void> _pickAndUploadImage({required bool isSignature}) async {
    if (_currentUser == null) return;
    if (isSignature ? _uploadingSignature : _uploadingPhoto) return;

    // file_picker 12: static pickFile(), bytes are read with readAsBytes()
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      _snack('Could not read that image. Try another one.', color: _C.red);
      return;
    }
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      _snack('Image must be smaller than 5 MB.', color: _C.red);
      return;
    }

    setState(() {
      if (isSignature) {
        _uploadingSignature = true;
      } else {
        _uploadingPhoto = true;
      }
    });

    try {
      final res = await _cloudinary.uploadFile(
        CloudinaryFile.fromBytesData(
          bytes,
          identifier: file.name,
          resourceType: CloudinaryResourceType.Image,
        ),
      );

      final url = res.secureUrl;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .update({isSignature ? 'signatureUrl' : 'photoUrl': url});

      if (!mounted) return;
      setState(() {
        if (isSignature) {
          signatureUrl = url;
        } else {
          photoUrl = url;
        }
      });
      _snack(
        isSignature ? 'E-signature saved.' : 'Profile photo updated.',
        color: _C.green,
      );
    } catch (e) {
      _snack('Upload failed: $e', color: _C.red);
    } finally {
      if (mounted) {
        setState(() {
          if (isSignature) {
            _uploadingSignature = false;
          } else {
            _uploadingPhoto = false;
          }
        });
      }
    }
  }

  Future<void> _removeImage({required bool isSignature}) async {
    if (_currentUser == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isSignature ? 'Remove e-signature?' : 'Remove profile photo?',
          style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 16, color: _C.ink),
        ),
        content: Text(
          isSignature
              ? 'Outgoing documents will no longer include your signature until you upload a new one.'
              : 'Your initial will be shown instead.',
          style: const TextStyle(fontSize: 13, color: _C.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: _C.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .update({isSignature ? 'signatureUrl' : 'photoUrl': FieldValue.delete()});

      if (!mounted) return;
      setState(() {
        if (isSignature) {
          signatureUrl = null;
        } else {
          photoUrl = null;
        }
      });
      _snack(isSignature ? 'E-signature removed.' : 'Profile photo removed.');
    } catch (e) {
      _snack('Could not remove: $e', color: _C.red);
    }
  }

  // Change password (re-authenticates with the current password first)
  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final current = _currentPasswordController.text;
    final next = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      _snack('Fill in all three password fields.', color: _C.red);
      return;
    }
    if (next.length < 6) {
      _snack('New password must be at least 6 characters.', color: _C.red);
      return;
    }
    if (next != confirm) {
      _snack('New passwords do not match.', color: _C.red);
      return;
    }
    if (next == current) {
      _snack('New password must be different from the current one.',
          color: _C.red);
      return;
    }
    final email = user.email;
    if (email == null || email.isEmpty) {
      _snack('This account has no email, so the password cannot be changed here.',
          color: _C.red);
      return;
    }

    setState(() => _isChangingPassword = true);

    try {
      final cred = EmailAuthProvider.credential(email: email, password: current);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(next);

      _currentPasswordController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();

      if (!mounted) return;
      Navigator.of(context).pop(); // close the drawer
      _snack('Password changed successfully!', color: _C.green);
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          msg = 'Current password is incorrect.';
          break;
        case 'weak-password':
          msg = 'New password is too weak.';
          break;
        case 'requires-recent-login':
          msg = 'Please log out and log in again, then retry.';
          break;
        case 'too-many-requests':
          msg = 'Too many attempts. Try again later.';
          break;
        default:
          msg = e.message ?? 'Could not change password.';
      }
      _snack(msg, color: _C.red);
    } catch (e) {
      _snack('Could not change password: $e', color: _C.red);
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  // ---------- HELPERS ----------

  // Returns (incomingCount, senderActionCount)
  (int, int) _countNotifications(QuerySnapshot snapshot, String currentUserId) {
    int incoming = 0;
    int senderAction = 0;

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final isArchived = data['isArchived'] == true;
      final status = (data['status'] ?? '').toString().toLowerCase();

      if (!isArchived) {
        final recipientId = data['recipientId'] ?? data['receiver_user_id'];
        if (recipientId == currentUserId && status == 'pending') {
          incoming++;
        }

        final senderId = data['senderId'] ?? data['uploaderId'];
        final seenBySender = data['seenBySender'] ?? false;
        if (senderId == currentUserId &&
            (status == 'approved' || status == 'rejected') &&
            !seenBySender) {
          senderAction++;
        }
      }
    }
    return (incoming, senderAction);
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName {
    final trimmed = userName.trim();
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(' ').first;
  }

  String get _initial =>
      userName.trim().isNotEmpty ? userName.trim()[0].toUpperCase() : 'U';

  // Profile picture, or the initial when there is none. Fills its parent.
  Widget _avatarContent(double fontSize) {
    final initial = Center(
      child: Text(
        _initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
        ),
      ),
    );

    if (photoUrl == null) return initial;

    return ClipOval(
      child: Image.network(
        photoUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => initial,
        loadingBuilder: (context, child, progress) =>
        progress == null ? child : initial,
      ),
    );
  }

  // (foreground, background, icon, label)
  (Color, Color, IconData, String) _statusStyle(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return (
        _C.green,
        const Color(0xFFE6F5EE),
        Icons.check_circle_outline,
        'Approved'
        );
      case 'rejected':
        return (
        _C.red,
        const Color(0xFFFBEAEA),
        Icons.cancel_outlined,
        'Rejected'
        );
      case 'forwarded':
        return (
        _C.blue,
        const Color(0xFFE8F0FE),
        Icons.send_outlined,
        'Forwarded'
        );
      default:
        return (
        const Color(0xFFB7791F),
        const Color(0xFFFCF3DC),
        Icons.schedule,
        'Pending'
        );
    }
  }

  void _go(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  // ---------- BUILD ----------

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
      backgroundColor: _C.paper,
      drawer: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('documents').snapshots(),
        builder: (context, notifSnapshot) {
          int count = 0;
          if (notifSnapshot.hasData) {
            final counts =
            _countNotifications(notifSnapshot.data!, currentUserId);
            count = counts.$1 + counts.$2;
          }
          return Sidebar(
            currentPage: 'dashboard.php',
            notificationCount: count,
          );
        },
      ),
      endDrawer: _buildProfileDrawer(),
      body: RefreshIndicator(
        onRefresh: _loadUserProfile,
        color: _C.blue,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(currentUserId),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAttentionSection(currentUserId),
                    _sectionTitle('Quick actions'),
                    const SizedBox(height: 12),
                    _buildQuickActions(),
                    const SizedBox(height: 28),
                    _buildRecentActivity(currentUserId),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- HEADER (greeting + document pipeline) ----------

  Widget _buildHeader(String currentUserId) {
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_C.ink, _C.inkSoft],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar
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
              const Spacer(),
              GestureDetector(
                onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _C.blue,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.85),
                            width: 2),
                      ),
                      child: _avatarContent(17),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.settings,
                            size: 10, color: _C.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Greeting
          Text(
            DateFormat('EEEE, MMMM d').format(DateTime.now()),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_greeting()}, $_firstName',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.apartment_rounded,
                  size: 15, color: Colors.white.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  position.isEmpty ? officeName : '$position at $officeName',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Pipeline (the signature element)
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
                    final status =
                    (data['status'] ?? '').toString().toLowerCase();
                    if (status == 'pending') pending++;
                    if (status == 'approved') approved++;
                    if (status == 'rejected') rejected++;
                  }
                }
              }

              return _buildPipelineCard(total, pending, approved, rejected);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineCard(
      int total, int pending, int approved, int rejected) {
    final other = total - pending - approved - rejected;

    Widget segment(int value, Color color) {
      return Expanded(
        flex: value,
        child: Container(
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$total',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  height: 1,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  total == 1 ? 'document sent' : 'documents sent',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Segmented progress bar
          if (total == 0)
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
            )
          else
            Row(
              children: [
                if (approved > 0) segment(approved, const Color(0xFF3DD68C)),
                if (pending > 0) segment(pending, const Color(0xFFF2C14E)),
                if (rejected > 0) segment(rejected, const Color(0xFFFF7B7B)),
                if (other > 0)
                  segment(other, Colors.white.withValues(alpha: 0.35)),
              ],
            ),
          const SizedBox(height: 16),

          Row(
            children: [
              _legendItem('Approved', approved, const Color(0xFF3DD68C)),
              _legendItem('Pending', pending, const Color(0xFFF2C14E)),
              _legendItem('Rejected', rejected, const Color(0xFFFF7B7B)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String label, int value, Color color) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- NEEDS ATTENTION ----------

  Widget _buildAttentionSection(String currentUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('documents').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final counts = _countNotifications(snapshot.data!, currentUserId);
        final incomingCount = counts.$1;
        final senderActionCount = counts.$2;

        if (incomingCount == 0 && senderActionCount == 0) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Needs your attention'),
              const SizedBox(height: 12),
              if (incomingCount > 0)
                _buildNotifBanner(
                  icon: Icons.move_to_inbox_outlined,
                  accent: const Color(0xFFB7791F),
                  tint: const Color(0xFFFCF3DC),
                  title: incomingCount == 1
                      ? '1 document waiting for you'
                      : '$incomingCount documents waiting for you',
                  subtitle: 'Review and approve, forward, or reject.',
                  actionText: 'Open inbox',
                  onTap: () => _go(const InboxScreen()),
                ),
              if (senderActionCount > 0)
                _buildNotifBanner(
                  icon: Icons.notifications_active_outlined,
                  accent: _C.blue,
                  tint: const Color(0xFFE8F0FE),
                  title: senderActionCount == 1
                      ? '1 of your documents was updated'
                      : '$senderActionCount of your documents were updated',
                  subtitle: 'Approved or rejected since you last checked.',
                  actionText: 'Check status',
                  onTap: () => _go(const TrackScreen()),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotifBanner({
    required IconData icon,
    required Color accent,
    required Color tint,
    required String title,
    required String subtitle,
    required String actionText,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.line),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _C.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: _C.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      actionText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                ),
                Icon(Icons.chevron_right_rounded, color: accent, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- QUICK ACTIONS ----------

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: _C.ink,
        letterSpacing: -0.3,
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        _quickAction(
          icon: Icons.upload_file_rounded,
          label: 'Upload',
          primary: true,
          onTap: () => _go(const UploadScreen()),
        ),
        const SizedBox(width: 10),
        _quickAction(
          icon: Icons.inbox_rounded,
          label: 'Inbox',
          onTap: () => _go(const InboxScreen()),
        ),
        const SizedBox(width: 10),
        _quickAction(
          icon: Icons.alt_route_rounded,
          label: 'Track',
          onTap: () => _go(const TrackScreen()),
        ),
        const SizedBox(width: 10),
        _quickAction(
          icon: Icons.history_rounded,
          label: 'Records',
          onTap: () => _go(const RecordsScreen()),
        ),
      ],
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return Expanded(
      child: Material(
        color: primary ? _C.blue : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primary ? _C.blue : _C.line),
            ),
            child: Column(
              children: [
                Icon(icon, color: primary ? Colors.white : _C.ink, size: 24),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: primary ? Colors.white : _C.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- RECENT ACTIVITY ----------

  Widget _buildRecentActivity(String currentUserId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _sectionTitle('Recent activity'),
            TextButton(
              onPressed: () => _go(const DocuListScreen()),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'See all',
                style: TextStyle(
                  color: _C.blue,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _C.line),
          ),
          child: StreamBuilder<QuerySnapshot>(
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
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyState();
              }

              // Filter out archived documents and sort by createdAt DESC
              final userDocs = snapshot.data!.docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return data['isArchived'] != true;
              }).toList();

              userDocs.sort((a, b) {
                final aTime =
                (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                final bTime =
                (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                if (aTime == null || bTime == null) return 0;
                return bTime.compareTo(aTime);
              });

              final recentDocs = userDocs.take(5).toList();

              if (recentDocs.isEmpty) return _buildEmptyState();

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: recentDocs.length,
                separatorBuilder: (context, index) => const Divider(
                  height: 1,
                  indent: 70,
                  endIndent: 16,
                  color: _C.line,
                ),
                itemBuilder: (context, index) {
                  final docData =
                  recentDocs[index].data() as Map<String, dynamic>;
                  final receiverUid = (docData['recipientId'] ??
                      docData['receiver_user_id']) as String?;

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
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F0FE),
              shape: BoxShape.circle,
            ),
            child:
            const Icon(Icons.description_outlined, color: _C.blue, size: 26),
          ),
          const SizedBox(height: 14),
          const Text(
            'No documents sent yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _C.text,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Upload a document and it will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _C.muted),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _go(const UploadScreen()),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.blue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'Upload a document',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocRow(Map<String, dynamic> doc, String receiverName) {
    final status = (doc['status'] ?? 'pending').toString();
    final style = _statusStyle(status);
    final fg = style.$1;
    final bg = style.$2;
    final icon = style.$3;
    final label = style.$4;

    final createdAt = (doc['createdAt'] as Timestamp?)?.toDate();
    final dateText = createdAt != null ? DateFormat('MMM d').format(createdAt) : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: fg, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc['title'] ??
                      doc['document_title'] ??
                      doc['filename'] ??
                      doc['fileName'] ??
                      'Untitled Document',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: _C.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  dateText.isEmpty
                      ? 'To $receiverName'
                      : 'To $receiverName, $dateText',
                  style: const TextStyle(fontSize: 12, color: _C.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- PROFILE DRAWER ----------

  Widget _buildProfileDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.88,
      backgroundColor: _C.paper,
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 12, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_C.ink, _C.inkSoft],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Account settings',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: _C.blue,
                        shape: BoxShape.circle,
                      ),
                      child: _avatarContent(26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            position.isEmpty ? officeName : '$position, $officeName',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ----- PROFILE -----
                  _drawerSection('Profile'),
                  Row(
                    children: [
                      _uploadingPhoto
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.photo_camera_outlined,
                          size: 20, color: _C.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          photoUrl == null
                              ? 'No profile photo yet'
                              : 'Profile photo set',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _C.text),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _drawerButton(
                          icon: Icons.upload_rounded,
                          label: photoUrl == null ? 'Add photo' : 'Change photo',
                          onPressed: _uploadingPhoto
                              ? null
                              : () => _pickAndUploadImage(isSignature: false),
                        ),
                      ),
                      if (photoUrl != null) ...[
                        const SizedBox(width: 8),
                        _drawerButton(
                          icon: Icons.delete_outline_rounded,
                          label: 'Remove',
                          danger: true,
                          onPressed: _uploadingPhoto
                              ? null
                              : () => _removeImage(isSignature: false),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildDrawerLabel('Full name'),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _drawerInputDecoration('Full name',
                        icon: Icons.person_outline_rounded),
                  ),
                  const SizedBox(height: 14),
                  _buildDrawerLabel('Position'),
                  TextField(
                    controller: _positionController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _drawerInputDecoration('Position',
                        icon: Icons.badge_outlined),
                  ),
                  const SizedBox(height: 14),
                  _buildDrawerLabel('Office'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2F7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _C.line),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.apartment_rounded,
                            size: 20, color: _C.faint),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            officeName,
                            style: const TextStyle(
                                fontSize: 14, color: _C.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isUpdating ? null : _updateProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _C.blue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isUpdating
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                          : const Text(
                        'Save profile',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),

                  // ----- E-SIGNATURE -----
                  const SizedBox(height: 28),
                  _drawerSection('E-signature'),
                  const Text(
                    'Used on documents you send out. A PNG with a transparent or white background works best.',
                    style: TextStyle(fontSize: 12, color: _C.muted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _uploadingSignature
                        ? null
                        : () => _pickAndUploadImage(isSignature: true),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 110,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _C.line),
                      ),
                      child: _uploadingSignature
                          ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                          : (signatureUrl != null
                          ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: Image.network(
                          signatureUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Text(
                              'Could not load signature',
                              style: TextStyle(
                                  fontSize: 12, color: _C.muted),
                            ),
                          ),
                        ),
                      )
                          : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.draw_outlined, color: _C.faint),
                          SizedBox(height: 4),
                          Text(
                            'Tap to upload signature image',
                            style: TextStyle(
                              fontSize: 12,
                              color: _C.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _drawerButton(
                          icon: Icons.upload_rounded,
                          label: signatureUrl == null
                              ? 'Upload signature'
                              : 'Replace signature',
                          onPressed: _uploadingSignature
                              ? null
                              : () => _pickAndUploadImage(isSignature: true),
                        ),
                      ),
                      if (signatureUrl != null) ...[
                        const SizedBox(width: 8),
                        _drawerButton(
                          icon: Icons.delete_outline_rounded,
                          label: 'Remove',
                          danger: true,
                          onPressed: _uploadingSignature
                              ? null
                              : () => _removeImage(isSignature: true),
                        ),
                      ],
                    ],
                  ),

                  // ----- SECURITY -----
                  const SizedBox(height: 28),
                  _drawerSection('Security'),
                  _buildDrawerLabel('Current password'),
                  TextField(
                    controller: _currentPasswordController,
                    obscureText: _hidePasswords,
                    decoration: _drawerInputDecoration('Current password',
                        icon: Icons.lock_outline_rounded, suffix: true),
                  ),
                  const SizedBox(height: 12),
                  _buildDrawerLabel('New password'),
                  TextField(
                    controller: _passwordController,
                    obscureText: _hidePasswords,
                    decoration: _drawerInputDecoration('At least 6 characters',
                        icon: Icons.lock_reset_rounded, suffix: true),
                  ),
                  const SizedBox(height: 12),
                  _buildDrawerLabel('Confirm new password'),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: _hidePasswords,
                    decoration: _drawerInputDecoration('Confirm new password',
                        icon: Icons.lock_reset_rounded, suffix: true),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isChangingPassword ? null : _changePassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _C.ink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isChangingPassword
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                          : const Text(
                        'Update password',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool danger = false,
  }) {
    final color = danger ? _C.red : _C.blue;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: onPressed == null ? _C.faint : color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: onPressed == null ? _C.faint : color,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        side: BorderSide(
            color: onPressed == null ? _C.line : color.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _drawerSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: _C.ink,
        ),
      ),
    );
  }

  Widget _buildDrawerLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _C.muted,
        ),
      ),
    );
  }

  InputDecoration _drawerInputDecoration(String hint,
      {IconData? icon, bool suffix = false}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _C.faint, fontSize: 14),
      prefixIcon:
      icon != null ? Icon(icon, size: 20, color: _C.faint) : null,
      suffixIcon: suffix
          ? IconButton(
        icon: Icon(
          _hidePasswords
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 20,
          color: _C.faint,
        ),
        onPressed: () => setState(() => _hidePasswords = !_hidePasswords),
      )
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      fillColor: Colors.white,
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _C.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _C.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _C.blue, width: 1.6),
      ),
    );
  }
}