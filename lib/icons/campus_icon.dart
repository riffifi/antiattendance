import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Bundled Phosphor artwork with the same theme and semantics as a native Icon.
class CampusIcon extends Icon {
  const CampusIcon(
    super.icon, {
    super.key,
    super.size,
    super.color,
    super.semanticLabel,
    super.textDirection,
  });
  static final _glyphs = <IconData, String>{
    Icons.add_rounded: 'plus',
    Icons.arrow_back_rounded: 'arrow-left',
    Icons.arrow_forward_rounded: 'arrow-right',
    Icons.arrow_upward: 'arrow-up',
    Icons.badge_outlined: 'identification-badge',
    Icons.calendar_today_outlined: 'calendar-blank',
    Icons.check_circle_outline: 'check-circle',
    Icons.check_circle_outline_rounded: 'check-circle',
    Icons.check_circle_rounded: 'check-circle',
    Icons.check_rounded: 'check',
    Icons.checkroom: 'coat-hanger',
    Icons.chevron_left_rounded: 'caret-left',
    Icons.chevron_right: 'caret-right',
    Icons.chevron_right_rounded: 'caret-right',
    Icons.circle_outlined: 'circle',
    Icons.close: 'x',
    Icons.close_rounded: 'x',
    Icons.cloud_off_rounded: 'cloud-slash',
    Icons.date_range_outlined: 'calendar',
    Icons.delete_outline_rounded: 'trash',
    Icons.devices_rounded: 'devices',
    Icons.dns_rounded: 'hard-drives',
    Icons.door_front_door_outlined: 'door',
    Icons.download_rounded: 'download-simple',
    Icons.event_available_rounded: 'calendar-check',
    Icons.flag_outlined: 'flag',
    Icons.flashlight_off_rounded: 'flashlight',
    Icons.flashlight_on_rounded: 'flashlight',
    Icons.group_add_outlined: 'user-plus',
    Icons.group_add_rounded: 'user-plus',
    Icons.groups_rounded: 'users-three',
    Icons.help_outline: 'question',
    Icons.info_outline_rounded: 'info',
    Icons.ios_share_rounded: 'share-network',
    Icons.keyboard_arrow_down_rounded: 'caret-down',
    Icons.language_rounded: 'globe',
    Icons.layers_outlined: 'stack',
    Icons.link_rounded: 'link',
    Icons.local_hospital_outlined: 'first-aid',
    Icons.lock_open_rounded: 'lock-open',
    Icons.lock_outline_rounded: 'lock',
    Icons.map_outlined: 'map-trifold',
    Icons.meeting_room_outlined: 'door-open',
    Icons.more_horiz_rounded: 'dots-three',
    Icons.more_vert: 'dots-three-vertical',
    Icons.more_vert_rounded: 'dots-three-vertical',
    Icons.my_location: 'crosshair',
    Icons.nfc_rounded: 'identification-card',
    Icons.no_photography_rounded: 'camera-slash',
    Icons.notifications_outlined: 'bell',
    Icons.open_in_new_rounded: 'arrow-square-out',
    Icons.person_add_rounded: 'user-plus',
    Icons.person_outline: 'user',
    Icons.person_outline_rounded: 'user',
    Icons.place_outlined: 'map-pin',
    Icons.playlist_add_check_rounded: 'list-checks',
    Icons.qr_code_rounded: 'qr-code',
    Icons.qr_code_scanner_rounded: 'scan',
    Icons.queue_outlined: 'stack-plus',
    Icons.radio_button_unchecked_rounded: 'circle',
    Icons.refresh_rounded: 'arrow-clockwise',
    Icons.remove_rounded: 'minus',
    Icons.restaurant: 'fork-knife',
    Icons.route_outlined: 'path',
    Icons.school_outlined: 'graduation-cap',
    Icons.search: 'magnifying-glass',
    Icons.search_rounded: 'magnifying-glass',
    Icons.sensors_rounded: 'broadcast',
    Icons.settings_outlined: 'gear',
    Icons.stairs_outlined: 'stairs',
    Icons.star: 'star',
    Icons.star_outline: 'star',
    Icons.stop_rounded: 'stop',
    Icons.sync_rounded: 'arrows-clockwise',
    Icons.system_update_rounded: 'download-simple',
    Icons.timer_outlined: 'timer',
    Icons.turn_left: 'arrow-bend-up-left',
    Icons.turn_right: 'arrow-bend-up-right',
    Icons.unfold_more_rounded: 'caret-up-down',
    Icons.wc: 'toilet',
    Icons.widgets_outlined: 'squares-four',
    Icons.wifi_find_rounded: 'wifi-high',
    Icons.wifi_off_rounded: 'wifi-slash',
    Icons.wifi_tethering_rounded: 'broadcast',
  };
  @override
  Widget build(BuildContext context) {
    final glyph = _glyphs[icon];
    if (glyph == null) return super.build(context);
    final theme = IconTheme.of(context);
    final resolvedSize = size ?? theme.size ?? 24;
    final resolvedColor =
        (color ?? theme.color ?? Theme.of(context).colorScheme.onSurface)
            .withValues(
              alpha:
                  (color ??
                          theme.color ??
                          Theme.of(context).colorScheme.onSurface)
                      .a *
                  (theme.opacity ?? 1),
            );
    return SvgPicture.asset(
      'assets/icons/phosphor/$glyph.svg',
      width: resolvedSize,
      height: resolvedSize,
      theme: SvgTheme(currentColor: resolvedColor),
      colorFilter: ColorFilter.mode(resolvedColor, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
    );
  }
}
