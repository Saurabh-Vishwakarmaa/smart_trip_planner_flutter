import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = true;

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: 1),
      );

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFFBF6F2);
    const brand = Color(0xFF065F46);
    const accent = Color(0xFFFFB020);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 75),

              // Brand
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.rotate(
                      angle: 35 * (math.pi / 180),
                      child: const Icon(Icons.flight, size: 28, color: accent),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Itinera AI",
                      style: GoogleFonts.roboto(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: brand,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Title + subtitle
              Center(
                
                child: Text(
                  "Hi, Welcome Back",
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0B1220),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  "Login to your account",
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF98A2B3),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 50),

              // Google button (network icon)
              SizedBox(
                height: 65,
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.network(
                        'https://developers.google.com/identity/images/g-logo.png',
                        height: 20,
                        width: 20,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.g_mobiledata, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Text("Sign in with Google",
                          style: GoogleFonts.inter(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Divider with label
              Row(
                children: [
                  const Expanded(child: Divider(color: Color(0xFFE7EAF0))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      "or Sign in with Email",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFFA0A7B4),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: Color(0xFFE7EAF0))),
                ],
              ),

              const SizedBox(height: 16),

              // Email
              Text(
                "Email address",
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF374151),
                  fontWeight: FontWeight.normal,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 65,
                child: TextField(
                      minLines: null,
                      maxLines: null,expands: true,
                  
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: "john@example.com",
                    hintStyle: GoogleFonts.inter(
                        color: const Color(0xFF9CA3AF), fontSize: 14),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 12, right: 8),
                      child: Icon(CupertinoIcons.envelope,
                          size: 18, color: Color(0xFF6B7280)),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 0, minHeight: 0),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    enabledBorder: _border(const Color(0xFFE5E7EB)),
                    focusedBorder: _border(brand),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Password
              Text(
                "Password",
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF374151),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 65,
                child: TextField(

                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  obscuringCharacter: '•',

  
                  decoration: InputDecoration(
                    constraints: const BoxConstraints(minHeight: 65),
                    hintText: "••••••••",
                    hintStyle: GoogleFonts.inter(
                        color: const Color(0xFF9CA3AF), fontSize: 16),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 12, right: 8),
                      child: Icon(CupertinoIcons.lock,
                          size: 18, color: Color(0xFF6B7280)),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 0, minHeight: 0),
                    suffixIcon: IconButton(
                      splashRadius: 18,
                      icon: Icon(
                        _obscurePassword
                            ? CupertinoIcons.eye_slash
                            : CupertinoIcons.eye,
                        size: 18,
                        color: const Color(0xFF6B7280),
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 20),
                        
                    enabledBorder: _border(const Color(0xFFE5E7EB)),
                    focusedBorder: _border(brand),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Remember me + Forgot password
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (v) =>
                          setState(() => _rememberMe = v ?? false),
                      activeColor: brand,
                      checkColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity:
                          const VisualDensity(horizontal: -4, vertical: -4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Remember me",
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF111827),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {},
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      "Forgot your password?",
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 25),

              // Primary CTA
              SizedBox(
                height: 65,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/home');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text("Login"),
                ),
              ),

              const SizedBox(height: 22),
            ],
          ),
        ),
      ),
    );
  }
}