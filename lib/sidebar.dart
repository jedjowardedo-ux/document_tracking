import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'upload_screen.dart';
import 'sign_in_screen.dart';
import 'inbox_screen.dart';
import 'track_screen.dart';
import 'docu_list_screen.dart'; // Make sure to create or import your DocuListScreen file

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Ready to leave?'),
          content: const Text('Confirm Logout'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
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
                backgroundColor: const Color(0xFF1E40AF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Yes, Logout'),
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
      case 'docu_list.php':
        targetScreen = const DocuListScreen();
        break;
      case 'track.php':
        targetScreen = const TrackScreen();
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
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const CircleAvatar(
                        backgroundColor: Color(0xFF2563EB),
                        child: Icon(Icons.description, color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: const TextSpan(
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            children: [
                              TextSpan(text: 'Document '),
                              TextSpan(
                                text: 'Tracker',
                                style: TextStyle(color: Color(0xFFFACC15)),
                              ),
                            ],
                          ),
                        ),
                        const Text(
                          'SECURE PORTAL',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFBFDBFE),
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),

              // Scrollable Nav List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
              const Divider(color: Colors.white24, height: 1),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: InkWell(
                  onTap: () => _confirmLogout(context),
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                    child: Row(
                      children: [
                        Icon(Icons.logout, color: Color(0xFFFCA5A5), size: 20),
                        SizedBox(width: 12),
                        Text(
                          'Logout',
                          style: TextStyle(
                            color: Color(0xFFFCA5A5),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
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

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: active ? Colors.white.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: active ? Border.all(color: Colors.white.withOpacity(0.25)) : null,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        dense: true,
        leading: Icon(icon, color: Colors.white, size: 20),
        title: Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        trailing: badgeCount > 0
            ? Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$badgeCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        )
            : null,
        onTap: () => _navigateTo(context, pageName),
      ),
    );
  }
}