import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geolocator/geolocator.dart';
import '../services/background_location_service.dart';
import '../services/location_service.dart';
import '../services/cloudinary_service.dart';

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
  bool _isDisposing = false;
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
      if (!mounted || _isDisposing) return;
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
    if (_isDisposing) return;
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

    if (!mounted || _isDisposing) return;
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
    if (_isRestoringSession || _isDisposing) return;
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
  if (!mounted || _isDisposing) return;
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
          if (!mounted || _isDisposing) return;
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

        if (!mounted || _isDisposing) return;

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
        if (!mounted || _isDisposing) return;
        setState(() => _step = 0);
      }
    } catch (e) {
      if (!mounted || _isDisposing) return;
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
        if (!mounted) return;
        setState(() => _step = 0);
      }
    } catch (e) {
      if (!mounted) return;
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

      if (role == 'parent') {
        final granted = await _ensureParentAlwaysPermissionBeforeEnterHome();
        if (!granted || !mounted) {
          _showMessage(
            'Cha/Mẹ cần cấp quyền vị trí "Luôn cho phép" để vào màn hình chính.',
          );
          return;
        }
      }

      final route = MaterialPageRoute(
        builder: (_) =>
            role == 'child' ? const ChildHomePage() : const ParentHomePage(),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await Navigator.of(context).pushReplacement(route);
    } finally {
      _isNavigatingToRoleHome = false;
    }
  }

  Future<bool> _ensureParentAlwaysPermissionBeforeEnterHome() async {
    if (defaultTargetPlatform != TargetPlatform.android || !mounted) {
      return true;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      final openLocationSettings = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Bật dịch vụ vị trí'),
          content: const Text(
            'Cha/Mẹ phải bật dịch vụ vị trí và cấp quyền "Luôn cho phép" mới được vào màn hình chính.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Đóng'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Mở cài đặt'),
            ),
          ],
        ),
      );

      if (openLocationSettings == true) {
        await Geolocator.openLocationSettings();
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.always) {
      return true;
    }

    if (!mounted) return false;
    final openAppSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Yêu cầu quyền Luôn cho phép'),
        content: const Text(
          'Cha/Mẹ bắt buộc cấp quyền vị trí ở mức "Luôn cho phép" để dùng theo dõi nền. Nếu chưa cấp, sẽ chưa vào được màn hình chính.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Đóng'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Mở cài đặt app'),
          ),
        ],
      ),
    );

    if (openAppSettings == true) {
      await Geolocator.openAppSettings();
    }

    return false;
  }

  @override
  void dispose() {
    _isDisposing = true;
    FocusManager.instance.primaryFocus?.unfocus();
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
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _parentLocationSub;
    bool _updatingLocation = false;
  static const int _maxImageSizeBytes = 5 * 1024 * 1024;
  static const int _maxVideoSizeBytes = 40 * 1024 * 1024;
  static const String _alwaysPermissionPromptKeyPrefix =
      'location.always.prompted';
  static const Set<String> _allowedExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  };
  static const Set<String> _allowedVideoExtensions = {
    'mp4',
    'mov',
    'm4v',
    'webm',
    '3gp',
  };

  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _chatComposerController = TextEditingController();
  final ValueNotifier<int> _composerUiVersion = ValueNotifier<int>(0);
  bool _loadingScope = true;
  bool _uploadingImage = false;
  bool _cancelUploadRequested = false;
  double _uploadProgress = 0;
  double _currentImageProgress = 0;
  String _currentImageName = '';
  String _uploadProgressLabel = '';
  CancelToken? _activeUploadCancelToken;
  final ValueNotifier<int> _shareBoxUiVersion = ValueNotifier<int>(0);
  DateTime _lastProgressPaintAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastPaintedOverallProgress = 0;
  double _lastPaintedCurrentProgress = 0;
  int _chatLoadLimit = 30;
  int _shareLoadLimit = 30;
  bool _loadingOlderChats = false;
  List<_PendingShareUpload> _pendingComposerUploads = [];
  bool _mediaPickerActive = false;
  _ComposerPickerMode _composerPickerMode = _ComposerPickerMode.all;
  List<AssetEntity> _composerGalleryAssets = [];
  final Map<String, Uint8List?> _composerThumbCache = {};
  final Set<String> _composerThumbLoading = <String>{};
  bool _composerGalleryLoading = false;
  bool _composerGalleryHasMore = true;
  int _composerGalleryPage = 0;
  final ScrollController _composerMediaScrollController = ScrollController();
  final ScrollController _chatTimelineScrollController = ScrollController();
  int _lastTimelineItemCount = 0;
  String? _lastTimelineTailKey;
  String? _scopeError;
  _FamilyScope? _scope;

  bool _isDeletedForUser(
    Map<String, dynamic> data,
    String uid,
  ) {
    final deletedFor = data['deletedFor'];
    if (deletedFor is! List) return false;
    return deletedFor.any((e) => e?.toString() == uid);
  }

  Future<void> _deleteTimelineItemForMe(
    _FamilyScope scope,
    _ShareTimelineItem item,
  ) async {
    try {
      if (item.isChat) {
        await _chatCollection(scope).doc(item.chat!.id).set({
          'deletedFor': FieldValue.arrayUnion([scope.selfUid]),
        }, SetOptions(merge: true));
      } else {
        await _shareCollection(scope).doc(item.media!.id).set({
          'deletedFor': FieldValue.arrayUnion([scope.selfUid]),
        }, SetOptions(merge: true));
      }
    } on FirebaseException catch (e) {
      _showMessage('Không thể xóa ở phía tôi: ${e.message ?? e.code}');
    } catch (e) {
      _showMessage('Không thể xóa ở phía tôi: $e');
    }
  }

  Future<void> _revokeTimelineItem(
    _FamilyScope scope,
    _ShareTimelineItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Thu hồi tin nhắn'),
        content: const Text(
          'Tin nhắn/media sẽ bị xóa ở cả bên gửi và bên nhận. Bạn có chắc chắn?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Thu hồi'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (item.isChat) {
        await _chatCollection(scope).doc(item.chat!.id).delete();
      } else {
        await _shareCollection(scope).doc(item.media!.id).delete();
      }
    } on FirebaseException catch (e) {
      _showMessage('Không thể thu hồi: ${e.message ?? e.code}');
    } catch (e) {
      _showMessage('Không thể thu hồi: $e');
    }
  }

  Future<void> _showMyMessageActions(
    _FamilyScope scope,
    _ShareTimelineItem item,
  ) async {
    if (item.senderUid != scope.selfUid) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Thu hồi'),
                subtitle: const Text('Xóa ở cả bên gửi và bên nhận'),
                onTap: () => Navigator.of(sheetContext).pop('revoke'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Xóa ở phía tôi'),
                subtitle: const Text('Chỉ xóa/ẩn ở bên bạn'),
                onTap: () => Navigator.of(sheetContext).pop('delete_for_me'),
              ),
            ],
          ),
        );
      },
    );

    if (selected == 'revoke') {
      await _revokeTimelineItem(scope, item);
    } else if (selected == 'delete_for_me') {
      await _deleteTimelineItemForMe(scope, item);
    }
  }

  void _notifyComposerUi() {
    if (!mounted) return;
    _composerUiVersion.value = _composerUiVersion.value + 1;
  }

  @override
  void initState() {
    super.initState();
    _composerMediaScrollController.addListener(_onComposerMediaScroll);
    _loadFamilyScope();
    if (!widget.isChildView) {
      _startLocationTracking();
    } else {
      _listenParentLocation();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _activeUploadCancelToken?.cancel('disposed');
    _chatComposerController.dispose();
    _composerMediaScrollController.dispose();
    _chatTimelineScrollController.dispose();
    _shareBoxUiVersion.dispose();
    _composerUiVersion.dispose();
    _positionStreamSub?.cancel();
    _parentLocationSub?.cancel();
    super.dispose();
  }

  void _notifyShareBoxUi() {
    if (!mounted) return;
    _shareBoxUiVersion.value = _shareBoxUiVersion.value + 1;
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showMessage('Vui lòng bật dịch vụ vị trí trên thiết bị.');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showMessage('Ứng dụng chưa có quyền truy cập vị trí.');
      return false;
    }

    return true;
  }

  Future<void> _ensureAlwaysPermissionPromptedForParent() async {
    if (widget.isChildView ||
        defaultTargetPlatform != TargetPlatform.android ||
        !mounted) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = '$_alwaysPermissionPromptKeyPrefix.${user.uid}';
    final promptedBefore = prefs.getBool(key) ?? false;
    if (promptedBefore) return;

    final currentPermission = await Geolocator.checkPermission();
    if (currentPermission == LocationPermission.always) {
      await prefs.setBool(key, true);
      return;
    }

    if (!mounted) return;
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Bật quyền vị trí luôn cho phép'),
          content: const Text(
            'Để cập nhật vị trí liên tục khi tắt app, vui lòng chọn quyền vị trí "Luôn cho phép" trong cài đặt ứng dụng.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Để sau'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Mở cài đặt'),
            ),
          ],
        );
      },
    );

    if (shouldOpenSettings == true) {
      await Geolocator.openAppSettings();
    }

    await prefs.setBool(key, true);
  }

  // Cha/mẹ: Theo dõi vị trí và cập nhật Firestore
  void _startLocationTracking() async {
    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission || !mounted) return;

    await _ensureAlwaysPermissionPromptedForParent();

    await BackgroundLocationService.start();

    _positionStreamSub?.cancel();
    try {
      final locationStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
      _positionStreamSub = locationStream.listen((pos) async {
        if (!mounted) return;
        setState(() => _currentPosition = pos);
        final address = await LocationService.getAddressFromLatLng(
          pos.latitude,
          pos.longitude,
        );
        if (!mounted) return;
        setState(() => _currentAddress = address);
        await _updateLocationToFirestore(pos, address);
      }, onError: (error) {
        _showMessage('Không thể theo dõi vị trí realtime: $error');
      });

      // Lấy vị trí lần đầu
      final pos = await LocationService.getCurrentPosition();
      if (!mounted) return;
      if (pos != null) {
        setState(() => _currentPosition = pos);
        final address = await LocationService.getAddressFromLatLng(
          pos.latitude,
          pos.longitude,
        );
        if (!mounted) return;
        setState(() => _currentAddress = address);
        await _updateLocationToFirestore(pos, address);
      }
    } catch (e) {
      _showMessage('Không thể khởi tạo theo dõi vị trí: $e');
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
    await BackgroundLocationService.stop();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Lấy uid cha/mẹ
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!mounted) return;
    final parentUid = (doc.data()?['parentUid'] ?? '').toString();
    if (parentUid.isEmpty) return;
    _parentLocationSub?.cancel();
    _parentLocationSub = FirebaseFirestore.instance
        .collection('users')
        .doc(parentUid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
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
    if (!mounted) return;
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
      if (!mounted) return;
      final data = currentDoc.data() ?? {};
      final expectedRole = widget.isChildView ? 'child' : 'parent';
      final currentRole = (data['role'] ?? '').toString().trim();
      if (currentRole != expectedRole) {
        await currentRef.set({'role': expectedRole}, SetOptions(merge: true));
        if (!mounted) return;
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
              if (!mounted) return;
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

      if (!mounted) return;
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
      if (!mounted) return;
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

  CollectionReference<Map<String, dynamic>> _chatCollection(
    _FamilyScope scope,
  ) {
    return FirebaseFirestore.instance
        .collection('channels')
        .doc(scope.channelId)
        .collection('chatMessages');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _taskStream(_FamilyScope scope) {
    return _taskCollection(
      scope,
    ).orderBy('scheduledAt', descending: false).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _shareStream(_FamilyScope scope) {
    return _shareStreamWithLimit(scope);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _shareStreamWithLimit(
    _FamilyScope scope, {
    int? limit,
  }) {
    final query = _shareCollection(
      scope,
    ).orderBy('createdAt', descending: true);

    return (limit != null ? query.limit(limit) : query).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _chatStream(
    _FamilyScope scope, {
    int? limit,
  }) {
    final query = _chatCollection(
      scope,
    ).orderBy('createdAt', descending: true);

    return (limit != null ? query.limit(limit) : query).snapshots();
  }

  Future<void> _sendChatMessage(_FamilyScope scope, String rawMessage) async {
    final message = rawMessage.trim();
    if (message.isEmpty) {
      return;
    }

    try {
      await _chatCollection(scope).add({
        'text': message,
        'senderUid': scope.selfUid,
        'senderRole': scope.selfRole,
        'createdAt': FieldValue.serverTimestamp(),
      });
      FocusManager.instance.primaryFocus?.unfocus();
    } on FirebaseException catch (e) {
      _showMessage('Không thể gửi tin nhắn: ${e.message ?? e.code}');
    } catch (e) {
      _showMessage('Không thể gửi tin nhắn: $e');
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlderChats) return;
    setState(() {
      _loadingOlderChats = true;
      _chatLoadLimit += 20;
      _shareLoadLimit += 20;
    });

    // Keep the flag true briefly so the next snapshot expansion doesn't
    // trigger auto-scroll-to-latest while the user is intentionally loading
    // older history.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _loadingOlderChats = false);
  }

  Future<void> _sendCurrentComposerMessage(_FamilyScope scope) async {
    final raw = _chatComposerController.text.trim();
    if (raw.isEmpty && _pendingComposerUploads.isEmpty) {
      return;
    }

    if (_pendingComposerUploads.isEmpty && raw.isNotEmpty) {
      await _sendChatMessage(scope, raw);
    }

    if (_pendingComposerUploads.isNotEmpty) {
      final uploads = _pendingComposerUploads
          .map((item) => item.copyWith(caption: ''))
          .toList();
      await _uploadSelectedImages(scope, uploads: uploads);
      if (!mounted) return;
      _pendingComposerUploads = [];
      _notifyComposerUi();
    }

    if (!mounted) return;
    _chatComposerController.clear();
    if (_mediaPickerActive) {
      _exitComposerMediaPicker();
    }
    _autoScrollChatToLatest(force: true);
  }

  Future<void> _captureComposerImageWithPreview(_FamilyScope scope) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (picked == null) return;

      final fileName = picked.name;
      final extension = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';
      if (!_allowedExtensions.contains(extension)) {
        _showMessage('Định dạng ảnh chưa được hỗ trợ.');
        return;
      }

      final fileSize = await picked.length();
      if (fileSize <= 0 || fileSize > _maxImageSizeBytes) {
        _showMessage('Ảnh không hợp lệ hoặc vượt quá 5MB.');
        return;
      }

      final previewBytes = await picked.readAsBytes();
      if (!mounted) return;
      final result = await Navigator.of(context).push<_CapturePreviewResult>(
        MaterialPageRoute(
          builder: (_) => _CapturePreviewPage(
            title: 'Ảnh vừa chụp',
            fileName: fileName,
            isVideo: false,
            previewBytes: previewBytes,
          ),
        ),
      );

      if (result?.send != true) return;

      await _uploadSelectedImages(
        scope,
        uploads: [
          _PendingShareUpload(
            file: picked,
            fileName: fileName,
            extension: extension,
            sizeBytes: fileSize,
            caption: '',
            bytes: previewBytes,
            mediaType: _ShareMediaType.image,
          ),
        ],
      );

      if (_mediaPickerActive) {
        await _loadComposerGalleryPage(reset: true);
      }
    } on PlatformException catch (e) {
      _showMessage('Không thể chụp ảnh: ${e.message ?? e.code}');
    } catch (e) {
      _showMessage('Không thể chụp ảnh: $e');
    }
  }

  Future<void> _captureComposerVideoWithPreview(_FamilyScope scope) async {
    try {
      final picked = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 3),
      );
      if (picked == null) return;

      final fileName = picked.name;
      final extension = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';
      if (!_allowedVideoExtensions.contains(extension)) {
        _showMessage('Định dạng video chưa được hỗ trợ.');
        return;
      }

      final fileSize = await picked.length();
      if (fileSize <= 0 || fileSize > _maxVideoSizeBytes) {
        _showMessage('Video không hợp lệ hoặc vượt quá 40MB.');
        return;
      }

      if (!mounted) return;
      final result = await Navigator.of(context).push<_CapturePreviewResult>(
        MaterialPageRoute(
          builder: (_) => _CapturePreviewPage(
            title: 'Video vừa quay',
            fileName: fileName,
            isVideo: true,
            previewBytes: null,
          ),
        ),
      );

      if (result?.send != true) return;

      await _uploadSelectedImages(
        scope,
        uploads: [
          _PendingShareUpload(
            file: picked,
            fileName: fileName,
            extension: extension,
            sizeBytes: fileSize,
            caption: '',
            bytes: Uint8List(0),
            mediaType: _ShareMediaType.video,
          ),
        ],
      );

      if (_mediaPickerActive) {
        await _loadComposerGalleryPage(reset: true);
      }
    } on PlatformException catch (e) {
      _showMessage('Không thể quay video: ${e.message ?? e.code}');
    } catch (e) {
      _showMessage('Không thể quay video: $e');
    }
  }

  Future<void> _enterComposerMediaPicker(_ComposerPickerMode mode) async {
    _mediaPickerActive = true;
    _composerPickerMode = mode;
    _chatComposerController.clear();
    _pendingComposerUploads = [];
    _composerGalleryAssets = [];
    _composerThumbCache.clear();
    _composerThumbLoading.clear();
    _composerGalleryPage = 0;
    _composerGalleryHasMore = true;
    _notifyComposerUi();
    await _loadComposerGalleryPage(reset: true);
  }

  void _exitComposerMediaPicker() {
    _mediaPickerActive = false;
    _pendingComposerUploads = [];
    _composerGalleryAssets = [];
    _composerThumbCache.clear();
    _composerThumbLoading.clear();
    _composerGalleryPage = 0;
    _composerGalleryHasMore = true;
    _notifyComposerUi();
  }

  Future<void> _prefetchComposerThumbs(List<AssetEntity> assets) async {
    final missing = assets
        .where(
          (asset) =>
              !_composerThumbCache.containsKey(asset.id) &&
              !_composerThumbLoading.contains(asset.id),
        )
        .toList();
    if (missing.isEmpty) return;

    _composerThumbLoading.addAll(missing.map((e) => e.id));
    final loaded = <String, Uint8List?>{};
    try {
      const batchSize = 4;
      for (var i = 0; i < missing.length; i += batchSize) {
        final batch = missing.skip(i).take(batchSize).toList();
        final results = await Future.wait(
          batch.map(
            (asset) => asset.thumbnailDataWithSize(
              const ThumbnailSize.square(180),
              quality: 65,
            ),
          ),
        );
        for (var j = 0; j < batch.length; j++) {
          loaded[batch[j].id] = results[j];
        }
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _composerThumbLoading.removeAll(missing.map((e) => e.id));
    }

    if (!mounted) return;
    _composerThumbCache.addAll(loaded);
    _notifyComposerUi();
  }

  void _onComposerMediaScroll() {
    if (!_mediaPickerActive || _composerGalleryLoading || !_composerGalleryHasMore) {
      return;
    }
    if (_composerMediaScrollController.position.extentAfter < 300) {
      _loadComposerGalleryPage();
    }
  }

  Future<void> _loadComposerGalleryPage({bool reset = false}) async {
    if (_composerGalleryLoading) return;
    if (!reset && !_composerGalleryHasMore) return;

    _composerGalleryLoading = true;
    _notifyComposerUi();
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        _showMessage('Cần quyền truy cập thư viện để chọn media.');
        return;
      }

      final requestType = _composerPickerMode == _ComposerPickerMode.image
          ? RequestType.image
          : _composerPickerMode == _ComposerPickerMode.video
              ? RequestType.video
              : RequestType.common;

      final filterOption = FilterOptionGroup()
        ..addOrderOption(
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        );

      final albums = await PhotoManager.getAssetPathList(
        type: requestType,
        onlyAll: true,
        filterOption: filterOption,
      );

      if (albums.isEmpty) {
        if (!mounted) return;
        _composerGalleryAssets = [];
        _composerGalleryHasMore = false;
        _notifyComposerUi();
        return;
      }

      if (reset) {
        _composerGalleryPage = 0;
      }

      final fetched = await albums.first.getAssetListPaged(
        page: _composerGalleryPage,
        size: 36,
      );

      if (!mounted) return;
      if (reset) {
        _composerGalleryAssets = fetched;
      } else {
        _composerGalleryAssets = [
          ..._composerGalleryAssets,
          ...fetched,
        ];
      }
      _composerGalleryPage += 1;
      _composerGalleryHasMore = fetched.length == 36;
      _notifyComposerUi();
      unawaited(_prefetchComposerThumbs(fetched.take(18).toList()));
    } catch (e) {
      _showMessage('Không thể tải thư viện media: $e');
    } finally {
      if (mounted) {
        _composerGalleryLoading = false;
        _notifyComposerUi();
      }
    }
  }

  int _composerCameraTileCount() {
    return _composerPickerMode == _ComposerPickerMode.all ? 2 : 1;
  }

  Widget _buildComposerCameraTile({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueGrey.shade200),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: Colors.black54),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<_PendingShareUpload?> _buildPendingUploadFromAsset(AssetEntity asset) async {
    final file = await asset.file;
    if (file == null) return null;

    final fileName = file.path.split(RegExp(r'[\\/]')).last;
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    final mediaType = asset.type == AssetType.video
        ? _ShareMediaType.video
        : _ShareMediaType.image;
    final sizeBytes = await file.length();

    if (mediaType == _ShareMediaType.image) {
      if (!_allowedExtensions.contains(extension) ||
          sizeBytes <= 0 ||
          sizeBytes > _maxImageSizeBytes) {
        _showMessage('Ảnh không hợp lệ hoặc vượt quá 5MB.');
        return null;
      }
    } else {
      if (!_allowedVideoExtensions.contains(extension) ||
          sizeBytes <= 0 ||
          sizeBytes > _maxVideoSizeBytes) {
        _showMessage('Video không hợp lệ hoặc vượt quá 40MB.');
        return null;
      }
    }

    return _PendingShareUpload(
      file: XFile(file.path, name: fileName),
      fileName: fileName,
      extension: extension,
      sizeBytes: sizeBytes,
      caption: '',
      bytes: Uint8List(0),
      mediaType: mediaType,
      sourceId: asset.id,
    );
  }

  int _selectedOrderForAsset(String assetId) {
    return _pendingComposerUploads.indexWhere((item) => item.sourceId == assetId);
  }

  Future<void> _toggleComposerAsset(AssetEntity asset) async {
    final currentIndex = _selectedOrderForAsset(asset.id);
    if (currentIndex >= 0) {
      _pendingComposerUploads.removeAt(currentIndex);
      _notifyComposerUi();
      return;
    }

    final pendingUpload = await _buildPendingUploadFromAsset(asset);
    if (pendingUpload == null || !mounted) return;
    _pendingComposerUploads = [..._pendingComposerUploads, pendingUpload];
    _notifyComposerUi();
  }

  String _formatAssetDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildComposerGalleryTile(_FamilyScope scope, int index) {
    final cameraTiles = _composerCameraTileCount();
    if (index < cameraTiles) {
      if (_composerPickerMode == _ComposerPickerMode.video) {
        return _buildComposerCameraTile(
          label: 'Quay video',
          icon: Icons.videocam_outlined,
          onTap: _uploadingImage ? null : () => _captureComposerVideoWithPreview(scope),
        );
      }

      if (_composerPickerMode == _ComposerPickerMode.image) {
        return _buildComposerCameraTile(
          label: 'Chụp ảnh',
          icon: Icons.camera_alt_outlined,
          onTap: _uploadingImage ? null : () => _captureComposerImageWithPreview(scope),
        );
      }

      // all-mode: show 2 separate tiles.
      if (index == 0) {
        return _buildComposerCameraTile(
          label: 'Chụp ảnh',
          icon: Icons.camera_alt_outlined,
          onTap: _uploadingImage ? null : () => _captureComposerImageWithPreview(scope),
        );
      }
      return _buildComposerCameraTile(
        label: 'Quay video',
        icon: Icons.videocam_outlined,
        onTap: _uploadingImage ? null : () => _captureComposerVideoWithPreview(scope),
      );
    }

    final assetIndex = index - cameraTiles;
    final asset = _composerGalleryAssets[assetIndex];
    final selectedOrder = _selectedOrderForAsset(asset.id);
    final thumbBytes = _composerThumbCache[asset.id];
    if (thumbBytes == null && !_composerThumbLoading.contains(asset.id)) {
      unawaited(_prefetchComposerThumbs([asset]));
    }

    return GestureDetector(
      onTap: _uploadingImage ? null : () => _toggleComposerAsset(asset),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumbBytes == null)
            Container(
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.image_outlined, color: Colors.black45),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(thumbBytes, fit: BoxFit.cover),
            ),
          if (selectedOrder >= 0)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueAccent, width: 2),
              ),
            ),
          if (asset.type == AssetType.video)
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam, size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      _formatAssetDuration(
                        Duration(seconds: asset.duration),
                      ),
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selectedOrder >= 0 ? Colors.blueAccent : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selectedOrder >= 0 ? Colors.blueAccent : Colors.black38,
                  width: 1.5,
                ),
              ),
              child: selectedOrder >= 0
                  ? Text(
                      '${selectedOrder + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposerMediaPickerPanel(_FamilyScope scope) {
    final mediaTitle = _composerPickerMode == _ComposerPickerMode.image
      ? 'Ảnh'
      : _composerPickerMode == _ComposerPickerMode.video
        ? 'Video'
        : 'Media';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Quay lại',
              onPressed: _uploadingImage ? null : _exitComposerMediaPicker,
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                '$mediaTitle đã chọn: ${_pendingComposerUploads.length}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Gửi',
              onPressed: _uploadingImage || _pendingComposerUploads.isEmpty
                  ? null
                  : () => _sendCurrentComposerMessage(scope),
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: GridView.builder(
            controller: _composerMediaScrollController,
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: _composerGalleryAssets.length + _composerCameraTileCount(),
            itemBuilder: (context, index) {
              return _buildComposerGalleryTile(scope, index);
            },
          ),
        ),
        if (_composerGalleryLoading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(
              height: 20,
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openImageAttachMenu(_FamilyScope scope) async {
    await _enterComposerMediaPicker(_ComposerPickerMode.image);
  }

  Future<void> _openVideoAttachMenu(_FamilyScope scope) async {
    await _enterComposerMediaPicker(_ComposerPickerMode.video);
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
                      : () {
                          FocusScope.of(dialogContext).unfocus();
                          Navigator.of(dialogContext).pop();
                        },
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
                            FocusScope.of(dialogContext).unfocus();
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

    FocusManager.instance.primaryFocus?.unfocus();
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
    try {
      var effectiveSource = source;
      if (kIsWeb && source == ImageSource.camera) {
        // Desktop Chrome often cannot provide a direct camera stream for image_picker.
        effectiveSource = ImageSource.gallery;
      }

      final picked = await _imagePicker.pickImage(
        source: effectiveSource,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 90,
      );
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

      final Uint8List bytes = await picked.readAsBytes();
      final caption = await _showShareComposerDialog(
        previewBytes: bytes,
        fileName: fileName,
        fileSize: fileSize,
        isVideo: false,
      );
      if (caption == null) {
        _showMessage('Đã hủy gửi ảnh.');
        return;
      }

      await _uploadSelectedImages(
        scope,
        uploads: [
          _PendingShareUpload(
            file: picked,
            fileName: fileName,
            extension: extension,
            sizeBytes: fileSize,
            caption: caption.trim(),
            bytes: bytes,
            mediaType: _ShareMediaType.image,
          ),
        ],
      );
    } on PlatformException catch (e) {
      _showMessage('Không thể chọn ảnh trên thiết bị này: ${e.message ?? e.code}');
    } catch (e) {
      _showMessage('Không thể xử lý ảnh đã chọn: $e');
    }
  }

  Future<void> _pickAndUploadVideo(_FamilyScope scope) async {
    try {
      final picked = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 3),
      );
      if (picked == null) {
        _showMessage('Không có video được chọn.');
        return;
      }

      final fileName = picked.name;
      final extension = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';
      if (!_allowedVideoExtensions.contains(extension)) {
        _showMessage('Video không hợp lệ. Chỉ hỗ trợ MP4, MOV, M4V, WEBM, 3GP.');
        return;
      }

      final fileSize = await picked.length();
      if (fileSize <= 0) {
        _showMessage('Video không hợp lệ hoặc rỗng.');
        return;
      }
      if (fileSize > _maxVideoSizeBytes) {
        _showMessage('Video vượt quá 40MB. Vui lòng chọn video nhỏ hơn.');
        return;
      }

      final bytes = await picked.readAsBytes();
      final caption = await _showShareComposerDialog(
        previewBytes: null,
        fileName: fileName,
        fileSize: fileSize,
        isVideo: true,
      );
      if (caption == null) {
        _showMessage('Đã hủy gửi video.');
        return;
      }

      await _uploadSelectedImages(
        scope,
        uploads: [
          _PendingShareUpload(
            file: picked,
            fileName: fileName,
            extension: extension,
            sizeBytes: fileSize,
            caption: caption.trim(),
            bytes: bytes,
            mediaType: _ShareMediaType.video,
          ),
        ],
      );
    } on PlatformException catch (e) {
      _showMessage('Không thể chọn video trên thiết bị này: ${e.message ?? e.code}');
    } catch (e) {
      _showMessage('Không thể xử lý video đã chọn: $e');
    }
  }

  Future<String?> _showShareComposerDialog({
    required Uint8List? previewBytes,
    required String fileName,
    required int fileSize,
    required bool isVideo,
  }) async {
    final captionController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isVideo ? 'Gửi video trực tiếp' : 'Gửi ảnh trực tiếp'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isVideo)
                  Container(
                    width: 280,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Icon(Icons.videocam, size: 56),
                    ),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      previewBytes!,
                      width: 280,
                      height: 280,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  fileName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Dung lượng: ${(fileSize / 1024).toStringAsFixed(1)} KB',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: captionController,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả (không bắt buộc)',
                    hintText: 'Ví dụ: Cha đang uống thuốc sau ăn',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Hủy'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.of(dialogContext).pop(captionController.text);
              },
              icon: const Icon(Icons.send),
              label: const Text('Gửi ngay'),
            ),
          ],
        );
      },
    );

    FocusManager.instance.primaryFocus?.unfocus();
    return result;
  }

  Future<void> _pickAndUploadMultipleImages(_FamilyScope scope) async {
    try {
      final pickedFiles = await _imagePicker.pickMultiImage(imageQuality: 90);
      if (pickedFiles.isEmpty) {
        _showMessage('Không có ảnh nào được chọn.');
        return;
      }

      final validUploads = <_PendingShareUpload>[];
      var skippedCount = 0;

      for (final picked in pickedFiles) {
        final fileName = picked.name;
        final extension = fileName.contains('.')
            ? fileName.split('.').last.toLowerCase()
            : '';
        if (!_allowedExtensions.contains(extension)) {
          skippedCount++;
          continue;
        }

        final fileSize = await picked.length();
        if (fileSize <= 0 || fileSize > _maxImageSizeBytes) {
          skippedCount++;
          continue;
        }

        final bytes = await picked.readAsBytes();
        validUploads.add(
          _PendingShareUpload(
            file: picked,
            fileName: fileName,
            extension: extension,
            sizeBytes: fileSize,
            caption: '',
            bytes: bytes,
            mediaType: _ShareMediaType.image,
          ),
        );
      }

      if (validUploads.isEmpty) {
        _showMessage('Không có ảnh hợp lệ để gửi (định dạng hoặc dung lượng > 5MB).');
        return;
      }

      final batchCaption = await _showBatchCaptionDialog(
        validCount: validUploads.length,
        skippedCount: skippedCount,
      );
      if (batchCaption == null) {
        _showMessage('Đã hủy gửi nhiều ảnh.');
        return;
      }

      for (var i = 0; i < validUploads.length; i++) {
        validUploads[i] = validUploads[i].copyWith(caption: batchCaption.trim());
      }

      await _uploadSelectedImages(scope, uploads: validUploads);
    } on PlatformException catch (e) {
      _showMessage('Không thể mở hộp chọn ảnh: ${e.message ?? e.code}');
    } catch (e) {
      _showMessage('Không thể xử lý danh sách ảnh: $e');
    }
  }

  Future<void> _uploadSelectedImages(
    _FamilyScope scope, {
    required List<_PendingShareUpload> uploads,
  }) async {
    if (uploads.isEmpty) return;

    final totalBytes = uploads.fold<int>(0, (acc, item) => acc + item.sizeBytes);
    var uploadedBytes = 0;
    var successCount = 0;

    setState(() {
      _uploadingImage = true;
      _cancelUploadRequested = false;
      _uploadProgress = 0;
      _currentImageProgress = 0;
      _currentImageName = '';
      _uploadProgressLabel = 'Bắt đầu tải media...';
    });
    _lastProgressPaintAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastPaintedOverallProgress = 0;
    _lastPaintedCurrentProgress = 0;
    _notifyShareBoxUi();

    try {
      for (var index = 0; index < uploads.length; index++) {
        if (_cancelUploadRequested) {
          break;
        }

        final item = uploads[index];
        _activeUploadCancelToken = CancelToken();
        if (mounted) {
          final effectiveTotal = totalBytes == 0 ? 1 : totalBytes;
          setState(() {
            _currentImageName = item.fileName;
            _uploadProgressLabel =
                'Đang tải ${index + 1}/${uploads.length}: ${item.fileName}';
            _currentImageProgress = 0;
            _uploadProgress = (uploadedBytes / effectiveTotal).clamp(0, 1);
          });
        }

        final uploadBytes =
            item.bytes.isNotEmpty ? item.bytes : await item.file.readAsBytes();

        final uploaded = await CloudinaryService.uploadBytes(
          bytes: uploadBytes,
          fileName: item.fileName,
          folder: 'sharebox/${scope.channelId}',
          resourceType: item.mediaType == _ShareMediaType.video
              ? 'video'
              : 'image',
          cancelToken: _activeUploadCancelToken,
          onProgress: (sent, total) {
            if (!mounted || _cancelUploadRequested) return;

            final safeTotal = total <= 0 ? item.sizeBytes : total;
            final currentProgress = (sent / safeTotal).clamp(0.0, 1.0);
            final effectiveTotal = totalBytes == 0 ? 1 : totalBytes;
            final overallProgress =
                ((uploadedBytes + (item.sizeBytes * currentProgress)) /
                        effectiveTotal)
                    .clamp(0.0, 1.0);

            final now = DateTime.now();
            final msSinceLast =
                now.difference(_lastProgressPaintAt).inMilliseconds;
            final isSignificantJump =
                (overallProgress - _lastPaintedOverallProgress).abs() > 0.02 ||
                (currentProgress - _lastPaintedCurrentProgress).abs() > 0.02 ||
                currentProgress >= 1;
            if (msSinceLast < 70 && !isSignificantJump) {
              return;
            }

            _lastProgressPaintAt = now;
            _lastPaintedOverallProgress = overallProgress;
            _lastPaintedCurrentProgress = currentProgress;
            _currentImageProgress = currentProgress;
            _uploadProgress = overallProgress;
            _uploadProgressLabel =
                'Đang tải ${index + 1}/${uploads.length}: ${item.fileName} (${(currentProgress * 100).toStringAsFixed(0)}%)';
            _notifyShareBoxUi();
          },
        );

        if (_cancelUploadRequested) {
          break;
        }

        uploadedBytes += item.sizeBytes;
        _activeUploadCancelToken = null;
        if (mounted) {
          final effectiveTotal = totalBytes == 0 ? 1 : totalBytes;
          setState(() {
            _currentImageProgress = 1;
            _uploadProgress = (uploadedBytes / effectiveTotal).clamp(0, 1);
          });
          _notifyShareBoxUi();
        }

        await _shareCollection(scope).add({
          'imageUrl': uploaded.secureUrl,
          'mediaUrl': uploaded.secureUrl,
          'mediaType': item.mediaType == _ShareMediaType.video
              ? 'video'
              : 'image',
          'cloudinaryPublicId': uploaded.publicId,
          'storageProvider': 'cloudinary',
          'fileName': item.fileName,
          'caption': item.caption,
          'sizeBytes': item.sizeBytes,
          'senderUid': scope.selfUid,
          'senderRole': scope.selfRole,
          'createdAt': FieldValue.serverTimestamp(),
        });
        successCount++;
      }

      if (_cancelUploadRequested) {
        _showMessage(
          'Đã hủy upload. Đã gửi thành công $successCount/${uploads.length} media.',
        );
        return;
      }

      if (mounted) {
        setState(() {
          _uploadProgress = 1;
          _currentImageProgress = 1;
          _uploadProgressLabel =
              'Hoàn tất $successCount/${uploads.length} media';
        });
        _notifyShareBoxUi();
      }
      _showMessage('Đã chia sẻ $successCount/${uploads.length} media thành công.');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _showMessage(
          'Đã hủy upload. Đã gửi thành công $successCount/${uploads.length} media.',
        );
      } else {
        _showMessage('Upload media thất bại: ${e.message ?? e.toString()}');
      }
    } on StateError catch (e) {
      _showMessage(e.message);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (_cancelUploadRequested || msg.contains('canceled')) {
        _showMessage(
          'Đã hủy upload. Đã gửi thành công $successCount/${uploads.length} media.',
        );
      } else {
        _showMessage('Upload media thất bại: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingImage = false;
          _cancelUploadRequested = false;
          _uploadProgress = 0;
          _currentImageProgress = 0;
          _currentImageName = '';
          _uploadProgressLabel = '';
        });
        _notifyShareBoxUi();
      }
      _activeUploadCancelToken = null;
    }
  }

  Future<void> _cancelUploadingImages() async {
    if (!_uploadingImage) return;

    _cancelUploadRequested = true;
    if (mounted) {
      setState(() {
        _uploadingImage = false;
        _uploadProgress = 0;
        _currentImageProgress = 0;
        _currentImageName = '';
        _uploadProgressLabel = 'Đã hủy upload.';
      });
      _notifyShareBoxUi();
    }

    try {
      _activeUploadCancelToken?.cancel('user canceled');
      _showMessage('Đã hủy upload.');
    } catch (_) {
      // Ignore cancellation race conditions.
    }
  }

  Future<String?> _showBatchCaptionDialog({
    required int validCount,
    required int skippedCount,
  }) async {
    final captionController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Gửi nhiều ảnh'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sẵn sàng gửi $validCount ảnh.'),
              if (skippedCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '$skippedCount ảnh bị bỏ qua vì không hợp lệ hoặc quá 5MB.',
                  style: const TextStyle(color: Colors.orange),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: captionController,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Mô tả chung (không bắt buộc)',
                  hintText: 'Ví dụ: Ảnh tình hình hôm nay',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Hủy'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.of(dialogContext).pop(captionController.text);
              },
              icon: const Icon(Icons.send),
              label: const Text('Gửi ngay'),
            ),
          ],
        );
      },
    );

    FocusManager.instance.primaryFocus?.unfocus();
    return result;
  }

  // ignore: unused_element
  Future<void> _deleteSharedMedia(
    _FamilyScope scope,
    _ShareImage image,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa media'),
        content: Text('Bạn có chắc muốn xóa "${image.fileName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _shareCollection(scope).doc(image.id).delete();
      _showMessage('Đã xóa media khỏi ShareBox.');
    } catch (e) {
      _showMessage('Không thể xóa media: $e');
    }
  }

  Future<void> _openImagePreview(_ShareImage image) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: image.isVideo
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: _InlineVideoPlayer(url: image.imageUrl),
                      )
                    : InteractiveViewer(
                        child: Image.network(
                          image.imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Không thể tải ảnh.'),
                            ),
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      image.fileName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (image.caption.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(image.caption),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Đóng'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
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
    FocusManager.instance.primaryFocus?.unfocus();
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

  void _autoScrollChatToLatest({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatTimelineScrollController.hasClients) return;

      final position = _chatTimelineScrollController.position;
      final shouldScroll = force || position.extentAfter < 220;
      if (!shouldScroll) return;

      final target = position.maxScrollExtent;
      if ((target - position.pixels).abs() < 2) return;

      _chatTimelineScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
    });
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
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text(
                      'Chat',
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
                    icon: Icons.chat_bubble_outline,
                    tooltip: 'Mở Chat',
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
    _chatLoadLimit = 30;
    _shareLoadLimit = 30;
    _lastTimelineItemCount = 0;
    _lastTimelineTailKey = null;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Chat'),
              backgroundColor: Colors.blueAccent,
            ),
            body: SafeArea(child: _buildChatPage(scope)),
          );
        },
      ),
    );
  }

  Widget _buildChatPage(_FamilyScope scope) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _shareStreamWithLimit(scope, limit: _shareLoadLimit),
              builder: (context, shareSnapshot) {
                if (shareSnapshot.connectionState == ConnectionState.waiting &&
                    !shareSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (shareSnapshot.hasError) {
                  return const Center(child: Text('Không thể tải media.'));
                }

                final shareDocs = shareSnapshot.data?.docs ?? const [];
                final mediaEntries = shareDocs
                    .where(
                      (doc) => !_isDeletedForUser(doc.data(), scope.selfUid),
                    )
                    .map((d) => _ShareImage.fromDoc(d))
                    .toList();

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _chatStream(scope, limit: _chatLoadLimit),
                  builder: (context, chatSnapshot) {
                    if (chatSnapshot.connectionState ==
                            ConnectionState.waiting &&
                        !chatSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (chatSnapshot.hasError) {
                      return Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.red.shade50,
                        ),
                        padding: const EdgeInsets.all(12),
                        child: const Text(
                          'Không thể tải chat. Kiểm tra Firestore Rules để cấp quyền đọc/ghi chatMessages.',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    final chatEntries = chatSnapshot.data?.docs
                            .where(
                              (doc) =>
                                  !_isDeletedForUser(doc.data(), scope.selfUid),
                            )
                            .map((d) => _ChatMessage.fromDoc(d))
                            .toList() ??
                        [];

                    final timelineItems = <_ShareTimelineItem>[
                      ...mediaEntries.map(_ShareTimelineItem.media),
                      ...chatEntries.map(_ShareTimelineItem.chat),
                    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

                    final tailKey = timelineItems.isEmpty
                        ? null
                        : '${timelineItems.last.createdAt.millisecondsSinceEpoch}_${timelineItems.last.senderUid}_${timelineItems.length}';
                    final hasNewTimelineItem =
                        _lastTimelineItemCount != timelineItems.length ||
                        _lastTimelineTailKey != tailKey;
                    if (hasNewTimelineItem && !_loadingOlderChats) {
                      _lastTimelineItemCount = timelineItems.length;
                      _lastTimelineTailKey = tailKey;
                      _autoScrollChatToLatest();
                    }

                    if (timelineItems.isEmpty) {
                      return const Center(child: Text('Chưa có nội dung chat.'));
                    }

                    return RefreshIndicator(
                      onRefresh: _loadOlderMessages,
                      child: ListView.separated(
                        controller: _chatTimelineScrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 10),
                        itemCount: timelineItems.length + 1,
                        separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  _loadingOlderChats
                                      ? 'Đang tải thêm tin nhắn...'
                                      : 'Kéo xuống để tải thêm tin nhắn cũ',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            );
                          }

                          final item = timelineItems[index - 1];
                            final isMine = item.senderUid == scope.selfUid;
                            final sideLabel = item.senderRole == 'parent'
                              ? 'Cha/Mẹ'
                              : 'Con';
                            final alignment = isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft;
                            final bubbleColor = isMine
                              ? Colors.blue.shade50
                              : Colors.grey.shade100;
                            final borderColor = isMine
                              ? Colors.blue.shade200
                              : Colors.blueGrey.shade200;
                          final bubble = ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 250),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: bubbleColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: borderColor),
                              ),
                              child: item.isChat
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.chat!.text,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$sideLabel • ${_formatDateTime(item.createdAt)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    )
                                  : GestureDetector(
                                      onTap: () =>
                                          _openImagePreview(item.media!),
                                      child: item.media!.isVideo
                                          ? Container(
                                              height: 120,
                                              width: 170,
                                              decoration: BoxDecoration(
                                                color: Colors.black12,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Center(
                                                child: Icon(
                                                  Icons.videocam,
                                                  size: 32,
                                                ),
                                              ),
                                            )
                                          : ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.network(
                                                item.media!.imageUrl,
                                                height: 130,
                                                width: 170,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) =>
                                                    const SizedBox(
                                                  height: 120,
                                                  width: 170,
                                                  child: Center(
                                                    child: Icon(
                                                      Icons.broken_image,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ),
                            ),
                          );

                          return Align(
                            alignment: alignment,
                            child: isMine
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      IconButton(
                                        tooltip: 'Tùy chọn',
                                        icon: const Icon(
                                          Icons.more_horiz,
                                          size: 20,
                                        ),
                                        onPressed: () =>
                                            _showMyMessageActions(scope, item),
                                      ),
                                      bubble,
                                    ],
                                  )
                                : bubble,
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.blueGrey.shade100),
            ),
          ),
          child: SafeArea(
            top: false,
            child: ValueListenableBuilder<int>(
              valueListenable: _composerUiVersion,
              builder: (context, composerTick, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_uploadingImage) ...[
                      LinearProgressIndicator(value: _uploadProgress),
                      const SizedBox(height: 8),
                    ],
                    if (_mediaPickerActive)
                      _buildComposerMediaPickerPanel(scope),
                    if (!_mediaPickerActive)
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Chọn ảnh',
                            onPressed: _uploadingImage
                                ? null
                                : () => _openImageAttachMenu(scope),
                            icon: const Icon(Icons.photo_library),
                          ),
                          IconButton(
                            tooltip: 'Chọn video',
                            onPressed: _uploadingImage
                                ? null
                                : () => _openVideoAttachMenu(scope),
                            icon: const Icon(Icons.videocam),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_pendingComposerUploads.isEmpty)
                                  TextField(
                                    controller: _chatComposerController,
                                    minLines: 1,
                                    maxLines: 3,
                                    textInputAction: TextInputAction.send,
                                    decoration: const InputDecoration(
                                      hintText: 'Nhập tin nhắn...',
                                    ),
                                    onSubmitted: (_) =>
                                        _sendCurrentComposerMessage(scope),
                                  ),
                                if (_pendingComposerUploads.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${_pendingComposerUploads.length} tệp đính kèm • ${_pendingComposerUploads.where((e) => e.mediaType == _ShareMediaType.image).length} ảnh, ${_pendingComposerUploads.where((e) => e.mediaType == _ShareMediaType.video).length} video',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                _pendingComposerUploads = [];
                                                _notifyComposerUi();
                                              },
                                              child: const Text('Xóa'),
                                            ),
                                          ],
                                        ),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: _pendingComposerUploads
                                              .map(
                                                (e) => Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        Colors.blueGrey.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: Colors
                                                          .blueGrey.shade100,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    e.fileName,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            margin: const EdgeInsets.only(left: 6),
                            child: IconButton(
                              tooltip: 'Gửi',
                              onPressed: () =>
                                  _sendCurrentComposerMessage(scope),
                              icon: const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
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

  // ignore: unused_element
  Widget _buildShareBoxCard(_FamilyScope scope, {bool fullScreen = false}) {
    const listHeight = 380.0;
    final content = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chat',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Khung chat chung cho tin nhắn và ảnh/video. Cha/Mẹ ở bên phải, Con ở bên trái.',
            ),
            const SizedBox(height: 10),
            _buildShareBoxUploadPanel(scope),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _shareStream(scope),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Không thể tải media ShareBox.');
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final mediaEntries =
                  snapshot.data?.docs
                    .where(
                      (doc) =>
                        !_isDeletedForUser(doc.data(), scope.selfUid),
                    )
                    .map((d) => _ShareImage.fromDoc(d))
                    .toList() ??
                    [];

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _chatStream(scope),
                  builder: (context, chatSnapshot) {
                    if (chatSnapshot.hasError) {
                      return Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.red.shade50,
                        ),
                        padding: const EdgeInsets.all(12),
                        child: const Text(
                          'Không thể tải chat. Kiểm tra Firestore Rules để cấp quyền đọc/ghi chatMessages.',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    if (chatSnapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final chatEntries =
                        chatSnapshot.data?.docs
                            .where(
                              (doc) => !_isDeletedForUser(
                                doc.data(),
                                scope.selfUid,
                              ),
                            )
                            .map((d) => _ChatMessage.fromDoc(d))
                            .toList() ??
                        [];

                    final timelineItems = <_ShareTimelineItem>[
                      ...mediaEntries.map(_ShareTimelineItem.media),
                      ...chatEntries.map(_ShareTimelineItem.chat),
                    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    if (timelineItems.isEmpty) {
                      return const Text('Chưa có nội dung nào trong Chat.');
                    }

                    final timelineList = ListView.separated(
                      reverse: true,
                      shrinkWrap: fullScreen,
                      physics: fullScreen
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      itemCount: timelineItems.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = timelineItems[index];
                        final isMine = item.senderUid == scope.selfUid;
                        final sideLabel = item.senderRole == 'parent'
                            ? 'Cha/Mẹ'
                            : 'Con';
                        final alignment = item.senderRole == 'parent'
                            ? Alignment.centerRight
                            : Alignment.centerLeft;
                        final bubbleColor = item.senderRole == 'parent'
                            ? Colors.blue.shade50
                            : Colors.grey.shade100;
                        final borderColor = item.senderRole == 'parent'
                            ? Colors.blue.shade200
                            : Colors.blueGrey.shade200;

                        final bubble = ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: bubbleColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor),
                            ),
                            child: item.isChat
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.chat!.text,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '$sideLabel • ${_formatDateTime(item.createdAt)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: () =>
                                            _openImagePreview(item.media!),
                                        child: item.media!.isVideo
                                            ? Container(
                                                height: 72,
                                                decoration: BoxDecoration(
                                                  color: Colors.black12,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Center(
                                                  child: Icon(
                                                    Icons.videocam,
                                                    size: 28,
                                                  ),
                                                ),
                                              )
                                            : ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.network(
                                                  item.media!.imageUrl,
                                                  height: 120,
                                                  width: double.infinity,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, _, _) =>
                                                      const SizedBox(
                                                    height: 72,
                                                    child: Center(
                                                      child: Icon(
                                                        Icons.broken_image,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                      ),
                                      if (item.media!.caption
                                          .trim()
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(item.media!.caption.trim()),
                                      ],
                                      const SizedBox(height: 6),
                                      Text(
                                        '$sideLabel • ${item.media!.isVideo ? 'Video' : 'Ảnh'} • ${_formatDateTime(item.createdAt)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        );

                        return Align(
                          alignment: alignment,
                          child: isMine
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    IconButton(
                                      tooltip: 'Tùy chọn',
                                      icon: const Icon(
                                        Icons.more_horiz,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _showMyMessageActions(scope, item),
                                    ),
                                    bubble,
                                  ],
                                )
                              : bubble,
                        );
                      },
                    );

                    if (fullScreen) {
                      return timelineList;
                    }

                    return SizedBox(
                      height: listHeight,
                      child: timelineList,
                    );
                  },
                );
              },
            ),
          ],
        ),
    );

    if (fullScreen) {
      return SingleChildScrollView(
        child: content,
      );
    }

    return Card(child: content);
  }

  Widget _buildShareBoxUploadPanel(_FamilyScope scope) {
    return ValueListenableBuilder<int>(
      valueListenable: _shareBoxUiVersion,
      builder: (context, value, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilledButton.icon(
              onPressed: _uploadingImage ? null : () => _showShareComposer(scope),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Tạo tin nhắn/ảnh/video'),
            ),
            const SizedBox(height: 6),
            const Text(
              'Một nút duy nhất để gửi tin nhắn, chụp ảnh, chọn nhiều ảnh hoặc chọn video trong Chat.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: !_uploadingImage
                  ? const SizedBox.shrink()
                  : Padding(
                      key: const ValueKey('upload-panel-visible'),
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tiến trình tệp hiện tại: ${(_currentImageProgress * 100).toStringAsFixed(0)}%${_currentImageName.isEmpty ? '' : ' • $_currentImageName'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: _currentImageProgress),
                            duration: const Duration(milliseconds: 120),
                            builder: (context, value, child) =>
                                LinearProgressIndicator(value: value),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Tiến trình tổng: ${(_uploadProgress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: _uploadProgress),
                            duration: const Duration(milliseconds: 120),
                            builder: (context, value, child) =>
                                LinearProgressIndicator(value: value),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _uploadProgressLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: _cancelUploadingImages,
                              icon: const Icon(Icons.close),
                              label: const Text('Hủy upload'),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showShareComposer(_FamilyScope scope) async {
    if (_uploadingImage) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Gửi tin nhắn'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showQuickMessageDialog(scope);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(kIsWeb ? 'Chọn ảnh & gửi' : 'Chụp ảnh & gửi'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickAndUploadImage(scope, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Chọn nhiều ảnh'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickAndUploadMultipleImages(scope);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Chọn video'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickAndUploadVideo(scope);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showQuickMessageDialog(_FamilyScope scope) async {
    String draftMessage = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Gửi tin nhắn'),
          content: TextField(
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onChanged: (value) => draftMessage = value,
            onSubmitted: (_) async {
              await _sendChatMessage(scope, draftMessage);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            decoration: const InputDecoration(
              hintText: 'Nhập tin nhắn cho gia đình...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Hủy'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await _sendChatMessage(scope, draftMessage);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              icon: const Icon(Icons.send),
              label: const Text('Gửi'),
            ),
          ],
        );
      },
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

class _CapturePreviewResult {
  const _CapturePreviewResult({required this.send});

  final bool send;
}

class _CapturePreviewPage extends StatelessWidget {
  const _CapturePreviewPage({
    required this.title,
    required this.fileName,
    required this.isVideo,
    required this.previewBytes,
  });

  final String title;
  final String fileName;
  final bool isVideo;
  final Uint8List? previewBytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: isVideo
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.videocam,
                            color: Colors.white70,
                            size: 72,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            fileName,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      )
                    : previewBytes == null
                        ? const SizedBox.shrink()
                        : InteractiveViewer(
                            child: Image.memory(
                              previewBytes!,
                              fit: BoxFit.contain,
                            ),
                          ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: IconButton(
                tooltip: 'Quay lại',
                onPressed: () => Navigator.of(context).pop(
                  const _CapturePreviewResult(send: false),
                ),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            Positioned(
              top: 10,
              left: 56,
              right: 12,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                tooltip: 'Gửi',
                backgroundColor: Colors.blueAccent,
                onPressed: () => Navigator.of(context).pop(
                  const _CapturePreviewResult(send: true),
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
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

class _InlineVideoPlayer extends StatefulWidget {
  const _InlineVideoPlayer({required this.url});

  final String url;

  @override
  State<_InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<_InlineVideoPlayer> {
  late final VideoPlayerController _controller;
  late final Future<void> _initializeFuture;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initializeFuture = _controller.initialize().then((_) {
      _controller.setLooping(false);
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!_controller.value.isInitialized) {
          return const Center(child: Text('Không thể tải video.'));
        }

        return Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: VideoPlayer(_controller),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            VideoProgressIndicator(
              _controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Lùi 10 giây',
                  onPressed: () async {
                    final current = _controller.value.position;
                    final target = current - const Duration(seconds: 10);
                    await _controller.seekTo(
                      target < Duration.zero ? Duration.zero : target,
                    );
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.replay_10),
                ),
                IconButton(
                  tooltip: _controller.value.isPlaying ? 'Tạm dừng' : 'Phát',
                  onPressed: () {
                    if (_controller.value.isPlaying) {
                      _controller.pause();
                    } else {
                      _controller.play();
                    }
                    setState(() {});
                  },
                  icon: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    size: 36,
                  ),
                ),
                IconButton(
                  tooltip: 'Tới 10 giây',
                  onPressed: () async {
                    final current = _controller.value.position;
                    final max = _controller.value.duration;
                    final target = current + const Duration(seconds: 10);
                    await _controller.seekTo(target > max ? max : target);
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.forward_10),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PendingShareUpload {
  const _PendingShareUpload({
    required this.file,
    required this.fileName,
    required this.extension,
    required this.sizeBytes,
    required this.caption,
    required this.bytes,
    required this.mediaType,
    this.sourceId,
  });

  final XFile file;
  final String fileName;
  final String extension;
  final int sizeBytes;
  final String caption;
  final Uint8List bytes;
  final _ShareMediaType mediaType;
  final String? sourceId;

  _PendingShareUpload copyWith({
    String? caption,
  }) {
    return _PendingShareUpload(
      file: file,
      fileName: fileName,
      extension: extension,
      sizeBytes: sizeBytes,
      caption: caption ?? this.caption,
      bytes: bytes,
      mediaType: mediaType,
      sourceId: sourceId,
    );
  }
}

enum _ShareMediaType { image, video }

enum _ComposerPickerMode { all, image, video }

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
    required this.id,
    required this.fileName,
    required this.imageUrl,
    required this.mediaType,
    required this.senderUid,
    required this.senderRole,
    required this.caption,
    required this.createdAt,
  });

  final String id;
  final String fileName;
  final String imageUrl;
  final String mediaType;
  final String senderUid;
  final String senderRole;
  final String caption;
  final DateTime createdAt;

  bool get isVideo => mediaType == 'video';

  factory _ShareImage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final createdAt = data['createdAt'];
    final fileName = (data['fileName'] ?? '').toString();
    final legacyUrl = (data['imageUrl'] ?? '').toString();
    final mediaUrl = (data['mediaUrl'] ?? legacyUrl).toString();
    final rawType = (data['mediaType'] ?? '').toString().toLowerCase();
    final inferredType = rawType.isNotEmpty
        ? rawType
        : (fileName.endsWith('.mp4') ||
                  fileName.endsWith('.mov') ||
                  fileName.endsWith('.m4v') ||
                  fileName.endsWith('.webm') ||
                  fileName.endsWith('.3gp')
              ? 'video'
              : 'image');

    return _ShareImage(
      id: doc.id,
      fileName: fileName,
      imageUrl: mediaUrl,
      mediaType: inferredType,
      senderUid: (data['senderUid'] ?? '').toString(),
      senderRole: (data['senderRole'] ?? '').toString(),
      caption: (data['caption'] ?? '').toString(),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.id,
    required this.text,
    required this.senderUid,
    required this.senderRole,
    required this.createdAt,
  });

  final String id;
  final String text;
  final String senderUid;
  final String senderRole;
  final DateTime createdAt;

  factory _ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final createdAt = data['createdAt'];
    return _ChatMessage(
      id: doc.id,
      text: (data['text'] ?? '').toString(),
      senderUid: (data['senderUid'] ?? '').toString(),
      senderRole: (data['senderRole'] ?? '').toString(),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    );
  }
}

class _ShareTimelineItem {
  const _ShareTimelineItem._({
    required this.chat,
    required this.media,
    required this.createdAt,
    required this.senderUid,
    required this.senderRole,
  });

  factory _ShareTimelineItem.chat(_ChatMessage message) {
    return _ShareTimelineItem._(
      chat: message,
      media: null,
      createdAt: message.createdAt,
      senderUid: message.senderUid,
      senderRole: message.senderRole,
    );
  }

  factory _ShareTimelineItem.media(_ShareImage media) {
    return _ShareTimelineItem._(
      chat: null,
      media: media,
      createdAt: media.createdAt,
      senderUid: media.senderUid,
      senderRole: media.senderRole,
    );
  }

  final _ChatMessage? chat;
  final _ShareImage? media;
  final DateTime createdAt;
  final String senderUid;
  final String senderRole;

  bool get isChat => chat != null;
}

