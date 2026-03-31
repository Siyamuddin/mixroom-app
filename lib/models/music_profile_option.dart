class MusicProfileOption {
  const MusicProfileOption({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

const List<MusicProfileOption> kMusicProfileOptions = <MusicProfileOption>[
  MusicProfileOption(value: 'producer', label: 'Producer'),
  MusicProfileOption(value: 'artist', label: 'Artist'),
  MusicProfileOption(value: 'songwriter', label: 'Songwriter'),
  MusicProfileOption(value: 'audio_engineer', label: 'Audio engineer'),
  MusicProfileOption(value: 'student', label: 'Student'),
  MusicProfileOption(value: 'music_enthusiast', label: 'Music enthusiast'),
  MusicProfileOption(value: 'beginner', label: 'Beginner'),
  MusicProfileOption(value: 'music_for_work', label: 'Make music for work'),
];

String musicProfileLabel(String? value) {
  final safeValue = (value ?? '').trim().toLowerCase();
  for (final option in kMusicProfileOptions) {
    if (option.value == safeValue) return option.label;
  }
  return '';
}
