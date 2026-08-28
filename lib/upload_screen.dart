import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'sidebar.dart';

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

  final List<String> _offices = [
    'College of Engineering',
    'College of Arts & Sciences',
    'Human Resource Management',
    'Finance & Accounting',
    'Registrar Office',
    'IT & Technical Support',
  ];

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
              primary: Color(0xFF2563EB),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a document to upload.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be signed in to upload a document.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final fileName = _pickedFile!.name;
      final fileBytes = await _pickedFile!.readAsBytes();

      if (fileBytes.length > 500000) {
        throw Exception(
          'File exceeds 500 KB size limit. Please choose a smaller file.',
        );
      }
      final fileDataBase64 = base64Encode(fileBytes);
      final fileExtension = _pickedFile!.extension;

      // Fetch sender name from profile
      final senderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final senderData = senderDoc.data();
      final senderName = senderData?['name'] ?? senderData?['userName'] ?? 'Unknown Sender';

      // 1. Create main document with unified senderId & uploaderId
      final docRef = await FirebaseFirestore.instance.collection('documents').add({
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
        'fileData': fileDataBase64,
        'fileExtension': fileExtension,
        'seenBySender': false,
        'remarks': 'Document submitted for routing.',
        'isArchived': false,
        'dueDate': _dueDateController.text.isNotEmpty ? _dueDateController.text : null,
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 56),
            title: const Text(
              'Success!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            content: Text(
              'Document "${_titleController.text}" sent for routing.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _resetForm();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const Sidebar(currentPage: 'upload.php'),
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
                  const Text(
                    'Upload Document',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      )
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Upload & Send Document',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Fill in the details below to start the document routing process.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
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
                        DropdownButtonFormField<String>(
                          key: Key('office_$_selectedOffice'),
                          initialValue: _selectedOffice,
                          hint: const Text('Select Office...'),
                          decoration: _inputDecoration(''),
                          items: _offices.map((office) {
                            return DropdownMenuItem<String>(
                              value: office,
                              child: Text(office),
                            );
                          }).toList(),
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
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
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
                                return const LinearProgressIndicator();
                              }
                              if (snapshot.hasError) {
                                return Text(
                                  'Error loading users: ${snapshot.error}',
                                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
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
                                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                  ),
                                );
                              }

                              return DropdownButtonFormField<String>(
                                key: Key('user_$_selectedUserId'),
                                initialValue: _selectedUserId,
                                hint: const Text('Select Recipient...'),
                                decoration: _inputDecoration(''),
                                items: userDocs.map((u) {
                                  final data = u.data() as Map<String, dynamic>;
                                  final name = data['name'] ?? data['userName'] ?? 'User';
                                  return DropdownMenuItem<String>(
                                    value: u.id,
                                    child: Text(name),
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
                            suffixIcon: const Icon(Icons.calendar_today, color: Color(0xFF2563EB), size: 20),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // File Attachment Zone
                        _buildLabel('Attach Document *'),
                        InkWell(
                          onTap: _isSubmitting ? null : _pickFile,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _pickedFile != null
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFFCBD5E1),
                                width: 2,
                              ),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 40,
                                  color: Color(0xFF2563EB),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Click to Select Document',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Supports PDF, DOC, DOCX, JPG, PNG (max 500 KB)',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                ),
                                if (_pickedFile != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDBEAFE),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.insert_drive_file, color: Color(0xFF2563EB), size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          _pickedFile!.name,
                                          style: const TextStyle(
                                            color: Color(0xFF1E40AF),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
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
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                                : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            label: Text(
                              _isSubmitting ? 'Submitting...' : 'Submit for Routing',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
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
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      fillColor: Colors.white,
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF475569), width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF475569), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
    );
  }
}