import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/section_header.dart';

/// In-app Legal documents (Privacy Policy, Terms, AI Disclaimer, Data Policy).
///
/// These mirror `docs/legal/*.md`. Keep both in sync when content changes.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  static const List<LegalDocument> _documents = [
    LegalDocument(
      id: 'privacy',
      title: 'Privacy Policy',
      subtitle: 'How PlantDoctor AI handles your information',
      icon: Icons.privacy_tip_outlined,
      color: AppColors.teal,
      updated: 'Updated 24 September 2026',
      sections: [
        ('Who we are',
            'PlantDoctor AI is developed and owned by Vansh Dhiman (brand: '
                'VanshDev), Karnal, Haryana, India. Support and legal contact: '
                'vanshdhimang9@gmail.com.'),
        ('Introduction',
            'This Privacy Policy explains how the app collects, uses, stores '
                'and protects information. PlantDoctor AI is an AI-assisted '
                'plant health and identification tool - it is not a laboratory '
                'or clinical diagnosis tool. Please read this together with '
                'the Terms & Conditions and AI Disclaimer.'),
        ('How images are processed',
            'Photos you capture or select are used only for the feature you '
                'requested. As currently implemented, plant images are '
                'processed on your device and are not uploaded to any '
                'external service. If a future version ever processes images '
                'through our own server infrastructure, this policy will be '
                'updated before that happens.'),
        ('Information we collect',
            'We collect only what is needed: plant photos you provide; saved '
                'plant information (name, species, notes, history); scan '
                'history; limited device information needed for the app to '
                'run; and information you voluntarily provide (e.g. follow-up '
                'answers). No registration or account is required. The current '
                'version collects no analytics or usage-tracking data.'),
        ('How information is used',
            'Information is used solely to run the analysis you request, show '
                'results and plant information, save and retrieve plants and '
                'history, keep the app working, and respond to support or '
                'legal requests. We do not use photos for advertising, '
                'profiling or selling data.'),
        ('Third-party sharing',
            'We do not sell, rent or trade your personal information, and we '
                'do not share your data with third parties for marketing. '
                'Disclosure happens only where required or permitted by law. '
                'No third-party analytics, advertising or tracking services '
                'are used in the current version.'),
        ('Your control and deletion',
            'You can delete saved plants from My Plants and scan history from '
                'History. Uninstalling the app removes its local database and '
                'stored photos. For anything you cannot delete yourself, email '
                'vanshdhimang9@gmail.com.'),
        ('Security',
            'Data is stored in the app\u2019s private storage on your device and '
                'nothing is transmitted in the current version. We follow '
                'reasonable security practices. No method of storage is 100% '
                'secure, so protect your device.'),
        ('Children',
            'The app does not intentionally collect personal information from '
                'any user, including children. If we become aware that such '
                'information was provided unintentionally, we will delete it '
                'on request.'),
        ('Changes & contact',
            'This policy may be updated as the app develops; changes update '
                'the date shown here. For privacy, legal, data-deletion or '
                'support requests, contact vanshdhimang9@gmail.com.'),
      ],
    ),
    LegalDocument(
      id: 'terms',
      title: 'Terms & Conditions',
      subtitle: 'The agreement governing your use of the app',
      icon: Icons.gavel_outlined,
      color: AppColors.primary,
      updated: 'Updated 24 September 2026',
      sections: [
        ('Agreement',
            'These Terms form a legal agreement between you and the developer, '
                'Vansh Dhiman (VanshDev, Karnal, Haryana, India). By '
                'installing or using PlantDoctor AI you accept these Terms.'),
        ('Service',
            'The app provides plant identification hints, visual health '
                'screening (an experimental, explainable software assessment), '
                'plant information, care guidance, saved plants and scan '
                'history, and a science-fair demo - for educational and '
                'informational purposes only.'),
        ('Eligibility & accounts',
            'No account is required and no registration data is collected. '
                'By using the app you confirm you are at least 13 years old '
                'or have a parent/guardian\u2019s permission.'),
        ('License',
            'You receive a personal, non-exclusive, non-transferable, '
                'revocable licence to use the app on your own devices for '
                'personal, non-commercial use. You may not copy, modify, '
                'reverse-engineer, resell or misuse the app.'),
        ('Your content & no diagnosis',
            'Photos and information you provide remain yours. The app '
                'provides AI-assisted, visual-only hints and does not provide '
                'a confirmed diagnosis, a guaranteed accuracy, or real-world '
                'validation. You are solely responsible for decisions based on '
                'its output, including any treatment or chemical use. Always '
                'verify serious decisions with an expert and follow product '
                'labels and local guidance.'),
        ('Treatment recommendations',
            'The app prioritises general care and low-risk actions and does '
                'not prescribe pesticides or fungicides as guaranteed '
                'treatments. It never provides hazardous mixing instructions.'),
        ('Intellectual property',
            'The PlantDoctor AI name, logo, brand (VanshDev), interface and '
                'code belong to Vansh Dhiman. Plant information is compiled '
                'from general botanical references and provided "as is" for '
                'education.'),
        ('Disclaimers & liability',
            'The app is provided "as is" without warranties of any kind. To '
                'the maximum extent permitted by law, the developer is not '
                'liable for indirect or consequential damages, and total '
                'liability is limited to the amount you paid (zero) or one '
                'hundred rupees, whichever is lower.'),
        ('Governing law',
            'These Terms are governed by the laws of India; disputes fall '
                'under the exclusive jurisdiction of the courts at Karnal, '
                'Haryana, India.'),
        ('Changes & contact',
            'Terms may be updated as the app develops. For questions, email '
                'vanshdhimang9@gmail.com.'),
      ],
    ),
    LegalDocument(
      id: 'ai_disclaimer',
      title: 'AI Disclaimer',
      subtitle: 'The real limits of the analysis',
      icon: Icons.priority_high_outlined,
      color: AppColors.warn,
      updated: 'Updated 24 September 2026',
      sections: [
        ('What it is',
            'PlantDoctor AI is an AI-assisted visual screening and educational '
                'tool. It analyses visible characteristics of photos - leaf '
                'colour, spots, brown areas, shape, texture and coverage - '
                'with an on-device engine. It is not a laboratory diagnosis '
                'or a replacement for a professional, plant clinic, extension '
                'service or lab.'),
        ('Results can be wrong or uncertain',
            'The app does not guarantee correct identification, a true '
                'biological condition, correct symptoms, or that no problem '
                'means healthy. The Health Index is an experimental software '
                'metric based on visible image characteristics, not a '
                'standard; an index change does not prove biological '
                'improvement or deterioration.'),
        ('Photo limitations',
            'Analysis is limited by the photo: dark, blurry or obstructed '
                'images reduce accuracy (you will be warned); the camera '
                'cannot see roots, soil or history; and many conditions look '
                'visually similar. The app therefore reports possible causes '
                'and hypotheses, never a confirmed diagnosis.'),
        ('Identification is a hint',
            'Suggested plant identities are candidates for you to verify '
                'against your own plant. When uncertain, the app says so '
                'explicitly.'),
        ('What to do with results',
            'Treat results as a starting point. Inspect the plant directly. '
                'For anything serious - especially chemicals, large crops or '
                'valuable plants - confirm with an appropriate expert before '
                'acting. Always follow product labels and local guidance.'),
        ('Science-fair results',
            'The built-in demo measures the engine on a labelled synthetic '
                'dataset. It shows internal consistency and honesty in a '
                'controlled demonstration; it is not validated real-world '
                'accuracy on real photographs.'),
      ],
    ),
    LegalDocument(
      id: 'data',
      title: 'Data Policy',
      subtitle: 'What data is stored and how to delete it',
      icon: Icons.storage_outlined,
      color: AppColors.forest,
      updated: 'Updated 24 September 2026',
      sections: [
        ('Where data lives',
            'In the current version all data is stored on your device: the '
                'local SQLite database (scan history, saved plants, notes), '
                'files in the app\u2019s private documents directory (photos), '
                'and local preferences. No data is uploaded to a server.'),
        ('What is stored',
            'Captured/selected photos (originals when saved plus downscaled '
                'working copies); saved check-up records (date, thumbnails, '
                'identification guess, confidence, health index, condition, '
                'causes, follow-up answers, notes); and saved plant records '
                '(name, species, date, photo, index, notes).'),
        ('Retention',
            'Saved scans and plants are kept until you delete them or '
                'uninstall the app, which removes the local database and '
                'stored photos. No analytics data exists to retain.'),
        ('Your control',
            'Delete history from History, saved plants from My Plants, or '
                'clear app data from Android settings to remove everything. '
                'Email vanshdhimang9@gmail.com for anything else.'),
        ('Permissions & offline',
            'Camera and gallery permissions are used only for the photos you '
                'choose. The app works fully offline. If a future version '
                'adds online AI, it will be isolated, will notify you before '
                'sending an image, and will fail gracefully without internet.'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Legal & privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'These documents mirror the full text in the project\u2019s '
            'docs/legal/ folder.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final doc in _documents)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _LegalDetailScreen(doc: doc),
                  ),
                ),
                leading: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: doc.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(doc.icon, color: doc.color, size: 24),
                ),
                title: Text(doc.title,
                    style: Theme.of(context).textTheme.titleMedium),
                subtitle: Text(doc.subtitle,
                    style: Theme.of(context).textTheme.bodySmall),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.inkMuted),
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Educational project. Text on this screen is a summary; the '
              'complete documents live in docs/legal/.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class LegalDocument {
  const LegalDocument({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.updated,
    required this.sections,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String updated;

  /// Ordered (heading, body) sections rendered on the detail page.
  final List<(String, String)> sections;
}

class _LegalDetailScreen extends StatelessWidget {
  const _LegalDetailScreen({required this.doc});

  final LegalDocument doc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(doc.title),
        backgroundColor: doc.color.withValues(alpha: 0.12),
        foregroundColor: AppColors.ink,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(doc.updated,
              style: theme.textTheme.bodySmall!
                  .copyWith(color: doc.color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(doc.subtitle, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          for (final (heading, body) in doc.sections) ...[
            SectionHeader(title: heading),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(body, style: theme.textTheme.bodyMedium),
              ),
            ),
            const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }
}