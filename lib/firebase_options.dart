import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
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
    apiKey: 'AIzaSyDNn7GI9BEQiqEI4STgMsgceSVEnnDLBts',
    appId: '1:808281806068:web:9c7b975836813772f13aa1',
    messagingSenderId: '808281806068',
    projectId: 'smart-node-8578c',
    authDomain: 'smart-node-8578c.firebaseapp.com',
    storageBucket: 'smart-node-8578c.firebasestorage.app',
    measurementId: 'G-RB0PP57SD9',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB2-35YT1RAYbKFsoFj6tSRH5_WbvRKU0U',
    appId: '1:808281806068:android:4c9b1fc22bec7753f13aa1',
    messagingSenderId: '808281806068',
    projectId: 'smart-node-8578c',
    storageBucket: 'smart-node-8578c.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyByz6f0tRTJj3zZ_hRoqayB0n1TrIORqEY',
    appId: '1:808281806068:ios:446ef716a6e19d63f13aa1',
    messagingSenderId: '808281806068',
    projectId: 'smart-node-8578c',
    storageBucket: 'smart-node-8578c.firebasestorage.app',
    androidClientId: '808281806068-35pupt1ld49n52svpcuqv3o2925trhhq.apps.googleusercontent.com',
    iosClientId: '808281806068-m26m49rogr2po7hmqo14g1i0ft356efd.apps.googleusercontent.com',
    iosBundleId: 'com.example.finalapp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyByz6f0tRTJj3zZ_hRoqayB0n1TrIORqEY',
    appId: '1:808281806068:ios:446ef716a6e19d63f13aa1',
    messagingSenderId: '808281806068',
    projectId: 'smart-node-8578c',
    storageBucket: 'smart-node-8578c.firebasestorage.app',
    androidClientId: '808281806068-35pupt1ld49n52svpcuqv3o2925trhhq.apps.googleusercontent.com',
    iosClientId: '808281806068-m26m49rogr2po7hmqo14g1i0ft356efd.apps.googleusercontent.com',
    iosBundleId: 'com.example.finalapp',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDNn7GI9BEQiqEI4STgMsgceSVEnnDLBts',
    appId: '1:808281806068:web:e70eec62d4963d4cf13aa1',
    messagingSenderId: '808281806068',
    projectId: 'smart-node-8578c',
    authDomain: 'smart-node-8578c.firebaseapp.com',
    storageBucket: 'smart-node-8578c.firebasestorage.app',
    measurementId: 'G-6LXVC1YXYQ',
  );

}