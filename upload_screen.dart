import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'sidebar.dart';
import 'office_service.dart';

// Cloudinary config — cloud name + unsigned preset from the console.
final _cloudinary = CloudinaryPublic('nikh0hne', 'document_tracking_uploads', cache: false);

// --- DESIGN TOKENS (same palette as the other screens) ---
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
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _dueDateController = TextEditingController();

  String? _selectedOffice;
  String? _selectedUserId;
  String? _selectedUserName;
  PlatformFile? _pickedFile;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _dueDateController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final year = date.year;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  // Floating, rounded snackbar (styling only)
  void _errorSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _C.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _C.blue,
              onPrimary: Colors.white,
              onSurface: _C.ink,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dueDateController.text = _formatDate(picked);
      });
    }
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
    );

    if (files.isNotEmpty) {
      setState(() {
        _pickedFile = files.first;
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_pickedFile == null) {
      _errorSnack('Please select a document to upload.');
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _errorSnack('You must be signed in to upload a document.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final fileName = _pickedFile!.name;
      final fileExtension = _pickedFile!.extension;
      final fileBytes = await _pickedFile!.readAsBytes();

      // Upload the actual file to Cloudinary (raw = works for pdf/doc/docx too,
      // not just images) and get back a public URL instead of embedding base64
      // data directly into the Firestore document.
      final cloudinaryResponse = await _cloudinary.uploadFile(
        CloudinaryFile.fromBytesData(
          fileBytes,
          identifier: fileName,
          resourceType: CloudinaryResourceType.Raw,
        ),
      );
      final fileUrl = cloudinaryResponse.secureUrl;

      // Fetch sender name from profile
      final senderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final senderData = senderDoc.data();
      final senderName = senderData?['name'] ?? senderData?['userName'] ?? 'Unknown Sender';

      // 1. Create main document with the next document number.
      //    The counter is read, incremented and the document created in ONE
      //    transaction, so numbers stay ascending with no duplicates even if
      //    two people upload at the same time.
      final db = FirebaseFirestore.instance;
      final counterRef = db.collection('counters').doc('documents');
      final docRef = db.collection('documents').doc(); // id created up front

      await db.runTransaction((tx) async {
        final counterSnap = await tx.get(counterRef);
        final next = ((counterSnap.data()?['last'] as num?)?.toInt() ?? 0) + 1;

        tx.set(counterRef, {'last': next});
        tx.set(docRef, {
          'docNumber': next, // 1, 2, 3...
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'uploaderId': currentUser.uid,
          'senderId': currentUser.uid, // Required by TrackScreen filter
          'senderName': senderName,
          'recipientId': _selectedUserId,
          'recipientName': _selectedUserName,
          'destinationOffice': _selectedOffice,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'fileName': fileName,
          'fileUrl': fileUrl,
          'fileExtension': fileExtension,
          'seenBySender': false,
          'remarks': 'Document submitted for routing.',
          'isArchived': false,
          'dueDate': _dueDateController.text.isNotEmpty ? _dueDateController.text : null,
        });
      });

      // 2. Add history node formatted for TrackScreen reading
      await docRef.collection('history').add({
        'senderId': currentUser.uid,
        'recipientId': _selectedUserId,         // Matches TrackScreen schema
        'destinationOffice': _selectedOffice,   // Matches TrackScreen schema
        'status': 'pending',
        'remarks': 'Document submitted for routing.',
        'fileName': fileName,
        'movedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE6F5EE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: _C.green, size: 38),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Success!',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: _C.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Document "${_titleController.text}" sent for routing.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _C.muted, fontSize: 13, height: 1.4),
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _resetForm();
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: _C.ink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _errorSnack('Upload failed: $e');
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _titleController.clear();
    _descriptionController.clear();
    _dueDateController.clear();
    setState(() {
      _selectedOffice = null;
      _selectedUserId = null;
      _selectedUserName = null;
      _pickedFile = null;
    });
  }

  Widget _buildHeader() {
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 22),
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
      child: Row(
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
                  'Upload Document',
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
                  'Send a file to another office for routing',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _C.paper,
      drawer: const Sidebar(currentPage: 'upload.php'),
      body: Column(
        children: [
          _buildHeader(),

          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _C.line),
                ),
                child: Form(
                  key: _formKey,
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
                              color: const Color(0xFFE8F0FE),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(Icons.upload_file_rounded,
                                color: _C.blue, size: 24),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Upload & Send Document',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: _C.ink,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Fill in the details below to start the document routing process.',
                                  style: TextStyle(
                                      fontSize: 12.5, color: _C.muted, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Title
                      _buildLabel('Document Title *'),
                      TextFormField(
                        controller: _titleController,
                        decoration: _inputDecoration('e.g. Budget Proposal 2026'),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Document title is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Description
                      _buildLabel('Description / Purpose (Optional)'),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        decoration: _inputDecoration('Briefly describe the document contents...'),
                      ),
                      const SizedBox(height: 16),

                      // Destination Office
                      _buildLabel('Destination Office *'),
                      OfficeDropdownField(
                        value: _selectedOffice,
                        hint: 'Select Office...',
                        decoration: _inputDecoration(''),
                        onChanged: (val) {
                          setState(() {
                            _selectedOffice = val;
                            _selectedUserId = null;
                            _selectedUserName = null;
                          });
                        },
                        validator: (val) => val == null ? 'Please select an office' : null,
                      ),
                      const SizedBox(height: 16),

                      // Specific Recipient
                      _buildLabel('Specific Recipient *'),
                      if (_selectedOffice == null)
                        InputDecorator(
                          decoration: _inputDecoration(''),
                          child: const Text(
                            'Select an office first...',
                            style: TextStyle(color: _C.faint, fontSize: 13),
                          ),
                        )
                      else
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              .where('officeName', isEqualTo: _selectedOffice)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: const LinearProgressIndicator(
                                  minHeight: 4,
                                  backgroundColor: _C.line,
                                  color: _C.blue,
                                ),
                              );
                            }
                            if (snapshot.hasError) {
                              return Text(
                                'Error loading users: ${snapshot.error}',
                                style: const TextStyle(color: _C.red, fontSize: 12),
                              );
                            }

                            final userDocs = (snapshot.data?.docs ?? [])
                                .where((u) => u.id != currentUid)
                                .toList();

                            if (userDocs.isEmpty) {
                              return InputDecorator(
                                decoration: _inputDecoration(''),
                                child: const Text(
                                  'No registered users in this office yet.',
                                  style: TextStyle(color: _C.faint, fontSize: 13),
                                ),
                              );
                            }

                            return DropdownButtonFormField<String>(
                              key: Key('user_$_selectedUserId'),
                              initialValue: _selectedUserId,
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                                  color: _C.muted),
                              hint: const Text('Select Recipient...',
                                  style: TextStyle(color: _C.faint, fontSize: 13)),
                              decoration: _inputDecoration(''),
                              items: userDocs.map((u) {
                                final data = u.data() as Map<String, dynamic>;
                                final name = data['name'] ?? data['userName'] ?? 'User';
                                return DropdownMenuItem<String>(
                                  value: u.id,
                                  child: Text(name,
                                      style: const TextStyle(fontSize: 14, color: _C.text)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                final match = userDocs.firstWhere((u) => u.id == val);
                                final data = match.data() as Map<String, dynamic>;
                                setState(() {
                                  _selectedUserId = val;
                                  _selectedUserName = data['name'] ?? data['userName'] ?? 'User';
                                });
                              },
                              validator: (val) => val == null ? 'Please select a recipient' : null,
                            );
                          },
                        ),
                      const SizedBox(height: 16),

                      // Deadline Date Picker
                      _buildLabel('Deadline (Optional)'),
                      TextFormField(
                        controller: _dueDateController,
                        readOnly: true,
                        onTap: _pickDate,
                        decoration: _inputDecoration('YYYY-MM-DD').copyWith(
                          suffixIcon: const Icon(Icons.calendar_today_outlined,
                              color: _C.blue, size: 20),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // File Attachment Zone
                      _buildLabel('Attach Document *'),
                      InkWell(
                        onTap: _isSubmitting ? null : _pickFile,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          decoration: BoxDecoration(
                            color: _pickedFile != null
                                ? const Color(0xFFF1F6FE)
                                : _C.paper,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _pickedFile != null
                                  ? const Color(0xFFCFE0FB)
                                  : _C.line,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE8F0FE),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 28,
                                  color: _C.blue,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Click to Select Document',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _C.ink,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Supports PDF, DOC, DOCX, JPG, PNG',
                                style: TextStyle(fontSize: 11, color: _C.faint),
                              ),
                              if (_pickedFile != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE6F5EE),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle_outline_rounded,
                                          color: _C.green, size: 16),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          _pickedFile!.name,
                                          style: const TextStyle(
                                            color: _C.green,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _submitForm,
                          icon: _isSubmitting
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                              : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                          label: Text(
                            _isSubmitting ? 'Submitting...' : 'Submit for Routing',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _C.ink,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _C.ink.withValues(alpha: 0.7),
                            disabledForegroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
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
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _C.muted,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _C.faint, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      fillColor: _C.paper,
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _C.blue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _C.red, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _C.red, width: 1.5),
      ),
    );
  }
}