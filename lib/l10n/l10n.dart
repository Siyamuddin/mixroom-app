// lib/l10n/l10n.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/main.dart';

class L10n {
  /// Supported locales
  static final List<Locale> supportedLocales = [
    const Locale('en'), // English
    const Locale('ko'), // Korean
    const Locale('zh'), // Chinese
    const Locale('ja'), // Japanese
  ];

  // static Locale getDeviceLocale(BuildContext context) {
  //   final deviceLocale = Localizations.localeOf(context);
  //   final providerLocale = Provider.of<LocaleProvider>(context).locale; // Remove listen: false to get the current value

  //   if (providerLocale != null) {
  //     return providerLocale;
  //   } else if (deviceLocale.languageCode != null) {
  //     return Locale(deviceLocale.languageCode);
  //   } else {
  //     return const Locale('en');
  //   }
  // }

  static Locale getDeviceLocale(BuildContext context) {
    return const Locale('en'); // TODO: TEMP FOR CES
    try {
      // Always use listen: false for utility functions
      final providerLocale =
          Provider.of<LocaleProvider>(context, listen: false).locale;
      if (providerLocale != null) return providerLocale;

      final deviceLocale = Localizations.localeOf(context);
      return Locale(deviceLocale.languageCode);
    } catch (e) {
      return const Locale('en'); // Fallback
    }
  }

  /// Simple translation map (replace with your ARB-generated translations)
  static final Map<String, Map<String, String>> _translations = {
    'en': {
      'hello': 'Hello',
      'share': 'Share',
      'Editor': 'Editor',
      'Video Editing': 'Video Editing',
      'Store': 'Store',
      'Mixroom': 'Mixroom',
      '© Mixroom': '© Mixroom',
      'Powered by Mixroom': 'Powered by Mixroom',
      'Audio-Only Mode': 'Audio-Only Mode',
      'Video Editor': 'Video Editor',
      'Video Audio Volume Automation': 'Video Audio Volume Automation',
      'Select Audio': 'Select Audio',
      'Select Video': 'Select Video',
      'Pick from Device': 'Pick from Device',
      'Crossfade (Video vs. All Audio)': 'Crossfade (Video vs. All Audio)',
      'Volume Balance': 'Volume Balance',
      'Add Audio Track': 'Add Audio Track',
      'Audio': 'Audio',
      'Offset': 'Offset',
      'Trim': 'Trim',
      'Volume Automation': 'Volume Automation',
      'Gain': 'Gain',
      'AI Sync': 'AI Sync',
      'Sync': 'Sync',
      'SYNC': 'SYNC',
      'Next': 'Next',
      'Syncing Audio': 'Syncing Audio',
      'AI Sync applied successfully!': 'AI Sync applied successfully!',
      'Audio Effects': 'Audio Effects',
      'Echo': 'Echo',
      'Reverb': 'Reverb',
      'Back': 'Back',
      'Export': 'Export',
      'EXPORT': 'EXPORT',
      'Exported file saved!': 'Exported file saved!',
      'Your video was exported successfully!':
          'Your video was exported successfully!',
      'Share directly to:': 'Share directly to:',
      'YouTube': 'YouTube',
      'Instagram': 'Instagram',
      'TikTok': 'TikTok',
      'Back to Editor': 'Back to Editor',
      'Export Successful': 'Export Successful',
      'Audio Editor': 'Audio Editor',
      'SoundCloud': 'SoundCloud',
      'Export canceled or failed.': 'Export canceled or failed.',
      'Your audio was exported successfully!':
          'Your audio was exported successfully!',
      'Coming soon': 'Coming soon',
      'Coming Soon': 'Coming Soon',
      'Search feature coming soon!': 'Search feature coming soon!',
      'Title / Artist / Genre / etc...': 'Title / Artist / Genre / etc...',
      'Explore feature coming soon!': 'Explore feature coming soon!',
      'Explore': 'Explore',
      'Basic': 'Basic',
      'Pro': 'Pro',
      'Welcome back': 'Welcome back',
      'Home': 'Home',
      'Projects': 'Projects',
      'Presets': 'Presets',
      'Uploads': 'Uploads',
      'My Account': 'My Account',
      'About': 'About',
      'How to Use': 'How to Use',
      'Notice': 'Notice',
      'Sign Out': 'Sign Out',
      'Failed to pick video file': 'Failed to pick video file',
      'No video selected': 'No video selected',
      'No audio tracks selected': 'No audio tracks selected',
      'Export failed': 'Export failed',
      'Unknown error': 'Unknown error',
      'Export error': 'Export error',
      'Offset cannot exceed 180 seconds.': 'Offset cannot exceed 180 seconds.',
      'Start from Now': 'Start from Now',
      'Delete track?': 'Delete track?',
      'Are you sure you want to delete this audio track?':
          'Are you sure you want to delete this audio track?',
      'Cancel': 'Cancel',
      'Delete': 'Delete',
      'Add Video Clip': 'Add Video Clip',
      'Pro Mode Feature': 'Pro Mode Feature',
      'Upgrade to Pro mode to import more than 1 video.':
          'Upgrade to Pro mode to import more than 1 video.',
      'Upgrade to Pro mode to import more than 3 audio tracks.':
          'Upgrade to Pro mode to import more than 3 audio tracks.',
      'Delete clip?': 'Delete clip?',
      'Are you sure you want to remove this video clip from your timeline?':
          'Are you sure you want to remove this video clip from your timeline?',
      'Exit project?': 'Exit project?',
      'All progress will be lost.': 'All progress will be lost.',
      'Confirm': 'Confirm',
      'Help': 'Help',
      'Automatically synchronizes all audio tracks to the video. Audio offset/trim may be adjusted.':
          'Automatically synchronizes all audio tracks to the video. Audio offset/trim may be adjusted.',
      'Audio Track Effects': 'Audio Track Effects',
      'Exporting...': 'Exporting...',
      'Please don\'t close the app or lock your screen.':
          'Please don\'t close the app or lock your screen.',
      'Track': 'Track',
      'Effects': 'Effects',
      'Concert Hall': 'Concert Hall',
      'Echoes': 'Echoes',
      'LoFi Effect': 'LoFi Effect',
      'Heavy Crunch': 'Heavy Crunch',
      'Applies wide reverb and subtle EQ to simulate a live concert space.':
          'Applies wide reverb and subtle EQ to simulate a live concert space.',
      'Applies reverb and delay to give an echo effect.':
          'Applies reverb and delay to give an echo effect.',
      'Applies filters and soft distortion for a vintage, relaxed vibe.':
          'Applies filters and soft distortion for a vintage, relaxed vibe.',
      'Crushes sound with heavy distortion.':
          'Crushes sound with heavy distortion.',
      'This will replace your current effects with ':
          'This will replace your current effects with ',
      'Add Effect': 'Add Effect',
      'Delete Effect?': 'Delete Effect?',
      'Parameters': 'Parameters',
      'Select ': 'Select ',
      'Close': 'Close',
      'Export failed: Output file missing or too small.':
          'Export failed: Output file missing or too small.',
      'Export failed! Check logs.': 'Export failed! Check logs.',
      'AI Sync failed: Computed offset exceeds audio length.':
          'AI Sync failed: Computed offset exceeds audio length.',
      'AI Sync failed: Computed trim exceeds audio length.':
          'AI Sync failed: Computed trim exceeds audio length.',
      'Done': 'Done',
      'Load Preset': 'Load Preset',
      'On Device': 'On Device',
      'Notifications': 'Notifications',
      'No new notifications': 'No new notifications',
      'Welcome to Mixroom': 'Welcome to Mixroom',
    },
    'ko': {
      'hello': '안녕하세요',
      'share': '공유',
      'Editor': '에디터',
      'Video Editing': '영상 편집',
      'Store': '스토어',
      'Mixroom': '믹스룸',
      '© Mixroom': '© 믹스룸',
      'Powered by Mixroom': '믹스룸 제공',
      'Audio-Only Mode': '오디오 전용 모드',
      'Video Editor': '비디오 편집기',
      'Video Audio Volume Automation': '비디오 오디오 볼륨 자동 조절',
      'Select Audio': '오디오 선택',
      'Pick from Device': '기기에서 선택',
      'Crossfade (Video vs. All Audio)': '크로스페이드 (비디오 대 모든 오디오)',
      'Volume Balance': 'Volume Balance',
      'Add Audio Track': '오디오 트랙 추가',
      'Audio': '오디오',
      'Offset': 'Offset', //'오프셋',
      'Trim': 'Trim', //'자르기',
      'Volume Automation': 'Volume Automation', //'볼륨 자동화',
      'Gain': 'Gain', //'게인',
      'AI Sync': 'AI Sync',
      'Next': '다음',
      'Syncing Audio': '오디오 싱크 중',
      'AI Sync applied successfully!': 'AI 싱크 적용 성공!',
      'Audio Effects': '오디오 이펙터',
      'Echo': '에코',
      'Reverb': '리버브',
      'Back': '뒤로',
      'Export': '내보내기',
      'EXPORT': '내보내기',
      'Exported file saved!': '내보낸 파일 저장 완료!',
      'Your video was exported successfully!': '비디오 내보내기 성공!',
      'Share directly to:': '다음으로 공유:',
      'YouTube': '유튜브',
      'Instagram': '인스타그램',
      'TikTok': '틱톡',
      'Back to Editor': '편집기로 돌아가기',
      'Export Successful': '내보내기 성공',
      'Audio Editor': '오디오 편집기',
      "SoundCloud": "사운드클라우드",
      "Export canceled or failed.": "내보내기 취소 또는 실패",
      "Your audio was exported successfully!": "오디오가 성공적으로 내보내졌습니다!",
      'Coming soon': '곧 제공 예정',
      'Coming Soon': '곧 공개',
      'Search feature coming soon!': '검색 기능이 곧 제공됩니다!',
      'Title / Artist / Genre / etc...': '제목 / 아티스트 / 장르 / 등...',
      'Explore feature coming soon!': '감상하기 기능이 곧 제공됩니다!',
      'Explore': '감상하기',
      'Basic': '베이직',
      'Pro': '프로',
      'Welcome back': '다시 오신 것을 환영합니다',
      'Home': '홈',
      'Projects': '프로젝트',
      'Presets': '프리셋',
      'Uploads': '업로드',
      'My Account': '내 계정',
      'About': '정보',
      'How to Use': '사용 방법',
      'Notice': '공지',
      'Sign Out': '로그아웃',
      'Failed to pick video file': '비디오 파일 선택 실패',
      'No video selected': '선택된 비디오가 없습니다',
      'No audio tracks selected': '선택된 오디오 트랙이 없습니다',
      'Export failed': '내보내기 실패',
      'Unknown error': '알 수 없는 오류',
      'Export error': '내보내기 오류',
      'Offset cannot exceed 180 seconds.': '오프셋은 180초를 초과할 수 없습니다.',
      'Start from Now': '지금부터 시작',
      'Delete track?': '트랙 삭제?',
      'Are you sure you want to delete this audio track?':
          '이 오디오 트랙을 삭제하시겠습니까?',
      'Cancel': '취소',
      'Delete': '삭제',
      'Add Video Clip': '비디오 클립 추가',
      'Pro Mode Feature': '프로 모드 기능',
      'Upgrade to Pro mode to import more than 1 video.':
          '1개 이상의 비디오를 가져오려면 프로 모드로 업그레이드하세요.',
      'Upgrade to Pro mode to import more than 3 audio tracks.':
          '3개 이상의 오디오 트랙을 가져오려면 프로 모드로 업그레이드하세요.',
      'Delete clip?': '클립을 삭제하시겠습니까?',
      'Are you sure you want to remove this video clip from your timeline?':
          '타임라인에서 이 비디오 클립을 제거하시겠습니까?',
      'Exit project?': '프로젝트를 종료하시겠습니까?',
      'All progress will be lost.': '모든 진행 내용이 사라집니다.',
      'Confirm': '확인',
      'Help': '도움말',
      'Automatically synchronizes all audio tracks to the video. Audio offset/trim may be adjusted.':
          '모든 오디오 트랙을 비디오와 자동으로 동기화합니다. 오디오 오프셋/트림이 조정될 수 있습니다.',
      'Audio Track Effects': '오디오 트랙 이펙터',
      'Exporting...': '내보내는 중...',
      'Please don\'t close the app or lock your screen.':
          '앱을 종료하거나 화면을 잠그지 마세요.',
      'Track': '트랙',
      'Effects': '이펙터',
      'Concert Hall': '콘서트 홀',
      'Echoes': '에코',
      'LoFi Effect': '로파이 효과',
      'Heavy Crunch': '헤비 크런치',
      'Applies wide reverb and subtle EQ to simulate a live concert space.':
          '라이브 콘서트 공간을 시뮬레이션하기 위해 넓은 리버브와 섬세한 EQ를 적용합니다.',
      'Applies reverb and delay to give an echo effect.':
          '에코 효과를 위해 리버브와 딜레이를 적용합니다.',
      'Applies filters and soft distortion for a vintage, relaxed vibe.':
          '빈티지하고 편안한 분위기를 위해 필터와 부드러운 디스토션을 적용합니다.',
      'Crushes sound with heavy distortion.': '강한 디스토션으로 사운드를 뭉개줍니다.',
      'This will replace your current effects with ': '현재 효과가 다음으로 교체됩니다: ',
      'Add Effect': '효과 추가',
      'Delete Effect?': '효과를 삭제하시겠습니까?',
      'Parameters': '파라미터',
      'Select ': '선택 ',
      'Close': '닫기',
      'Export failed: Output file missing or too small.':
          '내보내기 실패: 출력 파일이 없거나 너무 작습니다.',
      'Export failed! Check logs.': '내보내기 실패! 로그를 확인하세요.',
      'AI Sync failed: Computed offset exceeds audio length.':
          'AI 싱크 실패: 계산된 오프셋이 오디오 길이를 초과합니다.',
      'AI Sync failed: Computed trim exceeds audio length.':
          'AI 싱크 실패: 계산된 트림이 오디오 길이를 초과합니다.',
      'Done': '완료',
      'Load Preset': '프리셋 불러오기',
      'On Device': '기기 내',
      'Notifications': '알림',
      'No new notifications': '새 알림이 없습니다',
      'Welcome to Mixroom': '믹스룸에 오신 것을 환영합니다',
    },
    'zh': {
      'hello': '你好',
      'share': '分享',
      'Editor': '编辑器',
      'Video Editing': '视频编辑',
      'Store': '商店',
      'Mixroom': 'Mixroom',
      '© Mixroom': '© Mixroom',
      'Powered by Mixroom': '由Mixroom提供',
      'Audio-Only Mode': '仅音频模式',
      'Video Editor': '视频编辑器',
      'Video Audio Volume Automation': '视频音频音量自动化',
      'Select Audio': '选择音频',
      'Pick from Device': '从设备选择',
      'Crossfade (Video vs. All Audio)': '交叉淡化 (视频 vs 所有音频)',
      'Volume Balance': 'Volume Balance',
      'Add Audio Track': '添加音轨',
      'Audio': '音频',
      'Offset': '偏移',
      'Trim': '修剪',
      'Volume Automation': '音量自动化',
      'Gain': '增益',
      'AI Sync': 'AI同步',
      'Next': '下一步',
      'Syncing Audio': '同步音频中',
      'AI Sync applied successfully!': 'AI同步应用成功!',
      'Audio Effects': '音频效果',
      'Echo': '回声',
      'Reverb': '混响',
      'Back': '返回',
      'Export': '导出',
      'EXPORT': '导出',
      'Exported file saved!': '导出文件已保存!',
      'Your video was exported successfully!': '视频导出成功!',
      'Share directly to:': '直接分享到:',
      'YouTube': 'YouTube',
      'Instagram': 'Instagram',
      'TikTok': 'TikTok',
      'Back to Editor': '返回编辑器',
      'Export Successful': '导出成功',
      'Audio Editor': '音频编辑器',
      "SoundCloud": "SoundCloud",
      "Export canceled or failed.": "导出已取消或失败",
      "Your audio was exported successfully!": "音频导出成功！",
      'Coming soon': '即将推出',
      'Coming Soon': '敬请期待',
      'Search feature coming soon!': '搜索功能即将推出！',
      'Title / Artist / Genre / etc...': '标题 / 艺术家 / 类型 / 等…',
      'Explore feature coming soon!': '探索功能即将推出！',
      'Explore': '探索',
      'Basic': '基础',
      'Pro': '专业',
      'Welcome back': '欢迎回来',
      'Home': '首页',
      'Projects': '项目',
      'Presets': '预设',
      'Uploads': '上传',
      'My Account': '我的账户',
      'About': '关于',
      'How to Use': '使用指南',
      'Notice': '通知',
      'Sign Out': '退出登录',
      'Failed to pick video file': '选择视频文件失败',
      'No video selected': '未选择视频',
      'No audio tracks selected': '未选择音轨',
      'Export failed': '导出失败',
      'Unknown error': '未知错误',
      'Export error': '导出错误',
      'Offset cannot exceed 180 seconds.': '偏移量不能超过180秒。',
      'Start from Now': '从现在开始',
      'Delete track?': '删除轨道?',
      'Are you sure you want to delete this audio track?': '确定要删除此音频轨道吗？',
      'Cancel': '取消',
      'Delete': '删除',
      'Add Video Clip': '添加视频片段',
      'Pro Mode Feature': '专业模式功能',
      'Upgrade to Pro mode to import more than 1 video.': '升级到专业模式以导入超过1个视频。',
      'Upgrade to Pro mode to import more than 3 audio tracks.':
          '升级到专业模式以导入超过3条音轨。',
      'Delete clip?': '删除片段？',
      'Are you sure you want to remove this video clip from your timeline?':
          '确定要从时间轴中移除此视频片段吗？',
      'Exit project?': '退出项目？',
      'All progress will be lost.': '所有进度将丢失。',
      'Confirm': '确认',
      'Help': '帮助',
      'Automatically synchronizes all audio tracks to the video. Audio offset/trim may be adjusted.':
          '自动将所有音轨与视频同步。可能会调整音频的偏移/裁剪。',
      'Audio Track Effects': '音轨效果',
      'Exporting...': '正在导出…',
      'Please don\'t close the app or lock your screen.': '请不要关闭应用或锁定屏幕。',
      'Track': '轨道',
      'Effects': '效果',
      'Concert Hall': '音乐厅',
      'Echoes': '回声',
      'LoFi Effect': 'LoFi 效果',
      'Heavy Crunch': '重度失真',
      'Applies wide reverb and subtle EQ to simulate a live concert space.':
          '应用宽广混响和细微均衡，模拟现场音乐会空间。',
      'Applies reverb and delay to give an echo effect.': '应用混响和延迟以产生回声效果。',
      'Applies filters and soft distortion for a vintage, relaxed vibe.':
          '应用滤波和轻微失真，营造复古、松弛的氛围。',
      'Crushes sound with heavy distortion.': '使用强烈失真压碎声音。',
      'This will replace your current effects with ': '这将把您当前的效果替换为 ',
      'Add Effect': '添加效果',
      'Delete Effect?': '删除效果？',
      'Parameters': '参数',
      'Select ': '选择 ',
      'Close': '关闭',
      'Export failed: Output file missing or too small.': '导出失败：输出文件缺失或过小。',
      'Export failed! Check logs.': '导出失败！请检查日志。',
      'AI Sync failed: Computed offset exceeds audio length.':
          'AI 同步失败：计算的偏移超过音频长度。',
      'AI Sync failed: Computed trim exceeds audio length.':
          'AI 同步失败：计算的裁剪超过音频长度。',
      'Done': '完成',
      'Load Preset': '加载预设',
      'On Device': '在设备上',
      'Notifications': '通知',
      'No new notifications': '没有新通知',
      'Welcome to Mixroom': '欢迎来到 Mixroom',
    },
    'ja': {
      'hello': 'こんにちは',
      'share': '共有',
      'Editor': 'エディター',
      'Video Editing': '動画編集',
      'Store': 'ストア',
      'Mixroom': 'Mixroom',
      '© Mixroom': '© Mixroom',
      'Powered by Mixroom': 'Mixroom提供',
      'Audio-Only Mode': 'オーディオ専用モード',
      'Video Editor': '動画エディター',
      'Video Audio Volume Automation': '動画オーディオ音量自動化',
      'Select Audio': 'オーディオを選択',
      'Pick from Device': 'デバイスから選択',
      'Crossfade (Video vs. All Audio)': 'クロスフェード (動画 vs 全オーディオ)',
      'Volume Balance': 'Volume Balance',
      'Add Audio Track': 'オーディオトラックを追加',
      'Audio': 'オーディオ',
      'Offset': 'オフセット',
      'Trim': 'トリミング',
      'Volume Automation': '音量自動化',
      'Gain': 'ゲイン',
      'AI Sync': 'AI同期',
      'Next': '次へ',
      'Syncing Audio': 'オーディオ同期中',
      'AI Sync applied successfully!': 'AI同期が成功しました!',
      'Audio Effects': 'オーディオ効果',
      'Echo': 'エコー',
      'Reverb': 'リバーブ',
      'Back': '戻る',
      'Export': 'エクスポート',
      'EXPORT': 'エクスポート',
      'Exported file saved!': 'ファイルをエクスポートしました!',
      'Your video was exported successfully!': '動画のエクスポートが成功しました!',
      'Share directly to:': '直接共有:',
      'YouTube': 'YouTube',
      'Instagram': 'Instagram',
      'TikTok': 'TikTok',
      'Back to Editor': 'エディターに戻る',
      'Export Successful': 'エクスポート成功',
      'Audio Editor': 'オーディオエディター',
      "SoundCloud": "サウンドクラウド",
      "Export canceled or failed.": "エクスポートがキャンセルまたは失敗しました",
      "Your audio was exported successfully!": "オーディオのエクスポートが成功しました！",
      'Coming soon': '近日公開',
      'Coming Soon': '近日公開',
      'Search feature coming soon!': '検索機能は近日公開予定！',
      'Title / Artist / Genre / etc...': 'タイトル / アーティスト / ジャンル / など...',
      'Explore feature coming soon!': '探索機能は近日公開予定！',
      'Explore': '探索',
      'Basic': 'ベーシック',
      'Pro': 'プロ',
      'Welcome back': 'お帰りなさい',
      'Home': 'ホーム',
      'Projects': 'プロジェクト',
      'Presets': 'プリセット',
      'Uploads': 'アップロード',
      'My Account': 'マイアカウント',
      'About': 'アプリ情報',
      'How to Use': '使い方',
      'Notice': 'お知らせ',
      'Sign Out': 'サインアウト',
      'Failed to pick video file': '動画ファイルの選択に失敗しました',
      'No video selected': '動画が選択されていません',
      'No audio tracks selected': 'オーディオトラックが選択されていません',
      'Export failed': '書き出しに失敗しました',
      'Unknown error': '不明なエラー',
      'Export error': '書き出しエラー',
      'Offset cannot exceed 180 seconds.': 'オフセットは180秒を超えることはできません。',
      'Start from Now': '今から開始',
      'Delete track?': 'トラックを削除?',
      'Are you sure you want to delete this audio track?':
          'このオーディオトラックを削除してもよろしいですか？',
      'Cancel': 'キャンセル',
      'Delete': '削除',
      'Add Video Clip': '動画クリップを追加',
      'Pro Mode Feature': 'プロモードの機能',
      'Upgrade to Pro mode to import more than 1 video.':
          '1本以上の動画を取り込むにはプロモードにアップグレードしてください。',
      'Upgrade to Pro mode to import more than 3 audio tracks.':
          '3本以上のオーディオトラックを取り込むにはプロモードにアップグレードしてください。',
      'Delete clip?': 'クリップを削除しますか？',
      'Are you sure you want to remove this video clip from your timeline?':
          'タイムラインからこの動画クリップを削除してもよろしいですか？',
      'Exit project?': 'プロジェクトを終了しますか？',
      'All progress will be lost.': '進行状況はすべて失われます。',
      'Confirm': '確認',
      'Help': 'ヘルプ',
      'Automatically synchronizes all audio tracks to the video. Audio offset/trim may be adjusted.':
          'すべてのオーディオトラックを動画に自動同期します。オーディオのオフセット/トリムが調整される場合があります。',
      'Audio Track Effects': 'オーディオトラックのエフェクト',
      'Exporting...': '書き出し中...',
      'Please don\'t close the app or lock your screen.':
          'アプリを閉じたり画面をロックしないでください。',
      'Track': 'トラック',
      'Effects': 'エフェクト',
      'Concert Hall': 'コンサートホール',
      'Echoes': 'エコー',
      'LoFi Effect': 'LoFi エフェクト',
      'Heavy Crunch': 'ヘビークランチ',
      'Applies wide reverb and subtle EQ to simulate a live concert space.':
          '広がりのあるリバーブと繊細なEQでライブ会場の空間を再現します。',
      'Applies reverb and delay to give an echo effect.':
          'リバーブとディレイを適用してエコー効果を与えます。',
      'Applies filters and soft distortion for a vintage, relaxed vibe.':
          'フィルターと穏やかな歪みで、ヴィンテージでリラックスした雰囲気を演出します。',
      'Crushes sound with heavy distortion.': '強いディストーションでサウンドを潰します。',
      'This will replace your current effects with ':
          '現在のエフェクトは次の内容に置き換えられます： ',
      'Add Effect': 'エフェクトを追加',
      'Delete Effect?': 'エフェクトを削除しますか？',
      'Parameters': 'パラメーター',
      'Select ': '選択 ',
      'Close': '閉じる',
      'Export failed: Output file missing or too small.':
          '書き出し失敗：出力ファイルが見つからないか小さすぎます。',
      'Export failed! Check logs.': '書き出し失敗！ログを確認してください。',
      'AI Sync failed: Computed offset exceeds audio length.':
          'AI同期に失敗:計算されたオフセットが音声の長さを超えています。',
      'AI Sync failed: Computed trim exceeds audio length.':
          'AI同期に失敗:計算されたトリムが音声の長さを超えています。',
      'Done': '完了',
      'Load Preset': 'プリセットを読み込む',
      'On Device': 'このデバイス内',
      'Notifications': '通知',
      'No new notifications': '新しい通知はありません',
      'Welcome to Mixroom': 'Mixroomへようこそ',
    },
  };

  /// Get translated string
  static String translate(BuildContext context, String key) {
    final locale = getDeviceLocale(context);
    return _translations[locale.languageCode]?[key] ??
        _translations['en']?[key] ??
        key; // Final fallback: raw key (prevents null-crash on new strings)
  }

  static Future<void> setLocale(BuildContext context, Locale newLocale) async {
    // Save to provider and persistent storage
    await Provider.of<LocaleProvider>(context, listen: false)
        .setLocale(newLocale);

    // Directly access the state of MyApp and update the locale
    final appState = context.findAncestorStateOfType<MyAppState>();
    appState?.setAppLocale(newLocale);
  }
}
