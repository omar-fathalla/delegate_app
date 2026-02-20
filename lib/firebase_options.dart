// ignore_for_file: type=lint
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
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC3IAfxOSBzBsir0d9silrqHQK5b3dcEJQ',
    appId: '1:564223619997:web:382c753c3b586f52233574',
    messagingSenderId: '564223619997',
    projectId: 'practice-firebase-72df1',
    authDomain: 'practice-firebase-72df1.firebaseapp.com',
    storageBucket: 'practice-firebase-72df1.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAdPKLrk8zh93k6IQMs1l3wwHqPlv7tlsc',
    appId: '1:564223619997:android:170b65e4929f759d233574',
    messagingSenderId: '564223619997',
    projectId: 'practice-firebase-72df1',
    storageBucket: 'practice-firebase-72df1.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAi6ryBU40avvR0X6xwk7DAeyvNlrYhpgc',
    appId: '1:564223619997:ios:b9d69e6cf6fe5d87233574',
    messagingSenderId: '564223619997',
    projectId: 'practice-firebase-72df1',
    storageBucket: 'practice-firebase-72df1.firebasestorage.app',
    iosClientId:
        '564223619997-n7bfrj732fs10j5g3ar1e18sdgru5d90.apps.googleusercontent.com',
    iosBundleId: 'com.example.delegateApp',
  );
}
