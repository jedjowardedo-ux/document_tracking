import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<String?> signUp({
    required String employeeNumber,
    required String name,
    required String email,
    required String password,
    required String position,
    required String officeName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user!.uid;
      await _firestore.collection('users').doc(uid).set({
        'employeeNumber': employeeNumber,
        'name': name,
        'email': email,
        'position': position,
        'officeName': officeName,
        'profilePixUrl': '',
        'signaturePathUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Sign up failed';
    }
  }

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Sign in failed';
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}