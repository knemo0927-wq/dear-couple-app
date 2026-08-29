import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:flutter/material.dart';

Future<bool> confirmSharedMapPhotoDeletion(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('함께 보관한 사진 삭제'),
      content: const Text('삭제하면 상대방의 여행 지도에서도 이 사진이 사라져요.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('삭제'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class TravelMapPhotoItem {
  const TravelMapPhotoItem({
    required this.id,
    required this.url,
    required this.semanticLabel,
  });

  final String id;
  final String? url;
  final String semanticLabel;
}

class TravelMapCollapsedEditor extends StatelessWidget {
  const TravelMapCollapsedEditor({
    required this.placeName,
    required this.regionLabel,
    required this.onExpand,
    super.key,
  });

  final String? placeName;
  final String regionLabel;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TravelMapSheetFrame(
      child: ListTile(
        key: const ValueKey('travel-map-collapsed-editor'),
        contentPadding: EdgeInsets.zero,
        minTileHeight: 60,
        leading: const DearIconBubble(
          icon: Icons.location_on_rounded,
          size: 44,
          iconSize: 23,
        ),
        title: Text(
          placeName ?? '장소를 선택해 주세요',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
        ),
        subtitle: Text(
          placeName == null ? '지도나 검색에서 장소를 골라요' : '$regionLabel · 기록 편집',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        trailing: Icon(
          Icons.keyboard_arrow_up_rounded,
          color: onExpand == null
              ? scheme.onSurface.withValues(alpha: 0.38)
              : scheme.onSurface,
        ),
        onTap: onExpand,
      ),
    );
  }
}

class TravelMapRecordEditor extends StatelessWidget {
  const TravelMapRecordEditor({
    required this.placeName,
    required this.regionLabel,
    required this.palette,
    required this.selectedColor,
    required this.memoController,
    required this.visitedAt,
    required this.photos,
    required this.photosLoading,
    required this.saving,
    required this.deleting,
    required this.uploadingPhoto,
    required this.hasRecord,
    required this.onCollapse,
    required this.onPickDate,
    required this.onClearDate,
    required this.onSelectColor,
    required this.onSave,
    required this.onDelete,
    required this.onAddPhoto,
    required this.onDeletePhoto,
    this.photosError,
    this.onRetryPhotos,
    super.key,
  });

  final String placeName;
  final String regionLabel;
  final List<String> palette;
  final String selectedColor;
  final TextEditingController memoController;
  final DateTime? visitedAt;
  final List<TravelMapPhotoItem> photos;
  final bool photosLoading;
  final bool saving;
  final bool deleting;
  final bool uploadingPhoto;
  final bool hasRecord;
  final VoidCallback onCollapse;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;
  final ValueChanged<String> onSelectColor;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;
  final VoidCallback? onAddPhoto;
  final ValueChanged<String> onDeletePhoto;
  final String? photosError;
  final VoidCallback? onRetryPhotos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateLabel = visitedAt == null
        ? '방문일을 선택해 주세요'
        : '${visitedAt!.year}.${visitedAt!.month.toString().padLeft(2, '0')}.${visitedAt!.day.toString().padLeft(2, '0')}';
    final busy = saving || deleting;
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height *
        (mediaQuery.orientation == Orientation.landscape ? 0.44 : 0.73);

    return TravelMapSheetFrame(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const DearIconBubble(
                    icon: Icons.location_on_rounded,
                    size: 44,
                    iconSize: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          placeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w900,
                                height: 1.08,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          regionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: '편집 시트 닫기',
                    constraints:
                        const BoxConstraints.tightFor(width: 48, height: 48),
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.surfaceContainerHighest,
                      foregroundColor: scheme.onSurface,
                    ),
                    onPressed: onCollapse,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: 16),
              _EditorRow(
                label: '색상',
                child: SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: palette.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final hex = palette[index];
                      return _ColorSwatch(
                        colorHex: hex,
                        selected: selectedColor == hex,
                        onTap: busy ? null : () => onSelectColor(hex),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _EditorRow(
                label: '방문일',
                child: Material(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    key: const ValueKey('travel-map-visit-date'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: busy ? null : onPickDate,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 54),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: scheme.outline),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            color: scheme.onSurfaceVariant,
                            size: 21,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              dateLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: visitedAt == null
                                        ? scheme.onSurfaceVariant
                                        : scheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                          if (visitedAt != null)
                            IconButton(
                              tooltip: '방문일 지우기',
                              constraints: const BoxConstraints.tightFor(
                                width: 44,
                                height: 44,
                              ),
                              onPressed: busy ? null : onClearDate,
                              icon: const Icon(Icons.clear_rounded, size: 20),
                            )
                          else
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _EditorRow(
                label: '메모',
                crossAxisAlignment: CrossAxisAlignment.start,
                child: TextField(
                  key: const ValueKey('travel-map-memo-field'),
                  controller: memoController,
                  enabled: !busy,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 200,
                  decoration: InputDecoration(
                    hintText: '여행에서 기억하고 싶은 순간을 남겨보세요.',
                    filled: true,
                    fillColor: scheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: scheme.outline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: scheme.outline),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '사진',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 10),
              _PhotoStrip(
                photos: photos,
                loading: photosLoading,
                uploading: uploadingPhoto,
                enabled: !busy,
                onAddPhoto: onAddPhoto,
                onDeletePhoto: onDeletePhoto,
              ),
              if (photosError != null) ...[
                const SizedBox(height: 8),
                DearInlineError(
                  message: photosError!,
                  onRetry: onRetryPhotos,
                  retrying: photosLoading,
                  retryButtonKey:
                      const ValueKey('travel-map-photo-retry-button'),
                ),
              ],
              const SizedBox(height: 18),
              if (saving || deleting)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      saving ? '기록을 저장하고 있어요.' : '기록을 삭제하고 있어요.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('travel-map-delete-button'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        foregroundColor: scheme.error,
                        side: BorderSide(color: scheme.outline),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: hasRecord && !busy && !uploadingPhoto
                          ? onDelete
                          : null,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(deleting ? '삭제 중' : '삭제'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DearGradientButton(
                      key: const ValueKey('travel-map-save-button'),
                      label: saving ? '저장 중' : '저장',
                      onPressed: busy || uploadingPhoto ? null : onSave,
                      height: 54,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TravelMapSheetFrame extends StatelessWidget {
  const TravelMapSheetFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('travel-map-sheet-surface'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorRow extends StatelessWidget {
  const _EditorRow({
    required this.label,
    required this.child,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final String label;
  final Widget child;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        SizedBox(
          width: 66,
          child: Padding(
            padding: EdgeInsets.only(
              top: crossAxisAlignment == CrossAxisAlignment.start ? 14 : 0,
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.colorHex,
    required this.selected,
    required this.onTap,
  });

  final String colorHex;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = Color(
      int.parse('FF${colorHex.replaceAll('#', '')}', radix: 16),
    );
    final checkColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return Tooltip(
      message: '색상 $colorHex',
      child: Semantics(
        button: true,
        selected: selected,
        label: '여행 지역 색상 $colorHex',
        child: InkResponse(
          radius: 24,
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: AnimatedContainer(
                duration: DearMotion.duration(context, DearMotion.fast),
                width: selected ? 38 : 34,
                height: selected ? 38 : 34,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                    if (selected)
                      BoxShadow(
                        color: scheme.primary,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: checkColor,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.photos,
    required this.loading,
    required this.uploading,
    required this.enabled,
    required this.onAddPhoto,
    required this.onDeletePhoto,
  });

  final List<TravelMapPhotoItem> photos;
  final bool loading;
  final bool uploading;
  final bool enabled;
  final VoidCallback? onAddPhoto;
  final ValueChanged<String> onDeletePhoto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visiblePhotos = photos.take(8).toList(growable: false);
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visiblePhotos.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          if (index == visiblePhotos.length) {
            return _AddPhotoTile(
              enabled: enabled && !uploading && onAddPhoto != null,
              loading: loading || uploading,
              onTap: onAddPhoto,
            );
          }

          final photo = visiblePhotos[index];
          return Semantics(
            image: true,
            label: photo.semanticLabel,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: photo.url == null
                      ? _UnavailablePhotoPreview(scheme: scheme)
                      : Image.network(
                          photo.url!,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _UnavailablePhotoPreview(scheme: scheme),
                        ),
                ),
                Positioned(
                  top: -8,
                  right: -8,
                  child: IconButton.filled(
                    tooltip: '함께 보관한 사진 삭제',
                    constraints:
                        const BoxConstraints.tightFor(width: 44, height: 44),
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.surface,
                      foregroundColor: scheme.onSurface,
                      side: BorderSide(color: scheme.outline),
                    ),
                    onPressed: enabled ? () => onDeletePhoto(photo.id) : null,
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UnavailablePhotoPreview extends StatelessWidget {
  const _UnavailablePhotoPreview({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: Icon(
          Icons.broken_image_outlined,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '여행 사진 추가',
      child: Semantics(
        button: true,
        label: loading ? '여행 사진 업로드 중' : '여행 사진 추가',
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled && !loading ? onTap : null,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outline),
              ),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.add_photo_alternate_outlined,
                        color: scheme.primary,
                        size: 32,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
