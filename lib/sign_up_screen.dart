import 'package:flutter/material.dart';
import 'sign_in_screen.dart';
import 'services/auth_service.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _fullNameController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _positionController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _selectedOffice;
  bool _isPasswordHidden = true;
  bool _isConfirmPasswordHidden = true;
  bool _isLoading = false;

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
    _fullNameController.dispose();
    _employeeIdController.dispose();
    _emailController.dispose();
    _positionController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedOffice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an office or department')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final error = await _authService.signUp(
      employeeNumber: _employeeIdController.text.trim(),
      name: _fullNameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      position: _positionController.text.trim(),
      officeName: _selectedOffice!,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Account Created! Redirecting to Sign In...'),
        backgroundColor: Color(0xFF10B981),
      ),
    );

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SignInScreen()),
      );
    });
  }

  void _navigateToSignIn() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const SignInScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4F46E5), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Column(
                children: [
                  // App Header Logo
                  Container(
                    width: 84,
                    height: 84,
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/logo.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Document Tracker',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Create an account to get started',
                    style: TextStyle(fontSize: 14, color: Color(0xE6FFFFFF)),
                  ),
                  const SizedBox(height: 20),

                  Card(
                    elevation: 10,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    color: const Color(0xF5FFFFFF),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const FormSectionHeader(title: 'Personal Information'),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _fullNameController,
                              label: 'Full Name',
                              hint: 'e.g. John Doe',
                              icon: Icons.person_outline,
                              validator: (val) => val == null || val.trim().isEmpty ? 'Enter your full name' : null,
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _employeeIdController,
                              label: 'Employee ID',
                              hint: 'e.g. EMP-2026-001',
                              icon: Icons.badge_outlined,
                              validator: (val) => val == null || val.trim().isEmpty ? 'Enter employee ID' : null,
                            ),

                            const SizedBox(height: 18),

                            const FormSectionHeader(title: 'Work Details'),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _emailController,
                              label: 'Email Address',
                              hint: 'user@organization.com',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Enter email address';
                                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
                                  return 'Enter a valid email address';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _positionController,
                              label: 'Position / Role',
                              hint: 'e.g. Staff Officer',
                              icon: Icons.work_outline,
                              validator: (val) => val == null || val.trim().isEmpty ? 'Enter position' : null,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _selectedOffice,
                              decoration: _inputDecoration('Office / Department', Icons.business_outlined, 'Select department'),
                              items: _offices.map((office) {
                                return DropdownMenuItem(
                                  value: office,
                                  child: Text(office, style: const TextStyle(fontSize: 14)),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _selectedOffice = val),
                              validator: (val) => val == null ? 'Select an office' : null,
                            ),

                            const SizedBox(height: 18),

                            const FormSectionHeader(title: 'Security'),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _isPasswordHidden,
                              decoration: _inputDecoration('Password', Icons.lock_outline, 'Min. 6 characters').copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isPasswordHidden ? Icons.visibility_off : Icons.visibility,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () => setState(() => _isPasswordHidden = !_isPasswordHidden),
                                ),
                              ),
                              validator: (val) {
                                if (val == null || val.isEmpty) return 'Enter password';
                                if (val.length < 6) return 'Password must be at least 6 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: _isConfirmPasswordHidden,
                              decoration: _inputDecoration('Confirm Password', Icons.lock_reset, 'Re-type password').copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isConfirmPasswordHidden ? Icons.visibility_off : Icons.visibility,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () => setState(() => _isConfirmPasswordHidden = !_isConfirmPasswordHidden),
                                ),
                              ),
                              validator: (val) {
                                if (val != _passwordController.text) return 'Passwords do not match';
                                return null;
                              },
                            ),

                            const SizedBox(height: 22),

                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleSignUp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 2,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                    : const Text(
                                  'Sign Up',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Already have an account? ', style: TextStyle(color: Colors.white70)),
                      GestureDetector(
                        onTap: _navigateToSignIn,
                        child: const Text(
                          'Sign In',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: _inputDecoration(label, icon, hint),
      validator: validator,
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.grey[600]),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
      ),
    );
  }
}

class FormSectionHeader extends StatelessWidget {
  final String title;
  const FormSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
      ],
    );
  }
}