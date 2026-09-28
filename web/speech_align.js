// Loaded on demand by the web player. Recognizes one short clip of dialogue
// so a spoken line can be matched to the subtitle file. The model downloads
// the first time someone turns auto-sync on.
let transcriberPromise;

function resampleTo16k(input, sampleRate) {
  if (!sampleRate || sampleRate === 16000) return input;
  const ratio = sampleRate / 16000;
  const length = Math.max(1, Math.floor(input.length / ratio));
  const out = new Float32Array(length);
  for (let i = 0; i < length; i++) {
    const x = i * ratio;
    const i0 = Math.floor(x);
    const i1 = Math.min(i0 + 1, input.length - 1);
    const frac = x - i0;
    out[i] = input[i0] * (1 - frac) + input[i1] * frac;
  }
  return out;
}

async function srctvTranscribe(samples, sampleRate) {
  if (!transcriberPromise) {
    const { pipeline, env } = await import(
      'https://cdn.jsdelivr.net/npm/@xenova/transformers@2.17.2'
    );
    env.allowLocalModels = false;
    env.useBrowserCache = true;
    transcriberPromise = pipeline(
      'automatic-speech-recognition',
      'Xenova/whisper-base.en',
      { quantized: true },
    );
  }
  const transcriber = await transcriberPromise;
  const audio = resampleTo16k(samples, sampleRate || 48000);
  let result;
  try {
    result = await transcriber(audio, {
      language: 'english',
      task: 'transcribe',
      return_timestamps: true,
    });
  } catch (_) {
    result = await transcriber(audio, {
      language: 'english',
      task: 'transcribe',
    });
  }
  const chunks = result && Array.isArray(result.chunks) ? result.chunks : [];
  for (const chunk of chunks) {
    const text = String(chunk.text || '').trim();
    if (text.split(/\s+/).filter(Boolean).length < 4) continue;
    const start = Array.isArray(chunk.timestamp) ? Number(chunk.timestamp[0]) : 0;
    return JSON.stringify({
      text,
      start: Number.isFinite(start) && start > 0 ? start : 0,
    });
  }
  const text = result && result.text ? String(result.text).trim() : '';
  return JSON.stringify({ text, start: 0 });
}

window.srctvTranscribe = srctvTranscribe;
