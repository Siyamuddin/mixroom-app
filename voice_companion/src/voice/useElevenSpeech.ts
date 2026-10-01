import { useEffect, useRef } from 'react';
import { ElevenSpeechPort } from './speech.ts';
import type { SpeechPort } from './session.ts';

/** One adapter per component; renders do not replace callbacks or live sockets. */
export function useElevenSpeech(): SpeechPort {
  const port = useRef<ElevenSpeechPort | null>(null);
  if (!port.current) port.current = new ElevenSpeechPort();
  const speech = port.current;
  useEffect(() => () => {
    speech.stopSpeaking();
    void speech.stopListening().catch(() => undefined);
  }, [speech]);
  return speech;
}
