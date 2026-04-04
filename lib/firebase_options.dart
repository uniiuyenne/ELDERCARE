import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC3ZnLNyEofKDIQh7w1tSAcROXgqamzz5E',
    appId: '1:533606697818:web:e36947f1db9f010b344163',
    messagingSenderId: '533606697818',
    projectId: 'careelder-e475b',
    authDomain: 'careelder-e475b.firebaseapp.com',
    storageBucket: 'careelder-e475b.firebasestorage.app',
    measurementId: 'G-QHRYWQNJ8T',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAgUhHU8wSJgO5MVNy95tMT07NEjzMOfz0',
    appId: '1:448618578101:android:0b650370bb29e29cac3efc',
    messagingSenderId: '448618578101',
    projectId: 'react-native-firebase-testing',
    storageBucket: 'react-native-firebase-testing.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAgUhHU8wSJgO5MVNy95tMT07NEjzMOfz0',
    appId: '1:448618578101:ios:0b650370bb29e29cac3efc',
    messagingSenderId: '448618578101',
    projectId: 'react-native-firebase-testing',
    storageBucket: 'react-native-firebase-testing.appspot.com',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAgUhHU8wSJgO5MVNy95tMT07NEjzMOfz0',
    appId: '1:448618578101:macos:0b650370bb29e29cac3efc',
    messagingSenderId: '448618578101',
    projectId: 'react-native-firebase-testing',
    storageBucket: 'react-native-firebase-testing.appspot.com',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAgUhHU8wSJgO5MVNy95tMT07NEjzMOfz0',
    appId: '1:448618578101:windows:0b650370bb29e29cac3efc',
    messagingSenderId: '448618578101',
    projectId: 'react-native-firebase-testing',
    storageBucket: 'react-native-firebase-testing.appspot.com',
  );
}