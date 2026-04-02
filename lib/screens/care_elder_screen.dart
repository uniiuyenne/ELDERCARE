import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

class CareElderScreen extends StatefulWidget {
  const CareElderScreen({super.key});

  @override
  State<CareElderScreen> createState() => _CareElderScreenState();
}

class _CareElderScreenState extends State<CareElderScreen>
    with TickerProviderStateMixin {
  static const String _cacheNamespace = 'cache.profile';

  int _step = 0; // 0: Login, 1: Phone input, 2: Role/Linking
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
    final cachedParentPhone =
        prefs.getString(_cacheKey(uid, 'parentPhone')) ?? '';
    final cachedChildPhone =
        prefs.getString(_cacheKey(uid, 'childPhone')) ?? '';
    final cachedLinkedDone =
        prefs.getBool(_cacheKey(uid, 'linkedDone')) ?? false;

    if (!mounted) return;
    if (cachedPhone.isEmpty &&
        cachedRole.isEmpty &&
        cachedParentPhone.isEmpty &&
        cachedChildPhone.isEmpty) {
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
        _step = 2;
        shouldNavigate = _role == 'child' || _role == 'parent';
        roleToNavigate = _role ?? '';
      } else if (_userPhoneController.text.isNotEmpty) {
        _step = 2;
      }
    });

    if (shouldNavigate && roleToNavigate.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showRoleSuccessAndNavigate(roleToNavigate);
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
        final userDocRef = FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid);
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
          var refreshedChildPhone = (refreshedData['childPhone'] ?? '')
              .toString()
              .trim();
          if (refreshedChildPhone.isEmpty) {
            final refreshedLinkedChildPhones =
                refreshedData['linkedChildPhones'];
            if (refreshedLinkedChildPhones is List &&
                refreshedLinkedChildPhones.isNotEmpty) {
              refreshedChildPhone = refreshedLinkedChildPhones.first
                  .toString()
                  .trim();
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
            _step = 2;
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
            _showRoleSuccessAndNavigate(roleToNavigate);
          });
        }
      } else {
        setState(() => _step = 0);
      }
    } catch (e) {
      if (FirebaseAuth.instance.currentUser != null) {
        _showMessage(
          'Đã giữ phiên đăng nhập, nhưng khôi phục dữ liệu hồ sơ lỗi: $e',
        );
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

  Future<void> _showRoleSuccessAndNavigate(String role) async {
    if (!mounted || _isNavigatingToRoleHome) return;
    if (role != 'child' && role != 'parent') return;

    _isNavigatingToRoleHome = true;
    try {
      if (!mounted) return;

      final route = MaterialPageRoute(
        builder: (_) =>
            role == 'child' ? const ChildHomePage() : const ParentHomePage(),
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
      default:
        stepWidget = const Center(
          child: Text(
            'Hoàn thành',
            style: TextStyle(fontSize: 24, color: Colors.white),
          ),
        );
    }
    return KeyedSubtree(key: ValueKey<int>(_step), child: stepWidget);
  }

  Widget _buildLoginStep() {
    return SingleChildScrollView(
      child: SizedBox(
        width: 400,
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.login, size: 64, color: Colors.blueAccent),
                const SizedBox(height: 16),
                const Text(
                  'Đăng nhập bằng Google',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _signInWithGoogle,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                  ),
                  icon: const Icon(
                    Icons.login,
                    size: 28,
                    color: Colors.redAccent,
                  ),
                  label: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Đăng nhập với Google',
                          style: TextStyle(fontSize: 18, color: Colors.black87),
                        ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.phone_android,
                  size: 64,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nhập Số Điện Thoại',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
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
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Lưu số điện thoại',
                          style: TextStyle(fontSize: 18),
                        ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text(
                    'Đăng xuất',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                  ),
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
    bool isParentLinked =
        _role == 'parent' && _childPhoneController.text.isNotEmpty;

    if (isLinked || isParentLinked) {
      return SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
                    onPressed: () async {
                      final role = _role;
                      if (role == 'child' || role == 'parent') {
                        await _showRoleSuccessAndNavigate(role!);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 60),
                    ),
                    child: const Text(
                      'Hoàn thành',
                      style: TextStyle(fontSize: 18),
                    ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people, size: 64, color: Colors.blueAccent),
                const SizedBox(height: 16),
                const Text(
                  'Chọn vai trò',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => _selectRole('parent'),
                  icon: const Icon(Icons.elderly),
                  label: const Text(
                    'Tôi là Cha/Mẹ',
                    style: TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _selectRole('child'),
                  icon: const Icon(Icons.child_care),
                  label: const Text(
                    'Tôi là Con',
                    style: TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                  ),
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
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 60),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Liên kết với Cha/Mẹ',
                            style: TextStyle(fontSize: 18),
                          ),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text(
                    'Đăng xuất',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                  ),
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
          userCredential = await FirebaseAuth.instance.signInWithPopup(
            googleProvider,
          );
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

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        userCredential = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
      }

      await _tryPostSignIn(userCredential);
      _showMessage('Đăng nhập bằng Google thành công!');
      await _restoreSession();
    } on FirebaseAuthException catch (e) {
      final code = e.code.toLowerCase();
      if (code == 'operation-not-allowed' ||
          code == 'auth/operation-not-allowed') {
        _showMessage(
          'Google Sign-In chưa được bật trong Firebase Console (Authentication > Sign-in method).',
        );
      } else if (code == 'unauthorized-domain' ||
          code == 'auth/unauthorized-domain') {
        _showMessage(
          'Domain hiện tại chưa được phép. Hãy thêm localhost vào Authentication > Settings > Authorized domains.',
        );
      } else {
        _showMessage('FirebaseAuthException: ${e.code} - ${e.message}');
      }
    } on PlatformException catch (e) {
      final code = e.code.toLowerCase();
      final details = (e.message ?? e.details?.toString() ?? '').toLowerCase();
      final isApi10 =
          code.contains('sign_in_failed') &&
          (details.contains('apiexception: 10') ||
              details.contains('statuscode=developer_error'));
      if (isApi10) {
        _showMessage(
          'Google Sign-In Android lỗi code 10 (DEVELOPER_ERROR). Cần thêm SHA-1/SHA-256 của app vào Firebase Android app và tải lại google-services.json.',
        );
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

    final userDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
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

      if (_userPhoneController.text.isNotEmpty &&
          _role != null &&
          _role!.isNotEmpty) {
        // Nếu user đã hoàn thành profile trước đó, điều hướng về trang chủ theo vai trò.
        setState(() => _step = 2);
        await _showRoleSuccessAndNavigate(_role!);
      }
    }
  }

  Future<void> _tryPostSignIn(UserCredential userCredential) async {
    try {
      await _postSignIn(userCredential);
    } catch (e) {
      _showMessage(
        _friendlyFirestoreError(
          'Đăng nhập thành công nhưng đồng bộ hồ sơ thất bại',
          e,
        ),
      );
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
      _showMessage(
        'SĐT của tài khoản này đã khóa là $_serverPhone, không thể đổi. Nếu muốn dùng SĐT khác, hãy đăng nhập tài khoản Google khác.',
      );
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

      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid);

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
        _showMessage(
          'Tài khoản hiện tại không được đổi SĐT (đã khóa hoặc Rules chặn). Hãy dùng đúng SĐT đã lưu hoặc đổi tài khoản Google khác.',
        );
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

      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid);
      final userDoc = await userDocRef.get();
      final data = userDoc.data() ?? {};
      final existingRole = (data['role'] ?? '').toString();
      final existingParentPhone = (data['parentPhone'] ?? '').toString();

      if (existingRole == 'parent' && role != 'parent') {
        _showMessage('Vai trò Cha/Mẹ đã được khóa và không thể đổi.');
        return;
      }
      if (existingRole == 'child' &&
          existingParentPhone.isNotEmpty &&
          role != 'child') {
        _showMessage(
          'Tài khoản Con đã liên kết Cha/Mẹ, không thể đổi vai trò.',
        );
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
        _showMessage(
          'Bạn đã chọn vai trò Cha/Mẹ. Hệ thống sẽ tự động tìm các tài khoản con đã nhập SĐT của bạn.',
        );
        await _showRoleSuccessAndNavigate('parent');
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
      final childPhone =
          (childData['phone'] ?? _userPhoneController.text.trim()).toString();

      if (existingRole == 'parent') {
        _showMessage('Tài khoản Cha/Mẹ không thể liên kết theo vai trò Con.');
        return;
      }
      if (childPhone.isEmpty) {
        _showMessage('Vui lòng lưu số điện thoại của bạn trước khi liên kết.');
        return;
      }
      if (existingParentPhone.isNotEmpty &&
          existingParentPhone != parentPhone) {
        _showMessage(
          'Đã liên kết Cha/Mẹ trước đó, không thể đổi sang số khác.',
        );
        return;
      }
      if (existingParentPhone == parentPhone) {
        _showMessage('Tài khoản đã liên kết với Cha/Mẹ này.');
        setState(() => _step = 2);
        await _showRoleSuccessAndNavigate('child');
        return;
      }

      final parentSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: parentPhone)
          .limit(1)
          .get();

      if (parentSnapshot.docs.isEmpty) {
        _showMessage(
          'Không tìm thấy tài khoản cha/mẹ khớp SĐT này. Hãy đăng nhập tài khoản cha/mẹ và lưu SĐT trước.',
        );
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
        _showMessage(
          'Đã lưu parentPhone cho tài khoản Con, nhưng chưa ghi được childPhone ở tài khoản Cha/Mẹ do Rules. Hãy cập nhật Firestore Rules rồi thử lại.',
        );
      } else {
        _showMessage('Liên kết với cha/mẹ thành công');
      }
      setState(() => _step = 2);
      await _showRoleSuccessAndNavigate('child');
      _animationController.reset();
      _animationController.forward();
    } on FirebaseException catch (e) {
      if (e.plugin == 'cloud_firestore' && e.code == 'permission-denied') {
        _showMessage(
          'Rules hiện chưa cho phép tìm tài khoản cha/mẹ theo số điện thoại. Hãy cho phép user đã đăng nhập được đọc collection users.',
        );
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

      _childPhoneController.text = childPhones.isNotEmpty
          ? childPhones.first
          : '';
    } catch (_) {
      // Keep parent flow functional even if automatic lookup is blocked by rules.
    }
  }

  Future<void> _signOut({bool requireConfirm = true}) async {
    if (requireConfirm && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Xác nhận đăng xuất'),
          content: const Text('Bạn có chắc chắn muốn đăng xuất tài khoản?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Đăng xuất'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

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
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.showSnackBar(
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
      return childUid.trim().isNotEmpty ||
          childPhone.trim().isNotEmpty ||
          linkedDone;
    }
    if (r != 'child') return false;
    return parentUid.trim().isNotEmpty || linkedDone;
  }
}

class ChildHomePage extends StatelessWidget {
  const ChildHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FamilyHomePage(isChildView: true);
  }
}

class ParentHomePage extends StatelessWidget {
  const ParentHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FamilyHomePage(isChildView: false);
  }
}

class _FamilyHomePage extends StatefulWidget {
  const _FamilyHomePage({required this.isChildView});

  final bool isChildView;

  @override
  State<_FamilyHomePage> createState() => _FamilyHomePageState();
}

class _FamilyHomePageState extends State<_FamilyHomePage> {
    // Biến vị trí
    Position? _currentPosition;
    String? _currentAddress;
    StreamSubscription<Position>? _positionStreamSub;
    bool _updatingLocation = false;
  static const int _maxImageSizeBytes = 5 * 1024 * 1024;
  static const Set<String> _allowedExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  };

  final ImagePicker _imagePicker = ImagePicker();
  bool _loadingScope = true;
  bool _uploadingImage = false;
  String? _scopeError;
  _FamilyScope? _scope;

  @override
  void initState() {
    super.initState();
    _loadFamilyScope();
    if (!widget.isChildView) {
      _startLocationTracking();
    } else {
      _listenParentLocation();
    }
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    super.dispose();
  }

  // Cha/mẹ: Theo dõi vị trí và cập nhật Firestore
  void _startLocationTracking() async {
    _positionStreamSub?.cancel();
    final locationStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    );
    _positionStreamSub = locationStream.listen((pos) async {
      if (pos == null) return;
      setState(() => _currentPosition = pos);
      final address = await LocationService.getAddressFromLatLng(pos.latitude, pos.longitude);
      setState(() => _currentAddress = address);
      await _updateLocationToFirestore(pos, address);
    });
    // Lấy vị trí lần đầu
    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      setState(() => _currentPosition = pos);
      final address = await LocationService.getAddressFromLatLng(pos.latitude, pos.longitude);
      setState(() => _currentAddress = address);
      await _updateLocationToFirestore(pos, address);
    }
  }

  Future<void> _updateLocationToFirestore(Position pos, String address) async {
    if (_updatingLocation) return;
    _updatingLocation = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'location': {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'address': address,
          'updatedAt': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));
    } catch (_) {}
    _updatingLocation = false;
  }

  // Người con: Lắng nghe vị trí cha/mẹ realtime
  void _listenParentLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Lấy uid cha/mẹ
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final parentUid = (doc.data()?['parentUid'] ?? '').toString();
    if (parentUid.isEmpty) return;
    FirebaseFirestore.instance.collection('users').doc(parentUid).snapshots().listen((snap) {
      final data = snap.data();
      if (data != null && data['location'] != null) {
        final loc = data['location'];
        setState(() {
          _currentPosition = Position(
            latitude: (loc['lat'] ?? 0).toDouble(),
            longitude: (loc['lng'] ?? 0).toDouble(),
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
          );
          _currentAddress = loc['address']?.toString();
        });
      }
    });
  }

  Future<void> _loadFamilyScope() async {
    setState(() {
      _loadingScope = true;
      _scopeError = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _scopeError = 'Phiên đăng nhập đã hết hạn.';
          _loadingScope = false;
        });
        return;
      }

      final currentRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final currentDoc = await currentRef.get();
      final data = currentDoc.data() ?? {};
      final expectedRole = widget.isChildView ? 'child' : 'parent';
      final currentRole = (data['role'] ?? '').toString().trim();
      if (currentRole != expectedRole) {
        await currentRef.set({'role': expectedRole}, SetOptions(merge: true));
      }

      String partnerUid = '';
      String partnerRole = widget.isChildView ? 'parent' : 'child';

      if (widget.isChildView) {
        partnerUid = (data['parentUid'] ?? '').toString().trim();
        if (partnerUid.isEmpty) {
          final parentPhone = (data['parentPhone'] ?? '').toString().trim();
          if (parentPhone.isNotEmpty) {
            final parentByPhone = await FirebaseFirestore.instance
                .collection('users')
                .where('role', isEqualTo: 'parent')
                .where('phone', isEqualTo: parentPhone)
                .limit(1)
                .get();
            if (parentByPhone.docs.isNotEmpty) {
              partnerUid = parentByPhone.docs.first.id;
              await currentRef.set({
                'parentUid': partnerUid,
              }, SetOptions(merge: true));
            }
          }
        }
      } else {
        partnerUid = (data['childUid'] ?? '').toString().trim();
        if (partnerUid.isEmpty) {
          final linkedChildUids = data['linkedChildUids'];
          if (linkedChildUids is List && linkedChildUids.isNotEmpty) {
            partnerUid = linkedChildUids.first.toString().trim();
          }
        }
      }

      if (partnerUid.isEmpty) {
        setState(() {
          _scopeError = widget.isChildView
              ? 'Chưa tìm thấy tài khoản Cha/Mẹ đã liên kết.'
              : 'Chưa tìm thấy tài khoản Con đã liên kết.';
          _loadingScope = false;
        });
        return;
      }

      final ids = [user.uid, partnerUid]..sort();
      final channelId = '${ids.first}_${ids.last}';

      setState(() {
        _scope = _FamilyScope(
          selfUid: user.uid,
          partnerUid: partnerUid,
          channelId: channelId,
          selfRole: widget.isChildView ? 'child' : 'parent',
          partnerRole: partnerRole,
        );
        _loadingScope = false;
      });
    } catch (e) {
      setState(() {
        _scopeError = 'Không thể tải dữ liệu liên kết: $e';
        _loadingScope = false;
      });
    }
  }

  CollectionReference<Map<String, dynamic>> _taskCollection(
    _FamilyScope scope,
  ) {
    return FirebaseFirestore.instance
        .collection('channels')
        .doc(scope.channelId)
        .collection('tasks');
  }

  CollectionReference<Map<String, dynamic>> _shareCollection(
    _FamilyScope scope,
  ) {
    return FirebaseFirestore.instance
        .collection('channels')
        .doc(scope.channelId)
        .collection('sharebox');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _taskStream(_FamilyScope scope) {
    return _taskCollection(
      scope,
    ).orderBy('scheduledAt', descending: false).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _shareStream(_FamilyScope scope) {
    return _shareCollection(
      scope,
    ).orderBy('createdAt', descending: true).snapshots();
  }

  Future<void> _showTaskDialog({
    required _FamilyScope scope,
    _TaskItem? existing,
  }) async {
    if (scope.selfRole != 'child') {
      _showMessage('Chỉ tài khoản Con được thêm/sửa công việc.');
      return;
    }

    final titleController = TextEditingController(text: existing?.title ?? '');
    final noteController = TextEditingController(text: existing?.note ?? '');
    DateTime selectedDateTime =
        existing?.scheduledAt ?? DateTime.now().add(const Duration(hours: 1));
    var isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              title: Text(
                existing == null ? 'Thêm công việc' : 'Sửa công việc',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Tên công việc',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      minLines: 2,
                      maxLines: 4,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) =>
                          FocusScope.of(dialogContext).unfocus(),
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú (nội dung)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Thời hạn phải hoàn thành: ${_formatDateTime(selectedDateTime)}',
                          ),
                        ),
                        TextButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  final pickedDate = await showDatePicker(
                                    context: this.context,
                                    initialDate: selectedDateTime,
                                    firstDate: DateTime.now().subtract(
                                      const Duration(days: 365),
                                    ),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 3650),
                                    ),
                                  );
                                  if (pickedDate == null) return;
                                  if (!mounted) return;
                                  final pickedTime = await showTimePicker(
                                    context: this.context,
                                    initialTime: TimeOfDay.fromDateTime(
                                      selectedDateTime,
                                    ),
                                  );
                                  if (pickedTime == null) return;
                                  if (!dialogContext.mounted) return;

                                  setDialogState(() {
                                    selectedDateTime = DateTime(
                                      pickedDate.year,
                                      pickedDate.month,
                                      pickedDate.day,
                                      pickedTime.hour,
                                      pickedTime.minute,
                                    );
                                  });
                                },
                          child: const Text('Chọn giờ'),
                        ),
                      ],
                    ),
                    if (isSubmitting)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          FocusScope.of(dialogContext).unfocus();

                          final title = titleController.text.trim();
                          if (title.isEmpty) {
                            _showMessage('Tên công việc không được để trống.');
                            return;
                          }
                          final normalizedTitle = title.toUpperCase();

                          setDialogState(() => isSubmitting = true);

                          try {
                            final payload = {
                              'title': normalizedTitle,
                              'note': noteController.text.trim(),
                              'scheduledAt': Timestamp.fromDate(
                                selectedDateTime,
                              ),
                              'updatedAt': FieldValue.serverTimestamp(),
                              'updatedByUid': scope.selfUid,
                              'updatedByRole': scope.selfRole,
                            };

                            if (existing == null) {
                              await _taskCollection(scope).add({
                                ...payload,
                                'completed': false,
                                'checkedAt': null,
                                'checkedByUid': null,
                                'checkedByRole': null,
                                'createdAt': FieldValue.serverTimestamp(),
                              });
                            } else {
                              await _taskCollection(scope)
                                  .doc(existing.id)
                                  .set(payload, SetOptions(merge: true));
                            }

                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                          } on FirebaseException catch (e) {
                            _showMessage(
                              'Không thể lưu công việc: ${e.message ?? e.code}',
                            );
                          } catch (e) {
                            _showMessage('Không thể lưu công việc: $e');
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() => isSubmitting = false);
                            }
                          }
                        },
                  child: Text(existing == null ? 'Thêm' : 'Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteTask(_FamilyScope scope, _TaskItem task) async {
    if (scope.selfRole != 'child') {
      _showMessage('Chỉ tài khoản Con được xóa công việc.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận'),
        content: const Text('Bạn có chắc chắn muốn xóa?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _taskCollection(scope).doc(task.id).delete();
  }

  Future<void> _toggleTask(
    _FamilyScope scope,
    _TaskItem task,
    bool completed,
  ) async {
    if (scope.selfRole != 'child' && scope.selfRole != 'parent') {
      _showMessage('Tài khoản hiện tại không có quyền cập nhật công việc.');
      return;
    }

    try {
      await _taskCollection(scope).doc(task.id).set({
        'completed': completed,
        'checkedAt': completed ? FieldValue.serverTimestamp() : null,
        'checkedByUid': completed ? scope.selfUid : null,
        'checkedByRole': completed ? scope.selfRole : null,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUid': scope.selfUid,
        'updatedByRole': scope.selfRole,
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      _showMessage('Không thể cập nhật trạng thái: ${e.message ?? e.code}');
    } catch (e) {
      _showMessage('Không thể cập nhật trạng thái: $e');
    }
  }

  Future<void> _pickAndUploadImage(
    _FamilyScope scope,
    ImageSource source,
  ) async {
    final picked = await _imagePicker.pickImage(source: source);
    if (picked == null) {
      _showMessage('Không có ảnh được chọn.');
      return;
    }

    final fileName = picked.name;
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    if (!_allowedExtensions.contains(extension)) {
      _showMessage('File ảnh không hợp lệ. Chỉ hỗ trợ JPG, PNG, WEBP, HEIC.');
      return;
    }

    final fileSize = await picked.length();
    if (fileSize <= 0) {
      _showMessage('File ảnh không hợp lệ hoặc rỗng.');
      return;
    }
    if (fileSize > _maxImageSizeBytes) {
      _showMessage('Ảnh vượt quá 5MB. Vui lòng chọn ảnh nhỏ hơn.');
      return;
    }

    setState(() => _uploadingImage = true);
    try {
      final Uint8List bytes = await picked.readAsBytes();
      final contentType = extension == 'png'
          ? 'image/png'
          : extension == 'webp'
          ? 'image/webp'
          : 'image/jpeg';

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('sharebox')
          .child(scope.channelId)
          .child('${DateTime.now().millisecondsSinceEpoch}_$fileName');

      await storageRef.putData(
        bytes,
        SettableMetadata(contentType: contentType),
      );
      final imageUrl = await storageRef.getDownloadURL();

      await _shareCollection(scope).add({
        'imageUrl': imageUrl,
        'fileName': fileName,
        'sizeBytes': fileSize,
        'senderUid': scope.selfUid,
        'senderRole': scope.selfRole,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _showMessage('Đã chia sẻ ảnh thành công.');
    } catch (e) {
      _showMessage('Upload ảnh thất bại: $e');
    } finally {
      if (mounted) {
        setState(() => _uploadingImage = false);
      }
    }
  }

  Future<void> _signOutAndBackToLogin({bool requireConfirm = true}) async {
    if (requireConfirm && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Xác nhận đăng xuất'),
          content: const Text('Bạn có chắc chắn muốn đăng xuất tài khoản?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Đăng xuất'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

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
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const CareElderScreen()),
      (route) => false,
    );
  }

  Future<void> _openNotificationsPanel() async {
    final scope = _scope;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Thông báo',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: widget.isChildView && scope != null
                        ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: _taskCollection(scope).snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final docs = snapshot.data?.docs ?? const [];
                              final activities = <Map<String, dynamic>>[];
                              final now = DateTime.now();
                              for (final doc in docs) {
                                final data = doc.data();
                                final checkedAt = data['checkedAt'];
                                final checkedByRole = (data['checkedByRole'] ?? '')
                                    .toString();
                                final completed = data['completed'] == true;
                                final title =
                                    (data['title'] ?? 'Công việc').toString();

                                if (completed &&
                                    checkedByRole == 'parent' &&
                                    checkedAt is Timestamp) {
                                  activities.add({
                                    'type': 'completed',
                                    'title': title,
                                    'eventAt': checkedAt.toDate(),
                                  });
                                  continue;
                                }

                                final scheduledAt = data['scheduledAt'];
                                if (!completed &&
                                    scheduledAt is Timestamp &&
                                    scheduledAt.toDate().isBefore(now)) {
                                  activities.add({
                                    'type': 'overdue',
                                    'title': title,
                                    'eventAt': scheduledAt.toDate(),
                                  });
                                }
                              }

                              activities.sort(
                                (a, b) => (b['eventAt'] as DateTime)
                                .compareTo(a['eventAt'] as DateTime),
                              );

                              if (activities.isEmpty) {
                                return const Center(
                                  child: Text('Chưa có hoạt động mới từ Cha/Mẹ.'),
                                );
                              }

                              return ListView.separated(
                                itemCount: activities.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final item = activities[index];
                                  final type = item['type'] as String;
                                  final at = item['eventAt'] as DateTime;
                                  final title = item['title'] as String;
                                  final relative = _formatRelativeTime(at);
                                  final exact = _formatExactDateTime(at);
                                  final isCompleted = type == 'completed';

                                  final headline = isCompleted
                                      ? 'Cha/Mẹ đã hoàn thành "$title"'
                                      : 'Cha/Mẹ chưa hoàn thành "$title" (đã quá hạn)';

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    leading: Icon(
                                      isCompleted
                                          ? Icons.notifications_active
                                          : Icons.warning_amber_rounded,
                                      color: isCompleted
                                          ? Colors.blueAccent
                                          : Colors.orange,
                                    ),
                                    title: Text(headline),
                                    subtitle: Text('$relative\n$exact'),
                                    isThreeLine: true,
                                  );
                                },
                              );
                            },
                          )
                        : const Center(
                            child: Text('Chưa có thông báo mới.'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatExactDateTime(DateTime dateTime) {
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    final dd = dateTime.day.toString().padLeft(2, '0');
    final mon = dateTime.month.toString().padLeft(2, '0');
    final yy = dateTime.year.toString();
    return '$dd/$mon/$yy $hh:$mm';
  }

  String _formatRelativeTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) {
      return 'Vừa xong';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} phút trước';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} giờ trước';
    }
    return '${diff.inDays} ngày trước';
  }

  String _formatDateTime(DateTime dateTime) {
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    final dd = dateTime.day.toString().padLeft(2, '0');
    final mon = dateTime.month.toString().padLeft(2, '0');
    return '$hh:$mm - $dd/$mon';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isChildView
              ? 'Trang Chủ Tài Khoản Con'
              : 'Trang Chủ Tài Khoản Cha/Mẹ',
        ),
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            tooltip: 'Thông báo',
            onPressed: _openNotificationsPanel,
            icon: const Icon(Icons.notifications_none),
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: () => _signOutAndBackToLogin(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loadingScope
          ? const Center(child: CircularProgressIndicator())
          : _scopeError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_scopeError!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadFamilyScope,
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            )
          : _buildBody(_scope!),
    );
  }

  Widget _buildBody(_FamilyScope scope) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Card vị trí mới cho cha/mẹ và con
        if (!widget.isChildView) _buildLocationCardParent(),
        widget.isChildView
            ? _buildTopActionRow(scope)
            : _buildParentQuickActionRow(scope),
        const SizedBox(height: 12),
        _buildDashboardCard(scope),
        const SizedBox(height: 12),
        _buildTaskManagerCard(scope),
      ],
    );
  }

  // Card vị trí cho cha/mẹ
  Widget _buildLocationCardParent() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vị trí hiện tại', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            if (_currentPosition != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Địa chỉ chi tiết
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Địa chỉ chi tiết:', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(
                          _currentAddress ?? '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tọa độ: ${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: SizedBox(height: 40, width: 40, child: CircularProgressIndicator())),
              ),
          ],
        ),
      ),
    );
  }

  // Card vị trí cho người con
  Widget _buildLocationCardChild() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vị trí cha/mẹ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            if (_currentPosition != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Địa chỉ chi tiết
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Địa chỉ cha/mẹ:', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(
                          _currentAddress ?? '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tọa độ: ${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  // Nút Mở Google Maps
                  ElevatedButton.icon(
                    onPressed: () async {
                      final lat = _currentPosition!.latitude;
                      final lng = _currentPosition!.longitude;
                      final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
                      if (await canLaunchUrl(Uri.parse(url))) {
                        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.location_on),
                    label: const Text('Mở Google Maps'),
                  ),
                ],
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: SizedBox(height: 40, width: 40, child: CircularProgressIndicator())),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildParentQuickActionRow(_FamilyScope scope) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          height: 94,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SizedBox.expand(
                  child: FilledButton.icon(
                    onPressed: _showEmergencyCallConfirm,
                    icon: const Icon(Icons.sos),
                    label: const Text(
                      'Cuộc gọi\nkhẩn cấp',
                      textAlign: TextAlign.center,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      iconSize: 26,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox.expand(
                  child: FilledButton.icon(
                    onPressed: () => _openShareBoxBottomSheet(scope),
                    icon: const Icon(Icons.photo_library),
                    label: const Text(
                      'ShareBox',
                      textAlign: TextAlign.center,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      iconSize: 26,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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

  Future<void> _showEmergencyCallConfirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gọi khẩn cấp'),
        content: const Text('Bạn có muốn thực hiện cuộc gọi khẩn cấp 115 không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Gọi 115'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _showMessage('Vui lòng gọi 115 để liên hệ cấp cứu khẩn cấp.');
    }
  }

  Widget _buildTopActionRow(_FamilyScope scope) {
    final canAddTasks = scope.selfRole == 'child';
    const actionButtonSize = 56.0;
    const actionGap = 10.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildLocationCard(scope, embedded: true)),
            const SizedBox(width: 10),
            SizedBox(
              width: actionButtonSize,
              child: Column(
                children: [
                  _buildSideActionButton(
                    icon: Icons.photo_library,
                    tooltip: 'Mở ShareBox',
                    onTap: () => _openShareBoxBottomSheet(scope),
                    size: actionButtonSize,
                  ),
                  const SizedBox(height: actionGap),
                  _buildSideActionButton(
                    icon: Icons.add,
                    tooltip: canAddTasks
                        ? 'Thêm công việc'
                        : 'Chỉ tài khoản Con được thêm công việc',
                    onTap: canAddTasks
                        ? () => _showTaskDialog(scope: scope)
                        : null,
                    size: actionButtonSize,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    required double size,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: onTap == null ? Colors.grey.shade100 : Colors.blue.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.blueGrey.shade100),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Icon(
                icon,
                size: 26,
                color: onTap == null ? Colors.grey : Colors.blueAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openShareBoxBottomSheet(_FamilyScope scope) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildShareBoxCard(scope),
          ),
        );
      },
    );
  }

  Widget _buildLocationCard(_FamilyScope scope, {bool embedded = false}) {
    final String trackedUid = widget.isChildView
        ? scope.partnerUid
        : scope.selfUid;
    final String title = widget.isChildView
        ? 'Thanh ghim vị trí Cha/Mẹ'
        : 'Vị trí hiện tại (Cha/Mẹ)';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(trackedUid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? {};
        final location = data['location'];
        final lat = location is Map ? location['lat'] : null;
        final lng = location is Map ? location['lng'] : null;
        final address = location is Map ? location['address'] : null;
        final updatedAt = location is Map ? location['updatedAt'] : null;
        final updatedLabel = updatedAt is Timestamp
            ? _formatDateTime(updatedAt.toDate())
            : 'Chưa cập nhật';

        final hasLocation = lat != null && lng != null;
        final mapsUrl = hasLocation
            ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
            : '';

        final tile = Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.place, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (hasLocation) ...[
                Text(
                  widget.isChildView ? 'Địa chỉ cha/mẹ:' : 'Địa chỉ chi tiết:',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (address?.toString().trim().isNotEmpty ?? false)
                      ? address.toString()
                      : '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tọa độ: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cập nhật: $updatedLabel',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    if (!await canLaunchUrl(Uri.parse(mapsUrl))) return;
                    await launchUrl(
                      Uri.parse(mapsUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: const Icon(Icons.location_on),
                  label: const Text('Mở Google Maps'),
                ),
              ] else
                const Text('Chưa có vị trí realtime'),
            ],
          ),
        );

        if (embedded) {
          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blueGrey.shade100),
              borderRadius: BorderRadius.circular(12),
            ),
            child: tile,
          );
        }

        return Card(
          margin: EdgeInsets.zero,
          child: tile,
        );
      },
    );
  }

  Widget _buildDashboardCard(_FamilyScope scope) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _taskStream(scope),
      builder: (context, snapshot) {
        final now = DateTime.now();
        final tasks =
            snapshot.data?.docs.map((d) => _TaskItem.fromDoc(d)).toList() ?? [];

        var completedCount = 0;
        var pendingCount = 0;
        var overdueCount = 0;
        for (final task in tasks) {
          if (task.completed) {
            completedCount++;
          } else if (_isTaskOverdue(task, now)) {
            overdueCount++;
          } else {
            pendingCount++;
          }
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Thống kê công việc',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 112,
                        child: _buildStatTile(
                          label: 'Chưa hoàn thành',
                          value: pendingCount,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 112,
                        child: _buildStatTile(
                          label: 'Đã hết hạn',
                          value: overdueCount,
                          color: Colors.red,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 112,
                        child: _buildStatTile(
                          label: 'Đã hoàn thành',
                          value: completedCount,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatTile({
    required String label,
    required int value,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(
            height: 44,
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ),
          const Spacer(),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskManagerCard(_FamilyScope scope) {
    final canEditTasks = scope.selfRole == 'child';
    final canToggleCompletion = scope.selfRole == 'parent';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Danh sách công việc',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _taskStream(scope),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final tasks =
                    snapshot.data?.docs
                        .map((d) => _TaskItem.fromDoc(d))
                        .toList() ??
                    [];
                final now = DateTime.now();
                final completedTasks = tasks.where((t) => t.completed).toList();
                final pendingTasks = tasks
                    .where((t) => !t.completed && !_isTaskOverdue(t, now))
                    .toList();
                final overdueTasks = tasks
                    .where((t) => !t.completed && _isTaskOverdue(t, now))
                    .toList();

                if (tasks.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Chưa có công việc nào.'),
                  );
                }

                const listHeight = 420.0;
                return DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: 'Chưa hoàn thành'),
                          Tab(text: 'Đã hết hạn'),
                          Tab(text: 'Đã hoàn thành'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: listHeight,
                        child: TabBarView(
                          children: [
                            _buildTaskTabList(
                              scope: scope,
                              tasks: pendingTasks,
                              canEditTasks: canEditTasks,
                              canToggleCompletion: canToggleCompletion,
                              emptyMessage: 'Không có công việc đang chờ.',
                              highlightColor: Colors.orange,
                            ),
                            _buildTaskTabList(
                              scope: scope,
                              tasks: overdueTasks,
                              canEditTasks: canEditTasks,
                              canToggleCompletion: canToggleCompletion,
                              emptyMessage: 'Không có công việc quá hạn.',
                              highlightColor: Colors.red,
                            ),
                            _buildTaskTabList(
                              scope: scope,
                              tasks: completedTasks,
                              canEditTasks: canEditTasks,
                              canToggleCompletion: canToggleCompletion,
                              emptyMessage: 'Chưa có công việc hoàn thành.',
                              highlightColor: Colors.green,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareBoxCard(_FamilyScope scope) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ShareBox',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Chia sẻ ảnh từ camera hoặc thư viện. Ảnh sẽ đồng bộ realtime.',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _uploadingImage
                        ? null
                        : () => _pickAndUploadImage(scope, ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Chụp ảnh'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _uploadingImage
                        ? null
                        : () => _pickAndUploadImage(scope, ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Thư viện'),
                  ),
                ),
              ],
            ),
            if (_uploadingImage)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(),
              ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _shareStream(scope),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final images =
                    snapshot.data?.docs
                        .map((d) => _ShareImage.fromDoc(d))
                        .toList() ??
                    [];
                if (images.isEmpty) {
                  return const Text('Chưa có ảnh nào trong ShareBox.');
                }

                return SizedBox(
                  height: 260,
                  child: ListView.separated(
                    itemCount: images.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final image = images[index];
                      return Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blueGrey.shade100),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              image.imageUrl,
                              width: 54,
                              height: 54,
                              cacheWidth: 108,
                              cacheHeight: 108,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image),
                            ),
                          ),
                          title: Text(image.fileName),
                          subtitle: Text(
                            'Từ: ${image.senderRole == 'parent' ? 'Cha/Mẹ' : 'Con'}\n'
                            'Lúc: ${_formatDateTime(image.createdAt)}',
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskTabList({
    required _FamilyScope scope,
    required List<_TaskItem> tasks,
    required bool canEditTasks,
    required bool canToggleCompletion,
    required String emptyMessage,
    required Color highlightColor,
  }) {
    if (tasks.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(color: Colors.black54),
        ),
      );
    }

    return ListView.separated(
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final task = tasks[index];
        final showFullTaskInfo = widget.isChildView;
        final subtitleLines = <String>[
          if (task.note.isNotEmpty) 'Ghi chú: ${task.note}',
          if (showFullTaskInfo) 'Giờ tạo: ${_formatDateTime(task.createdAt)}',
          'Thời hạn: ${_formatDateTime(task.scheduledAt)}',
          if (showFullTaskInfo)
            'Trạng thái: ${task.completed ? 'Đã check' : 'Chưa check'}',
        ];

        return Container(
          decoration: BoxDecoration(
            color: highlightColor.withValues(alpha: 0.08),
            border: Border.all(color: highlightColor.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            leading: widget.isChildView
                ? null
                : Checkbox(
                    value: task.completed,
                onChanged: canToggleCompletion
                        ? (value) => _toggleTask(scope, task, value ?? false)
                        : null,
                  ),
            title: Text(
              task.title.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(subtitleLines.join('\n')),
            trailing: canEditTasks
                ? PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showTaskDialog(scope: scope, existing: task);
                      } else if (value == 'delete') {
                        _deleteTask(scope, task);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Sửa')),
                      PopupMenuItem(value: 'delete', child: Text('Xóa')),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }

  bool _isTaskOverdue(_TaskItem task, DateTime now) {
    return !task.completed && task.scheduledAt.isBefore(now);
  }
}

class _FamilyScope {
  const _FamilyScope({
    required this.selfUid,
    required this.partnerUid,
    required this.channelId,
    required this.selfRole,
    required this.partnerRole,
  });

  final String selfUid;
  final String partnerUid;
  final String channelId;
  final String selfRole;
  final String partnerRole;
}

class _TaskItem {
  const _TaskItem({
    required this.id,
    required this.title,
    required this.note,
    required this.createdAt,
    required this.scheduledAt,
    required this.completed,
    this.checkedAt,
  });

  final String id;
  final String title;
  final String note;
  final DateTime createdAt;
  final DateTime scheduledAt;
  final bool completed;
  final DateTime? checkedAt;

  factory _TaskItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final createdAt = data['createdAt'];
    final scheduledAt = data['scheduledAt'];
    final checkedAt = data['checkedAt'];
    return _TaskItem(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      note: (data['note'] ?? '').toString(),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      scheduledAt: scheduledAt is Timestamp
          ? scheduledAt.toDate()
          : DateTime.now(),
      completed: data['completed'] == true,
      checkedAt: checkedAt is Timestamp ? checkedAt.toDate() : null,
    );
  }
}

class _ShareImage {
  const _ShareImage({
    required this.fileName,
    required this.imageUrl,
    required this.senderRole,
    required this.createdAt,
  });

  final String fileName;
  final String imageUrl;
  final String senderRole;
  final DateTime createdAt;

  factory _ShareImage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final createdAt = data['createdAt'];
    return _ShareImage(
      fileName: (data['fileName'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      senderRole: (data['senderRole'] ?? '').toString(),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    );
  }
}

