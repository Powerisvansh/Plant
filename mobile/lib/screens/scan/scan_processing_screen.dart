import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../services/analysis/analyze_service.dart';
import 'analysis_result_screen.dart';

/// Runs the analysis pipeline and navigates to the results.
class ScanProcessingScreen extends StatefulWidget {
  const ScanProcessingScreen({
    super.key,
    required this.scanId,
    required this.inputs,
  });

  final String scanId;
  final List<ScanInput> inputs;

  @override
  State<ScanProcessingScreen> createState() => _ScanProcessingScreenState();
}

class _ScanProcessingScreenState extends State<ScanProcessingScreen> {
  String _note = 'Preparing your photos…';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final service = context.read<AnalyzeService>();
    setState(() => _note = 'Measuring colour, spots and damage…');
    try {
      final bundle = await service.analyze(
        scanId: widget.scanId,
        inputs: widget.inputs,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AnalysisResultScreen(
            scanId: widget.scanId,
            bundle: bundle,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: _error == null
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            strokeWidth: 4,
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(Icons.error_outline,
                          size: 44, color: AppColors.danger),
                ),
                const SizedBox(height: 24),
                Text(
                  _error ?? _note,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'PlantDoctor analyses photos on this device only.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}