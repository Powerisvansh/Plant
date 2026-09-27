import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/formats.dart';
import '../../core/theme/app_theme.dart';
import '../../models/analysis_models.dart';
import '../../services/analysis/analyze_service.dart';
import '../../state/providers.dart';
import 'scan_processing_screen.dart';

class _PickedPhoto {
  _PickedPhoto({required this.path, required this.subject});

  String path;
  ImageSubjectType subject;
}

/// Capture flow: user adds 1-4 photos from camera or gallery, optionally
/// marks what each one shows, then starts the analysis.
class ScanCaptureScreen extends StatefulWidget {
  const ScanCaptureScreen({super.key});

  @override
  State<ScanCaptureScreen> createState() => _ScanCaptureScreenState();
}

class _ScanCaptureScreenState extends State<ScanCaptureScreen> {
  final List<_PickedPhoto> _photos = [];
  final _picker = ImagePicker();
  bool _busy = false;

  Future<void> _addFrom(ImageSource source) async {
    if (_busy || _photos.length >= AppConstants.maxScanImages) return;
    setState(() => _busy = true);
    try {
      if (source == ImageSource.camera) {
        final shot = await _picker.pickImage(
          source: source,
          maxWidth: 1920,
          imageQuality: 90,
        );
        if (shot == null) return;
        setState(() {
          _photos.add(_PickedPhoto(path: shot.path, subject: ImageSubjectType.wholePlant));
        });
      } else {
        final picks = await _picker.pickMultiImage(maxWidth: 1920, imageQuality: 90);
        if (picks.isEmpty) return;
        setState(() {
          for (final p in picks) {
            if (_photos.length >= AppConstants.maxScanImages) break;
            _photos.add(_PickedPhoto(path: p.path, subject: ImageSubjectType.wholePlant));
          }
        });
      }
    } catch (e) {
      _toast('Could not open the camera or photo picker.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove(int index) => setState(() => _photos.removeAt(index));

  Future<void> _analyse() async {
    if (_photos.isEmpty) return;
    final files = Provider.of<AnalyzeService>(context, listen: false).files;
    // Keep durable originals so history can recover them later.
    final scanId = newScanId();
    final inputs = <ScanInput>[];
    for (var i = 0; i < _photos.length; i++) {
      final dest = await files.copyOriginal(scanId, i, _photos[i].path);
      inputs.add((path: dest, subject: _photos[i].subject));
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ScanProcessingScreen(scanId: scanId, inputs: inputs),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = _photos.length >= AppConstants.maxScanImages;
    return Scaffold(
      appBar: AppBar(title: const Text('Check-up photos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Add up to ${AppConstants.maxScanImages} photos.',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            'Best results come from a sharp, well-lit leaf or whole plant.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < _photos.length; i++) _photoTile(i),
              if (!full) _addTile(),
            ],
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _photos.isEmpty ? null : _analyse,
            icon: const Icon(Icons.spa_outlined),
            label: Text('Analyse ${_photos.length} photo${_photos.length == 1 ? '' : 's'}'),
          ),
          if (_photos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                'Scanning stays on your phone - no photos are uploaded.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.inkMuted),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: full ? null : () => _addFrom(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: full ? null : () => _addFrom(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addTile() {
    return InkWell(
      onTap: () => _addFrom(ImageSource.gallery),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primaryLight),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: AppColors.primary, size: 28),
            SizedBox(height: 6),
            Text('Add photo', style: TextStyle(color: AppColors.forest)),
          ],
        ),
      ),
    );
  }

  Widget _photoTile(int index) {
    final photo = _photos[index];
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(photo.path),
                  width: 104,
                  height: 104,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 104,
                    height: 104,
                    color: AppColors.border,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: InkWell(
                  onTap: () => _remove(index),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.ink,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          DropdownButton<ImageSubjectType>(
            value: photo.subject,
            isExpanded: true,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            items: [
              for (final s in ImageSubjectType.values)
                DropdownMenuItem(value: s, child: Text(subjectLabel(s))),
            ],
            onChanged: (v) => setState(() => photo.subject = v ?? ImageSubjectType.unknown),
          ),
        ],
      ),
    );
  }
}