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
      if (!this._audioCtx) this._audioCtx = new Ctx();
      if (this._audioCtx.state === "suspended") {
        this._audioCtx.resume().catch(() => {});
      }
      return this._audioCtx;
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
        this._emit(
          "produce",
          JSON.stringify({
            kind: (appData && appData.kind) || kind,
            rtpParameters,
            appData,
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
        if (video) this.localStreams.cam = stream;
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
      const nodes = document.querySelectorAll("audio, video");
      nodes.forEach((el) => this._applySink(el));
    },

    setCameraDevice(deviceId) {
      this._cameraDeviceId = deviceId || "";
    },

    _applySink(el) {
      if (!el || typeof el.setSinkId !== "function" || !this._outputDevice) return;
      el.setSinkId(this._outputDevice).catch(() => {});
    },

    async getDisplayMedia(withAudio) {
      return this._run(async () => {
      const stream = await navigator.mediaDevices.getDisplayMedia({
        video: true,
        audio: !!withAudio,
      });
      this.localStreams.screen = stream;
      return stream.id;
      });
    },

    async produceKind(kind) {
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
      const existing = this.producers[kind];
      if (existing) {
        try {
          existing.close();
        } catch (_) {}
        delete this.producers[kind];
      }
      const producer = await this.sendTransport.produce({
        track,
        stopTracks: false,
        appData: { kind },
      });
      this.producers[kind] = producer;
      if (kind === "audio" && this.localStreams.mic) {
        this._startMeter("local", this.localStreams.mic);
      }
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
      const key = info.remoteId + ":" + info.consumerKind;
      this.consumers[key] = consumer;
      const stream = new MediaStream([consumer.track]);
      if (consumer.track.kind === "audio") {
        this._attachStream(key, stream, "audio");
        this._startMeter(key, stream);
      }
      return key;
      });
    },

    bindMediaElement(key, el) {
      if (!el) return;
      el.id = "kurier-media-" + key;
      el.autoplay = true;
      el.playsInline = true;
      el.muted = true;
      el.setAttribute("playsinline", "true");
      el.setAttribute("muted", "true");
      const apply = () => {
        let track;
        if (key === "local:video") {
          track = this.localStreams.cam && this.localStreams.cam.getVideoTracks()[0];
        } else if (key === "preview:video") {
          track = this.localStreams.preview && this.localStreams.preview.getVideoTracks()[0];
        } else if (key === "local:screen") {
          track = this.localStreams.screen && this.localStreams.screen.getVideoTracks()[0];
        } else {
          const consumer = this.consumers[key];
          track = consumer && consumer.track;
        }
        if (!track) return false;
        el.srcObject = new MediaStream([track]);
        this._playMedia(el);
        return true;
      };
      if (apply()) return;
      let n = 0;
      const t = setInterval(() => {
        if (apply() || ++n > 40) clearInterval(t);
      }, 50);
    },

    _attachStream(key, stream, kind) {
      let el = document.getElementById("kurier-media-" + key);
      if (!el) {
        el = document.createElement(kind === "audio" ? "audio" : "video");
        el.id = "kurier-media-" + key;
        el.autoplay = true;
        el.playsInline = true;
        el.setAttribute("playsinline", "true");
        if (kind === "audio") {
          el.style.cssText = "position:absolute;width:1px;height:1px;opacity:0;pointer-events:none";
        } else {
          el.style.cssText =
            "width:100%;height:100%;object-fit:cover;background:#000;border-radius:8px";
        }
        const host = document.getElementById("kurier-media-host") || document.body;
        host.appendChild(el);
      }
      el.srcObject = stream;
      this._applySink(el);
      const playbackStream =
        String(key).endsWith(":screen_audio") ||
        String(key).endsWith(":external_audio");
      el.muted = playbackStream;
      if (playbackStream) el.volume = 0;
      this._playMedia(el);
      el.addEventListener("canplay", () => this._playMedia(el), { once: true });
    },

    setConsumerVolume(key, volume) {
      const el = document.getElementById("kurier-media-" + key);
      if (!el) return;
      const v = Math.max(0, Math.min(1, volume));
      el.volume = v;
      el.muted = v === 0;
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
      if (stream) stream.getAudioTracks().forEach((t) => (t.enabled = !paused));
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
      return !!(c && c.track && c.track.readyState === "live");
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
          p.catch(() => {
            if (n < 4) setTimeout(() => attempt(n + 1), 200);
          });
        }
      };
      attempt(0);
    },

    closeConsumer(key) {
      this._stopMeter(key);
      delete this._statsPrev[key];
      const c = this.consumers[key];
      if (c) {
        try {
          c.close();
        } catch (_) {}
        delete this.consumers[key];
      }
      const el = document.getElementById("kurier-media-" + key);
      if (el) el.remove();
    },

    closeAll() {
      this._stopAllMeters();
      Object.keys(this.producers).forEach((k) => this.closeProducer(k));
      Object.keys(this.consumers).forEach((k) => this.closeConsumer(k));
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
      this.device = null;
      this._pendingConnectSend = null;
      this._pendingConnectRecv = null;
      this._pendingProduce = null;
      this._statsPrev = {};
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

    canShareScreen() {
      return !!(navigator.mediaDevices && navigator.mediaDevices.getDisplayMedia);
    },

    isIos() {
      return (
        /iPad|iPhone|iPod/.test(navigator.userAgent) ||
        (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
      );
    },

    async unlockAudio() {
      return this._run(async () => {
      try {
        const Ctx = window.AudioContext || window.webkitAudioContext;
        if (!this._audioCtx) this._audioCtx = new Ctx();
        if (this._audioCtx.state === "suspended") await this._audioCtx.resume();
        const osc = this._audioCtx.createOscillator();
        const gain = this._audioCtx.createGain();
        gain.gain.value = 0.0001;
        osc.connect(gain);
        gain.connect(this._audioCtx.destination);
        osc.start();
        osc.stop(this._audioCtx.currentTime + 0.05);
      } catch (_) {}
      this.resumePlayback();
      return "";
      });
    },

    playPing() {
      try {
        const ctx = this._audioCtx || new (window.AudioContext || window.webkitAudioContext)();
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.frequency.value = 880;
        gain.gain.value = 0.08;
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start();
        gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.18);
        osc.stop(ctx.currentTime + 0.2);
      } catch (_) {}
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

    resumePlayback() {
      document.querySelectorAll('[id^="kurier-media-"]').forEach((el) => {
        this._playMedia(el);
      });
    },
  };

  global.KurierMediasoup = KurierMediasoup;

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      KurierMediasoup.resumePlayback();
      KurierMediasoup._emit("visibility", "visible");
    }
  });
})(window);
