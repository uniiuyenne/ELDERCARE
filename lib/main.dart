import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      if (kIsWeb) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } else {
        await Firebase.initializeApp();
      }
    }
  } catch (e) {
    final msg = e.toString().toLowerCase();
    if (!msg.contains('duplicate-app')) {
      rethrow;
    }
  }
  // Disable app verification for development/testing with test phone numbers
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    await FirebaseAuth.instance.setSettings(
      appVerificationDisabledForTesting: true,
    );
    debugPrint('Firebase Auth test mode enabled (no real SMS, using test phone numbers only)');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CareElder',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const CareElderScreen(),
    );
  }
}

class CareElderScreen extends StatefulWidget {
  const CareElderScreen({super.key});

  @override
  State<CareElderScreen> createState() => _CareElderScreenState();
}

class _CareElderScreenState extends State<CareElderScreen> with TickerProviderStateMixin {
  static const String _cacheNamespace = 'cache.profile';

  int _step = 0; // 0: Login, 1: Phone input, 2: Role/Linking, 3: Done
  String? _role; // 'child' or 'parent'
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _userPhoneController = TextEditingController();
  final TextEditingController _parentPhoneController = TextEditingController();
  final TextEditingController _childPhoneController = TextEditingController();
  bool _isLoading = false;
  bool _isRestoringSession = false;
  bool _isNavigatingToRoleHome = false;
  bool _phoneLocked = false;
  String _serverPhone = '';

  late AnimationController _animationController;
  StreamSubscription<User?>? _authSub;
  String? _lastAuthUid;

  String _cacheKey(String uid, String field) => '$_cacheNamespace.$uid.$field';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _animationController.forward();

    _restoreCachedProfile();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      if (user != null) {
        if (_lastAuthUid != null && _lastAuthUid != user.uid) {
          _emailController.clear();
          _passwordController.clear();
          _userPhoneController.clear();
          _parentPhoneController.clear();
          _childPhoneController.clear();
          _role = null;
          setState(() => _step = 1);
        }
        _lastAuthUid = user.uid;
        _restoreCachedProfile();
        _restoreSession();
      } else {
        _lastAuthUid = null;
        _isNavigatingToRoleHome = false;
        setState(() => _step = 0);
      }
    });

    if (kIsWeb) {
      _checkRedirectResult();
    }
  }

  Future<void> _restoreCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final cachedPhone = prefs.getString(_cacheKey(uid, 'phone')) ?? '';
    final cachedRole = prefs.getString(_cacheKey(uid, 'role')) ?? '';
    final cachedParentPhone = prefs.getString(_cacheKey(uid, 'parentPhone')) ?? '';
    final cachedChildPhone = prefs.getString(_cacheKey(uid, 'childPhone')) ?? '';
    final cachedLinkedDone = prefs.getBool(_cacheKey(uid, 'linkedDone')) ?? false;

    if (!mounted) return;
    if (cachedPhone.isEmpty && cachedRole.isEmpty && cachedParentPhone.isEmpty && cachedChildPhone.isEmpty) {
      return;
    }

    var shouldNavigate = false;
    var roleToNavigate = '';
    setState(() {
      _userPhoneController.text = cachedPhone;
      _role = cachedRole;
      _parentPhoneController.text = cachedParentPhone;
      _childPhoneController.text = cachedChildPhone;

      if (_isProfileCompleted(
        role: _role,
        phone: _userPhoneController.text,
        parentPhone: _parentPhoneController.text,
        childPhone: _childPhoneController.text,
        linkedDone: cachedLinkedDone,
      )) {
        _step = 3;
        shouldNavigate = _role == 'child' || _role == 'parent';
        roleToNavigate = _role ?? '';
      } else if (_userPhoneController.text.isNotEmpty) {
        _step = 2;
      }
    });

    if (shouldNavigate && roleToNavigate.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showRoleSuccessAndNavigate(roleToNavigate, shouldShowDialog: false);
      });
    }
  }

  Future<void> _cacheProfileSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final phone = _userPhoneController.text.trim();
    final role = (_role ?? '').trim();
    final parentPhone = _parentPhoneController.text.trim();
    final childPhone = _childPhoneController.text.trim();
    final linkedDone = _isProfileCompleted(
      role: role,
      phone: phone,
      parentPhone: parentPhone,
      childPhone: childPhone,
    );

    await prefs.setString(_cacheKey(uid, 'phone'), phone);
    await prefs.setString(_cacheKey(uid, 'role'), role);
    await prefs.setString(_cacheKey(uid, 'parentPhone'), parentPhone);
    await prefs.setString(_cacheKey(uid, 'childPhone'), childPhone);
    await prefs.setBool(_cacheKey(uid, 'linkedDone'), linkedDone);
  }

  Future<void> _clearCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await prefs.remove(_cacheKey(uid, 'phone'));
    await prefs.remove(_cacheKey(uid, 'role'));
    await prefs.remove(_cacheKey(uid, 'parentPhone'));
    await prefs.remove(_cacheKey(uid, 'childPhone'));
    await prefs.remove(_cacheKey(uid, 'linkedDone'));
  }

  Future<void> _restoreSession() async {
    if (_isRestoringSession) return;
    _isRestoringSession = true;
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final userDocRef = FirebaseFirestore.instance.collection('users').doc(currentUser.uid);
        final userDoc = await userDocRef.get();
        if (!userDoc.exists) {
          await userDocRef.set({
            'email': currentUser.email,
            'name': currentUser.displayName,
            'role': '',
            'phone': '',
            'parentPhone': '',
            'childPhone': '',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        final data = (await userDocRef.get()).data() ?? {};
        _serverPhone = (data['phone'] ?? '').toString().trim();
        _phoneLocked = data['phoneLocked'] == true;
        _userPhoneController.text = _serverPhone;
        _role = (data['role'] ?? '').toString();
        _parentPhoneController.text = (data['parentPhone'] ?? '').toString();
        var restoredChildPhone = (data['childPhone'] ?? '').toString().trim();
        if (restoredChildPhone.isEmpty) {
          final linkedChildPhones = data['linkedChildPhones'];
          if (linkedChildPhones is List && linkedChildPhones.isNotEmpty) {
            restoredChildPhone = linkedChildPhones.first.toString().trim();
          }
        }
        _childPhoneController.text = restoredChildPhone;
        final parentUid = (data['parentUid'] ?? '').toString();
        final childUid = (data['childUid'] ?? '').toString();
        final linkLocked = data['linkLocked'] == true;

        // Keep parent-side child link fresh when children link after parent setup.
        if (_role == 'parent' && _serverPhone.isNotEmpty) {
          await _autoLinkChildrenByParentPhone(_serverPhone);
          final refreshedData = (await userDocRef.get()).data() ?? {};
          var refreshedChildPhone = (refreshedData['childPhone'] ?? '').toString().trim();
          if (refreshedChildPhone.isEmpty) {
            final refreshedLinkedChildPhones = refreshedData['linkedChildPhones'];
            if (refreshedLinkedChildPhones is List && refreshedLinkedChildPhones.isNotEmpty) {
              refreshedChildPhone = refreshedLinkedChildPhones.first.toString().trim();
            }
          }
          _childPhoneController.text = refreshedChildPhone;
        }
        await _cacheProfileSnapshot();

        var shouldNavigate = false;
        var roleToNavigate = '';
        setState(() {
          if (_isProfileCompleted(
            role: _role,
            phone: _userPhoneController.text,
            parentPhone: _parentPhoneController.text,
            childPhone: _childPhoneController.text,
            parentUid: parentUid,
            childUid: childUid,
            linkedDone: linkLocked,
          )) {
            _step = 3;
            shouldNavigate = _role == 'child' || _role == 'parent';
            roleToNavigate = _role ?? '';
          } else if (_userPhoneController.text.isNotEmpty) {
            _step = 2;
          } else {
            _step = 1;
          }
        });

        if (shouldNavigate && roleToNavigate.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showRoleSuccessAndNavigate(roleToNavigate, shouldShowDialog: false);
          });
        }
      } else {
        setState(() => _step = 0);
      }
    } catch (e) {
      if (FirebaseAuth.instance.currentUser != null) {
        _showMessage('Đã giữ phiên đăng nhập, nhưng khôi phục dữ liệu hồ sơ lỗi: $e');
      } else {
        _showMessage('Lỗi khôi phục phiên: $e');
      }
    } finally {
      _isRestoringSession = false;
    }
  }

  Future<void> _checkRedirectResult() async {
    try {
      final result = await FirebaseAuth.instance.getRedirectResult();
      if (result.user != null) {
        await _tryPostSignIn(result);
        await _restoreSession();
        _showMessage('Đăng nhập Google qua redirect thành công');
        return;
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await _restoreSession();
      } else {
        setState(() => _step = 0);
      }
    } catch (e) {
      // If user is already authenticated, do not force them back to login
      // just because profile sync fails.
      if (FirebaseAuth.instance.currentUser != null) {
        _showMessage('Đăng nhập thành công nhưng đồng bộ dữ liệu lỗi: $e');
        setState(() => _step = 1);
      } else {
        _showMessage('Lỗi redirect Google Auth: $e');
        setState(() => _step = 0);
      }
    }
  }

  Future<void> _showRoleSuccessAndNavigate(String role, {bool shouldShowDialog = true}) async {
    if (!mounted || _isNavigatingToRoleHome) return;
    if (role != 'child' && role != 'parent') return;

    _isNavigatingToRoleHome = true;
    try {
      if (shouldShowDialog) {
        final content = role == 'child'
            ? 'Đăng nhập vai trò Con thành công. Bạn sẽ được chuyển sang trang chủ tài khoản Con.'
            : 'Đăng nhập vai trò Cha/Mẹ thành công. Bạn sẽ được chuyển sang trang chủ tài khoản Cha/Mẹ.';
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Thông báo'),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }

      if (!mounted) return;

      final route = MaterialPageRoute(
        builder: (_) => role == 'child' ? const ChildHomePage() : const ParentHomePage(),
      );
      await Navigator.of(context).pushReplacement(route);
    } finally {
      _isNavigatingToRoleHome = false;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _userPhoneController.dispose();
    _parentPhoneController.dispose();
    _childPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.health_and_safety),
            SizedBox(width: 8),
            Text('CareElder', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blueAccent, Colors.lightBlueAccent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: _buildStep(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    Widget stepWidget;
    switch (_step) {
      case 0:
        stepWidget = _buildLoginStep();
        break;
      case 1:
        stepWidget = _buildPhoneInputStep();
        break;
      case 2:
        stepWidget = _buildRoleLinkStep();
        break;
      case 3:
        stepWidget = _buildDoneStep();
        break;
      default:
        stepWidget = const Center(child: Text('Hoàn thành', style: TextStyle(fontSize: 24, color: Colors.white)));
    }
    return KeyedSubtree(
      key: ValueKey<int>(_step),
      child: stepWidget,
    );
  }

  Widget _buildLoginStep() {
    return SingleChildScrollView(
      child: SizedBox(
        width: 400,
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.login, size: 64, color: Colors.blueAccent),
                const SizedBox(height: 16),
                const Text(
                  'Đăng nhập bằng Google',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _signInWithGoogle,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                  ),
                  icon: const Icon(Icons.login, size: 28, color: Colors.redAccent),
                  label: _isLoading
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Đăng nhập với Google', style: TextStyle(fontSize: 18, color: Colors.black87)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneInputStep() {
    return SingleChildScrollView(
      child: SizedBox(
        width: 400,
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phone_android, size: 64, color: Colors.blueAccent),
                const SizedBox(height: 16),
                const Text(
                  'Nhập Số Điện Thoại',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _userPhoneController,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại của bạn (+84...)',
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _savePhone,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Lưu số điện thoại', style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleLinkStep() {
    bool isLinked = _role == 'child' && _parentPhoneController.text.isNotEmpty;
    bool isParentLinked = _role == 'parent' && _childPhoneController.text.isNotEmpty;

    if (isLinked || isParentLinked) {
      return SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 64, color: Colors.green),
                  const SizedBox(height: 16),
                  Text(
                    isLinked
                        ? 'Đã liên kết với cha/mẹ: ${_parentPhoneController.text}'
                        : 'Đã liên kết với con: ${_childPhoneController.text}',
                    style: const TextStyle(fontSize: 18, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => setState(() => _step = 3),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                    child: const Text('Hoàn thành', style: TextStyle(fontSize: 18)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: SizedBox(
        width: 400,
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people, size: 64, color: Colors.blueAccent),
                const SizedBox(height: 16),
                const Text(
                  'Chọn vai trò',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => _selectRole('parent'),
                  icon: const Icon(Icons.elderly),
                  label: const Text('Tôi là Cha/Mẹ', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _selectRole('child'),
                  icon: const Icon(Icons.child_care),
                  label: const Text('Tôi là Con', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                ),
                if (_role == 'child') ...[
                  const SizedBox(height: 24),
                  TextField(
                    controller: _parentPhoneController,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại Cha/Mẹ',
                      prefixIcon: Icon(Icons.phone),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _linkParent,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Liên kết với Cha/Mẹ', style: TextStyle(fontSize: 18)),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Đăng xuất', style: TextStyle(fontSize: 16)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDoneStep() {
    final currentUser = FirebaseAuth.instance.currentUser;
    return SingleChildScrollView(
      child: SizedBox(
        width: 400,
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.thumb_up, size: 64, color: Colors.green),
                const SizedBox(height: 16),
                const Text(
                  'Hoàn thành!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
                const SizedBox(height: 12),
                Text(
                  'Email: ${currentUser?.email ?? ''}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'UID: ${currentUser?.uid ?? ''}',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Text(
                  'SĐT: ${_userPhoneController.text}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vai trò: ${_role ?? 'Chưa chọn'}',
                  style: const TextStyle(fontSize: 16),
                ),
                if ((_role ?? '') == 'child') ...[
                  const SizedBox(height: 8),
                  Text(
                    'SĐT Cha/Mẹ đã liên kết: ${_parentPhoneController.text}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ] else if ((_role ?? '') == 'parent') ...[
                  const SizedBox(height: 8),
                  Text(
                    'SĐT Con đã liên kết: ${_childPhoneController.text}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _signOut,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                  child: const Text('Đăng xuất', style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      UserCredential userCredential;
      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.setCustomParameters({'prompt': 'select_account'});

        try {
          userCredential = await FirebaseAuth.instance.signInWithPopup(googleProvider);
        } on FirebaseAuthException catch (e) {
          final code = e.code.toLowerCase();
          if (code == 'popup-blocked' ||
              code == 'auth/popup-blocked' ||
              code == 'popup-closed-by-user' ||
              code == 'auth/popup-closed-by-user' ||
              code == 'cancelled-popup-request' ||
              code == 'auth/cancelled-popup-request' ||
              code == 'operation-not-supported-in-this-environment' ||
              code == 'auth/operation-not-supported-in-this-environment') {
            _showMessage('Popup bị chặn/đóng, thử redirect...');
            await FirebaseAuth.instance.signInWithRedirect(googleProvider);
            // Redirect will navigate away; result handled in initState via _checkRedirectResult
            if (mounted) {
              setState(() => _isLoading = false);
            }
            return;
          }
          rethrow;
        }
      } else {
        // On Android/iOS, use native GoogleSignIn to avoid browser redirect/session issues.
        final googleSignIn = GoogleSignIn();
        try {
          await googleSignIn.signOut();
        } catch (_) {
          // Ignore if no previous Google session exists on this device.
        }

        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          _showMessage('Hủy đăng nhập Google');
          if (mounted) {
            setState(() => _isLoading = false);
          }
          return;
        }

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      }

      await _tryPostSignIn(userCredential);
      _showMessage('Đăng nhập bằng Google thành công!');
      await _restoreSession();
    } on FirebaseAuthException catch (e) {
      final code = e.code.toLowerCase();
      if (code == 'operation-not-allowed' || code == 'auth/operation-not-allowed') {
        _showMessage('Google Sign-In chưa được bật trong Firebase Console (Authentication > Sign-in method).');
      } else if (code == 'unauthorized-domain' || code == 'auth/unauthorized-domain') {
        _showMessage('Domain hiện tại chưa được phép. Hãy thêm localhost vào Authentication > Settings > Authorized domains.');
      } else {
        _showMessage('FirebaseAuthException: ${e.code} - ${e.message}');
      }
    } on PlatformException catch (e) {
      final code = e.code.toLowerCase();
      final details = (e.message ?? e.details?.toString() ?? '').toLowerCase();
      final isApi10 = code.contains('sign_in_failed') &&
          (details.contains('apiexception: 10') || details.contains('statuscode=developer_error'));
      if (isApi10) {
        _showMessage('Google Sign-In Android lỗi code 10 (DEVELOPER_ERROR). Cần thêm SHA-1/SHA-256 của app vào Firebase Android app và tải lại google-services.json.');
      } else {
        _showMessage('Lỗi đăng nhập Google: ${e.code} - ${e.message}');
      }
    } catch (e) {
      _showMessage('Lỗi đăng nhập Google: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _postSignIn(UserCredential userCredential) async {
    final User? user = userCredential.user;
    if (user == null) return;

    final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final docSnapshot = await userDoc.get();

    if (!docSnapshot.exists) {
      await userDoc.set({
        'email': user.email,
        'name': user.displayName,
        'role': '',
        'phone': '',
        'parentPhone': '',
        'childPhone': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _role = null;
      _userPhoneController.text = '';
      _parentPhoneController.text = '';
      _childPhoneController.text = '';
      await _cacheProfileSnapshot();
    } else {
      final data = docSnapshot.data() ?? {};
      _userPhoneController.text = (data['phone'] ?? '').toString();
      _role = (data['role'] ?? '').toString();
      _parentPhoneController.text = (data['parentPhone'] ?? '').toString();
      _childPhoneController.text = (data['childPhone'] ?? '').toString();
      await _cacheProfileSnapshot();

      if (_userPhoneController.text.isNotEmpty && _role != null && _role!.isNotEmpty) {
        // Nếu user đã hoàn thành profile trước đó, điều hướng về trang chủ theo vai trò.
        setState(() => _step = 3);
        await _showRoleSuccessAndNavigate(_role!, shouldShowDialog: true);
      }
    }
  }

  Future<void> _tryPostSignIn(UserCredential userCredential) async {
    try {
      await _postSignIn(userCredential);
    } catch (e) {
      _showMessage(_friendlyFirestoreError('Đăng nhập thành công nhưng đồng bộ hồ sơ thất bại', e));
    }
  }

  Future<void> _savePhone() async {
    final phone = _userPhoneController.text.trim();
    if (phone.isEmpty) {
      _showMessage('Vui lòng nhập số điện thoại');
      return;
    }
    if (!phone.startsWith('+')) {
      _showMessage('Nhập số điện thoại theo định dạng +84...');
      return;
    }

    if (_phoneLocked && _serverPhone.isNotEmpty && phone != _serverPhone) {
      _showMessage('SĐT của tài khoản này đã khóa là $_serverPhone, không thể đổi. Nếu muốn dùng SĐT khác, hãy đăng nhập tài khoản Google khác.');
      _userPhoneController.text = _serverPhone;
      return;
    }

    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        _showMessage('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.');
        return;
      }

      final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);

      await userDocRef.set({
        'email': FirebaseAuth.instance.currentUser?.email,
        'phone': phone,
        'phoneLocked': true,
      }, SetOptions(merge: true));

      _serverPhone = phone;
      _phoneLocked = true;

      if ((_role ?? '') == 'parent') {
        await _autoLinkChildrenByParentPhone(phone);
      }

      await _cacheProfileSnapshot();
      _showMessage('Số điện thoại đã lưu');
      setState(() => _step = 2);
      _animationController.reset();
      _animationController.forward();
    } on FirebaseException catch (e) {
      if (e.plugin == 'cloud_firestore' && e.code == 'permission-denied') {
        await _restoreSession();
        _showMessage('Tài khoản hiện tại không được đổi SĐT (đã khóa hoặc Rules chặn). Hãy dùng đúng SĐT đã lưu hoặc đổi tài khoản Google khác.');
      } else {
        _showMessage(_friendlyFirestoreError('Lỗi lưu số điện thoại', e));
      }
    } catch (e) {
      _showMessage(_friendlyFirestoreError('Lỗi lưu số điện thoại', e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectRole(String role) async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        _showMessage('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.');
        return;
      }

      final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final userDoc = await userDocRef.get();
      final data = userDoc.data() ?? {};
      final existingRole = (data['role'] ?? '').toString();
      final existingParentPhone = (data['parentPhone'] ?? '').toString();

      if (existingRole == 'parent' && role != 'parent') {
        _showMessage('Vai trò Cha/Mẹ đã được khóa và không thể đổi.');
        return;
      }
      if (existingRole == 'child' && existingParentPhone.isNotEmpty && role != 'child') {
        _showMessage('Tài khoản Con đã liên kết Cha/Mẹ, không thể đổi vai trò.');
        return;
      }
      if (existingRole.isNotEmpty && existingRole != role) {
        _showMessage('Vai trò đã được thiết lập và không thể thay đổi.');
        return;
      }

      _role = role;

      await userDocRef.set({
        'role': role,
        'roleLocked': true,
      }, SetOptions(merge: true));

      if (role == 'parent') {
        final ownPhone = _userPhoneController.text.trim();
        if (ownPhone.isNotEmpty) {
          await _autoLinkChildrenByParentPhone(ownPhone);
        }
        await _cacheProfileSnapshot();
        _showMessage('Bạn đã chọn vai trò Cha/Mẹ. Hệ thống sẽ tự động tìm các tài khoản con đã nhập SĐT của bạn.');
        await _showRoleSuccessAndNavigate('parent', shouldShowDialog: true);
      } else {
        await _cacheProfileSnapshot();
        _showMessage('Bạn đã chọn vai trò Con. Nhập SĐT cha/mẹ để liên kết.');
      }
    } catch (e) {
      _showMessage(_friendlyFirestoreError('Lỗi chọn vai trò', e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _linkParent() async {
    final parentPhone = _parentPhoneController.text.trim();
    if (parentPhone.isEmpty) {
      _showMessage('Vui lòng nhập SĐT cha/mẹ');
      return;
    }
    if (!parentPhone.startsWith('+')) {
      _showMessage('Nhập số điện thoại theo định dạng +84...');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        _showMessage('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.');
        return;
      }

      final childRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final childDoc = await childRef.get();
      final childData = childDoc.data() ?? {};
      final existingRole = (childData['role'] ?? '').toString();
      final existingParentPhone = (childData['parentPhone'] ?? '').toString();
      final childPhone = (childData['phone'] ?? _userPhoneController.text.trim()).toString();

      if (existingRole == 'parent') {
        _showMessage('Tài khoản Cha/Mẹ không thể liên kết theo vai trò Con.');
        return;
      }
      if (childPhone.isEmpty) {
        _showMessage('Vui lòng lưu số điện thoại của bạn trước khi liên kết.');
        return;
      }
      if (existingParentPhone.isNotEmpty && existingParentPhone != parentPhone) {
        _showMessage('Đã liên kết Cha/Mẹ trước đó, không thể đổi sang số khác.');
        return;
      }
      if (existingParentPhone == parentPhone) {
        _showMessage('Tài khoản đã liên kết với Cha/Mẹ này.');
        setState(() => _step = 3);
        await _showRoleSuccessAndNavigate('child', shouldShowDialog: true);
        return;
      }

      final parentSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: parentPhone)
          .limit(1)
          .get();

      if (parentSnapshot.docs.isEmpty) {
        _showMessage('Không tìm thấy tài khoản cha/mẹ khớp SĐT này. Hãy đăng nhập tài khoản cha/mẹ và lưu SĐT trước.');
        return;
      }

      final parentDoc = parentSnapshot.docs.first;
      if (parentDoc.id == uid) {
        _showMessage('Không thể liên kết chính tài khoản của bạn làm Cha/Mẹ.');
        return;
      }

      await childRef.set({
        'role': 'child',
        'parentPhone': parentPhone,
        'parentUid': parentDoc.id,
        'linkLocked': true,
        'linkedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final Map<String, dynamic> parentUpdates = {
        'linkedChildUids': FieldValue.arrayUnion([uid]),
        'linkedChildPhones': FieldValue.arrayUnion([childPhone]),
        'childUid': uid,
        'childPhone': childPhone,
        'linkLocked': true,
      };
      var parentMirrorFailed = false;
      try {
        await parentDoc.reference.set(parentUpdates, SetOptions(merge: true));
      } catch (_) {
        parentMirrorFailed = true;
      }

      await _cacheProfileSnapshot();
      if (parentMirrorFailed) {
        _showMessage('Đã lưu parentPhone cho tài khoản Con, nhưng chưa ghi được childPhone ở tài khoản Cha/Mẹ do Rules. Hãy cập nhật Firestore Rules rồi thử lại.');
      } else {
        _showMessage('Liên kết với cha/mẹ thành công');
      }
      setState(() => _step = 3);
      await _showRoleSuccessAndNavigate('child', shouldShowDialog: true);
      _animationController.reset();
      _animationController.forward();
    } on FirebaseException catch (e) {
      if (e.plugin == 'cloud_firestore' && e.code == 'permission-denied') {
        _showMessage('Rules hiện chưa cho phép tìm tài khoản cha/mẹ theo số điện thoại. Hãy cho phép user đã đăng nhập được đọc collection users.');
      } else {
        _showMessage(_friendlyFirestoreError('Lỗi liên kết', e));
      }
    } catch (e) {
      _showMessage(_friendlyFirestoreError('Lỗi liên kết', e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _autoLinkChildrenByParentPhone(String parentPhone) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || parentPhone.trim().isEmpty) return;

    try {
      final childrenSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'child')
          .where('parentPhone', isEqualTo: parentPhone)
          .get();

      if (childrenSnapshot.docs.isEmpty) {
        _childPhoneController.clear();
        return;
      }

      final childUids = <String>[];
      final childPhones = <String>[];
      for (final doc in childrenSnapshot.docs) {
        if (doc.id == uid) continue;
        childUids.add(doc.id);
        final p = (doc.data()['phone'] ?? '').toString().trim();
        if (p.isNotEmpty) childPhones.add(p);
      }

      if (childUids.isEmpty) {
        _childPhoneController.clear();
        return;
      }

      final parentRef = FirebaseFirestore.instance.collection('users').doc(uid);
      await parentRef.set({
        'role': 'parent',
        'roleLocked': true,
        'childUid': childUids.first,
        'childPhone': childPhones.isNotEmpty ? childPhones.first : '',
        'linkedChildUids': FieldValue.arrayUnion(childUids),
        'linkedChildPhones': FieldValue.arrayUnion(childPhones),
        'linkLocked': true,
      }, SetOptions(merge: true));

      _childPhoneController.text = childPhones.isNotEmpty ? childPhones.first : '';
    } catch (_) {
      // Keep parent flow functional even if automatic lookup is blocked by rules.
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    await _clearCachedProfile();
    _emailController.clear();
    _passwordController.clear();
    _userPhoneController.clear();
    _parentPhoneController.clear();
    _childPhoneController.clear();
    _role = null;
    setState(() => _step = 0);
    _animationController.reset();
    _animationController.forward();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blueAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _friendlyFirestoreError(String prefix, Object error) {
    if (error is FirebaseException &&
        error.plugin == 'cloud_firestore' &&
        error.code == 'permission-denied') {
      return '$prefix: Firestore đang chặn quyền ghi. Hãy cập nhật Rules để user đã đăng nhập có quyền ghi hồ sơ của chính họ.';
    }
    return '$prefix: $error';
  }

  bool _isProfileCompleted({
    required String? role,
    required String phone,
    required String parentPhone,
    String childPhone = '',
    String parentUid = '',
    String childUid = '',
    bool linkedDone = false,
  }) {
    if (phone.trim().isEmpty) return false;
    final r = (role ?? '').trim();
    if (r == 'parent') {
      return childUid.trim().isNotEmpty || childPhone.trim().isNotEmpty || linkedDone;
    }
    if (r != 'child') return false;
    return parentUid.trim().isNotEmpty || linkedDone;
  }
}

class ChildHomePage extends StatelessWidget {
  const ChildHomePage({super.key});

  Future<void> _signOutAndBackToLogin(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final prefs = await SharedPreferences.getInstance();
      final keysToRemove = prefs
          .getKeys()
          .where((k) => k.startsWith('flutter.cache.profile.$uid.'))
          .toList();
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
    }
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const CareElderScreen()),
      (route) => false,
    );
  }

  void _showShareBox(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ShareBox'),
        content: const Text('Đây là ShareBox của tài khoản Con.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trang Chủ Tài Khoản Con'),
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            tooltip: 'ShareBox',
            onPressed: () => _showShareBox(context),
            icon: const Icon(Icons.share),
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: () => _signOutAndBackToLogin(context),
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'đây là trang chủ tài khoản con',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ParentHomePage extends StatelessWidget {
  const ParentHomePage({super.key});

  Future<void> _signOutAndBackToLogin(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final prefs = await SharedPreferences.getInstance();
      final keysToRemove = prefs
          .getKeys()
          .where((k) => k.startsWith('flutter.cache.profile.$uid.'))
          .toList();
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
    }
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const CareElderScreen()),
      (route) => false,
    );
  }

  void _showShareBox(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ShareBox'),
        content: const Text('Đây là ShareBox của tài khoản Cha/Mẹ.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trang Chủ Tài Khoản Cha/Mẹ'),
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            tooltip: 'ShareBox',
            onPressed: () => _showShareBox(context),
            icon: const Icon(Icons.share),
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: () => _signOutAndBackToLogin(context),
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'đây là trang chủ của tài khoản bố mẹ',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
