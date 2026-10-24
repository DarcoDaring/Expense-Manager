import 'package:flutter/material.dart';

import '../services/attachment_service.dart';

/// Full-screen, pinch-to-zoom view of an expense's attachment.
class AttachmentViewer extends StatelessWidget {
  final String name;
  const AttachmentViewer({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Attachment', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.file(
            AttachmentService.fileFor(name),
            errorBuilder: (_, _, _) => const Text('Image not found',
                style: TextStyle(color: Colors.white70)),
          ),
        ),
      ),
    );
  }
}
