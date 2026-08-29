/* global mediasoupClient */
(function (global) {
  const SIGNAL_TIMEOUT_MS = 12000;

  function wait(ms) {
    return new Promise((r) => setTimeout(r, ms));
  }

  function parseJson(value) {
    if (value == null || value === "") return {};
    if (typeof value === "object") return value;
    return JSON.parse(String(value));
  }

  function unwrapCaps(input) {
    let caps = parseJson(input);
    if (caps.routerRtpCapabilities) caps = caps.routerRtpCapabilities;
    if (caps.rtpCapabilities) caps = caps.rtpCapabilities;
    if (caps.json && Array.isArray(caps.json.codecs)) caps = caps.json;
    if (!caps || !Array.isArray(caps.codecs)) {
      throw new Error("Invalid router RTP capabilities from voice.join");
    }
    return caps;
  }

  function iceFrom(iceServersJson) {
    const iceServers = parseJson(iceServersJson);
    return Array.isArray(iceServers) && iceServers.length ? iceServers : undefined;
  }

  function packOk(value) {
    return JSON.stringify({ ok: true, v: value == null ? "" : String(value) });
  }

  function packErr(err) {
    const msg = err && err.message ? String(err.message) : String(err);
    return JSON.stringify({ ok: false, v: msg || "Voice engine error" });
  }

  function flagOn(value) {
    return value === true || value === "true" || value === 1;
  }

  function isUserMediaAbort(err) {
    const name = err && err.name;
    return name === "NotAllowedError" || name === "NotFoundError" || name === "AbortError";
  }

  const SCREEN_MAX_BITRATE_KBPS = 2500;
  const SIMULCAST_WEBCAM_MAX_BITRATE = 900000;
  const SIMULCAST_MIN_MAX_BITRATE = 100000;
  const SIMULCAST_LOW_LAYER_MAX_BITRATE = 150000;
  const SIMULCAST_LOW_LAYER_BITRATE_RATIO = 0.35;
  const SIMULCAST_LOW_LAYER_MAX_FRAMERATE = 24;
  const SIMULCAST_LOW_LAYER_SCALE = 4;
  const SIMULCAST_MID_LAYER_MAX_BITRATE = 500000;
  const SIMULCAST_MID_LAYER_BITRATE_RATIO = 0.65;
  const SIMULCAST_MID_LAYER_MAX_FRAMERATE = 30;
  const SIMULCAST_MID_LAYER_SCALE = 2;
  const SIMULCAST_SCREEN_LOW_LAYER_MAX_BITRATE = 1500000;
  const SIMULCAST_SCREEN_LOW_LAYER_BITRATE_RATIO = 0.2;
  const SIMULCAST_SCREEN_LOW_LAYER_MAX_FRAMERATE = 30;
  const SIMULCAST_SCREEN_MID_LAYER_MAX_BITRATE = 4000000;
  const SIMULCAST_SCREEN_MID_LAYER_BITRATE_RATIO = 0.6;
  const SIMULCAST_SCREEN_MID_LAYER_MAX_FRAMERATE = 60;
  const SIMULCAST_HIGH_LAYER_SCALE = 1;

  function getSimulcastEncodings(maxBitrate) {
    const safeMaxBitrate = Math.max(SIMULCAST_MIN_MAX_BITRATE, maxBitrate);
    return [
      {
        maxBitrate: Math.min(
          SIMULCAST_LOW_LAYER_MAX_BITRATE,
          Math.round(safeMaxBitrate * SIMULCAST_LOW_LAYER_BITRATE_RATIO)
        ),
        maxFramerate: SIMULCAST_LOW_LAYER_MAX_FRAMERATE,
        scaleResolutionDownBy: SIMULCAST_LOW_LAYER_SCALE,
      },
      {
        maxBitrate: Math.min(
          SIMULCAST_MID_LAYER_MAX_BITRATE,
          Math.round(safeMaxBitrate * SIMULCAST_MID_LAYER_BITRATE_RATIO)
        ),
        maxFramerate: SIMULCAST_MID_LAYER_MAX_FRAMERATE,
        scaleResolutionDownBy: SIMULCAST_MID_LAYER_SCALE,
      },
      {
        maxBitrate: safeMaxBitrate,
        scaleResolutionDownBy: SIMULCAST_HIGH_LAYER_SCALE,
      },
    ];
  }

  function getScreenShareSimulcastEncodings(maxBitrate) {
    const safeMaxBitrate = Math.max(SIMULCAST_MIN_MAX_BITRATE, maxBitrate);
    return [
      {
        maxBitrate: Math.min(
          SIMULCAST_SCREEN_LOW_LAYER_MAX_BITRATE,
          Math.round(safeMaxBitrate * SIMULCAST_SCREEN_LOW_LAYER_BITRATE_RATIO)
        ),
        maxFramerate: SIMULCAST_SCREEN_LOW_LAYER_MAX_FRAMERATE,
        scaleResolutionDownBy: SIMULCAST_LOW_LAYER_SCALE,
      },
      {
        maxBitrate: Math.min(
          SIMULCAST_SCREEN_MID_LAYER_MAX_BITRATE,
          Math.round(safeMaxBitrate * SIMULCAST_SCREEN_MID_LAYER_BITRATE_RATIO)
        ),
        maxFramerate: SIMULCAST_SCREEN_MID_LAYER_MAX_FRAMERATE,
        scaleResolutionDownBy: SIMULCAST_MID_LAYER_SCALE,
      },
      {
        maxBitrate: safeMaxBitrate,
        scaleResolutionDownBy: SIMULCAST_HIGH_LAYER_SCALE,
      },
    ];
  }

  function getSimulcastQualityLayers(encodings) {
    return encodings.map((_, index) => ({
      spatialLayer: index,
      label: index === 0 ? "Low" : index === encodings.length - 1 ? "High" : "Medium",
    }));
  }

  function screenCodecOptions(maxKbps) {
    return {
      videoGoogleStartBitrate: Math.min(2000, maxKbps),
      videoGoogleMaxBitrate: maxKbps,
      videoGoogleMinBitrate: Math.min(200, maxKbps),
    };
  }

  const SPEAKING_THRESHOLD = 8;
  const SPEAKING_QUIET = 15;
  const SPEAKING_NORMAL = 30;

  function speakingIntensityOf(level) {
    if (level <= SPEAKING_THRESHOLD) return 0;
    if (level < SPEAKING_QUIET) return 1;
    if (level < SPEAKING_NORMAL) return 2;
    return 3;
  }

  const KurierMediasoup = {
    device: null,
    sendTransport: null,
    recvTransport: null,
    producers: {},
    consumers: {},
    localStreams: {},
    handlers: {},
    evtName: "",
    evtPayload: "",
    _pendingConnectSend: null,
    _pendingConnectRecv: null,
    _pendingProduce: null,
    _meters: {},
    _meterRaf: 0,
    _localMeterPaused: false,
    _statsPrev: {},
    _transportPrev: { producer: null, consumer: null, screen: null },
    _transportTotals: { sent: 0, received: 0 },
    _gains: {},
    _volumes: {},
    _keepAlive: null,
    _dummyTracks: {},
    _boundMedia: {},
    _bindTimers: {},
    _sendConnState: "",
    _recvConnState: "",
    _resumeTimer: 0,
    _resumingPlayback: false,
    _wakeLock: null,
    _wakeLockWanted: false,

    async _run(work) {
      try {
        return packOk(await work());
      } catch (err) {
        return packErr(err);
      }
    },

    _emit(name, payload) {
      try {
        this.evtName = String(name ?? "");
        this.evtPayload = String(payload ?? "");
        const fn = this.handlers[name];
        if (typeof fn === "function") fn();
      } catch (err) {
        console.error("KurierMediasoup emit failed", name, err);
      }
    },

    on(name, fn) {
      this.handlers[name] = fn;
      if (name === "speaking") this._emitCurrentSpeaking();
    },

    _ensureAudioCtx() {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (!this._audioCtx) {
        this._audioCtx = new Ctx();
        this._audioCtx.onstatechange = () => {
          const ctx = this._audioCtx;
          if (!ctx) return;
          if (ctx.state === "suspended" || ctx.state === "interrupted") {
            ctx.resume().catch(() => {});
            return;
          }
          if (ctx.state !== "running") return;
          this._reattachVoiceGraphs(true);
          this.resumePlayback();
        };
      }
      if (
        this._audioCtx.state === "suspended" ||
        this._audioCtx.state === "interrupted" ||
        this._audioCtx.state !== "running"
      ) {
        this._audioCtx.resume().catch(() => {});
      }
      this._applyCtxSink();
      return this._audioCtx;
    },

    _applyCtxSink() {
      const ctx = this._audioCtx;
      if (!ctx || typeof ctx.setSinkId !== "function") return;
      ctx.setSinkId(this._outputDevice || "").catch(() => {});
    },

    _startKeepAlive() {
      const ctx = this._ensureAudioCtx();
      if (this._keepAlive && this._keepAlive.osc) return;
      this._stopKeepAlive();
      try {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        gain.gain.value = 0.0001;
        osc.frequency.value = 20;
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.onended = () => {
          if (this._keepAlive && this._keepAlive.osc === osc) {
            this._keepAlive = null;
            if (this.sendTransport || this.recvTransport) this._startKeepAlive();
          }
        };
        osc.start();
        this._keepAlive = { osc: osc, gain: gain };
      } catch (_) {}
    },

    _stopKeepAlive() {
      const keep = this._keepAlive;
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
      this._keepAlive = null;
    },

    _isPlaybackKey(key) {
      const s = String(key);
      return s.endsWith(":screen_audio") || s.endsWith(":external_audio");
    },

    _usesHtmlAudioPlayback() {
      return this.isIos();
    },

    _audioHost(kind) {
      if (kind === "audio" && this._usesHtmlAudioPlayback()) return document.body;
      return document.getElementById("kurier-media-host") || document.body;
    },

    _styleAudioElement(el) {
      el.setAttribute("playsinline", "true");
      el.setAttribute("webkit-playsinline", "true");
      el.playsInline = true;
      el.autoplay = true;
      if (this._usesHtmlAudioPlayback()) {
        el.style.cssText =
          "position:fixed;left:0;top:0;width:1px;height:1px;opacity:0.01;pointer-events:none;z-index:-1";
      } else {
        el.style.cssText =
          "position:absolute;width:1px;height:1px;opacity:0;pointer-events:none";
      }
    },

    _attachVoiceGraph(key, stream) {
      if (this._usesHtmlAudioPlayback()) return false;
      this._detachVoiceGraph(key);
      if (!stream || !stream.getAudioTracks || !stream.getAudioTracks().length) {
        return false;
      }
      try {
        const ctx = this._ensureAudioCtx();
        const source = ctx.createMediaStreamSource(stream);
        const gain = ctx.createGain();
        const stored = this._volumes[key];
        const initial = typeof stored === "number" ? stored : this._isPlaybackKey(key) ? 0 : 1;
        gain.gain.value = initial;
        source.connect(gain);
        gain.connect(ctx.destination);
        this._gains[key] = { source: source, gain: gain };
        return true;
      } catch (err) {
        console.warn("voice graph failed", key, err);
        return false;
      }
    },

    _detachVoiceGraph(key) {
      const graph = this._gains[key];
      if (!graph) return;
      try {
        graph.source.disconnect();
      } catch (_) {}
      try {
        graph.gain.disconnect();
      } catch (_) {}
      delete this._gains[key];
    },

    _stopDummyTracks(key) {
      const tracks = this._dummyTracks[key];
      if (!tracks) return;
      tracks.forEach((t) => {
        try {
          t.stop();
        } catch (_) {}
      });
      delete this._dummyTracks[key];
    },

    _emitSpeaking(key, level, intensity) {
      this._emit(
        "speaking",
        JSON.stringify({ key: key, level: level, intensity: intensity })
      );
    },

    _emitCurrentSpeaking() {
      Object.keys(this._meters).forEach((key) => {
        const m = this._meters[key];
        const intensity = key === "local" && this._localMeterPaused ? 0 : m.intensity;
        this._emitSpeaking(key, 0, intensity);
      });
    },

    _startMeter(key, stream) {
      this._stopMeter(key, false);
      if (!stream) return;
      try {
        const clonedTracks = stream.getAudioTracks().map((t) => t.clone());
        if (!clonedTracks.length) return;
        const meterStream = new MediaStream(clonedTracks);
        const ctx = this._ensureAudioCtx();
        const analyser = ctx.createAnalyser();
        analyser.fftSize = 512;
        analyser.minDecibels = -90;
        analyser.maxDecibels = -10;
        analyser.smoothingTimeConstant = 0.85;
        const source = ctx.createMediaStreamSource(meterStream);
        source.connect(analyser);
        this._meters[key] = {
          analyser: analyser,
          source: source,
          clonedTracks: clonedTracks,
          intensity: 0,
          level: 0,
          data: new Uint8Array(analyser.frequencyBinCount),
        };
        this._tickMeters();
      } catch (err) {
        console.warn("speaking meter failed", key, err);
      }
    },

    _stopMeter(key, emitSilent) {
      const m = this._meters[key];
      if (!m) return;
      try {
        m.source.disconnect();
      } catch (_) {}
      if (m.clonedTracks) {
        m.clonedTracks.forEach((t) => {
          try {
            t.stop();
          } catch (_) {}
        });
      }
      delete this._meters[key];
      if (emitSilent !== false) this._emitSpeaking(key, 0, 0);
      if (!Object.keys(this._meters).length && this._meterRaf) {
        cancelAnimationFrame(this._meterRaf);
        this._meterRaf = 0;
      }
    },

    _stopAllMeters() {
      Object.keys(this._meters).forEach((key) => this._stopMeter(key, false));
      if (this._meterRaf) {
        cancelAnimationFrame(this._meterRaf);
        this._meterRaf = 0;
      }
      this._localMeterPaused = false;
    },

    _tickMeters() {
      if (this._meterRaf) return;
      const loop = () => {
        this._meterRaf = 0;
        const keys = Object.keys(this._meters);
        if (!keys.length) return;
        for (let i = 0; i < keys.length; i++) {
          const key = keys[i];
          const m = this._meters[key];
          if (!m) continue;
          if (key === "local" && this._localMeterPaused) {
            if (m.intensity !== 0) {
              m.intensity = 0;
              this._emitSpeaking(key, 0, 0);
            }
            continue;
          }
          m.analyser.getByteFrequencyData(m.data);
          let sum = 0;
          for (let n = 0; n < m.data.length; n++) sum += m.data[n] * m.data[n];
          const rms = Math.sqrt(sum / Math.max(1, m.data.length));
          const level = Math.min(100, (rms / 255) * 100);
          m.level = level;
          const intensity = speakingIntensityOf(level);
          if (intensity !== m.intensity) {
            m.intensity = intensity;
            this._emitSpeaking(key, level, intensity);
          }
        }
        this._meterRaf = requestAnimationFrame(loop);
      };
      this._meterRaf = requestAnimationFrame(loop);
    },

    async ready(timeoutMs) {
      return this._run(async () => {
        const deadline = Date.now() + (timeoutMs || 12000);
        while (!global.mediasoupClient && Date.now() < deadline) {
          await wait(50);
        }
        if (!global.mediasoupClient) {
          throw new Error("mediasoup-client is not loaded");
        }
        return "";
      });
    },

    _deviceCtor() {
      const m = global.mediasoupClient;
      if (!m) throw new Error("mediasoup-client is not loaded");
      const Device = m.Device || (m.default && m.default.Device);
      if (!Device) throw new Error("mediasoup-client Device export missing");
      return Device;
    },

    async loadDevice(capsJson) {
      return this._run(async () => {
        const deadline = Date.now() + 12000;
        while (!global.mediasoupClient && Date.now() < deadline) {
          await wait(50);
        }
        if (!global.mediasoupClient) {
          throw new Error("mediasoup-client is not loaded");
        }
        const routerRtpCapabilities = unwrapCaps(capsJson);
        const Device = this._deviceCtor();
        this.device = new Device();
        await this.device.load({ routerRtpCapabilities });
        const caps = this.device.recvRtpCapabilities || this.device.rtpCapabilities;
        if (!caps) throw new Error("Failed to load device RTP capabilities");
        return JSON.stringify(caps);
      });
    },

    _armConnect(transport, emitName, pendingKey) {
      transport.on("connect", ({ dtlsParameters }, callback, errback) => {
        this[pendingKey] = { callback, errback };
        this._emit(emitName, JSON.stringify(dtlsParameters));
        setTimeout(() => {
          if (this[pendingKey] && this[pendingKey].errback === errback) {
            this[pendingKey] = null;
            errback(new Error(emitName + " timed out"));
          }
        }, SIGNAL_TIMEOUT_MS);
      });
    },

    async createSendTransport(paramsJson, iceServersJson) {
      return this._run(async () => {
      if (!this.device) throw new Error("Voice device is not loaded");
      const params = parseJson(paramsJson);
      if (!params.id || !params.iceParameters || !params.dtlsParameters) {
        throw new Error("Invalid producer transport parameters");
      }
      const iceServers = iceFrom(iceServersJson);
      this.sendTransport = this.device.createSendTransport({
        ...params,
        ...(iceServers ? { iceServers } : {}),
      });
      this._armConnect(this.sendTransport, "connectSend", "_pendingConnectSend");
      this.sendTransport.on("produce", ({ kind, rtpParameters, appData }, callback, errback) => {
        this._pendingProduce = { callback, errback };
        const data = appData || {};
        this._emit(
          "produce",
          JSON.stringify({
            kind: data.kind || kind,
            rtpParameters,
            appData: data,
            qualityLayers: data.qualityLayers,
          })
        );
        setTimeout(() => {
          if (this._pendingProduce && this._pendingProduce.errback === errback) {
            this._pendingProduce = null;
            errback(new Error("produce timed out"));
          }
        }, SIGNAL_TIMEOUT_MS);
      });
      this.sendTransport.on("connectionstatechange", (state) => {
        this._sendConnState = String(state || "");
        this._emit("sendState", state);
      });
      return this.sendTransport.id;
      });
    },

    async createRecvTransport(paramsJson, iceServersJson) {
      return this._run(async () => {
      if (!this.device) throw new Error("Voice device is not loaded");
      const params = parseJson(paramsJson);
      if (!params.id || !params.iceParameters || !params.dtlsParameters) {
        throw new Error("Invalid consumer transport parameters");
      }
      const iceServers = iceFrom(iceServersJson);
      this.recvTransport = this.device.createRecvTransport({
        ...params,
        ...(iceServers ? { iceServers } : {}),
      });
      this._armConnect(this.recvTransport, "connectRecv", "_pendingConnectRecv");
      this.recvTransport.on("connectionstatechange", (state) => {
        this._recvConnState = String(state || "");
        this._emit("recvState", state);
      });
      return this.recvTransport.id;
      });
    },

    finishConnectSend(ok) {
      const p = this._pendingConnectSend;
      this._pendingConnectSend = null;
      if (!p) return;
      if (ok) p.callback();
      else p.errback(new Error("connect send failed"));
    },

    finishConnectRecv(ok) {
      const p = this._pendingConnectRecv;
      this._pendingConnectRecv = null;
      if (!p) return;
      if (ok) p.callback();
      else p.errback(new Error("connect recv failed"));
    },

    finishProduce(producerId) {
      const p = this._pendingProduce;
      this._pendingProduce = null;
      if (!p) return;
      if (producerId) p.callback({ id: producerId });
      else p.errback(new Error("produce failed"));
    },

    async restartIce(direction, iceParametersJson) {
      return this._run(async () => {
        const iceParameters = parseJson(iceParametersJson);
        const transport =
          direction === "send" ? this.sendTransport : this.recvTransport;
        if (!transport) throw new Error("transport missing");
        if (!iceParameters || !iceParameters.usernameFragment) {
          throw new Error("Invalid ICE parameters");
        }
        await transport.restartIce({ iceParameters });
        return "";
      });
    },

    _isMobile() {
      if (this.isIos()) return true;
      const ua = navigator.userAgent || "";
      if (/Android/i.test(ua)) return true;
      try {
        if (window.matchMedia && window.matchMedia("(pointer: coarse)").matches) {
          return true;
        }
      } catch (_) {}
      return false;
    },

    _watchMicTrack(stream) {
      if (!stream) return;
      stream.getAudioTracks().forEach((t) => {
        t.onended = () => {
          if (this.localStreams.mic === stream) this._emit("micEnded", "");
        };
      });
    },

    _setMicStream(stream) {
      const prev = this.localStreams.mic;
      if (prev && prev !== stream) {
        prev.getTracks().forEach((t) => {
          try {
            t.stop();
          } catch (_) {}
        });
      }
      this.localStreams.mic = stream;
      this._markSpeechTrack(stream);
      this._watchMicTrack(stream);
      this._startMeter("local", stream);
    },

    _markSpeechTrack(stream) {
      if (!stream) return;
      stream.getAudioTracks().forEach((t) => {
        try {
          t.contentHint = "speech";
        } catch (_) {}
      });
    },

    _audioConstraints(deviceId, extra) {
      const opts = extra && typeof extra === "object" ? extra : {};
      const echoOn = opts.echoCancellation !== false;
      const audio = {
        echoCancellation: echoOn,
        autoGainControl: opts.autoGainControl !== false,
        noiseSuppression: !!opts.noiseSuppression || (this._isMobile() && echoOn),
      };
      if (deviceId) audio.deviceId = { exact: deviceId };
      return audio;
    },

    async getUserMedia(audio, video, deviceId, constraintsJson) {
      return this._run(async () => {
      const extra = parseJson(constraintsJson);
      const constraints = {};
      if (audio) constraints.audio = this._audioConstraints(deviceId, extra);
      if (video) {
        constraints.video = { width: { ideal: 1280 }, height: { ideal: 720 } };
        const cam = extra.videoDeviceId || this._cameraDeviceId;
        if (cam) constraints.video.deviceId = { exact: cam };
      }
      try {
        const stream = await navigator.mediaDevices.getUserMedia(constraints);
        if (audio) {
          this._setMicStream(stream);
        }
        if (video) {
          this.localStreams.cam = stream;
          this._rebindMedia("local:video");
        }
        return stream.id;
      } catch (err) {
        if (deviceId && audio) {
          const stream = await navigator.mediaDevices.getUserMedia({
            audio: this._audioConstraints(null, extra),
          });
          this._setMicStream(stream);
          return stream.id;
        }
        throw err;
      }
      });
    },

    async startMicTest(deviceId, constraintsJson) {
      return this._run(async () => {
        this.stopMicTest();
        const extra = parseJson(constraintsJson);
        const stream = await navigator.mediaDevices.getUserMedia({
          audio: this._audioConstraints(deviceId, extra),
        });
        this.localStreams.micTest = stream;
        this._markSpeechTrack(stream);
        this._startMeter("test", stream);
        return stream.id;
      });
    },

    stopMicTest() {
      this._stopMeter("test");
      const stream = this.localStreams.micTest;
      if (stream) {
        stream.getTracks().forEach((t) => t.stop());
        this.localStreams.micTest = null;
      }
    },

    micTestLevel() {
      const m = this._meters.test;
      return m && typeof m.level === "number" ? m.level : 0;
    },

    async startVideoPreview(deviceId) {
      return this._run(async () => {
        this.stopVideoPreview();
        const video = { width: { ideal: 1280 }, height: { ideal: 720 } };
        const cam = deviceId || this._cameraDeviceId;
        if (cam) video.deviceId = { exact: cam };
        this.localStreams.preview = await navigator.mediaDevices.getUserMedia({
          video,
        });
        this._rebindMedia("preview:video");
        return "preview:video";
      });
    },

    stopVideoPreview() {
      const stream = this.localStreams.preview;
      if (stream) {
        stream.getTracks().forEach((t) => t.stop());
        this.localStreams.preview = null;
      }
    },

    setOutputDevice(deviceId) {
      this._outputDevice = deviceId || "";
      this._applyCtxSink();
      const nodes = document.querySelectorAll("audio, video");
      nodes.forEach((el) => this._applySink(el));
      if (global.KurierSounds && typeof global.KurierSounds.setOutputDevice === "function") {
        global.KurierSounds.setOutputDevice(this._outputDevice);
      }
    },

    setCameraDevice(deviceId) {
      this._cameraDeviceId = deviceId || "";
    },

    _applySink(el) {
      if (!el || typeof el.setSinkId !== "function") return;
      el.setSinkId(this._outputDevice || "").catch(() => {});
    },

    _vp8Codec() {
      const codecs =
        this.device &&
        this.device.rtpCapabilities &&
        this.device.rtpCapabilities.codecs;
      if (!codecs || !codecs.length) return undefined;
      return codecs.find((c) => String(c.mimeType || "").toLowerCase() === "video/vp8");
    },

    _watchScreenTrack(stream) {
      if (!stream) return;
      stream.getVideoTracks().forEach((t) => {
        try {
          t.contentHint = "detail";
        } catch (_) {}
        t.onended = () => {
          if (this.localStreams.screen === stream) this._emit("screenEnded", "");
        };
      });
    },

    async getDisplayMedia(withAudio) {
      return this._run(async () => {
      const video = {
        width: { ideal: 1920 },
        height: { ideal: 1080 },
        frameRate: { ideal: 30 },
      };
      const audio = withAudio
        ? {
            echoCancellation: false,
            noiseSuppression: false,
            autoGainControl: false,
          }
        : false;
      const preferred = {
        video,
        audio,
        selfBrowserSurface: "exclude",
        preferCurrentTab: false,
        surfaceSwitching: "include",
        monitorTypeSurfaces: "include",
      };
      let stream;
      try {
        stream = await navigator.mediaDevices.getDisplayMedia(preferred);
      } catch (err) {
        if (isUserMediaAbort(err)) throw err;
        stream = await navigator.mediaDevices.getDisplayMedia({ video, audio });
      }
      this.localStreams.screen = stream;
      this._watchScreenTrack(stream);
      this._rebindMedia("local:screen");
      return stream.id;
      });
    },

    async produceKind(kind, simulcastEnabled) {
      return this._run(async () => {
      let track;
      if (kind === "audio") {
        track = this.localStreams.mic && this.localStreams.mic.getAudioTracks()[0];
      } else if (kind === "video") {
        if (!this.localStreams.cam) {
          const video = { width: { ideal: 1280 }, height: { ideal: 720 } };
          if (this._cameraDeviceId) video.deviceId = { exact: this._cameraDeviceId };
          this.localStreams.cam = await navigator.mediaDevices.getUserMedia({
            video,
          });
        }
        track = this.localStreams.cam.getVideoTracks()[0];
      } else if (kind === "screen") {
        track = this.localStreams.screen && this.localStreams.screen.getVideoTracks()[0];
      } else if (kind === "screen_audio") {
        track = this.localStreams.screen && this.localStreams.screen.getAudioTracks()[0];
      }
      if (!track) throw new Error("no local track for " + kind);
      if (!this.sendTransport) throw new Error("send transport missing");
      if (kind === "screen") {
        try {
          track.contentHint = "detail";
        } catch (_) {}
      }
      const existing = this.producers[kind];
      if (existing) {
        try {
          existing.close();
        } catch (_) {}
        delete this.producers[kind];
      }
      const vp8 = this._vp8Codec();
      const options = {
        track,
        stopTracks: false,
        appData: { kind },
      };
      if (kind === "screen") {
        options.codecOptions = screenCodecOptions(SCREEN_MAX_BITRATE_KBPS);
        if (vp8) options.codec = vp8;
      }
      let producer;
      const useSimulcast = flagOn(simulcastEnabled) && vp8 && (kind === "screen" || kind === "video");
      if (useSimulcast) {
        const encodings =
          kind === "screen"
            ? getScreenShareSimulcastEncodings(SCREEN_MAX_BITRATE_KBPS * 1000)
            : getSimulcastEncodings(SIMULCAST_WEBCAM_MAX_BITRATE);
        const qualityLayers = getSimulcastQualityLayers(encodings);
        try {
          producer = await this.sendTransport.produce({
            ...options,
            codec: vp8,
            encodings,
            appData: { kind, qualityLayers },
          });
        } catch (_) {
          producer = await this.sendTransport.produce(options);
        }
      } else {
        producer = await this.sendTransport.produce(options);
      }
      this.producers[kind] = producer;
      if (kind === "audio" && this.localStreams.mic) {
        this._startMeter("local", this.localStreams.mic);
      }
      if (kind === "video") this._rebindMedia("local:video");
      if (kind === "screen") this._rebindMedia("local:screen");
      return producer.id;
      });
    },

    async consume(consumerJson) {
      return this._run(async () => {
      const info = parseJson(consumerJson);
      if (!this.recvTransport) throw new Error("recv transport missing");
      const consumer = await this.recvTransport.consume({
        id: info.consumerId,
        producerId: info.producerId,
        kind: info.rtpKind || (info.consumerKind && String(info.consumerKind).includes("audio") ? "audio" : "video"),
        rtpParameters: info.consumerRtpParameters,
      });
      try {
        await consumer.resume();
      } catch (_) {}
      const key = info.remoteId + ":" + info.consumerKind;
      this.consumers[key] = consumer;
      const stream = new MediaStream([consumer.track]);
      if (consumer.track.kind === "audio") {
        this._attachStream(key, stream, "audio");
        this._startMeter(key, stream);
        this._ensureAudioCtx();
        const reattach = () => {
          if (this.consumers[key] !== consumer) return;
          if (!this._usesHtmlAudioPlayback()) {
            this._attachVoiceGraph(key, stream);
          }
          this._ensureAudioCtx();
          this.resumePlayback();
        };
        consumer.track.addEventListener("unmute", reattach);
        if (!consumer.track.muted) reattach();
      } else {
        this._rebindMedia(key);
      }
      return key;
      });
    },

    _mediaTrackForKey(key) {
      if (key === "local:video") {
        return this.localStreams.cam && this.localStreams.cam.getVideoTracks()[0];
      }
      if (key === "preview:video") {
        return this.localStreams.preview && this.localStreams.preview.getVideoTracks()[0];
      }
      if (key === "local:screen") {
        return this.localStreams.screen && this.localStreams.screen.getVideoTracks()[0];
      }
      const consumer = this.consumers[key];
      return consumer && consumer.track;
    },

    _rebindMedia(key) {
      const el = this._boundMedia[key];
      if (el) this.bindMediaElement(key, el);
    },

    bindMediaElement(key, el) {
      if (!el) return;
      this._boundMedia[key] = el;
      if (this._bindTimers[key]) {
        clearInterval(this._bindTimers[key]);
        delete this._bindTimers[key];
      }
      el.id = "kurier-media-" + key;
      el.autoplay = true;
      el.playsInline = true;
      el.muted = true;
      el.setAttribute("playsinline", "true");
      el.setAttribute("webkit-playsinline", "true");
      el.setAttribute("muted", "true");
      const apply = () => {
        const bound = this._boundMedia[key];
        if (!bound) return true;
        const track = this._mediaTrackForKey(key);
        if (!track) return false;
        bound.srcObject = new MediaStream([track]);
        this._playMedia(bound);
        return true;
      };
      if (apply()) return;
      let n = 0;
      this._bindTimers[key] = setInterval(() => {
        if (apply() || ++n > 80) {
          clearInterval(this._bindTimers[key]);
          delete this._bindTimers[key];
        }
      }, 50);
    },

    _attachStream(key, stream, kind) {
      let el = document.getElementById("kurier-media-" + key);
      const htmlAudio = kind === "audio" && this._usesHtmlAudioPlayback();
      if (!el) {
        el = document.createElement(kind === "audio" ? "audio" : "video");
        el.id = "kurier-media-" + key;
        el.autoplay = true;
        el.playsInline = true;
        el.setAttribute("playsinline", "true");
        el.setAttribute("webkit-playsinline", "true");
        if (kind === "audio") {
          this._styleAudioElement(el);
        } else {
          el.style.cssText =
            "width:100%;height:100%;object-fit:cover;background:#000;border-radius:8px";
        }
        this._audioHost(kind).appendChild(el);
      } else if (kind === "audio" && htmlAudio && el.parentNode !== document.body) {
        this._styleAudioElement(el);
        document.body.appendChild(el);
      }
      el.srcObject = stream;
      if (kind === "audio") {
        this._stopDummyTracks(key);
        if (!htmlAudio) {
          const dummy = stream.getAudioTracks().map((t) => t.clone());
          this._dummyTracks[key] = dummy;
          el.srcObject = dummy.length ? new MediaStream(dummy) : stream;
        }
      }
      this._applySink(el);
      const playbackStream = this._isPlaybackKey(key);
      const usedGraph =
        kind === "audio" && !htmlAudio ? this._attachVoiceGraph(key, stream) : false;
      if (usedGraph) {
        el.muted = false;
        el.volume = 0;
      } else if (kind === "audio") {
        el.muted = playbackStream || this._volumes[key] === 0;
        el.volume = playbackStream
          ? 0
          : typeof this._volumes[key] === "number"
            ? this._volumes[key]
            : 1;
      } else {
        el.muted = true;
      }
      this._playMedia(el);
      el.addEventListener("canplay", () => this._playMedia(el), { once: true });
    },

    setConsumerVolume(key, volume) {
      const v = Math.max(0, Math.min(1, volume));
      this._volumes[key] = v;
      const graph = this._gains[key];
      if (graph && graph.gain) {
        graph.gain.gain.value = v;
      }
      const el = document.getElementById("kurier-media-" + key);
      if (!el) return;
      if (graph && !this._usesHtmlAudioPlayback()) {
        el.volume = 0;
        el.muted = false;
      } else {
        el.volume = v;
        el.muted = v === 0;
      }
    },

    closeProducer(kind) {
      const p = this.producers[kind];
      if (p) {
        try {
          p.close();
        } catch (_) {}
        delete this.producers[kind];
      }
      if (kind === "video" && this.localStreams.cam) {
        this.localStreams.cam.getTracks().forEach((t) => t.stop());
        this.localStreams.cam = null;
      }
      if ((kind === "screen" || kind === "screen_audio") && this.localStreams.screen) {
        this.localStreams.screen.getTracks().forEach((t) => t.stop());
        this.localStreams.screen = null;
      }
    },

    pauseMic(paused) {
      const p = this.producers.audio;
      if (p) {
        if (paused) p.pause();
        else p.resume();
      }
      const stream = this.localStreams.mic;
      if (stream && !this.isIos()) {
        stream.getAudioTracks().forEach((t) => (t.enabled = !paused));
      }
      this._localMeterPaused = !!paused;
      const m = this._meters.local;
      if (!m) return;
      if (paused) {
        if (m.intensity !== 0) {
          m.intensity = 0;
          this._emitSpeaking("local", 0, 0);
        }
      } else {
        m.intensity = -1;
      }
    },

    async getMediaStats(key) {
      return this._run(async () => {
        const now = performance.now();
        const prev = this._statsPrev[key] || {};
        let fps = 0;
        let bytes = 0;
        let frames;

        const el = document.getElementById("kurier-media-" + key);
        if (el) {
          if (typeof el.getVideoPlaybackQuality === "function") {
            const q = el.getVideoPlaybackQuality();
            frames = q && q.totalVideoFrames;
          } else if (el.webkitDecodedFrameCount != null) {
            frames = el.webkitDecodedFrameCount;
          }
        }

        let statsSource = this.consumers[key];
        if (!statsSource && key === "local:screen") {
          statsSource = this.producers.screen;
        }
        if (!statsSource && this.producers[key]) {
          statsSource = this.producers[key];
        }

        if (statsSource && typeof statsSource.getStats === "function") {
          const report = await statsSource.getStats();
          report.forEach((s) => {
            const video =
              s.kind === "video" || s.mediaType === "video" || s.framesPerSecond != null;
            if (s.type === "inbound-rtp" && video) {
              if (typeof s.bytesReceived === "number") bytes = s.bytesReceived;
              if (typeof s.framesPerSecond === "number") fps = s.framesPerSecond;
            }
            if (s.type === "outbound-rtp" && video) {
              if (typeof s.bytesSent === "number") bytes = s.bytesSent;
              if (typeof s.framesPerSecond === "number") fps = s.framesPerSecond;
            }
          });
        }

        const dt = (now - (prev.t || 0)) / 1000;
        if (dt > 0 && prev.t) {
          if (typeof frames === "number" && typeof prev.frames === "number") {
            const fromFrames = (frames - prev.frames) / dt;
            if (fromFrames >= 0) fps = fromFrames;
          }
        }
        let bytesPerSec = 0;
        if (dt > 0 && prev.t && typeof prev.bytes === "number") {
          const delta = (bytes - prev.bytes) / dt;
          if (delta >= 0) bytesPerSec = delta;
        }

        this._statsPrev[key] = {
          t: now,
          frames: typeof frames === "number" ? frames : prev.frames,
          bytes: bytes,
        };

        return JSON.stringify({
          fps: Math.max(0, Math.round(fps)),
          bytesPerSec: Math.max(0, Math.round(bytesPerSec)),
        });
      });
    },

    _resetTransportStats() {
      this._transportPrev = { producer: null, consumer: null, screen: null };
      this._transportTotals = { sent: 0, received: 0 };
    },

    _parseTransportStats(statsReport, isProducer) {
      let bytesReceived = 0;
      let bytesSent = 0;
      let packetsReceived = 0;
      let packetsSent = 0;
      let packetsLost = 0;
      let rtt = 0;
      let jitter = 0;
      if (statsReport && typeof statsReport.forEach === "function") {
        statsReport.forEach((stat) => {
          if (stat.type === "outbound-rtp" && isProducer) {
            bytesSent += stat.bytesSent || 0;
            packetsSent += stat.packetsSent || 0;
          } else if (stat.type === "inbound-rtp" && !isProducer) {
            bytesReceived += stat.bytesReceived || 0;
            packetsReceived += stat.packetsReceived || 0;
            packetsLost += stat.packetsLost || 0;
            jitter += stat.jitter || 0;
          } else if (stat.type === "candidate-pair" && stat.state === "succeeded") {
            rtt = (stat.currentRoundTripTime || 0) * 1000;
          }
        });
      }
      return {
        bytesReceived,
        bytesSent,
        packetsReceived,
        packetsSent,
        packetsLost,
        rtt,
        jitter,
        timestamp: Date.now(),
      };
    },

    _parseScreenShareStats(statsReport) {
      let codec = "";
      let encoderImplementation = "";
      let width = 0;
      let height = 0;
      let frameRate = 0;
      let packetsSent = 0;
      let bytesSent = 0;
      let keyFramesEncoded = 0;
      let framesEncoded = 0;
      let qualityLimitationReason = "none";
      const codecMap = new Map();
      const layers = [];
      if (!statsReport || typeof statsReport.forEach !== "function") return null;
      statsReport.forEach((stat) => {
        if (stat.type === "codec") codecMap.set(stat.id, stat.mimeType || "");
      });
      statsReport.forEach((stat) => {
        if (stat.type !== "outbound-rtp" || stat.kind !== "video") return;
        const layerBytesSent = stat.bytesSent || 0;
        const layerPacketsSent = stat.packetsSent || 0;
        const layerFrameRate = stat.framesPerSecond || 0;
        const layerWidth = stat.frameWidth || 0;
        const layerHeight = stat.frameHeight || 0;
        const layerKeyFramesEncoded = stat.keyFramesEncoded || 0;
        const layerFramesEncoded = stat.framesEncoded || 0;
        const layerQualityLimitationReason = stat.qualityLimitationReason || "none";
        const layerCodec =
          stat.codecId && codecMap.has(stat.codecId) ? codecMap.get(stat.codecId) : "";
        bytesSent += layerBytesSent;
        packetsSent += layerPacketsSent;
        frameRate = Math.max(frameRate, layerFrameRate);
        width = Math.max(width, layerWidth);
        height = Math.max(height, layerHeight);
        keyFramesEncoded += layerKeyFramesEncoded;
        framesEncoded += layerFramesEncoded;
        if (layerQualityLimitationReason !== "none") {
          qualityLimitationReason = layerQualityLimitationReason;
        }
        if (!encoderImplementation && stat.encoderImplementation) {
          encoderImplementation = stat.encoderImplementation;
        }
        if (stat.codecId && codecMap.has(stat.codecId)) {
          codec = codecMap.get(stat.codecId);
        }
        layers.push({
          id: stat.id,
          rid: stat.rid || stat.id,
          codec: layerCodec,
          width: layerWidth,
          height: layerHeight,
          frameRate: layerFrameRate,
          packetsSent: layerPacketsSent,
          bytesSent: layerBytesSent,
          keyFramesEncoded: layerKeyFramesEncoded,
          framesEncoded: layerFramesEncoded,
          qualityLimitationReason: layerQualityLimitationReason,
        });
      });
      if (!width && !height && !bytesSent) return null;
      return {
        codec,
        encoderImplementation,
        width,
        height,
        frameRate,
        packetsSent,
        bytesSent,
        keyFramesEncoded,
        framesEncoded,
        qualityLimitationReason,
        simulcast: layers.length > 1,
        layers,
        timestamp: Date.now(),
      };
    },

    async getTransportStats() {
      return this._run(async () => {
        let producerStats = null;
        let consumerStats = null;
        if (this.sendTransport && typeof this.sendTransport.getStats === "function") {
          try {
            producerStats = this._parseTransportStats(
              await this.sendTransport.getStats(),
              true
            );
          } catch (_) {
            producerStats = null;
          }
        }
        if (this.recvTransport && typeof this.recvTransport.getStats === "function") {
          try {
            consumerStats = this._parseTransportStats(
              await this.recvTransport.getStats(),
              false
            );
          } catch (_) {
            consumerStats = null;
          }
        }

        let screenShare = null;
        const screenProducer = this.producers.screen;
        if (screenProducer && !screenProducer.closed && typeof screenProducer.getStats === "function") {
          try {
            const parsed = this._parseScreenShareStats(await screenProducer.getStats());
            if (parsed) {
              let bitrate = 0;
              const prev = this._transportPrev.screen;
              const layerBytesSent = {};
              const layers = parsed.layers.map((layer) => {
                let layerBitrate = 0;
                if (prev) {
                  const previousBytes = prev.layerBytesSent[layer.id];
                  const timeDelta = (parsed.timestamp - prev.timestamp) / 1000;
                  if (
                    previousBytes != null &&
                    layer.bytesSent > previousBytes &&
                    timeDelta > 0
                  ) {
                    layerBitrate = (layer.bytesSent - previousBytes) / timeDelta;
                  }
                }
                layerBytesSent[layer.id] = layer.bytesSent;
                return { ...layer, bitrate: layerBitrate };
              });
              if (prev && parsed.bytesSent > prev.bytesSent) {
                const timeDelta = (parsed.timestamp - prev.timestamp) / 1000;
                if (timeDelta > 0) bitrate = (parsed.bytesSent - prev.bytesSent) / timeDelta;
              }
              this._transportPrev.screen = {
                bytesSent: parsed.bytesSent,
                layerBytesSent,
                timestamp: parsed.timestamp,
              };
              screenShare = { ...parsed, layers, bitrate };
            }
          } catch (_) {
            this._transportPrev.screen = null;
          }
        } else {
          this._transportPrev.screen = null;
        }

        const prevProducer = this._transportPrev.producer;
        const prevConsumer = this._transportPrev.consumer;
        const bytesReceivedDelta =
          consumerStats && prevConsumer
            ? Math.max(0, consumerStats.bytesReceived - prevConsumer.bytesReceived)
            : 0;
        const bytesSentDelta =
          producerStats && prevProducer
            ? Math.max(0, producerStats.bytesSent - prevProducer.bytesSent)
            : 0;
        let currentBitrateSent = 0;
        let currentBitrateReceived = 0;
        if (producerStats && prevProducer && bytesSentDelta > 0) {
          const dt = (producerStats.timestamp - prevProducer.timestamp) / 1000;
          if (dt > 0) currentBitrateSent = bytesSentDelta / dt;
        }
        if (consumerStats && prevConsumer && bytesReceivedDelta > 0) {
          const dt = (consumerStats.timestamp - prevConsumer.timestamp) / 1000;
          if (dt > 0) currentBitrateReceived = bytesReceivedDelta / dt;
        }
        this._transportTotals.sent += bytesSentDelta;
        this._transportTotals.received += bytesReceivedDelta;
        this._transportPrev.producer = producerStats;
        this._transportPrev.consumer = consumerStats;
        return JSON.stringify({
          producer: producerStats,
          consumer: consumerStats,
          screenShare,
          totalBytesSent: this._transportTotals.sent,
          totalBytesReceived: this._transportTotals.received,
          currentBitrateSent,
          currentBitrateReceived,
        });
      });
    },

    consumerTrackLive(key) {
      const c = this.consumers[key];
      return !!(
        c &&
        c.track &&
        c.track.readyState === "live" &&
        !c.track.muted
      );
    },

    audioProducerLive() {
      const p = this.producers.audio;
      if (!p || p.closed) return false;
      const stream = this.localStreams.mic;
      const track = (stream && stream.getAudioTracks()[0]) || p.track;
      return !!(track && track.readyState === "live");
    },

    _playMedia(el) {
      if (!el || typeof el.play !== "function") return;
      const attempt = (n) => {
        const p = el.play();
        if (p && typeof p.catch === "function") {
          p.catch((err) => {
            console.warn("media play failed", el.id, err);
            if (n < 8) setTimeout(() => attempt(n + 1), 250);
          });
        }
      };
      attempt(0);
    },

    closeConsumer(key) {
      this._stopMeter(key);
      this._detachVoiceGraph(key);
      this._stopDummyTracks(key);
      delete this._volumes[key];
      delete this._statsPrev[key];
      const c = this.consumers[key];
      if (c) {
        try {
          c.close();
        } catch (_) {}
        delete this.consumers[key];
      }
      const el = document.getElementById("kurier-media-" + key);
      if (el) {
        try {
          el.pause();
        } catch (_) {}
        el.srcObject = null;
        el.remove();
      }
    },

    closeAll() {
      this._wakeLockWanted = false;
      this._releaseWakeLock();
      this._stopResumeLoop();
      this._stopAllMeters();
      Object.keys(this.producers).forEach((k) => this.closeProducer(k));
      Object.keys(this.consumers).forEach((k) => this.closeConsumer(k));
      this._stopKeepAlive();
      this._gains = {};
      this._volumes = {};
      this._dummyTracks = {};
      ["mic", "cam", "screen", "micTest", "preview"].forEach((name) => {
        const s = this.localStreams[name];
        if (s) s.getTracks().forEach((t) => t.stop());
        this.localStreams[name] = null;
      });
      try {
        this.sendTransport && this.sendTransport.close();
      } catch (_) {}
      try {
        this.recvTransport && this.recvTransport.close();
      } catch (_) {}
      this.sendTransport = null;
      this.recvTransport = null;
      this._sendConnState = "";
      this._recvConnState = "";
      this.device = null;
      this._pendingConnectSend = null;
      this._pendingConnectRecv = null;
      this._pendingProduce = null;
      this._statsPrev = {};
      Object.keys(this._bindTimers).forEach((key) => clearInterval(this._bindTimers[key]));
      this._bindTimers = {};
      this._boundMedia = {};
      this._resetTransportStats();
    },

    async enumerate() {
      return this._run(async () => {
      const devices = await navigator.mediaDevices.enumerateDevices();
      return JSON.stringify(
        devices.map((d) => ({
          deviceId: d.deviceId,
          kind: d.kind,
          label: d.label,
        }))
      );
      });
    },

    setWakeLock(wanted) {
      this._wakeLockWanted = !!wanted;
      if (!wanted) {
        this._releaseWakeLock();
        return;
      }
      this._acquireWakeLock();
    },

    async _acquireWakeLock() {
      if (!this._wakeLockWanted || this._wakeLock) return;
      const api = navigator.wakeLock;
      if (!api || typeof api.request !== "function") return;
      try {
        const sentinel = await api.request("screen");
        if (!this._wakeLockWanted) {
          try {
            sentinel.release();
          } catch (_) {}
          return;
        }
        this._wakeLock = sentinel;
        sentinel.addEventListener("release", () => {
          if (this._wakeLock === sentinel) this._wakeLock = null;
        });
      } catch (_) {}
    },

    _releaseWakeLock() {
      const lock = this._wakeLock;
      this._wakeLock = null;
      try {
        if (lock) lock.release();
      } catch (_) {}
    },

    canShareScreen() {
      return !!(navigator.mediaDevices && navigator.mediaDevices.getDisplayMedia);
    },

    isIos() {
      return (
        /iPad|iPhone|iPod/.test(navigator.userAgent) ||
        (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
      );
    },

    canSetOutputDevice() {
      try {
        const Ctx = window.AudioContext || window.webkitAudioContext;
        const ctxProto = Ctx && Ctx.prototype;
        const mediaProto = window.HTMLMediaElement && HTMLMediaElement.prototype;
        return !!(
          (ctxProto && typeof ctxProto.setSinkId === "function") ||
          (mediaProto && typeof mediaProto.setSinkId === "function")
        );
      } catch (_) {
        return false;
      }
    },

    _thawFromGesture() {
      try {
        const ctx = this._ensureAudioCtx();
        if (ctx && ctx.state !== "running") ctx.resume().catch(() => {});
      } catch (_) {}
      if (this.sendTransport || this.recvTransport) {
        try {
          this._startKeepAlive();
        } catch (_) {}
      }
      if (global.KurierSounds && global.KurierSounds.unlock) {
        try {
          global.KurierSounds.unlock();
        } catch (_) {}
      }
      this.resumePlayback();
    },

    async unlockAudio() {
      return this._run(async () => {
      this._thawFromGesture();
      try {
        const ctx = this._audioCtx;
        if (ctx && ctx.state !== "running") await ctx.resume();
      } catch (_) {}
      if (global.KurierSounds && global.KurierSounds.unlock) {
        try {
          await global.KurierSounds.unlock();
        } catch (_) {}
      }
      this.resumePlayback();
      return "";
      });
    },

    playPing() {
      if (global.KurierSounds && global.KurierSounds.playSound) {
        global.KurierSounds.playSound("message_received");
      }
    },

    notify(title, body) {
      if (!("Notification" in window) || Notification.permission !== "granted") return;
      try {
        new Notification(title, { body, icon: "/icons/Icon-192.png" });
      } catch (_) {}
    },

    async requestNotifications() {
      return this._run(async () => {
        if (!("Notification" in window)) return "unsupported";
        return Notification.requestPermission();
      });
    },

    notificationPermission() {
      if (!("Notification" in window)) return "unsupported";
      return Notification.permission;
    },

    copyText(text) {
      return this._run(async () => {
        await navigator.clipboard.writeText(text);
        return "";
      });
    },

    _reattachVoiceGraphs(force) {
      if (this._usesHtmlAudioPlayback()) return;
      Object.keys(this.consumers).forEach((key) => {
        const c = this.consumers[key];
        if (!c || !c.track || c.track.kind !== "audio") return;
        if (!force && this._gains[key]) return;
        this._attachVoiceGraph(key, new MediaStream([c.track]));
      });
    },

    _startResumeLoop() {
      if (this._resumeTimer) return;
      this._resumeTimer = setInterval(() => {
        if (!this.sendTransport && !this.recvTransport) {
          this._stopResumeLoop();
          return;
        }
        this.resumePlayback();
      }, 5000);
    },

    _stopResumeLoop() {
      if (!this._resumeTimer) return;
      clearInterval(this._resumeTimer);
      this._resumeTimer = 0;
    },

    _elementPlaying(el) {
      return !!(el && el.srcObject && !el.paused && !el.ended && el.readyState > 0);
    },

    _playbackSnapshot() {
      const liveAudioKeys = [];
      const graphKeys = [];
      const playingKeys = [];
      Object.keys(this.consumers).forEach((key) => {
        const c = this.consumers[key];
        if (!c || !c.track || c.track.kind !== "audio") return;
        if (c.track.readyState === "live") liveAudioKeys.push(key);
        if (this._gains[key]) graphKeys.push(key);
        const el = document.getElementById("kurier-media-" + key);
        if (this._elementPlaying(el)) playingKeys.push(key);
      });
      return {
        ctxRunning: !!(this._audioCtx && this._audioCtx.state === "running"),
        keepAlive: !!(this._keepAlive && this._keepAlive.osc),
        recvState: this._recvConnState || "",
        sendState: this._sendConnState || "",
        liveAudioKeys: liveAudioKeys,
        graphKeys: graphKeys,
        playingKeys: playingKeys,
      };
    },

    async playbackHealthy() {
      return this._run(async () => JSON.stringify(this._playbackSnapshot()));
    },

    resumePlayback() {
      if (this._resumingPlayback) return;
      this._resumingPlayback = true;
      try {
        if (this._audioCtx) this._ensureAudioCtx();
        if (this.sendTransport || this.recvTransport || this._keepAlive) {
          this._startKeepAlive();
          this._startResumeLoop();
        }
        this._reattachVoiceGraphs(false);
        document.querySelectorAll('[id^="kurier-media-"]').forEach((el) => {
          this._playMedia(el);
        });
      } finally {
        this._resumingPlayback = false;
      }
    },
  };

  global.KurierMediasoup = KurierMediasoup;

  ["touchstart", "pointerdown", "click"].forEach((type) => {
    document.addEventListener(
      type,
      () => KurierMediasoup._thawFromGesture(),
      { capture: true, passive: true }
    );
  });

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      KurierMediasoup.resumePlayback();
      KurierMediasoup._acquireWakeLock();
      KurierMediasoup._emit("visibility", "visible");
      if (global.KurierSounds && global.KurierSounds.unlock) {
        global.KurierSounds.unlock();
      }
    }
  });
})(window);
