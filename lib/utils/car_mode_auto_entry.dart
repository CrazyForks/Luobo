/// 判断"播放页停留 30s 自动进入车载页"的倒计时是否应该运行。
///
/// 仅普通歌曲播放中计时；任一条件成立即禁止 —— 电台播放、应用退后台、
/// 车载页已展示、歌词页展示。抽成纯函数以便单测钉死守卫逻辑
/// （test/utils/car_mode_auto_entry_test.dart），防止后续调参回归。
bool shouldRunAutoCarModeTimer({
  required bool isPlaying,
  required bool isPlayingRadio,
  required bool appBackgrounded,
  required bool carModeOpen,
  required bool lyricsShowing,
}) {
  if (appBackgrounded || carModeOpen || lyricsShowing) return false;
  return isPlaying && !isPlayingRadio;
}
