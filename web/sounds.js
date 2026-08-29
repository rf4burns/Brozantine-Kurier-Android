(function (global) {
  const SOUNDS_VOLUME = 2;
  const SOUND_TYPES = [
    "message_received",
    "message_sent",
    "server_disconnected",
    "own_user_left_voice_channel",
    "own_user_joined_voice_channel",
    "own_user_muted_mic",
    "own_user_unmuted_mic",
    "own_user_muted_sound",
    "own_user_unmuted_sound",
    "own_user_started_webcam",
    "own_user_stopped_webcam",
    "own_user_started_screenshare",
    "own_user_stopped_screenshare",
    "remote_user_joined_voice_channel",
    "remote_user_left_voice_channel",
    "remote_user_started_screenshare",
    "remote_user_stopped_screenshare",
  ];

  // 1-sample silent WAV; looping this marks Chromium tabs as audible.
  const SILENT_WAV =
    "data:audio/wav;base64,UklGRigAAABXQVZFZm10IBIAAAABAAEARKwAAIhYAQACABAAAABkYXRhAgAAAAEA";

  let audioCtx;
  let hasAudioContext = false;
  let pendingAudioContext = null;
  let keepAlive = null;
  let silentEl = null;
  let unlocked = false;
  let outputDevice = "";

  const isIos = () =>
    /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);

  const isAndroid = () => /Android/i.test(navigator.userAgent);

  const isDesktop = () => !isIos() && !isAndroid();

  const createAudioContext = () => {
    const Ctor = window.AudioContext || window.webkitAudioContext;
    if (!Ctor) return null;
    return new Ctor();
  };

  const getAudioContext = () => {
    if (hasAudioContext && audioCtx.state === "closed") {
      hasAudioContext = false;
    }
    if (!hasAudioContext) {
      const ctx = createAudioContext();
      if (!ctx) return null;
      audioCtx = ctx;
      hasAudioContext = true;
      applySink(ctx);
    }
    return audioCtx;
  };

  const applySink = (ctx) => {
    if (ctx && typeof ctx.setSinkId === "function") {
      ctx.setSinkId(outputDevice || "").catch(() => {});
    }
    if (silentEl && typeof silentEl.setSinkId === "function") {
      silentEl.setSinkId(outputDevice || "").catch(() => {});
    }
  };

  const setOutputDevice = (deviceId) => {
    outputDevice = deviceId || "";
    applySink(hasAudioContext ? audioCtx : null);
  };

  const ensureAudioContextRunning = async () => {
    if (pendingAudioContext) return pendingAudioContext;
    pendingAudioContext = (async () => {
      const ctx = getAudioContext();
      if (!ctx) return null;
      if (ctx.state === "suspended" || ctx.state === "interrupted") {
        try {
          await ctx.resume();
        } catch (_) {}
      }
      if (ctx.state !== "running") return null;
      return ctx;
    })();
    try {
      return await pendingAudioContext;
    } finally {
      pendingAudioContext = null;
    }
  };

  const getReadyAudioContext = () => {
    if (!hasAudioContext) throw new Error("Audio context is not initialized");
    return audioCtx;
  };

  const now = () => getReadyAudioContext().currentTime;

  const createOsc = (type, freq) => {
    const osc = getReadyAudioContext().createOscillator();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, now());
    return osc;
  };

  const createGain = (value = 1) => {
    const gain = getReadyAudioContext().createGain();
    gain.gain.setValueAtTime(value * SOUNDS_VOLUME, now());
    return gain;
  };

  const sfxMessageReceived = () => {
    const osc = createOsc("sine", 600);
    const gain = createGain(0.05);
    gain.gain.exponentialRampToValueAtTime(0.0001, now() + 0.05);
    osc.connect(gain).connect(audioCtx.destination);
    osc.start();
    osc.stop(now() + 0.05);
  };

  const sfxMessageSent = () => {
    const osc = createOsc("sine", 750);
    const gain = createGain(0.04);
    gain.gain.exponentialRampToValueAtTime(0.0001, now() + 0.04);
    osc.connect(gain).connect(audioCtx.destination);
    osc.start();
    osc.stop(now() + 0.04);
  };

  const sfxServerDisconnected = () => {
    const notes = [
      { freq: 988, gain: 0.115, delay: 0 },
      { freq: 784, gain: 0.108, delay: 0.09 },
      { freq: 659, gain: 0.106, delay: 0.18 },
      { freq: 523, gain: 0.12, delay: 0.27 },
    ];
    notes.forEach(({ freq, gain: g, delay }, index) => {
      const startAt = now() + delay;
      const endAt = startAt + (index === notes.length - 1 ? 0.24 : 0.18);
      const osc = createOsc("sine", freq);
      const gain = createGain(g);
      gain.gain.setValueAtTime(g * SOUNDS_VOLUME, startAt);
      gain.gain.exponentialRampToValueAtTime(0.0001, endAt);
      if (index === notes.length - 1) {
        osc.frequency.exponentialRampToValueAtTime(440, endAt);
        const harmonicOsc = createOsc("triangle", 784);
        const harmonicGain = createGain(0.05);
        harmonicGain.gain.exponentialRampToValueAtTime(0.0001, endAt);
        harmonicOsc.connect(harmonicGain).connect(audioCtx.destination);
        harmonicOsc.start(startAt + 0.02);
        harmonicOsc.stop(endAt);
      }
      osc.connect(gain).connect(audioCtx.destination);
      osc.start(startAt);
      osc.stop(endAt);
    });
  };

  const sfxOwnUserJoinedVoiceChannel = () => {
    [
      { freq: 523, gain: 0.09 },
      { freq: 659, gain: 0.07 },
      { freq: 784, gain: 0.06 },
    ].forEach(({ freq, gain: g }) => {
      const osc = createOsc("sine", freq);
      const gain = createGain(g);
      gain.gain.exponentialRampToValueAtTime(0.0001, now() + 0.25);
      osc.connect(gain).connect(audioCtx.destination);
      osc.start();
      osc.stop(now() + 0.25);
    });
    [
      { freq: 1046, gain: 0.04 },
      { freq: 1318, gain: 0.03 },
    ].forEach(({ freq, gain: g }) => {
      const osc = createOsc("triangle", freq);
      const gain = createGain(g);
      gain.gain.exponentialRampToValueAtTime(0.0001, now() + 0.3);
      osc.connect(gain).connect(audioCtx.destination);
      osc.start(now() + 0.08);
      osc.stop(now() + 0.3);
    });
  };

  const sfxOwnUserLeftVoiceChannel = () => {
    [
      { freq: 440, gain: 0.09 },
      { freq: 523, gain: 0.07 },
      { freq: 659, gain: 0.06 },
    ].forEach(({ freq, gain: g }) => {
      const osc = createOsc("sine", freq);
      const gain = createGain(g);
      gain.gain.exponentialRampToValueAtTime(0.0001, now() + 0.3);
      osc.connect(gain).connect(audioCtx.destination);
      osc.start();
      osc.stop(now() + 0.3);
    });
    const osc2 = createOsc("triangle", 880);
    const gain2 = createGain(0.04);
    gain2.gain.exponentialRampToValueAtTime(0.0001, now() + 0.25);
    osc2.connect(gain2).connect(audioCtx.destination);
    osc2.start(now() + 0.05);
    osc2.stop(now() + 0.3);
  };

  const sfxOwnUserMutedMic = () => {
    const osc = createOsc("sine", 350);
    const gain = createGain(0.05);
    gain.gain.exponentialRampToValueAtTime(0.0001, now() + 0.06);
    osc.connect(gain).connect(audioCtx.destination);
    osc.start();
    osc.stop(now() + 0.06);
  };

  const sfxOwnUserUnmutedMic = () => {
    const osc = createOsc("sine", 500);
    const gain = createGain(0.05);
    gain.gain.exponentialRampToValueAtTime(0.0001, now() + 0.06);
    osc.connect(gain).connect(audioCtx.destination);
    osc.start();
    osc.stop(now() + 0.06);
  };

  const sfxOwnUserMutedSound = () => {
    const osc = createOsc("sine", 450);
    const gain = createGain(0.05);
    gain.gain.exponentialRampToValueAtTime(0.0001, now() + 0.06);
    osc.connect(gain).connect(audioCtx.destination);
    osc.start();
    osc.stop(now() + 0.06);
  };

  const sfxOwnUserUnmutedSound = () => {
    const osc = createOsc("sine", 650);
    const gain = createGain(0.05);
    gain.gain.exponentialRampToValueAtTime(0.0001, now() + 0.06);
    osc.connect(gain).connect(audioCtx.destination);
    osc.start();
    osc.stop(now() + 0.06);
  };

  const sfxOwnUserStartedWebcam = () => {
    const osc1 = createOsc("sine", 700);
    const gain1 = createGain(0.07);
    gain1.gain.exponentialRampToValueAtTime(0.0001, now() + 0.12);
    osc1.connect(gain1).connect(audioCtx.destination);
    osc1.start();
    osc1.stop(now() + 0.12);
    const osc2 = createOsc("sine", 900);
    const gain2 = createGain(0.04);
    gain2.gain.exponentialRampToValueAtTime(0.0001, now() + 0.1);
    osc2.connect(gain2).connect(audioCtx.destination);
    osc2.start(now() + 0.04);
    osc2.stop(now() + 0.12);
  };

  const sfxOwnUserStoppedWebcam = () => {
    const osc1 = createOsc("sine", 700);
    const gain1 = createGain(0.07);
    osc1.frequency.exponentialRampToValueAtTime(500, now() + 0.12);
    gain1.gain.exponentialRampToValueAtTime(0.0001, now() + 0.14);
    osc1.connect(gain1).connect(audioCtx.destination);
    osc1.start();
    osc1.stop(now() + 0.14);
  };

  const sfxOwnUserStartedScreenshare = () => {
    [
      { freq: 600, delay: 0 },
      { freq: 800, delay: 0.06 },
      { freq: 1000, delay: 0.12 },
    ].forEach(({ freq, delay }) => {
      const t = now() + delay;
      const osc = createOsc("sine", freq);
      const gain = createGain(0.08);
      gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.1);
      osc.connect(gain).connect(audioCtx.destination);
      osc.start(t);
      osc.stop(t + 0.1);
    });
    const osc2 = createOsc("triangle", 1200);
    const gain2 = createGain(0.03);
    gain2.gain.exponentialRampToValueAtTime(0.0001, now() + 0.2);
    osc2.connect(gain2).connect(audioCtx.destination);
    osc2.start(now() + 0.08);
    osc2.stop(now() + 0.22);
  };

  const sfxOwnUserStoppedScreenshare = () => {
    const osc1 = createOsc("sine", 900);
    const gain1 = createGain(0.08);
    osc1.frequency.exponentialRampToValueAtTime(550, now() + 0.18);
    gain1.gain.exponentialRampToValueAtTime(0.0001, now() + 0.2);
    osc1.connect(gain1).connect(audioCtx.destination);
    osc1.start();
    osc1.stop(now() + 0.2);
    const osc2 = createOsc("triangle", 1100);
    const gain2 = createGain(0.03);
    osc2.frequency.exponentialRampToValueAtTime(700, now() + 0.18);
    gain2.gain.exponentialRampToValueAtTime(0.0001, now() + 0.2);
    osc2.connect(gain2).connect(audioCtx.destination);
    osc2.start(now() + 0.05);
    osc2.stop(now() + 0.2);
  };

  const sfxRemoteUserJoinedVoiceChannel = () => {
    [
      { freq: 587, gain: 0.06, delay: 0 },
      { freq: 740, gain: 0.05, delay: 0.06 },
      { freq: 880, gain: 0.04, delay: 0.12 },
    ].forEach(({ freq, gain: g, delay }) => {
      const t = now() + delay;
      const osc = createOsc("sine", freq);
      const gain = createGain(g);
      gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.2);
      osc.connect(gain).connect(audioCtx.destination);
      osc.start(t);
      osc.stop(t + 0.2);
    });
  };

  const sfxRemoteUserLeftVoiceChannel = () => {
    [
      { freq: 659, gain: 0.06, delay: 0 },
      { freq: 523, gain: 0.05, delay: 0.06 },
      { freq: 440, gain: 0.04, delay: 0.12 },
    ].forEach(({ freq, gain: g, delay }) => {
      const t = now() + delay;
      const osc = createOsc("sine", freq);
      const gain = createGain(g);
      gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.2);
      osc.connect(gain).connect(audioCtx.destination);
      osc.start(t);
      osc.stop(t + 0.2);
    });
  };

  const sfxRemoteUserStartedScreenshare = () => {
    [
      { freq: 600, delay: 0 },
      { freq: 800, delay: 0.06 },
      { freq: 1000, delay: 0.12 },
    ].forEach(({ freq, delay }) => {
      const t = now() + delay;
      const osc = createOsc("sine", freq);
      const gain = createGain(0.06);
      gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.1);
      osc.connect(gain).connect(audioCtx.destination);
      osc.start(t);
      osc.stop(t + 0.1);
    });
    const osc2 = createOsc("triangle", 1200);
    const gain2 = createGain(0.02);
    gain2.gain.exponentialRampToValueAtTime(0.0001, now() + 0.2);
    osc2.connect(gain2).connect(audioCtx.destination);
    osc2.start(now() + 0.08);
    osc2.stop(now() + 0.22);
  };

  const sfxRemoteUserStoppedScreenshare = () => {
    const osc1 = createOsc("sine", 900);
    const gain1 = createGain(0.06);
    osc1.frequency.exponentialRampToValueAtTime(550, now() + 0.18);
    gain1.gain.exponentialRampToValueAtTime(0.0001, now() + 0.2);
    osc1.connect(gain1).connect(audioCtx.destination);
    osc1.start();
    osc1.stop(now() + 0.2);
    const osc2 = createOsc("triangle", 1100);
    const gain2 = createGain(0.02);
    osc2.frequency.exponentialRampToValueAtTime(700, now() + 0.18);
    gain2.gain.exponentialRampToValueAtTime(0.0001, now() + 0.2);
    osc2.connect(gain2).connect(audioCtx.destination);
    osc2.start(now() + 0.05);
    osc2.stop(now() + 0.2);
  };

  const playSfx = (type) => {
    switch (type) {
      case "message_received":
        return sfxMessageReceived();
      case "message_sent":
        return sfxMessageSent();
      case "server_disconnected":
        return sfxServerDisconnected();
      case "own_user_joined_voice_channel":
        return sfxOwnUserJoinedVoiceChannel();
      case "own_user_left_voice_channel":
        return sfxOwnUserLeftVoiceChannel();
      case "own_user_muted_mic":
        return sfxOwnUserMutedMic();
      case "own_user_unmuted_mic":
        return sfxOwnUserUnmutedMic();
      case "own_user_muted_sound":
        return sfxOwnUserMutedSound();
      case "own_user_unmuted_sound":
        return sfxOwnUserUnmutedSound();
      case "own_user_started_webcam":
        return sfxOwnUserStartedWebcam();
      case "own_user_stopped_webcam":
        return sfxOwnUserStoppedWebcam();
      case "own_user_started_screenshare":
        return sfxOwnUserStartedScreenshare();
      case "own_user_stopped_screenshare":
        return sfxOwnUserStoppedScreenshare();
      case "remote_user_joined_voice_channel":
        return sfxRemoteUserJoinedVoiceChannel();
      case "remote_user_left_voice_channel":
        return sfxRemoteUserLeftVoiceChannel();
      case "remote_user_started_screenshare":
        return sfxRemoteUserStartedScreenshare();
      case "remote_user_stopped_screenshare":
        return sfxRemoteUserStoppedScreenshare();
      default:
        return;
    }
  };

  const startOscKeepAlive = () => {
    if (!isDesktop() || !unlocked) return;
    const ctx = getAudioContext();
    if (!ctx) return;
    if (keepAlive && keepAlive.osc) return;
    stopOscKeepAlive();
    try {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      gain.gain.value = 0.0001;
      osc.frequency.value = 20;
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.onended = () => {
        if (keepAlive && keepAlive.osc === osc) {
          keepAlive = null;
          if (unlocked) startOscKeepAlive();
        }
      };
      osc.start();
      keepAlive = { osc: osc, gain: gain };
    } catch (_) {}
  };

  const stopOscKeepAlive = () => {
    const keep = keepAlive;
    if (!keep) return;
    try {
      keep.osc.stop();
    } catch (_) {}
    try {
      keep.osc.disconnect();
    } catch (_) {}
    try {
      keep.gain.disconnect();
    } catch (_) {}
    keepAlive = null;
  };

  const startSilentMedia = () => {
    if (!isDesktop() || !unlocked) return;
    if (silentEl) {
      silentEl.play().catch(() => {});
      return;
    }
    try {
      const el = document.createElement("audio");
      el.src = SILENT_WAV;
      el.loop = true;
      el.preload = "auto";
      el.volume = 0.01;
      el.setAttribute("playsinline", "");
      el.setAttribute("aria-hidden", "true");
      el.style.display = "none";
      document.body.appendChild(el);
      silentEl = el;
      el.play().catch(() => {});
      applySink(hasAudioContext ? audioCtx : null);
    } catch (_) {}
  };

  const stopSilentMedia = () => {
    if (!silentEl) return;
    try {
      silentEl.pause();
    } catch (_) {}
    try {
      silentEl.remove();
    } catch (_) {}
    silentEl = null;
  };

  const startKeepAlive = () => {
    if (!isDesktop() || !unlocked) return;
    startOscKeepAlive();
    startSilentMedia();
  };

  const stopKeepAlive = () => {
    unlocked = false;
    stopOscKeepAlive();
    stopSilentMedia();
  };

  const unlock = async () => {
    unlocked = true;
    const ctx = await ensureAudioContextRunning();
    if (ctx) startKeepAlive();
    return "";
  };

  const playSound = async (type) => {
    try {
      const ctx = await ensureAudioContextRunning();
      if (!ctx) return;
      if (unlocked && isDesktop()) startKeepAlive();
      playSfx(type);
    } catch (_) {}
  };

  const thaw = () => {
    if (!unlocked) return;
    unlock();
  };

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") thaw();
  });
  document.addEventListener("resume", thaw);
  document.addEventListener("pageshow", thaw);

  global.KurierSounds = {
    playSound,
    unlock,
    stopKeepAlive,
    setOutputDevice,
    getSoundTypes: () => SOUND_TYPES.slice(),
  };
})(window);
