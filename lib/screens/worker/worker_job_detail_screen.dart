import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/theme.dart';

class WorkerJobDetailScreen extends StatelessWidget {
  final String id;
  const WorkerJobDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0FDFF),
      appBar: AppBar(
        title: Text('WorkerJobDetailScreen', style: GoogleFonts.nunito(fontWeight: FontWeight.w900, color: AppColors.navy)),
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppColors.navy), onPressed: () => context.pop()),
      ),
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.construction, size: 48, color: AppColors.cyanLight),
        const SizedBox(height: 12),
        Text('ID: ${id}', style: TextStyle(color: AppColors.gray500)),
        Text('Implement from Next.js reference', style: TextStyle(color: AppColors.gray400, fontSize: 12)),
      ])),
    );
  }
}
