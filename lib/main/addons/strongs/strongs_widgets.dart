import 'package:flutter/material.dart';

import 'strongs_models.dart';
import 'strongs_theme.dart';

/// Small centred dim title ("Strongs Lookup"), the `<center>` in the JSX.
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Center(
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: StrongsTheme.of(context).dimmerText,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

/// One dictionary entry: lemma, transliteration, pronunciation, usage,
/// definition, and the tappable code tag. Shared by BOTH sheets (the two CSS
/// files had identical rules for it).
class StrongsEntry extends StatelessWidget {
  const StrongsEntry({super.key, required this.def, this.onTagTap});

  final StrongsDef def;
  final VoidCallback? onTagTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = StrongsTheme.of(context);
    final rtl = def.strongsId.startsWith('H'); // Hebrew reads right-to-left

    final label = theme.textTheme.labelSmall!.copyWith(
      color: t.dimmerText,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w600,
    );
    final body = theme.textTheme.bodyMedium!.copyWith(height: 1.5);

    Widget field(String name, String? value) {
      if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${name.toUpperCase()}: ', style: label),
              TextSpan(text: value.trim(), style: body),
            ],
          ),
        ),
      );
    }

    final hasTranslit = (def.transliteration ?? '').trim().isNotEmpty;
    final hasPron = (def.pronunciation ?? '').trim().isNotEmpty;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        def.lemma ?? '',
                        textDirection: rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontFamily: t.lemmaFontFamily,
                          fontFamilyFallback: const ['serif'],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasTranslit)
                            Text(
                              def.transliteration!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: t.dimText,
                              ),
                            ),
                          if (hasPron)
                            Text(
                              '[${def.pronunciation}]',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: t.dimmerText,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                field('Usage', def.kjvDef),
                field('Definition', def.definition),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: isDark ? Colors.black26 : Colors.black12,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: onTagTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  def.strongsId,
                  style: TextStyle(
                    color: t.refColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
