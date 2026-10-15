import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'upload_screen.dart';
import 'sign_in_screen.dart';
import 'inbox_screen.dart';
import 'chat_screen.dart';
import 'track_screen.dart';
import 'docu_list_screen.dart'; // Make sure to create or import your DocuListScreen file
import 'archive_screen.dart';
import 'records.dart';

// --- DESIGN TOKENS (same palette as the other screens) ---
class _C {
  static const ink = Color(0xFF0B1B3A);
  static const inkSoft = Color(0xFF14337A);
  static const blue = Color(0xFF2563EB);
  static const muted = Color(0xFF64748B);
  static const red = Color(0xFFD64545);
  static const paper = Color(0xFFF5F7FB);
  static const line = Color(0xFFE3E8F0);
  static const text = Color(0xFF1E293B);
  static const amber = Color(0xFFD99A1E);
}

class Sidebar extends StatelessWidget {
  final String currentPage;
  final int notificationCount;

  const Sidebar({
    super.key,
    this.currentPage = 'dashboard.php',
    this.notificationCount = 3,
  });

  bool _isActive(String pageName) => currentPage == pageName;

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
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
                  color: const Color(0xFFFBEAEA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.logout_rounded, color: _C.red, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Ready to leave?',
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
            child: const Text(
              'Confirm Logout',
              style: TextStyle(fontSize: 13, color: _C.text, height: 1.4),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 46),
                foregroundColor: _C.muted,
                side: const BorderSide(color: _C.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const SignInScreen()),
                      (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 46),
                backgroundColor: _C.ink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Yes, Logout', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }

  void _navigateTo(BuildContext context, String pageName) {
    Navigator.of(context).pop(); // Close drawer
    if (_isActive(pageName)) return;

    Widget targetScreen;
    switch (pageName) {
      case 'dashboard.php':
        targetScreen = const DashboardScreen();
        break;
      case 'upload.php':
        targetScreen = const UploadScreen();
        break;
      case 'inbox.php':
        targetScreen = const InboxScreen();
        break;
      case 'chat.php':
        targetScreen = const ChatScreen();
        break;
      case 'docu_list.php':
        targetScreen = const DocuListScreen();
        break;
      case 'track.php':
        targetScreen = const TrackScreen();
        break;
      case 'records.php':
        targetScreen = const RecordsScreen();
        break;
      case 'archive.php':
        targetScreen = const ArchiveScreen();
        break;
      default:
        return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => targetScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: _C.ink,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_C.ink, _C.inkSoft],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                      ),
                      child: const Icon(Icons.description_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                              children: [
                                TextSpan(text: 'Document '),
                                TextSpan(
                                  text: 'Tracker',
                                  style: TextStyle(color: Color(0xFFFACC15)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Secure portal',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
              ),

              // Scrollable Nav List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  children: [
                    _buildNavItem(
                      context,
                      title: 'Dashboard',
                      icon: Icons.grid_view_rounded,
                      pageName: 'dashboard.php',
                    ),
                    _buildNavItem(
                      context,
                      title: 'Inbox',
                      icon: Icons.notifications_outlined,
                      pageName: 'inbox.php',
                      badgeCount: notificationCount,
                    ),
                    _buildNavItem(
                      context,
                      title: 'Chat',
                      icon: Icons.chat_bubble_outline_rounded,
                      pageName: 'chat.php',
                    ),
                    _buildNavItem(
                      context,
                      title: 'Upload File',
                      icon: Icons.file_upload_outlined,
                      pageName: 'upload.php',
                    ),
                    _buildNavItem(
                      context,
                      title: 'DocuList',
                      icon: Icons.article_outlined,
                      pageName: 'docu_list.php',
                    ),
                    _buildNavItem(
                      context,
                      title: 'Track Status',
                      icon: Icons.alt_route_rounded,
                      pageName: 'track.php',
                    ),
                    _buildNavItem(
                      context,
                      title: 'Records',
                      icon: Icons.history_rounded,
                      pageName: 'records.php',
                    ),
                    _buildNavItem(
                      context,
                      title: 'Archive',
                      icon: Icons.archive_outlined,
                      pageName: 'archive.php',
                    ),
                  ],
                ),
              ),

              // Footer Logout
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                child: Material(
                  color: _C.red.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => _confirmLogout(context),
                    borderRadius: BorderRadius.circular(14),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.logout_rounded,
                              color: Color(0xFFFFB4B4), size: 20),
                          SizedBox(width: 12),
                          Text(
                            'Logout',
                            style: TextStyle(
                              color: Color(0xFFFFB4B4),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      BuildContext context, {
        required String title,
        required IconData icon,
        required String pageName,
        int badgeCount = 0,
      }) {
    final bool active = _isActive(pageName);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: active ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _navigateTo(context, pageName),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: active ? _C.blue : Colors.white.withValues(alpha: 0.85),
                  size: 21,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: active ? _C.ink : Colors.white.withValues(alpha: 0.9),
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _C.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}