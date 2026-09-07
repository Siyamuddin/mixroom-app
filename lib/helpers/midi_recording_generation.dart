class MidiRecordingGeneration {
  int _value = 0;

  int get current => _value;

  void invalidate() {
    _value++;
  }

  bool isCurrent(int generation) => generation == _value;
}
