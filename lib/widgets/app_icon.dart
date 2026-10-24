import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models.dart';

/// A bare icon: coloured Material icon, or a small brand badge. [color] only
/// recolours plain icons; badges always use their brand colours.
class AppIcon extends StatelessWidget {
  final int index;
  final double size;
  final Color? color;
  const AppIcon(this.index, {super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    final spec = iconSpec(index);
    if (spec.badge) return _Badge(spec, size);
    return Icon(spec.icon, size: size, color: color ?? spec.color);
  }
}

/// An icon on a tile of [size]: a solid badge for brands, a tinted rounded
/// square for plain icons ([color] overrides the tint, e.g. a category colour).
class IconTile extends StatelessWidget {
  final int index;
  final double size;
  final Color? color;
  const IconTile(this.index, {super.key, this.size = 48, this.color});

  @override
  Widget build(BuildContext context) {
    final spec = iconSpec(index);
    if (spec.badge) return _Badge(spec, size);
    final c = color ?? spec.color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(spec.icon, color: c, size: size * .5),
    );
  }
}

class _Badge extends StatelessWidget {
  final AppIconSpec spec;
  final double size;
  const _Badge(this.spec, this.size);

  /// Real brand logo: an SVG on a plain tile, or a PNG app icon filling it.
  Widget _logo(BuildContext context) {
    final radius = BorderRadius.circular(size * .3);
    final border = Border.all(color: Colors.black.withValues(alpha: .08), width: .8);
    final Widget image = spec.svg
        ? Padding(
            padding: EdgeInsets.all(size * .17),
            child: SvgPicture.asset(spec.asset!, fit: BoxFit.contain),
          )
        : Image.asset(spec.asset!,
            fit: BoxFit.cover, filterQuality: FilterQuality.medium, gaplessPlayback: true);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: spec.color, borderRadius: radius, border: border),
      child: image,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (spec.asset != null) return _logo(context);
    final dark = spec.color.computeLuminance() < .06;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: spec.color,
        borderRadius: BorderRadius.circular(size * .3),
        // Near-black badges would vanish on a dark background.
        border: dark ? Border.all(color: Colors.white24, width: .8) : null,
      ),
      child: spec.icon != null
          ? Icon(spec.icon, size: size * .62, color: spec.fg)
          : Padding(
              padding: EdgeInsets.all(size * .1),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(spec.label!,
                    maxLines: 1,
                    style: TextStyle(
                      color: spec.fg,
                      fontWeight: FontWeight.w900,
                      fontSize: size * .5,
                      height: 1,
                    )),
              ),
            ),
    );
  }
}

/// Bottom sheet with every icon, grouped and searchable. Returns the chosen
/// index, or null if dismissed.
Future<int?> showIconPicker(BuildContext context, {int? selected}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _IconPicker(selected: selected),
  );
}

class _IconPicker extends StatefulWidget {
  final int? selected;
  const _IconPicker({this.selected});

  @override
  State<_IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<_IconPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _q.trim().toLowerCase();
    bool hit(AppIconSpec s) =>
        q.isEmpty || s.name.toLowerCase().contains(q) || s.group.toLowerCase().contains(q);

    final sections = <Widget>[];
    for (final g in kIconGroups) {
      final items = [
        for (var i = 0; i < kIcons.length; i++)
          if (kIcons[i].group == g && hit(kIcons[i])) i,
      ];
      if (items.isEmpty) continue;
      sections
        ..add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
          child: Text(g, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ))
        ..add(Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final i in items)
              Tooltip(
                message: kIcons[i].name,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(context, i),
                  child: Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: i == widget.selected
                          ? cs.primary.withValues(alpha: .15)
                          : null,
                      border: Border.all(
                          color: i == widget.selected ? cs.primary : cs.outlineVariant,
                          width: i == widget.selected ? 2 : 1),
                    ),
                    child: AppIcon(i, size: 34),
                  ),
                ),
              ),
          ],
        ));
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choose an icon',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
              hintText: 'Search Netflix, rent, bank…',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          Expanded(
            child: sections.isEmpty
                ? Center(
                    child: Text('No matching icons',
                        style: TextStyle(color: cs.onSurfaceVariant)))
                : ListView(padding: const EdgeInsets.only(bottom: 24), children: sections),
          ),
        ],
      ),
    );
  }
}

/// A tile showing the chosen icon with a button that opens the full picker.
class IconField extends StatelessWidget {
  final int index;
  final ValueChanged<int> onPick;
  final Color? color;
  const IconField({super.key, required this.index, required this.onPick, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final picked = await showIconPicker(context, selected: index);
        if (picked != null) onPick(picked);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            IconTile(index, size: 56, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(iconSpec(index).name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text('Tap to change icon',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
