import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'sidebar.dart';

// --- DESIGN TOKENS (same palette as the dashboard) ---
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
  static const amber = Color(0xFFB7791F);
}

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  String _activeFilter = 'all'; // 'all' | 'overdue' | 'handled' | 'pickup'

  // Dynamic user & office cache to mirror PHP table JOINs
  final Map<String, Future<Map<String, String>>> _uploaderCache = {};

  // Multi-select (long press) for the Handled / Pick-up tabs
  bool _selectionMode = false;
  final Set<String> _selected = {};

  void _setFilter(String f) {
    setState(() {
      _activeFilter = f;
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _startSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selected
        ..clear()
        ..add(id);
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  // Removed from MY lists only; the document itself stays for everyone else
  bool _isHiddenForMe(Map<String, dynamic> d) {
    final h = d['hiddenBy'];
    return h is List && h.contains(_currentUser?.uid);
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    if (count == 0) return;
    final listName = _activeFilter == 'pickup' ? 'Pick-up' : 'Handled';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          'Delete $count ${count == 1 ? 'item' : 'items'}?',
          style: const TextStyle(fontWeight: FontWeight.w800, color: _C.ink),
        ),
        content: Text(
          'They will be removed from your $listName list. The documents themselves are not deleted and still appear in Records.',
          style: const TextStyle(color: _C.muted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _C.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      for (final id in _selected) {
        batch.update(db.collection('documents').doc(id), {
          'hiddenBy': FieldValue.arrayUnion([_currentUser!.uid]),
        });
      }
      await batch.commit();
      _exitSelection();
      _snack('Removed $count ${count == 1 ? 'item' : 'items'}.',
          color: _C.green);
    } catch (e) {
      _snack('Could not delete: $e', color: _C.red);
    }
  }

  String _getTodayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  bool _isOverdue(String? dueDate) {
    if (dueDate == null || dueDate.trim().isEmpty) return false;
    final today = _getTodayString();
    return dueDate.compareTo(today) < 0;
  }

  String? _dueOf(Map<String, dynamic> data) {
    final raw = data['dueDate'] ?? data['due_date'];
    return raw?.toString();
  }

  // e.g. "APPROVED - PICKED UP" (same wording as Records > Logs)
  String _statusLabel(Map<String, dynamic> d) {
    final st = (d['status'] ?? '').toString().toUpperCase();
    if (d['pickedUp'] == true) return '$st - PICKED UP';
    if (d['pickupRequested'] == true) return '$st - PICK-UP REQUESTED';
    return st;
  }

  // True if [uid] is the original sender of this document
  bool _isSenderOf(Map<String, dynamic> d, String uid) {
    return [d['pickupSenderId'], d['senderId'], d['uploaderId'], d['uploader_id']]
        .contains(uid);
  }

  String _formatDue(String dueDate) {
    final parsed = DateTime.tryParse(dueDate);
    if (parsed == null) return dueDate;
    return DateFormat('MMM d').format(parsed);
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

  // --- CLOUDINARY FILE HELPERS ---

  /// Pulls the Cloudinary file URL out of a document, checking a few
  /// likely field names so this keeps working regardless of what your
  /// upload code calls it.
  String? _getFileUrl(Map<String, dynamic> data) {
    final url = data['fileUrl'] ??
        data['cloudinaryUrl'] ??
        data['secure_url'] ??
        data['fileURL'];
    if (url == null) return null;
    final s = url.toString().trim();
    return s.isEmpty ? null : s;
  }

  String _getFileExtension(Map<String, dynamic> data, String url) {
    final explicit = (data['fileExtension'] ?? '').toString().toLowerCase();
    if (explicit.isNotEmpty) return explicit.replaceAll('.', '');
    final clean = url.split('?').first;
    final parts = clean.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  bool _isImageExt(String ext) =>
      ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);

  bool _isPdfExt(String ext) => ext == 'pdf';

  bool _isOfficeExt(String ext) =>
      ['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'].contains(ext);

  String _officeViewerUrl(String fileUrl) {
    final encoded = Uri.encodeComponent(fileUrl);
    return 'https://view.officeapps.live.com/op/embed.aspx?src=$encoded';
  }

  /// Builds a printable/previewable PDF byte stream for a document.
  /// - PDFs are fetched and returned as-is.
  /// - Images are fetched and wrapped into a single-page PDF.
  Future<Uint8List> _buildPdfBytes(String url, String ext) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch file (${response.statusCode})');
    }
    final bytes = response.bodyBytes;

    if (_isPdfExt(ext)) {
      return bytes;
    }

    // Wrap image in a simple one-page PDF so we can preview/print it.
    final image = pw.MemoryImage(bytes);
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (ctx) => pw.Center(
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ),
    );
    return doc.save();
  }

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

  void _showFileError(Object e) {
    _snack('Could not load file: $e', color: _C.red);
  }

  // --- ACTIONS: QUICK VIEW / PRINT / DOWNLOAD ---

  Widget _previewHeader(String title, BuildContext ctx, {Widget? extra}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.description_outlined,
                color: _C.blue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15, color: _C.ink),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (extra != null) extra,
          IconButton(
            icon: const Icon(Icons.close_rounded, color: _C.muted),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  void _quickViewDocument(Map<String, dynamic> data) {
    final url = _getFileUrl(data);
    if (url == null) {
      _snack('No file attached to this document.');
      return;
    }
    final ext = _getFileExtension(data, url);
    final title = (data['title'] ??
        data['document_title'] ??
        data['filename'] ??
        data['fileName'] ??
        'Document')
        .toString();

    // Word / Excel / PowerPoint -> embedded Office Online viewer
    if (_isOfficeExt(ext)) {
      _showWebViewPreview(title, _officeViewerUrl(url), data);
      return;
    }

    // PDFs and images -> PdfPreview (built-in print/share)
    if (_isImageExt(ext) || _isPdfExt(ext)) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(ctx).size.height * 0.85,
            child: Column(
              children: [
                _previewHeader(title, ctx),
                const Divider(height: 1, color: _C.line),
                Expanded(
                  // PdfPreview already ships with its own print & share
                  // (share doubles as "download to device") action buttons.
                  child: PdfPreview(
                    build: (format) => _buildPdfBytes(url, ext),
                    allowPrinting: true,
                    allowSharing: true,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    useActions: true,
                    loadingWidget:
                    const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    // Anything else (zip, txt, etc.) — no in-app preview available
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Preview not available',
            style: TextStyle(fontWeight: FontWeight.w800, color: _C.ink)),
        content: Text(
          'This file type (.$ext) can\'t be previewed in the app. Open it in another app instead?',
          style: const TextStyle(color: _C.muted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _C.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.blue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadDocument(data);
            },
            child: const Text('Open file'),
          ),
        ],
      ),
    );
  }

  void _showWebViewPreview(
      String title, String viewerUrl, Map<String, dynamic> data) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(viewerUrl));

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(ctx).size.height * 0.85,
          child: Column(
            children: [
              _previewHeader(
                title,
                ctx,
                extra: IconButton(
                  icon: const Icon(Icons.download_outlined, color: _C.muted),
                  tooltip: 'Download',
                  onPressed: () => _downloadDocument(data),
                ),
              ),
              const Divider(height: 1, color: _C.line),
              Expanded(child: WebViewWidget(controller: controller)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadDocument(Map<String, dynamic> data) async {
    final url = _getFileUrl(data);
    if (url == null) {
      _snack('No file attached to this document.');
      return;
    }

    try {
      final uri = Uri.parse(url);
      final launched =
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('No app available to open this file');
    } catch (e) {
      _showFileError(e);
    }
  }

  // --- PICK-UP ACTIONS ---

  // Receiver asks the sender to come and pick up the document
  Future<void> _requestPickup(String docId, Map<String, dynamic> data) async {
    try {
      final me = await _getUploaderDetails(_currentUser!.uid, {});
      final originalSender =
          data['uploaderId'] ?? data['uploader_id'] ?? data['senderId'];
      await FirebaseFirestore.instance.collection('documents').doc(docId).update({
        'pickupRequested': true,
        'pickedUp': false,
        'pickupSenderId': originalSender,
        'pickupRequestedBy': _currentUser!.uid,
        'pickupRequestedByName': me['name'],
        'pickupRequestedByOffice': me['office'],
        'pickupRequestedAt': FieldValue.serverTimestamp(),
      });
      _snack('Pick-up requested. The sender has been notified.', color: _C.green);
    } catch (e) {
      _snack('Could not request pick-up: $e', color: _C.red);
    }
  }

  // Sender confirms they physically picked the document up
  Future<void> _confirmPickedUp(String docId) async {
    try {
      await FirebaseFirestore.instance.collection('documents').doc(docId).update({
        'pickedUp': true,
        'pickedUpBy': _currentUser!.uid,
        'pickedUpAt': FieldValue.serverTimestamp(),
      });
      _snack('Marked as picked up.', color: _C.green);
    } catch (e) {
      _snack('Could not update: $e', color: _C.red);
    }
  }

  // --- OTHER ACTIONS ---

  Future<void> _processAction(String docId, String newStatus) async {
    final label = newStatus.isEmpty
        ? newStatus
        : newStatus[0].toUpperCase() + newStatus.substring(1);
    final isApprove = newStatus == 'approved';
    final accent = isApprove ? _C.green : _C.red;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isApprove
                    ? Icons.check_circle_outline_rounded
                    : Icons.cancel_outlined,
                color: accent,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isApprove ? 'Approve this document?' : 'Reject this document?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 18, color: _C.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'It will be marked as ${label.toLowerCase()} and the sender will be notified.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _C.muted, fontSize: 13),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _C.muted,
                    side: const BorderSide(color: _C.line),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(isApprove ? 'Approve' : 'Reject',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.collection('documents').doc(docId).update({
        'status': newStatus,
        'seenBySender': false,
        'handledBy': FieldValue.arrayUnion([_currentUser!.uid]),
        'lastAction': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _snack('Document ${label.toLowerCase()}.', color: accent);
    } catch (e) {
      _snack('Error updating document: $e', color: _C.red);
    }
  }

  Widget _detailBlock(String label, String value) {
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

  void _showDetailsDialog(
      Map<String, dynamic> data, String uploaderName, String senderOffice) {
    final title = data['title'] ??
        data['document_title'] ??
        data['filename'] ??
        data['fileName'] ??
        'Untitled Document';
    final description = (data['description']?.toString().isNotEmpty == true)
        ? data['description'].toString()
        : 'No description provided.';
    final remarks = (data['remarks']?.toString().isNotEmpty == true)
        ? data['remarks'].toString()
        : 'No remarks provided.';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 12, 0),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.description_outlined, color: _C.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title.toString(),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: _C.ink),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: _C.muted),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              _detailBlock('Description', description),
              const SizedBox(height: 14),
              _detailBlock('Remarks', remarks),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded,
                      size: 18, color: _C.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Sender: $uploaderName',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _C.text)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.apartment_rounded,
                      size: 18, color: _C.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Office: $senderOffice',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _C.text)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: _C.muted)),
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (bottomCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 12,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(bottomCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 18),
                    const Text('Forward document',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _C.ink,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 4),
                    const Text(
                        'Choose who receives it next. You can also attach an updated file.',
                        style: TextStyle(fontSize: 13, color: _C.muted)),
                    const SizedBox(height: 20),

                    // Target Office Dropdown (Fetched from Firestore 'offices' collection)
                    _fieldLabel('Target office'),
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
                          isExpanded: true,
                          hint: const Text('Select office'),
                          decoration:
                          _inputDecoration('', icon: Icons.apartment_rounded),
                          items: officeOptions
                              .map((o) => DropdownMenuItem(
                              value: o,
                              child: Text(o, overflow: TextOverflow.ellipsis)))
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
                    const SizedBox(height: 16),

                    // Recipient Dropdown
                    _fieldLabel('Recipient'),
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
                          final uOffice = data['officeName'] ?? data['office'];
                          return uOffice == forwardOffice;
                        }).toList();

                        return DropdownButtonFormField<String>(
                          value: forwardUserId,
                          isExpanded: true,
                          hint: Text(filteredUsers.isEmpty
                              ? 'No recipient found for this office'
                              : 'Select person'),
                          decoration: _inputDecoration('',
                              icon: Icons.person_outline_rounded),
                          items: filteredUsers.map((u) {
                            final data = u.data() as Map<String, dynamic>;
                            final name =
                                data['userName'] ?? data['name'] ?? 'User';
                            return DropdownMenuItem<String>(
                                value: u.id,
                                child: Text(name, overflow: TextOverflow.ellipsis));
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
                    const SizedBox(height: 16),

                    // Remarks
                    _fieldLabel('Forwarding remarks (optional)'),
                    TextField(
                      controller: remarksController,
                      maxLines: 3,
                      decoration: _inputDecoration('Add routing instructions'),
                    ),
                    const SizedBox(height: 16),

                    // Optional Replacement File
                    InkWell(
                      onTap: () async {
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
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: _C.paper,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _C.line),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              newFile == null
                                  ? Icons.attach_file_rounded
                                  : Icons.insert_drive_file_outlined,
                              size: 20,
                              color: _C.blue,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                newFile == null
                                    ? 'Attach an updated file (optional)'
                                    : newFile!.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: newFile == null ? _C.muted : _C.text,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Forward Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.send_rounded, size: 18),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _C.blue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () async {
                          if (forwardUserId == null) {
                            _snack('Please select a recipient to forward.');
                            return;
                          }

                          final updatePayload = <String, dynamic>{
                            'recipientId': forwardUserId,
                            'receiver_user_id': forwardUserId,
                            'recipientName': forwardUserName,
                            'destinationOffice': forwardOffice,
                            'remarks': remarksController.text.trim(),
                            'status': 'pending',
                            'handledBy':
                            FieldValue.arrayUnion([_currentUser!.uid]),
                            'lastAction': 'forwarded',
                            'updatedAt': FieldValue.serverTimestamp(),
                          };

                          // NOTE: You mentioned you're on Cloudinary now — this
                          // still uploads the replacement file as base64 into
                          // Firestore. If you have a Cloudinary upload helper
                          // already, swap this block to call it and store the
                          // returned secure_url in 'fileUrl' instead.
                          if (newFile != null) {
                            final fileBytes = await newFile!.readAsBytes();
                            if (fileBytes.length > 500000) {
                              _snack('File exceeds 500 KB size limit.');
                              return;
                            }
                            updatePayload['fileData'] = base64Encode(fileBytes);
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
                          _snack('Document forwarded.', color: _C.green);
                        },
                        label: const Text('Forward document',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
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

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view inbox.')),
      );
    }

    final currentUserId = _currentUser!.uid;

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _exitSelection();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: _C.paper,
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

                  // Receiver asked me (the sender) to pick up a document
                  if (_isSenderOf(data, currentUserId) &&
                      data['pickupRequested'] == true &&
                      data['pickedUp'] != true) {
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
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('documents').snapshots(),
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final allDocs =
            snapshot.hasData ? snapshot.data!.docs : <QueryDocumentSnapshot>[];
            Map<String, dynamic> m(QueryDocumentSnapshot d) =>
                d.data() as Map<String, dynamic>;

            // Match backend logic: receiver_user_id == user_id AND status == 'pending' AND is_archived == FALSE
            final pendingDocs = allDocs.where((d) {
              final data = m(d);
              final recipientId = data['recipientId'] ?? data['receiver_user_id'];
              final status = (data['status'] ?? '').toString().toLowerCase();
              return recipientId == currentUserId &&
                  status == 'pending' &&
                  data['isArchived'] != true;
            }).toList();

            final overdueDocs =
            pendingDocs.where((d) => _isOverdue(_dueOf(m(d)))).toList();

            // Docs I already approved / rejected / forwarded
            final handledDocs = allDocs.where((d) {
              final data = m(d);
              if (data['isArchived'] == true) return false;
              if (_isHiddenForMe(data)) return false;
              final by = data['handledBy'];
              final viaField = by is List && by.contains(currentUserId);
              final recipientId = data['recipientId'] ?? data['receiver_user_id'];
              final status = (data['status'] ?? '').toString().toLowerCase();
              final viaStatus = recipientId == currentUserId &&
                  (status == 'approved' || status == 'rejected');
              return viaField || viaStatus;
            }).toList();

            // Docs where a receiver asked ME (the sender) to pick up
            final pickupDocs = allDocs.where((d) {
              final data = m(d);
              return _isSenderOf(data, currentUserId) &&
                  data['pickupRequested'] == true &&
                  !_isHiddenForMe(data) &&
                  data['isArchived'] != true;
            }).toList();

            List<QueryDocumentSnapshot> source;
            switch (_activeFilter) {
              case 'overdue':
                source = overdueDocs;
                break;
              case 'handled':
                source = handledDocs;
                break;
              case 'pickup':
                source = pickupDocs;
                break;
              default:
                source = pendingDocs;
            }
            final docs = List<QueryDocumentSnapshot>.from(source);

            // Order by updatedAt DESC
            docs.sort((a, b) {
              final aTime = (m(a)['updatedAt'] ?? m(a)['createdAt']) as Timestamp?;
              final bTime = (m(b)['updatedAt'] ?? m(b)['createdAt']) as Timestamp?;
              if (aTime == null || bTime == null) return 0;
              return bTime.compareTo(aTime);
            });

            return Column(
              children: [
                _buildHeader(
                  pendingDocs.length,
                  overdueDocs.length,
                  handledDocs.length,
                  // tab badge counts only requests still waiting for pick-up
                  pickupDocs.where((d) => m(d)['pickedUp'] != true).length,
                  docs.map((d) => d.id).toList(),
                ),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : docs.isEmpty
                      ? _buildEmptyState()
                      : _buildList(docs),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------- HEADER ----------

  Widget _buildHeader(int total, int overdue, int handled, int pickup,
      List<String> visibleIds) {
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
          if (_selectionMode) _selectionBar(visibleIds) else Row(
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
                      'Inbox',
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
                      total == 0
                          ? 'Nothing waiting for review'
                          : total == 1
                          ? '1 document waiting for review'
                          : '$total documents waiting for review',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Filter tabs (four tabs share the width and scale down to fit)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                _filterTab(
                  label: 'All',
                  count: total,
                  selected: _activeFilter == 'all',
                  onTap: () => _setFilter('all'),
                ),
                _filterTab(
                  label: 'Overdue',
                  count: overdue,
                  selected: _activeFilter == 'overdue',
                  danger: true,
                  onTap: () => _setFilter('overdue'),
                ),
                _filterTab(
                  label: 'Handled',
                  count: handled,
                  selected: _activeFilter == 'handled',
                  onTap: () => _setFilter('handled'),
                ),
                _filterTab(
                  label: 'Pick-up',
                  count: pickup,
                  selected: _activeFilter == 'pickup',
                  onTap: () => _setFilter('pickup'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar(List<String> visibleIds) {
    final allSelected =
        visibleIds.isNotEmpty && visibleIds.every(_selected.contains);

    return Row(
      children: [
        InkWell(
          onTap: _exitSelection,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: const Icon(Icons.close_rounded,
                color: Colors.white, size: 22),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            '${_selected.length} selected',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            if (allSelected) {
              _selected.clear();
            } else {
              _selected
                ..clear()
                ..addAll(visibleIds);
            }
          }),
          child: Text(
            allSelected ? 'Deselect all' : 'Select all',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: _selected.isEmpty ? null : _deleteSelected,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _C.red.withValues(alpha: _selected.isEmpty ? 0.35 : 0.9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: Colors.white, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _filterTab({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final Color selectedText = danger ? _C.red : _C.ink;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (danger) ...[
                  Icon(
                    Icons.schedule_rounded,
                    size: 15,
                    color: selected
                        ? selectedText
                        : Colors.white.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? selectedText
                        : Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: selected
                        ? selectedText.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: selected ? selectedText : Colors.white,
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

  // ---------- LIST ----------

  Widget _buildEmptyState() {
    final f = _activeFilter;
    final overdueView = f == 'overdue';

    final title = f == 'overdue'
        ? 'Nothing is overdue'
        : f == 'handled'
        ? 'No handled documents yet'
        : f == 'pickup'
        ? 'No pick-up requests'
        : 'Your inbox is clear';
    final sub = f == 'overdue'
        ? 'All your pending documents are within their due dates.'
        : f == 'handled'
        ? 'Documents you approve, reject or forward appear here.'
        : f == 'pickup'
        ? 'When a receiver asks you to pick up a document, it shows here.'
        : 'New documents sent to you will show up here.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: overdueView
                    ? const Color(0xFFE6F5EE)
                    : const Color(0xFFE8F0FE),
                shape: BoxShape.circle,
              ),
              child: Icon(
                overdueView
                    ? Icons.task_alt_rounded
                    : Icons.mark_email_read_outlined,
                color: overdueView ? _C.green : _C.blue,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _C.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _C.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<QueryDocumentSnapshot> docs) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data() as Map<String, dynamic>;
        final uploaderId =
        (data['uploaderId'] ?? data['senderId'] ?? data['uploader_id'])
        as String?;

        return FutureBuilder<Map<String, String>>(
          future: _getUploaderDetails(uploaderId, data),
          builder: (context, detailsSnapshot) {
            var uploaderName = detailsSnapshot.data?['name'] ??
                data['senderName'] ??
                'Loading...';
            var senderOffice = detailsSnapshot.data?['office'] ??
                data['destinationOffice'] ??
                'General Office';

            // In the Pick-up tab show WHO is waiting for the sender
            if (_activeFilter == 'pickup') {
              uploaderName = data['pickupRequestedByName'] ?? 'Receiver';
              senderOffice = data['pickupRequestedByOffice'] ?? '';
            }

            return _buildDocCard(doc.id, data, uploaderName.toString(),
                senderOffice.toString());
          },
        );
      },
    );
  }

  Widget _buildDocCard(String docId, Map<String, dynamic> data,
      String uploaderName, String senderOffice) {
    final title = (data['title'] ??
        data['document_title'] ??
        data['filename'] ??
        data['fileName'] ??
        'Untitled Document')
        .toString();
    final dueDate = _dueOf(data);
    // Overdue styling only applies to pending cards
    final late = (_activeFilter == 'all' || _activeFilter == 'overdue') &&
        _isOverdue(dueDate);
    final description = data['description']?.toString() ?? '';
    final accent = late ? _C.red : _C.blue;

    // Long press to select is only available in Handled / Pick-up
    final canSelect = _activeFilter == 'handled' || _activeFilter == 'pickup';
    final selecting = _selectionMode && canSelect;
    final isSelected = _selected.contains(docId);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress:
      canSelect && !_selectionMode ? () => _startSelection(docId) : null,
      onTap: selecting ? () => _toggleSelect(docId) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? _C.blue
                : (late ? const Color(0xFFF3C4C4) : _C.line),
            width: isSelected ? 1.6 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Selection check mark (left side)
              if (selecting)
                Container(
                  width: 46,
                  color: isSelected ? const Color(0xFFE8F0FE) : _C.paper,
                  alignment: Alignment.center,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? _C.blue : Colors.white,
                      border: Border.all(
                          color: isSelected ? _C.blue : _C.faint, width: 1.6),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check_rounded,
                        size: 16, color: Colors.white)
                        : null,
                  ),
                ),
              // Status rail
              Container(width: 5, color: accent),
              Expanded(
                child: IgnorePointer(
                  ignoring: selecting,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sender row
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 19,
                              backgroundColor: const Color(0xFFE8F0FE),
                              child: Text(
                                uploaderName.isNotEmpty
                                    ? uploaderName[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, color: _C.blue),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    uploaderName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: _C.text,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    senderOffice,
                                    style: const TextStyle(
                                        fontSize: 12, color: _C.muted),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (late)
                              _dueChip('Overdue', _C.red, const Color(0xFFFBEAEA))
                            else if (dueDate != null && dueDate.isNotEmpty)
                              _dueChip('Due ${_formatDue(dueDate)}', _C.muted,
                                  _C.paper),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Title + description
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: _C.ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, color: _C.muted, height: 1.4),
                          ),
                        ],
                        const SizedBox(height: 12),

                        // Utility actions
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _utilityChip(
                              icon: Icons.info_outline_rounded,
                              label: 'Details',
                              onTap: () =>
                                  _showDetailsDialog(data, uploaderName, senderOffice),
                            ),
                            _utilityChip(
                              icon: Icons.visibility_outlined,
                              label: 'Preview',
                              onTap: () => _quickViewDocument(data),
                            ),
                            _utilityChip(
                              icon: Icons.download_outlined,
                              label: 'Download',
                              onTap: () => _downloadDocument(data),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Footer: decisions / pick-up (depends on the active tab)
                        ..._buildFooter(docId, data),
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

  List<Widget> _buildFooter(String docId, Map<String, dynamic> data) {
    final requested = data['pickupRequested'] == true;
    final pickedUp = data['pickedUp'] == true;

    // SENDER: confirm pick-up
    if (_activeFilter == 'pickup') {
      return [
        Text('Status: ${_statusLabel(data)}',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: pickedUp ? _C.green : _C.muted)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: _decisionButton(
            icon: pickedUp
                ? Icons.check_circle_outline_rounded
                : Icons.inventory_2_outlined,
            label: pickedUp ? 'Already picked up' : 'Picked up',
            color: _C.green,
            filled: !pickedUp,
            onTap: pickedUp ? null : () => _confirmPickedUp(docId),
          ),
        ),
      ];
    }

    // RECEIVER: request pick-up after acting
    if (_activeFilter == 'handled') {
      return [
        Text('Status: ${_statusLabel(data)}',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: pickedUp ? _C.green : _C.muted)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: _decisionButton(
            icon: pickedUp
                ? Icons.check_circle_outline_rounded
                : Icons.inventory_2_outlined,
            label: pickedUp
                ? 'Picked up by sender'
                : requested
                ? 'Pick-up requested'
                : 'Request pick up',
            color: _C.blue,
            filled: !requested && !pickedUp,
            onTap: (requested || pickedUp)
                ? null
                : () => _requestPickup(docId, data),
          ),
        ),
      ];
    }

    // PENDING: decisions + locked pick-up button
    return [
      const Divider(height: 1, color: _C.line),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: _decisionButton(
              icon: Icons.close_rounded,
              label: 'Reject',
              color: _C.red,
              onTap: () => _processAction(docId, 'rejected'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _decisionButton(
              icon: Icons.send_rounded,
              label: 'Forward',
              color: _C.blue,
              onTap: () => _openForwardModal(docId),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _decisionButton(
              icon: Icons.check_rounded,
              label: 'Approve',
              color: _C.green,
              filled: true,
              onTap: () => _processAction(docId, 'approved'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: _decisionButton(
          icon: Icons.lock_outline_rounded,
          label: 'Request pick up (after action)',
          color: _C.blue,
          onTap: null, // disabled until an action is taken
        ),
      ),
    ];
  }

  Widget _dueChip(String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _utilityChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _C.paper,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: _C.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _C.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _decisionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool filled = false,
  }) {
    return SizedBox(
      height: 44,
      child: filled
          ? ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          textStyle:
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      )
          : OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.35)),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          textStyle:
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, {IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _C.faint, fontSize: 14),
      prefixIcon: icon != null ? Icon(icon, size: 20, color: _C.faint) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      fillColor: _C.paper,
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