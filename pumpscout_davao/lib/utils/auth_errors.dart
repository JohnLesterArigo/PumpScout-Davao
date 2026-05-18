part of '../main.dart';

String _authErrorMessage(FirebaseAuthException error) {
  return switch (error.code) {
    'email-already-in-use' => 'That email is already registered.',
    'invalid-email' => 'Please enter a valid email address.',
    'user-not-found' => 'No account found for that email.',
    'wrong-password' => 'Incorrect password.',
    'invalid-credential' => 'Invalid email or password.',
    'weak-password' => 'Password should be at least 6 characters.',
    'user-disabled' => 'This account has been disabled.',
    'too-many-requests' => 'Too many attempts. Please try again later.',
    'no-current-user' =>
      'Your account was created, but the verification email could not be sent. Please sign in to resend it.',
    'network-request-failed' => 'Network error. Please check your connection.',
    _ => error.message ?? 'Authentication failed. Please try again.',
  };
}
