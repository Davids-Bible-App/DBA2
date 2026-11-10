import 'package:flutter/material.dart';

import '../downloader.dart';
import '../engine_installer.dart';
import '../llm_engine.dart';

/// Shown only while the engine is missing (Windows first run). Vanishes once installed.
class EngineInstallBanner extends StatefulWidget {
  const EngineInstallBanner({
    super.key,
    required this.engine,
    required this.installer,
  });
  final LlmEngine engine;
  final EngineInstaller installer;

  @override
  State<EngineInstallBanner> createState() => _EngineInstallBannerState();
}

class _EngineInstallBannerState extends State<EngineInstallBanner> {
  late final _url = TextEditingController(text: widget.installer.customUrl);

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _start() {
    widget.installer.customUrl = _url.text; // saved for next time; empty = auto
    widget.installer.install();
  }

  @override
  Widget build(BuildContext context) {
    final installer = widget.installer;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.engine, installer]),
      builder: (context, _) {
        if (widget.engine.installed) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        final working = installer.state == InstallState.working;
        return Card(
          color: cs.secondaryContainer,
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  working ? installer.stage : "The local AI engine (llama.cpp) isn't installed yet. It's a one-time download from GitHub.",
                ),
                if (installer.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      installer.error!,
                      style: TextStyle(color: cs.error),
                    ),
                  ),
                if (!working)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: _url,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        labelText: 'Custom download link (optional)',
                        hintText: 'https://…/llama-…-bin-win-vulkan-x64.zip',
                      ),
                    ),
                  ),
                if (working)
                  ValueListenableBuilder<DownloadProgress?>(
                    valueListenable: installer.progress,
                    builder: (context, p, _) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(value: p?.fraction),
                    ),
                  ),
                const SizedBox(height: 8),
                if (working)
                  OutlinedButton(
                    onPressed: installer.cancel,
                    child: const Text('Cancel'),
                  )
                else
                  FilledButton(
                    onPressed: _start,
                    child: Text(
                      installer.error != null ? 'Retry' : 'Download engine',
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
