import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/theme.dart';

// ── Phone Input ─────────────────────────────────────────────────
class PhoneInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onSubmit;

  const PhoneInput({super.key, required this.controller, this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (_, val, __) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.cyanBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cyanLight, width: 2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const Text('🇮🇳', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                '+91',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w700,
                  color: AppColors.cyanDark,
                  fontSize: 14,
                ),
              ),
              Container(
                width: 1,
                height: 20,
                color: AppColors.cyanLight,
                margin: const EdgeInsets.symmetric(horizontal: 8),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onSubmitted: (_) => onSubmit?.call(),
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.gray900,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '98765 43210',
                    hintStyle: GoogleFonts.nunito(
                      color: AppColors.cyanLight,
                      fontWeight: FontWeight.w700,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (val.text.length == 10)
                Text('✓',
                    style: TextStyle(
                        color: AppColors.cyanDark,
                        fontWeight: FontWeight.w700)),
            ],
          ),
        );
      },
    );
  }
}

// ── OTP Input ───────────────────────────────────────────────────
class OtpInputRow extends StatefulWidget {
  final void Function(String) onCompleted;
  final void Function(String) onChange;

  const OtpInputRow(
      {super.key, required this.onCompleted, required this.onChange});

  @override
  State<OtpInputRow> createState() => _OtpInputRowState();
}

class _OtpInputRowState extends State<OtpInputRow> {
  final List<TextEditingController> _ctrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    for (final n in _nodes) n.dispose();
    super.dispose();
  }

  String get _otp => _ctrls.map((c) => c.text).join();

  void _onChanged(String val, int idx) {
    if (val.isNotEmpty) {
      if (idx < 5) {
        _nodes[idx + 1].requestFocus();
      } else {
        _nodes[idx].unfocus();
      }
    }
    widget.onChange(_otp);
    if (_otp.length == 6) widget.onCompleted(_otp);
  }

  void _onKeyEvent(KeyEvent event, int idx) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _ctrls[idx].text.isEmpty &&
        idx > 0) {
      _nodes[idx - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        return Container(
          width: 44,
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: AppColors.cyanBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cyanLight, width: 2),
          ),
          child: KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (e) => _onKeyEvent(e, i),
            child: TextField(
              controller: _ctrls[i],
              focusNode: _nodes[i],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(1),
              ],
              style: GoogleFonts.nunito(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.cyanDark,
              ),
              decoration:
                  const InputDecoration(border: InputBorder.none, isDense: true),
              onChanged: (v) => _onChanged(v, i),
            ),
          ),
        );
      }),
    );
  }
}

// ── Cyan Button ─────────────────────────────────────────────────
class CyanButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final String label;
  final IconData? icon;

  const CyanButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cyan,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                  Text(
                    label,
                    style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Error Box ───────────────────────────────────────────────────
class ErrorBox extends StatelessWidget {
  final String? message;
  const ErrorBox({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message!,
              style: TextStyle(
                  color: AppColors.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Brand Logo ──────────────────────────────────────────────────
class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Cleen',
              style: GoogleFonts.nunito(
                fontSize: size,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: AppColors.navy,
                letterSpacing: -1,
                height: 1,
              ),
            ),
            Text(
              'zo',
              style: GoogleFonts.nunito(
                fontSize: size,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: AppColors.cyan,
                letterSpacing: -1,
                height: 1,
              ),
            ),
          ],
        ),
        Positioned(
          top: -size * 0.17,
          right: -size * 0.3,
          child: Text(
            '✦',
            style: TextStyle(
              fontSize: size * 0.37,
              color: AppColors.cyanLight,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}
