import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
  }) async {
    await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      await _auth.signInWithPopup(provider);
      return;
    }

    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      // User cancelled the sign-in flow.
      return;
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {
        // Ignore GoogleSignIn signOut errors; Firebase signOut still proceeds.
      }
    }
    await _auth.signOut();
  }

  static String friendlyErrorMessage(Object error) {
    if (error is FirebaseAuthException) {
      final code = error.code.toLowerCase();

      switch (code) {
        case 'invalid-email':
        case 'auth/invalid-email':
          return 'Email không hợp lệ.';
        case 'user-not-found':
        case 'auth/user-not-found':
          return 'Không tìm thấy tài khoản với email này.';
        case 'wrong-password':
        case 'auth/wrong-password':
          return 'Mật khẩu không đúng.';
        case 'invalid-credential':
        case 'auth/invalid-credential':
          return 'Thông tin đăng nhập không đúng.';
        case 'user-disabled':
        case 'auth/user-disabled':
          return 'Tài khoản đã bị vô hiệu hóa.';
        case 'email-already-in-use':
        case 'auth/email-already-in-use':
          return 'Email này đã được đăng ký.';
        case 'weak-password':
        case 'auth/weak-password':
          return 'Mật khẩu quá yếu (tối thiểu 6 ký tự).';
        case 'operation-not-allowed':
        case 'auth/operation-not-allowed':
          return 'Email/Password chưa được bật trong Firebase Console.';
        case 'too-many-requests':
        case 'auth/too-many-requests':
          return 'Thử lại sau (quá nhiều yêu cầu).';
        case 'network-request-failed':
        case 'auth/network-request-failed':
          return 'Lỗi mạng, vui lòng kiểm tra kết nối.';
        case 'popup-closed-by-user':
        case 'auth/popup-closed-by-user':
          return 'Đã hủy đăng nhập Google.';
        default:
          return 'Lỗi đăng nhập: ${error.message ?? error.code}';
      }
    }

    final msg = error.toString().toLowerCase();
    if (msg.contains('sign_in_canceled') ||
        msg.contains('sign in canceled') ||
        msg.contains('canceled')) {
      return 'Đã hủy đăng nhập.';
    }

    return 'Có lỗi xảy ra: $error';
  }
}
