import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/transcoding_service.dart';
import '../theme/app_theme.dart';

/// 音质与流媒体（转码设置）二级页。
/// 内容自 `settings_playback_tab.dart:609-897`（_buildTranscodingSection +
/// _showSmartTranscodingHelp）整体搬移，逻辑零改动；仅把状态类成员
/// （_isDark / _buildSection / _buildDivider）改写为入参传递。
class SettingsStreamingTab extends StatelessWidget {
  const SettingsStreamingTab({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<TranscodingService>(
      builder: (context, ts, _) {
        final accent = Theme.of(context).colorScheme.primary;
        final secondaryText =
            isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText;

        Widget connectionBadge() {
          final isWifi = ts.currentConnectionType == ConnectionType.wifi;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (isWifi ? Colors.green : Colors.orange)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isWifi ? Icons.wifi_rounded : Icons.signal_cellular_alt,
                  size: 12,
                  color: isWifi ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  isWifi
                      ? AppLocalizations.of(context)!.networkWifi
                      : AppLocalizations.of(context)!.networkMobile,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isWifi ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            _buildSection(
              isDark,
              title: AppLocalizations.of(context)!.sectionStreamingQuality,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF9500), Color(0xFFFF3B30)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      CupertinoIcons.waveform,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    AppLocalizations.of(context)!.transcodingEnable,
                    style: const TextStyle(fontSize: 16),
                  ),
                  subtitle: Text(
                    AppLocalizations.of(context)!.transcodingEnableSubtitle,
                    style: TextStyle(fontSize: 13, color: secondaryText),
                  ),
                  trailing: CupertinoSwitch(
                    value: ts.enabled,
                    activeTrackColor: accent,
                    onChanged: (v) => ts.setEnabled(v),
                  ),
                ),
                // 局域网连接时强制原码（规则 1）：即便设置了转码码率也
                // 不生效，这里显式提示，避免用户以为设置失效。
                if (ts.isLanOverrideActive) ...[
                  _buildDivider(isDark),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lan_rounded,
                          size: 16,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!
                                .transcodingLanForceOriginal,
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (ts.enabled) ...[
                  _buildDivider(isDark),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [accent, accent.withValues(alpha: 0.6)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.auto_fix_high_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.smartTranscoding,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => _showSmartTranscodingHelp(context),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context)!.smartTranscodingSubtitle,
                      style: TextStyle(fontSize: 13, color: secondaryText),
                    ),
                    trailing: CupertinoSwitch(
                      value: ts.smartEnabled,
                      activeTrackColor: accent,
                      onChanged: (v) => ts.setSmartEnabled(v),
                    ),
                  ),
                  if (ts.smartEnabled)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          Text(
                            AppLocalizations.of(context)!
                                .smartTranscodingDetectedNetwork,
                            style: TextStyle(fontSize: 12, color: secondaryText),
                          ),
                          connectionBadge(),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              ts.getCurrentBitrate() != null
                                  ? '${ts.getCurrentBitrate()} kbps'
                                  : AppLocalizations.of(context)!
                                      .transcodingFormatOriginal,
                              style: TextStyle(
                                fontSize: 12,
                                color: secondaryText,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.end,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (ts.smartEnabled) ...[
                    _buildDivider(isDark),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: const Icon(Icons.wifi_rounded, size: 20),
                      title: Text(
                          AppLocalizations.of(context)!.transcodingWifiQuality),
                      subtitle: Text(
                        AppLocalizations.of(context)!
                            .transcodingWifiQualitySubtitleSmart,
                        style: TextStyle(fontSize: 12, color: secondaryText),
                      ),
                      trailing: DropdownButton<int>(
                        value: ts.wifiBitrate,
                        underline: const SizedBox(),
                        items: TranscodeBitrate.options.map((bitrate) {
                          final label = bitrate == TranscodeBitrate.original
                              ? AppLocalizations.of(context)!
                                  .transcodingBitrateOriginal
                              : '$bitrate kbps';
                          return DropdownMenuItem(
                              value: bitrate, child: Text(label));
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) ts.setWifiBitrate(v);
                        },
                      ),
                    ),
                    _buildDivider(isDark),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: const Icon(
                        Icons.signal_cellular_alt_rounded,
                        size: 20,
                      ),
                      title: Text(
                          AppLocalizations.of(context)!.transcodingMobileQuality),
                      subtitle: Text(
                        AppLocalizations.of(context)!
                            .transcodingMobileQualitySubtitleSmart,
                        style: TextStyle(fontSize: 12, color: secondaryText),
                      ),
                      trailing: DropdownButton<int>(
                        value: ts.mobileBitrate,
                        underline: const SizedBox(),
                        items: TranscodeBitrate.options.map((bitrate) {
                          final label = bitrate == TranscodeBitrate.original
                              ? AppLocalizations.of(context)!
                                  .transcodingBitrateOriginal
                              : '$bitrate kbps';
                          return DropdownMenuItem(
                              value: bitrate, child: Text(label));
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) ts.setMobileBitrate(v);
                        },
                      ),
                    ),
                  ] else ...[
                    _buildDivider(isDark),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: const Icon(Icons.speed_rounded, size: 20),
                      title: Text(
                          AppLocalizations.of(context)!.transcodingManualBitrate),
                      subtitle: Text(
                        AppLocalizations.of(context)!
                            .transcodingManualBitrateSubtitle,
                        style: TextStyle(fontSize: 12, color: secondaryText),
                      ),
                      trailing: DropdownButton<int>(
                        value: ts.manualBitrate,
                        underline: const SizedBox(),
                        items: TranscodeBitrate.options.map((bitrate) {
                          final label = bitrate == TranscodeBitrate.original
                              ? AppLocalizations.of(context)!
                                  .transcodingBitrateOriginal
                              : '$bitrate kbps';
                          return DropdownMenuItem(
                              value: bitrate, child: Text(label));
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) ts.setManualBitrate(v);
                        },
                      ),
                    ),
                  ],
                  _buildDivider(isDark),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.audio_file_rounded, size: 20),
                    title: Text(AppLocalizations.of(context)!.transcodingFormat),
                    subtitle: Text(
                      AppLocalizations.of(context)!.transcodingFormatSubtitle,
                      style: TextStyle(fontSize: 12, color: secondaryText),
                    ),
                    trailing: DropdownButton<String>(
                      value: ts.format,
                      underline: const SizedBox(),
                      items: TranscodeFormat.options.map((format) {
                        final label = format == TranscodeFormat.original
                            ? AppLocalizations.of(context)!
                                .transcodingFormatOriginal
                            : format.toUpperCase();
                        return DropdownMenuItem(
                            value: format, child: Text(label));
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) ts.setFormat(v);
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }

  void _showSmartTranscodingHelp(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.smartTranscodingHelpTitle),
        content: Text(l10n.smartTranscodingHelpBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    bool isDark, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: isDark
                  ? AppTheme.darkSecondaryText
                  : AppTheme.lightSecondaryText,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _buildDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Container(
        height: 0.5,
        color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
      ),
    );
  }
}
