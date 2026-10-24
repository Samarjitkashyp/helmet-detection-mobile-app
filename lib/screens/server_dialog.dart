import 'package:flutter/material.dart';

import '../core/api.dart';

/// Lets you point the app at another backend (e.g. a PC on the same WiFi while developing).
Future<void> showServerDialog(BuildContext context, Api api) async {
  final controller = TextEditingController(text: api.baseUrl);
  // 'save' | 'reset' | null (cancel)
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Server address'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(hintText: Api.defaultBaseUrl),
          ),
          const SizedBox(height: 12),
          const Text(
            'Default: ${Api.defaultBaseUrl}\n'
            'Local testing: http://<your PC IP>:8000 (debug builds only)',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'reset'), child: const Text('Use default')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'save'),
          style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (action == 'save') await api.setBaseUrl(controller.text);
  if (action == 'reset') await api.resetBaseUrl();
  controller.dispose();
}
