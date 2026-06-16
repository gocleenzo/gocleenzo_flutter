import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _cyan   = Color(0xFF06B6D4);
const _cyanDk = Color(0xFF0891B2);
const _star   = Color(0xFFF59E0B);
const _ink    = Color(0xFF0F172A);
const _muted  = Color(0xFF64748B);

/// Compulsory post-service review. Returns true once submitted.
/// The customer cannot dismiss it without submitting (canPop: false).
Future<bool?> showReviewPopup(
  BuildContext context, {
  required String bookingId,
  String? workerId,
  String? serviceId,
  String? serviceName,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ReviewPopup(
      bookingId: bookingId,
      workerId: workerId,
      serviceId: serviceId,
      serviceName: serviceName,
    ),
  );
}

class _ReviewPopup extends StatefulWidget {
  final String bookingId;
  final String? workerId;
  final String? serviceId;
  final String? serviceName;
  const _ReviewPopup({
    required this.bookingId,
    this.workerId,
    this.serviceId,
    this.serviceName,
  });

  @override
  State<_ReviewPopup> createState() => _ReviewPopupState();
}

class _ReviewPopupState extends State<_ReviewPopup> {
  int _serviceStars = 0;
  int _workerStars = 0;
  final _msgCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _serviceStars > 0 && _workerStars > 0 && !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit) {
      setState(() => _error = 'Please rate both the service and the worker.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final c = Supabase.instance.client;
    try {
      await c.from('reviews').upsert({
        'booking_id': widget.bookingId,
        'customer_id': c.auth.currentUser!.id,
        if (widget.workerId != null) 'worker_id': widget.workerId,
        if (widget.serviceId != null) 'service_id': widget.serviceId,
        'service_rating': _serviceStars,
        'worker_rating': _workerStars,
        'comment':
            _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
      }, onConflict: 'booking_id');
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not submit. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // compulsory — must submit to close
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(20),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.celebration_rounded,
                        color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(height: 14),
                const Center(
                  child: Text('How did it go?',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: _ink)),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    widget.serviceName == null
                        ? 'Your service is complete'
                        : 'Rate your ${widget.serviceName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: _muted),
                  ),
                ),
                const SizedBox(height: 22),

                _starBlock('Service', _serviceStars,
                    (v) => setState(() => _serviceStars = v)),
                const SizedBox(height: 18),
                _starBlock('Worker', _workerStars,
                    (v) => setState(() => _workerStars = v)),
                const SizedBox(height: 18),

                const Text('Leave a message (optional)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _ink)),
                const SizedBox(height: 8),
                TextField(
                  controller: _msgCtrl,
                  maxLines: 3,
                  maxLength: 300,
                  style: const TextStyle(fontSize: 13, color: _ink),
                  decoration: InputDecoration(
                    hintText: 'Tell us about your experience...',
                    hintStyle: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    counterText: '',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: Color(0xFFE2E8F0))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: _cyanDk, width: 2)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _canSubmit ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _cyanDk,
                      disabledBackgroundColor: const Color(0xFFCBD5E1),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.4))
                        : const Text('Submit review',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _starBlock(String label, int value, ValueChanged<int> onChange) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 8),
        Row(
          children: List.generate(5, (i) {
            final filled = i < value;
            return GestureDetector(
              onTap: () {
                onChange(i + 1);
                HapticFeedback.lightImpact();
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  filled ? Icons.star_rounded : Icons.star_border_rounded,
                  color: filled ? _star : const Color(0xFFCBD5E1),
                  size: 38,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}