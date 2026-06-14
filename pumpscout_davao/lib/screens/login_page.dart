part of '../main.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _inkBlue = Color(0xFF102A43);
  static const _deepBlue = Color(0xFF07192F);
  static const _redAccent = Color(0xFFE94B5A);
  static const _fieldFill = Color(0xFFF7FAFC);

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final vehicleNameController = TextEditingController();
  bool isSignUp = false;
  bool rememberMe = true;
  bool isPasswordVisible = false;
  bool isLoading = false;
  bool isSendingPasswordReset = false;
  String vehicleWheels = '4 wheels';
  String vehicleUse = 'Private';
  String preferredFuelType = 'Gasoline';
  String? feedbackText;
  bool isFeedbackError = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    vehicleNameController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    final displayName = nameController.text.trim();

    if (email.isEmpty ||
        password.isEmpty ||
        (isSignUp && displayName.isEmpty)) {
      setState(() {
        feedbackText = 'Please complete all required fields.';
        isFeedbackError = true;
      });
      return;
    }

    setState(() {
      isLoading = true;
      feedbackText = null;
      isFeedbackError = true;
    });

    try {
      final auth = FirebaseAuth.instance;
      UserCredential credential;

      if (isSignUp) {
        credential = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        await credential.user?.updateDisplayName(displayName);
        final user = credential.user;
        if (user != null) {
          await user.sendEmailVerification();
          try {
            await saveUserProfile(
              user,
              displayName: displayName,
              vehicleProfile: {
                'name': vehicleNameController.text.trim(),
                'wheels': vehicleWheels,
                'use': vehicleUse,
                'preferredFuelType': preferredFuelType,
              },
              emailVerified: false,
            );
          } catch (error) {
            debugPrint('Profile save after sign-up failed: $error');
          }
          await auth.signOut();
        }
        if (!mounted) return;
        setState(() {
          isSignUp = false;
          feedbackText =
              'Verification email sent to $email. Please verify before signing in.';
          isFeedbackError = false;
        });
        return;
      } else {
        credential = await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      final user = credential.user;
      if (user != null) {
        await user.reload();
        final refreshedUser = auth.currentUser ?? user;
        if (requiresEmailVerification(refreshedUser) &&
            !refreshedUser.emailVerified) {
          await refreshedUser.sendEmailVerification();
          await auth.signOut();
          if (!mounted) return;
          setState(() {
            feedbackText =
                'Please verify your email first. We sent a new verification link to $email.';
            isFeedbackError = true;
          });
          return;
        }

        await saveUserProfile(
          refreshedUser,
          displayName: displayName,
          emailVerified: refreshedUser.emailVerified,
        );
      }
    } on FirebaseAuthException catch (error) {
      setState(() {
        if (isSignUp && error.code == 'email-already-in-use') {
          isSignUp = false;
          feedbackText =
              'That email already has an account. Sign in with your password, then check your inbox for the verification link.';
        } else {
          feedbackText = _authErrorMessage(error);
        }
        isFeedbackError = true;
      });
    } catch (error) {
      setState(() {
        feedbackText = 'Login failed. Please try again.';
        isFeedbackError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> saveUserProfile(
    User user, {
    required String displayName,
    Map<String, String>? vehicleProfile,
    bool? emailVerified,
  }) async {
    final now = Timestamp.now();
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final snapshot = await userRef.get();
    final userData = <String, Object?>{
      'uid': user.uid,
      'email': user.email,
      'displayName': displayName.isNotEmpty
          ? displayName
          : user.displayName ?? '',
      'emailVerified': emailVerified ?? user.emailVerified,
      'lastLoginAt': now,
      if (!snapshot.exists) 'createdAt': now,
      if (!snapshot.exists) 'role': 'user',
    };
    if (vehicleProfile != null) {
      userData['vehicle'] = vehicleProfile;
    }

    await userRef.set(userData, SetOptions(merge: true));
    try {
      await syncPublicLeaderboardProfile(user, displayName: displayName);
    } catch (error) {
      debugPrint('Public leaderboard profile sync failed: $error');
    }
  }

  void toggleMode() {
    setState(() {
      isSignUp = !isSignUp;
      feedbackText = null;
      isFeedbackError = true;
    });
  }

  Future<void> sendPasswordReset() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      setState(() {
        feedbackText = 'Enter your email address first.';
        isFeedbackError = true;
      });
      return;
    }

    setState(() {
      isSendingPasswordReset = true;
      feedbackText = null;
      isFeedbackError = true;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() {
        feedbackText = 'Password reset email sent to $email.';
        isFeedbackError = false;
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        feedbackText = _authErrorMessage(error);
        isFeedbackError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        feedbackText = 'Password reset failed. Please try again.';
        isFeedbackError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          isSendingPasswordReset = false;
        });
      }
    }
  }

  void showSocialLoginMessage(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$provider sign-in is not configured yet.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _deepBlue,
      body: Stack(
        children: [
          const Positioned.fill(child: _AuthBackground()),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(0, 0, 0, 24 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: isSignUp
                        ? const SizedBox.shrink()
                        : TweenAnimationBuilder<double>(
                            key: const ValueKey('login-map-header'),
                            tween: Tween(begin: 0.96, end: 1),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (context, scale, child) {
                              return Transform.scale(
                                scale: scale,
                                child: child,
                              );
                            },
                            child: const _LoginHeaderBackground(),
                          ),
                  ),
                  SizedBox(height: isSignUp ? 18 : 18),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final offset = Tween<Offset>(
                              begin: const Offset(0, 0.04),
                              end: Offset.zero,
                            ).animate(animation);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: offset,
                                child: child,
                              ),
                            );
                          },
                          child: Column(
                            key: ValueKey(isSignUp),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                isSignUp ? 'Create Account' : 'Welcome Back!',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isSignUp
                                    ? 'Join PumpScout Davao and start tracking smarter fuel stops.'
                                    : 'Sign in to find fuel prices, route estimates, and nearby stations.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 14,
                                  height: 1.45,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (isSignUp)
                                _authField(
                                  controller: nameController,
                                  label: 'Full name*',
                                  hintText: 'Juan dela Cruz',
                                  icon: Icons.person_outline,
                                  textInputAction: TextInputAction.next,
                                ),
                              if (isSignUp) ...[
                                _authField(
                                  controller: vehicleNameController,
                                  label: 'Vehicle name or model',
                                  hintText: 'Toyota Vios',
                                  icon: Icons.directions_car_outlined,
                                  textInputAction: TextInputAction.next,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _authDropdownField(
                                        label: 'Vehicle',
                                        icon: Icons.two_wheeler_outlined,
                                        value: vehicleWheels,
                                        items: const ['4 wheels', '2 wheels'],
                                        onChanged: (value) {
                                          setState(() {
                                            vehicleWheels = value;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _authDropdownField(
                                        label: 'Use',
                                        icon: Icons.badge_outlined,
                                        value: vehicleUse,
                                        items: const ['Private', 'Public'],
                                        onChanged: (value) {
                                          setState(() {
                                            vehicleUse = value;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                _authDropdownField(
                                  label: 'Preferred fuel type',
                                  icon: Icons.local_gas_station_outlined,
                                  value: preferredFuelType,
                                  items: const [
                                    'Gasoline',
                                    'Diesel',
                                    'Premium Gasoline',
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      preferredFuelType = value;
                                    });
                                  },
                                ),
                              ],
                              _authField(
                                controller: emailController,
                                label: 'Email address',
                                icon: Icons.mail_outline,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                              ),
                              _authField(
                                controller: passwordController,
                                label: 'Password',
                                icon: Icons.lock_outline,
                                obscureText: !isPasswordVisible,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => submit(),
                                suffixIcon: IconButton(
                                  tooltip: isPasswordVisible
                                      ? 'Hide password'
                                      : 'Show password',
                                  onPressed: () {
                                    setState(() {
                                      isPasswordVisible = !isPasswordVisible;
                                    });
                                  },
                                  icon: Icon(
                                    isPasswordVisible
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: _inkBlue.withValues(alpha: 0.54),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: Checkbox(
                                      value: rememberMe,
                                      activeColor: _redAccent,
                                      checkColor: Colors.white,
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.74,
                                        ),
                                        width: 1.5,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      onChanged: (value) {
                                        setState(() {
                                          rememberMe = value ?? true;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Remember me',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.80,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (!isSignUp)
                                    TextButton(
                                      onPressed:
                                          isSendingPasswordReset || isLoading
                                          ? null
                                          : sendPasswordReset,
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.zero,
                                        minimumSize: const ui.Size(0, 36),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'Forgot Password?',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (feedbackText != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (isFeedbackError
                                                ? _redAccent
                                                : const Color(0xFF1E8E3E))
                                            .withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          (isFeedbackError
                                                  ? _redAccent
                                                  : const Color(0xFF1E8E3E))
                                              .withValues(alpha: 0.36),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        isFeedbackError
                                            ? Icons.error_outline
                                            : Icons.check_circle_outline,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          feedbackText!,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (isSendingPasswordReset) ...[
                                const SizedBox(height: 12),
                                const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Sending reset email...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 24),
                              SizedBox(
                                height: 54,
                                child: FilledButton.icon(
                                  onPressed: isLoading || isSendingPasswordReset
                                      ? null
                                      : submit,
                                  icon: Icon(
                                    isSignUp
                                        ? Icons.person_add_alt_1
                                        : Icons.route,
                                    size: 20,
                                  ),
                                  label: Text(
                                    isLoading
                                        ? 'Please wait...'
                                        : isSignUp
                                        ? 'Create account'
                                        : 'Sign in',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _redAccent,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: _redAccent
                                        .withValues(alpha: 0.46),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              _socialDivider(),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: _socialButton(
                                      label: 'Google',
                                      mark: 'G',
                                      onPressed: () =>
                                          showSocialLoginMessage('Google'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _socialButton(
                                      label: 'Apple',
                                      icon: Icons.apple,
                                      onPressed: () =>
                                          showSocialLoginMessage('Apple'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),
                              Center(
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      isSignUp
                                          ? 'Already have an account? '
                                          : "Don't have an account? ",
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.68,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: toggleMode,
                                      child: Text(
                                        isSignUp ? 'Sign in' : 'Sign up',
                                        style: const TextStyle(
                                          color: _redAccent,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _authField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool obscureText = false,
    Widget? suffixIcon,
    ValueChanged<String>? onSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(label),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            obscureText: obscureText,
            style: const TextStyle(
              color: _inkBlue,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: hintText,
              filled: true,
              fillColor: _fieldFill,
              hintStyle: TextStyle(
                color: _inkBlue.withValues(alpha: 0.42),
                fontWeight: FontWeight.w600,
              ),
              prefixIcon: Icon(icon, size: 20, color: _redAccent),
              suffixIcon: suffixIcon,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 17,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.20),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: _redAccent, width: 1.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _authDropdownField({
    required String label,
    required IconData icon,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(label),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: value,
            dropdownColor: _fieldFill,
            style: const TextStyle(
              color: _inkBlue,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: _fieldFill,
              prefixIcon: Icon(icon, size: 20, color: _redAccent),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.20),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: _redAccent, width: 1.8),
              ),
            ),
            items: items
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              onChanged(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.88),
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
    );
  }

  Widget _socialDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.14))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Or continue with',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.66),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.14))),
      ],
    );
  }

  Widget _socialButton({
    required String label,
    required VoidCallback onPressed,
    String? mark,
    IconData? icon,
  }) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          backgroundColor: Colors.white.withValues(alpha: 0.04),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mark != null)
              Text(
                mark,
                style: const TextStyle(
                  color: Color(0xFF4285F4),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              )
            else
              Icon(icon, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginHeaderBackground extends StatelessWidget {
  const _LoginHeaderBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 282,
      width: double.infinity,
      alignment: Alignment.topCenter,
      child: Image.asset(
        'assets/images/pslogo_transparent.png',
        width: double.infinity,
        height: 262,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.local_gas_station, color: Colors.white, size: 72),
      ),
    );
  }
}

class _AuthBackground extends StatelessWidget {
  const _AuthBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF07192F), Color(0xFF061222), Color(0xFF0C1726)],
        ),
      ),
      child: CustomPaint(painter: _BackgroundDotPainter()),
    );
  }
}

class _BackgroundDotPainter extends CustomPainter {
  const _BackgroundDotPainter();

  @override
  void paint(Canvas canvas, ui.Size size) {
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..style = PaintingStyle.fill;
    final redPaint = Paint()
      ..color = _LoginPageState._redAccent.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var y = 20.0; y < size.height; y += 18) {
      for (var x = 18.0; x < size.width; x += 18) {
        if ((x + y).round() % 4 == 0) {
          canvas.drawCircle(Offset(x, y), 1.1, dotPaint);
        }
      }
    }

    canvas.drawCircle(Offset(size.width * 0.18, 88), 84, redPaint);
    canvas.drawCircle(Offset(size.width * 0.86, 180), 112, redPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
