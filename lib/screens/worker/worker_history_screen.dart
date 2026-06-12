import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/theme.dart';

class WorkerHistoryScreen extends StatelessWidget {
  const WorkerHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0FDFF),
      appBar: AppBar(
        title: Text('WorkerHistoryScreen', style: GoogleFonts.nunito(fontWeight: FontWeight.w900, color: AppColors.navy)),
        backgroundColor: Colors.transparent, elevation: 0,
      ),
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.construction, size: 48, color: AppColors.cyanLight),
        const SizedBox(height: 12),
        Text('WorkerHistoryScreen', style: GoogleFonts.nunito(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.navy)),
        Text('Implement from Next.js reference', style: TextStyle(color: AppColors.gray400, fontSize: 12)),
      ])),
    );
  }
}
