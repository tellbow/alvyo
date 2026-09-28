import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';
import 'report_dialog.dart';

/// Picks photos; replaced in widget tests.
typedef PhotoPicker = Future<List<XFile>> Function(ImageSource source);

Future<List<XFile>> _pick(ImageSource source) async => source == ImageSource.camera
    ? [?await ImagePicker().pickImage(source: ImageSource.camera)]
    : ImagePicker().pickMultiImage();

/// The photos of a route or journey as a strip of thumbnails; each opens
/// large. Those who may edit add photos from the camera or the library.
/// Nothing shows offline, or when there are none and the user may not add.
class PhotoStrip extends StatefulWidget {
  const PhotoStrip({super.key, required this.api, required this.id, this.journey = false, this.pick = _pick});
  final Api api;
  final String id;
  final bool journey;
  final PhotoPicker pick;

  @override
  State<PhotoStrip> createState() => _PhotoStripState();
}

class _PhotoStripState extends State<PhotoStrip> {
  List<Photo> _photos = const [];
  bool _canEdit = false;

  /// While uploading: done of total.
  (int, int)? _uploading;

  @override
  void initState() {
    super.initState();
    widget.api.photos(widget.id, journey: widget.journey).then(_take, onError: (Object _) {});
  }

  void _take(({List<Photo> photos, bool canEdit}) p) {
    if (!mounted) return;
    setState(() {
      _photos = p.photos;
      _canEdit = p.canEdit;
    });
  }

  String _problem(AppLocalizations t, Object e) => switch (e) {
    ApiException(status: 413) => t.photosProblemSize,
    ApiException(status: 415) => t.photosProblemFormat,
    ApiException(status: 422) => t.photosProblemLimit,
    ApiException(status: 429) => t.photosProblemRate,
    _ => t.photosProblemOther,
  };

  Future<void> _add() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('photo-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(t.photosCamera),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              key: const Key('photo-library'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(t.photosLibrary),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(t.photosHint, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final files = await widget.pick(source);
    for (final (i, f) in files.indexed) {
      if (!mounted) return;
      setState(() => _uploading = (i, files.length));
      try {
        _take(await widget.api.addPhoto(widget.id, await f.readAsBytes(), f.name, journey: widget.journey));
      } on Object catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('${f.name}: ${_problem(t, e)}')));
      }
    }
    if (mounted) setState(() => _uploading = null);
  }

  Future<void> _open(int index) async {
    final changed = await Navigator.of(context).push<({List<Photo> photos, bool canEdit})>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PhotoViewer(
          api: widget.api,
          id: widget.id,
          journey: widget.journey,
          photos: _photos,
          canEdit: _canEdit,
          index: index,
        ),
      ),
    );
    if (changed != null) _take(changed);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_photos.isEmpty && !_canEdit) return const SizedBox.shrink();
    return Column(
      key: const Key('photos'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(t.photosTitle, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final (i, p) in _photos.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    key: Key('photo-$i'),
                    onTap: () => _open(i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        widget.api.photoUrl(p.id, 'thumb'),
                        headers: widget.api.authHeaders,
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        semanticLabel: p.caption.isEmpty ? t.photosTitle : p.caption,
                        errorBuilder: (_, _, _) =>
                            const SizedBox.square(dimension: 88, child: Icon(Icons.broken_image)),
                      ),
                    ),
                  ),
                ),
              if (_canEdit)
                SizedBox.square(
                  dimension: 88,
                  child: switch (_uploading) {
                    (final done, final total) => Center(
                      child: Text(t.photosUploading(done, total), textAlign: TextAlign.center),
                    ),
                    _ => OutlinedButton(
                      key: const Key('photo-add'),
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: _add,
                      child: Tooltip(message: t.photosAdd, child: const Icon(Icons.add_a_photo_outlined)),
                    ),
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Photos shown large, one after the other; captions changed and photos
/// deleted by those who may edit, reported by others. Pops with the photos
/// as they are when changed.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.api,
    required this.id,
    required this.journey,
    required this.photos,
    required this.canEdit,
    required this.index,
  });
  final Api api;
  final String id;
  final bool journey;
  final List<Photo> photos;
  final bool canEdit;
  final int index;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late var _photos = widget.photos;
  late final _pages = PageController(initialPage: widget.index);
  late var _at = widget.index;
  ({List<Photo> photos, bool canEdit})? _changed;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _change(Future<({List<Photo> photos, bool canEdit})> call) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final p = await call;
      _changed = p;
      if (p.photos.isEmpty) {
        nav.pop(p);
        return;
      }
      if (mounted) {
        setState(() {
          _photos = p.photos;
          _at = _at.clamp(0, p.photos.length - 1);
        });
      }
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  Future<void> _caption(Photo p) async {
    final t = AppLocalizations.of(context);
    final field = TextEditingController(text: p.caption);
    final caption = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.photosCaption),
        content: TextField(key: const Key('photo-caption'), controller: field, autofocus: true, maxLength: 500),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, field.text.trim()), child: Text(t.save)),
        ],
      ),
    );
    if (caption != null) await _change(widget.api.captionPhoto(widget.id, p.id, caption, journey: widget.journey));
  }

  Future<void> _delete(Photo p) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t.photosDeleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(
            key: const Key('photo-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.photosDelete),
          ),
        ],
      ),
    );
    if (ok == true) await _change(widget.api.deletePhoto(widget.id, p.id, journey: widget.journey));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = _photos[_at];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${_at + 1} / ${_photos.length}'),
          actions: [
            PopupMenuButton<String>(
              key: const Key('photo-menu'),
              iconColor: Colors.white,
              onSelected: (v) => switch (v) {
                'caption' => _caption(p),
                'delete' => _delete(p),
                _ => report(context, widget.api, kind: 'photo', id: p.id),
              },
              itemBuilder: (_) => [
                if (widget.canEdit) ...[
                  PopupMenuItem(value: 'caption', child: Text(t.photosCaption)),
                  PopupMenuItem(key: const Key('photo-delete'), value: 'delete', child: Text(t.photosDelete)),
                ] else
                  PopupMenuItem(value: 'report', child: Text(t.reportAction)),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _photos.length,
                onPageChanged: (i) => setState(() => _at = i),
                itemBuilder: (context, i) => InteractiveViewer(
                  child: Image.network(
                    widget.api.photoUrl(_photos[i].id, 'large'),
                    headers: widget.api.authHeaders,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : const Center(child: CircularProgressIndicator()),
                    errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image, color: Colors.white)),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  [if (p.caption.isNotEmpty) p.caption, if (p.uploader.isNotEmpty) t.photosBy(p.uploader)].join('\n'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
