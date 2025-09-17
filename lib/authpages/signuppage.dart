import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Registerpage extends StatefulWidget {
  const Registerpage({super.key});

  @override
  State<Registerpage> createState() => _RegisterpageState();
}

class _RegisterpageState extends State<Registerpage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFFFBF6F2); // soft cream background
    final brand = const Color(0xFF065F46); // deep green brand
    final accent = Colors.orange;

    OutlineInputBorder _border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: 1),
        );

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 36),

              // Brand
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.rotate(
                    angle: 40 * (3.14159265359 / 180),
                    child: Icon(Icons.flight, size: 28, color: accent),
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

              const SizedBox(height: 28),

              // Title
              Text(
                "Create your Account",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 32,
                  color: const Color(0xFF111827),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Lets get started",
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 28),

              // Google button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    foregroundColor: const Color(0xFF111827),
                    textStyle: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.network(
                        "https://www.gstatic.com/images/branding/product/1x/gsa_64dp.png",
                        height: 22,
                        width: 22,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.g_mobiledata, size: 26),
                      ),
                      const SizedBox(width: 10),
                      Text("Sign up with Google", style: GoogleFonts.inter()),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 22),

              // Divider with label
              Row(
                children: [
                  Expanded(
                      child:
                          Container(height: 1, color: const Color(0xFFE5E7EB))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      "or Sign up with Email",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                      child:
                          Container(height: 1, color: const Color(0xFFE5E7EB))),
                ],
              ),

              const SizedBox(height: 18),

              // Email
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Email address",
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF374151),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: "john@example.com",
                  hintStyle:
                      GoogleFonts.inter(color: const Color(0xFF9CA3AF), fontSize: 14),
                  filled: true,
                  fillColor: Colors.white,

                  // LEFT-ALIGNED prefix icon
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 12, right: 8),
                    child: Icon(CupertinoIcons.envelope,
                        size: 20, color: Color(0xFF6B7280)),
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 0, minHeight: 0),

                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  enabledBorder: _border(const Color(0xFFE5E7EB)),
                  focusedBorder: _border(brand),
                ),
              ),

              const SizedBox(height: 16),

              // Password
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Password",
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF374151),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                enableSuggestions: false,
                autocorrect: false,
                obscuringCharacter: '•',
                decoration: InputDecoration(
                  hintText: "••••••••",
                  hintStyle:
                      GoogleFonts.inter(color: const Color(0xFF9CA3AF), fontSize: 16),
                  filled: true,
                  fillColor: Colors.white,

                  // LEFT-ALIGNED prefix icon
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 12, right: 8),
                    child: Icon(CupertinoIcons.lock,
                        size: 20, color: Color(0xFF6B7280)),
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 0, minHeight: 0),

                  // RIGHT-ALIGNED eye toggle (works)
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      splashRadius: 18,
                      icon: Icon(
                        _obscurePassword
                            ? CupertinoIcons.eye_slash
                            : CupertinoIcons.eye,
                        color: const Color(0xFF6B7280),
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  suffixIconConstraints:
                      const BoxConstraints(minWidth: 0, minHeight: 0),

                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  enabledBorder: _border(const Color(0xFFE5E7EB)),
                  focusedBorder: _border(brand),
                ),
              ),

              const SizedBox(height: 16),

              // Confirm Password
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Confirm Password",
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF374151),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                enableSuggestions: false,
                autocorrect: false,
                obscuringCharacter: '•',
                decoration: InputDecoration(
                  hintText: "••••••••",
                  hintStyle:
                      GoogleFonts.inter(color: const Color(0xFF9CA3AF), fontSize: 16),
                  filled: true,
                  fillColor: Colors.white,

                  // LEFT-ALIGNED prefix icon
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 12, right: 8),
                    child: Icon(CupertinoIcons.lock,
                        size: 20, color: Color(0xFF6B7280)),
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 0, minHeight: 0),

                  // RIGHT-ALIGNED eye toggle (works)
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      splashRadius: 18,
                      icon: Icon(
                        _obscureConfirm
                            ? CupertinoIcons.eye_slash
                            : CupertinoIcons.eye,
                        color: const Color(0xFF6B7280),
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  suffixIconConstraints:
                      const BoxConstraints(minWidth: 0, minHeight: 0),

                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  enabledBorder: _border(const Color(0xFFE5E7EB)),
                  focusedBorder: _border(brand),
                ),
              ),

              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text("Sign UP"),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}