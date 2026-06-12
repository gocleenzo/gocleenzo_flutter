import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../utils/theme.dart';

class WorkerDashboardScreen extends StatefulWidget {
  const WorkerDashboardScreen({super.key});

  @override
  State<WorkerDashboardScreen> createState() => _WorkerDashboardScreenState();
}

class _WorkerDashboardScreenState extends State<WorkerDashboardScreen> {
  String _workerId = '';
  String _workerName = 'Worker';
  bool _available = true;
  List<Map<String, dynamic>> _newJobs = [];
  Map<String, dynamic>? _activeJob;
  Map<String, int> _stats = {'earned': 0, 'completed': 0};
  bool _loading = true;
  String _actionId = '';
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _channel = SupabaseService.subscribeToBookings(_loadAll);
  }

  @override
  void dispose() {
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _loadAll() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    final profile = await SupabaseService.getUserProfile(user.id);
    final workerData = await SupabaseService.client
        .from('workers')
        .select('is_available')
        .eq('user_id', user.id)
        .maybeSingle();
    final allBookings = await SupabaseService.getAllBookings();

    if (!mounted) return;
    setState(() {
      _workerId = user.id;
      _workerName = (profile?['full_name'] as String?) ?? 'Worker';
      _available = (workerData?['is_available'] as bool?) ?? true;

      _newJobs = allBookings.where((b) => b['status'] == 'pending').toList();

      final activeList = allBookings.where((b) =>
          b['worker_id'] == user.id &&
          ['accepted', 'otp_verified', 'in_progress'].contains(b['status']));
      _activeJob = activeList.isNotEmpty ? activeList.first : null;

      final done = allBookings
          .where((b) => b['worker_id'] == user.id && b['status'] == 'completed')
          .toList();
      _stats = {
        'earned': done.fold(
            0, (s, b) => s + ((b['final_amount'] as num?)?.toInt() ?? 0)),
        'completed': done.length,
      };
      _loading = false;
    });
  }

  Future<void> _acceptJob(String jobId) async {
    setState(() => _actionId = jobId);
    await SupabaseService.acceptJob(jobId, _workerId);
    setState(() => _actionId = '');
    await _loadAll();
  }

  Future<void> _toggleAvailability() async {
    final next = !_available;
    setState(() => _available = next);
    await SupabaseService.updateWorkerAvailability(_workerId, next);
  }

  String _fmtDate(String iso) {
    final d = DateTime.parse(iso);
    return DateFormat('EEE d MMM · hh:mm a').format(d);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0FDFF),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(AppColors.cyan),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0FDFF),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: CustomScrollView(
          slivers: [
            _buildHeader(),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildStatsRow(),
                  const SizedBox(height: 16),
                  if (_activeJob != null) ...[
                    _buildActiveJobCard(),
                    const SizedBox(height: 16),
                  ],
                  _buildSectionTitle('New Jobs (${_newJobs.length})'),
                  const SizedBox(height: 8),
                  if (_newJobs.isEmpty) _emptyJobs(),
                  ..._newJobs.map(_buildJobCard),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        padding: EdgeInsets.fromLTRB(
            20, MediaQuery.of(context).padding.top + 16, 20, 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D2D5E), Color(0xFF1A4080)],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hey, $_workerName 👷',
                      style: GoogleFonts.nunito(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                  const Text('Worker Dashboard',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ),
            ),
            GestureDetector(
              onTap: _toggleAvailability,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _available ? AppColors.success : AppColors.error,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(
                      _available ? 'Online' : 'Offline',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
            child: _statCard(
                '💰', 'Earned Today', '₹${_stats['earned']}', AppColors.success)),
        const SizedBox(width: 12),
        Expanded(
            child: _statCard(
                '✅', 'Completed', '${_stats['completed']}', AppColors.cyan)),
      ],
    );
  }

  Widget _statCard(String icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.1), blurRadius: 12)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          Text(value,
              style: GoogleFonts.nunito(
                  fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          Text(label,
              style: TextStyle(color: AppColors.gray500, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildActiveJobCard() {
    final job = _activeJob!;
    final names =
        (job['service_names'] as List?)?.cast<String>() ?? ['Service'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF0D2D5E), Color(0xFF1A4080)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: AppColors.cyan,
                borderRadius: BorderRadius.circular(100)),
            child: const Text('ACTIVE JOB',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 12),
          Text(names.first,
              style: GoogleFonts.nunito(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 17)),
          const SizedBox(height: 4),
          Text(_fmtDate(job['scheduled_at'] as String),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => context.push('/worker/jobs/${job['id']}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyan,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 44),
            ),
            child: Text('View Job Details',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: GoogleFonts.nunito(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: AppColors.navy));
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final names =
        (job['service_names'] as List?)?.cast<String>() ?? ['Service'];
    final addr = job['addresses'] as Map<String, dynamic>?;
    final isLoading = _actionId == job['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(names.take(2).join(', '),
              style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: AppColors.navy)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.location_on, size: 13, color: AppColors.gray400),
              const SizedBox(width: 4),
              Text('${addr?['area']}, ${addr?['city']}',
                  style:
                      TextStyle(color: AppColors.gray500, fontSize: 12)),
              const Spacer(),
              Text(_fmtDate(job['scheduled_at'] as String),
                  style:
                      TextStyle(color: AppColors.gray400, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('₹${job['final_amount'] ?? 0}',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.cyan,
                      fontSize: 16)),
              const Spacer(),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () => _acceptJob(job['id'] as String),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size(100, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text('Accept',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyJobs() {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Text('🔍', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text('No new jobs right now',
              style: TextStyle(
                  color: AppColors.gray400, fontWeight: FontWeight.w700)),
          Text('Pull down to refresh',
              style: TextStyle(color: AppColors.gray400, fontSize: 12)),
        ],
      ),
    );
  }
}