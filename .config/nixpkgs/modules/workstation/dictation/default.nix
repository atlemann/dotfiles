{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.workstation.dictation;
  user = config.attributes.mainUser.name;

  models = {
    "tiny.en"   = { file = "ggml-tiny.en.bin";   sha256 = "07qbja4m5isssw42prv227gbyrf3nsjms6h8rlyrkpbgd3w4q7lj"; };
    "base.en"   = { file = "ggml-base.en.bin";   sha256 = "00nhqqvgwyl9zgyy7vk9i3n017q2wlncp5p7ymsk0cpkdp47jdx0"; };
    "small.en"  = { file = "ggml-small.en.bin";  sha256 = "0p8yqkwvpl9lyy43yajk305bps0v5z1qgyg0jwh35j7cb1nqs4y6"; };
    # Add medium.en or larger by running:
    #   nix-prefetch-url https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin
    # then add an entry here.
  };

  selected = models.${cfg.model};

  modelFile = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${selected.file}";
    sha256 = selected.sha256;
  };

  whisperPkg =
    if cfg.backend == "cuda"   then pkgs.whisper-cpp.override { cudaSupport = true; }
    else if cfg.backend == "vulkan" then pkgs.whisper-cpp-vulkan
    else pkgs.whisper-cpp;

  pttScript = pkgs.writeShellApplication {
    name = "whisper-ptt";
    runtimeInputs = [
      whisperPkg
      pkgs.alsa-utils
      pkgs.xdotool
      pkgs.libnotify
      pkgs.coreutils
      pkgs.procps
      pkgs.gnused
    ];
    text = ''
      set -euo pipefail
      STATE_DIR="''${XDG_RUNTIME_DIR:-/tmp}/whisper-ptt"
      mkdir -p "$STATE_DIR"
      PIDFILE="$STATE_DIR/rec.pid"
      WAV="$STATE_DIR/rec.wav"
      MODEL="${modelFile}"

      case "''${1:-}" in
        start)
          if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            exit 0
          fi
          rm -f "$WAV"
          arecord -q -t wav -f S16_LE -c 1 -r 16000 "$WAV" &
          echo $! > "$PIDFILE"
          notify-send -t 1500 -h string:x-canonical-private-synchronous:dictation \
            "Dictation" "Recording…" || true
          ;;

        stop)
          if [ ! -f "$PIDFILE" ]; then
            exit 0
          fi
          pid=$(cat "$PIDFILE")
          rm -f "$PIDFILE"
          kill -TERM "$pid" 2>/dev/null || true
          for _ in $(seq 1 50); do
            if ! kill -0 "$pid" 2>/dev/null; then break; fi
            sleep 0.02
          done

          if [ ! -s "$WAV" ]; then
            notify-send -t 1500 -h string:x-canonical-private-synchronous:dictation \
              "Dictation" "No audio captured" || true
            exit 0
          fi

          notify-send -t 1500 -h string:x-canonical-private-synchronous:dictation \
            "Dictation" "Transcribing…" || true

          text=$(whisper-cli -m "$MODEL" -nt -np -l en -f "$WAV" 2>/dev/null \
            | tr '\n' ' ' \
            | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

          if [ -z "$text" ]; then
            notify-send -t 2000 -h string:x-canonical-private-synchronous:dictation \
              "Dictation" "No speech detected" || true
            exit 0
          fi

          xdotool type --clearmodifiers --delay 0 -- "$text"
          notify-send -t 1000 -h string:x-canonical-private-synchronous:dictation \
            "Dictation" "Done" || true
          ;;

        *)
          echo "usage: whisper-ptt {start|stop}" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.workstation.dictation = {
    enable = mkEnableOption "whisper.cpp push-to-talk dictation";

    backend = mkOption {
      type = types.enum [ "cpu" "vulkan" "cuda" ];
      default = "cpu";
      description = ''
        Compute backend for whisper.cpp.
          cpu    works everywhere.
          vulkan needs a Vulkan-capable GPU + driver (AMD/Intel/NVIDIA).
          cuda   needs NVIDIA + the proprietary nvidia driver.
      '';
    };

    model = mkOption {
      type = types.enum (attrNames models);
      default = "base.en";
      description = "ggml model variant. Larger = more accurate but slower.";
    };

    hotkey = mkOption {
      type = types.str;
      default = "Mod4+grave";
      description = ''
        i3 keybinding for push-to-talk. Press-and-hold records, release
        transcribes and types into the focused window. Use the literal
        modifier name (Mod1, Mod4, …) — the i3 `$mod` variable is not in
        scope for keybindings emitted by home-manager.
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pttScript whisperPkg ];

    home-manager.users."${user}" = mkIf config.wm.i3.enable {
      xsession.windowManager.i3.config.keybindings = mkOptionDefault {
        "${cfg.hotkey}"            = "exec --no-startup-id ${pttScript}/bin/whisper-ptt start";
        "--release ${cfg.hotkey}"  = "exec --no-startup-id ${pttScript}/bin/whisper-ptt stop";
      };
    };
  };
}
