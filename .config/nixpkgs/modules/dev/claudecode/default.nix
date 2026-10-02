{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.dev.claudecode;
  bcfg = cfg.bedrock;

  user = config.attributes.mainUser.name;
  installDir = "${config.users.users."${user}".home}/${bcfg.installSubdir}";

  credentialProcess = "${installDir}/credential-process";
  otelHelper = "${installDir}/otel-helper";

  # Overridden locally rather than through nixpkgs.overlays, because
  # modules/nix/core sets nixpkgs.pkgs to an externally built instance and
  # whether overlays still apply on top of that is nixpkgs-version dependent.
  # claude-code is a prebuilt binary fetched by URL with no npmDeps, so
  # swapping version + src is the whole bump.
  claudeCodePackage =
    if cfg.versionOverride == null then
      pkgs.claude-code
    else
      pkgs.claude-code.overrideAttrs (old: {
        version = cfg.versionOverride.version;
        src = pkgs.fetchurl {
          # Rewrite the version in the upstream URL so the platform segment
          # (linux-x64 / linux-arm64) stays whatever nixpkgs resolved.
          url = builtins.replaceStrings [ old.version ] [ cfg.versionOverride.version ]
                  (builtins.head old.src.urls);
          hash = cfg.versionOverride.hash;
        };
      });

  managedSettings = {
    env = {
      CLAUDE_CODE_USE_BEDROCK = "1";
      AWS_REGION = bcfg.region;
      AWS_PROFILE = bcfg.profile;
      AWS_CREDENTIAL_PROCESS = "${credentialProcess} --profile ${bcfg.profile}";

      ANTHROPIC_DEFAULT_OPUS_MODEL = bcfg.models.opus;
      ANTHROPIC_DEFAULT_SONNET_MODEL = bcfg.models.sonnet;
      ANTHROPIC_DEFAULT_HAIKU_MODEL = bcfg.models.haiku;
      ANTHROPIC_SMALL_FAST_MODEL = bcfg.models.haiku;
    } // optionalAttrs bcfg.telemetry.enable {
      CLAUDE_CODE_ENABLE_TELEMETRY = "1";
      OTEL_METRICS_EXPORTER = "otlp";
      OTEL_LOGS_EXPORTER = "none";
      OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
      OTEL_EXPORTER_OTLP_ENDPOINT = bcfg.telemetry.endpoint;
      OTEL_RESOURCE_ATTRIBUTES =
        concatStringsSep "," (mapAttrsToList (k: v: "${k}=${v}") bcfg.telemetry.resourceAttributes);
    };

    awsAuthRefresh = "${credentialProcess} --profile ${bcfg.profile}";
  } // optionalAttrs bcfg.telemetry.enable {
    otelHeadersHelper = "${otelHelper} --profile ${bcfg.profile}";
  };

  # Appended to ~/.aws/config on activation if the profile is absent. The AWS SDK
  # has no conf.d mechanism, and the file stays user-writable so `aws configure`
  # keeps working, so this cannot be an environment.etc / home.file entry.
  awsProfileStanza = pkgs.writeText "aws-profile-${bcfg.profile}" ''

    [profile ${bcfg.profile}]
    credential_process = ${credentialProcess} --profile ${bcfg.profile}
    region = ${bcfg.region}
  '';

  statusLine = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = with pkgs; [ coreutils git gnugrep jq ];
    # Missing fields and non-repo dirs are expected; errexit would blank the line.
    bashOptions = [ ];
    text = builtins.readFile ./statusline.sh;
  };
in
  {
    options = {
      dev.claudecode = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to install Claude Code along with its sandbox dependencies (bubblewrap, socat).";
        };

        versionOverride = mkOption {
          type = types.nullOr (types.submodule {
            options = {
              version = mkOption {
                type = types.str;
                example = "2.1.280";
                description = "Upstream claude-code release to build instead of the nixpkgs one.";
              };
              hash = mkOption {
                type = types.str;
                example = "sha256-J5EOKucE2PLoAkiX2P3x53EIB7r09pgsDjeXwFgxU4Q=";
                description = "SRI hash of that release's claude.zst.";
              };
            };
          });
          default = null;
          description = ''
            Build a newer claude-code than the pinned nixpkgs provides, for when a
            model needs a version nixpkgs has not packaged yet (e.g. opus-5-5
            requires >= 2.1.280).

            Temporary by nature: this PINS the version, so once nixpkgs catches up
            the override holds you back instead of moving you forward. A warning
            fires when that happens — remove the override then.

            To get the hash for a version:
              nix-prefetch-url https://downloads.claude.ai/claude-code-releases/<version>/linux-x64/claude.zst
              nix hash to-sri --type sha256 <base32 output>
          '';
        };

        bedrock = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Route Claude Code at AWS Bedrock through the organization's OIDC-federated
              role, via the credential-process helper shipped in the IT-distributed
              claude-code-package.

              The helpers themselves are NOT managed here: they are version-stamped
              binaries that IT re-rolls independently, so they stay where install.sh
              puts them (see installSubdir). Only the configuration is declarative.
            '';
          };

          installSubdir = mkOption {
            type = types.str;
            default = "claude-code-with-bedrock";
            description = "Directory under the main user's home where install.sh placed credential-process and otel-helper.";
          };

          profile = mkOption {
            type = types.str;
            default = "oec-prod-us-east-1";
            description = "Profile name, matching a key in the package's config.json and the generated ~/.aws/config entry.";
          };

          region = mkOption {
            type = types.str;
            default = "us-east-1";
            description = "AWS region used for Bedrock calls.";
          };

          models = {
            opus = mkOption {
              type = types.str;
              default = "global.anthropic.claude-opus-5-5[1m]";
              description = "Model the 'opus' alias resolves to. Verify IDs with `aws bedrock list-foundation-models` before bumping.";
            };
            sonnet = mkOption {
              type = types.str;
              default = "global.anthropic.claude-sonnet-5";
              description = "Model the 'sonnet' alias resolves to.";
            };
            haiku = mkOption {
              type = types.str;
              default = "global.anthropic.claude-haiku-4-5-20251001-v1:0";
              description = "Model the 'haiku' alias resolves to, also used for background/small-fast tasks.";
            };
          };

          telemetry = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Export Claude Code OTLP metrics to the organization's collector.";
            };
            endpoint = mkOption {
              type = types.str;
              default = "https://telemetry.openearth.community";
              description = "OTLP endpoint.";
            };
            resourceAttributes = mkOption {
              type = types.attrsOf types.str;
              default = {
                department = "default";
                "team.id" = "default";
                cost_center = "default";
                organization = "default";
                project = "default";
                settings_version = "2026-09-08-112517";
              };
              description = "OTEL_RESOURCE_ATTRIBUTES entries, as shipped in the package's settings.json.";
            };
          };
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        environment.systemPackages = [
          claudeCodePackage    # Anthropic's official CLI for Claude
          pkgs.bubblewrap      # Required for Claude Code's sandbox feature (bwrap)
          pkgs.socat           # Required for Claude Code's sandboxed network proxy
        ];

        # Managed, so it wins over any statusLine left in ~/.claude/settings.json.
        environment.etc."claude-code/managed-settings.d/40-statusline.json".text =
          builtins.toJSON {
            statusLine = { type = "command"; command = "${statusLine}/bin/claude-statusline"; };
          };

        warnings = optional
          (cfg.versionOverride != null
            && versionAtLeast pkgs.claude-code.version cfg.versionOverride.version)
          ''
            dev.claudecode.versionOverride pins claude-code ${cfg.versionOverride.version},
            but nixpkgs now provides ${pkgs.claude-code.version}. The override is now a
            ceiling rather than an upgrade — remove it.
          '';
      })

      (mkIf (cfg.enable && bcfg.enable) {
        # Highest-precedence settings layer, and one Claude Code only ever reads.
        # ~/.claude/settings.json is deliberately left unmanaged: Claude Code
        # rewrites it at runtime (/model, /config, plugin toggles), so a read-only
        # store symlink there would break those. `env` merges per-key across
        # layers, so user-level keys not named here still apply.
        #
        # ANTHROPIC_MODEL is intentionally omitted even though the package sets it:
        # here it would pin the default model with no way to override it.
        # A drop-in rather than the bare managed-settings.json: if a future
        # IT-distributed package ships its own managed-settings.json, install.sh
        # writes that exact path, which would fail against a read-only store symlink.
        environment.etc."claude-code/managed-settings.d/50-bedrock-oidc.json".text =
          builtins.toJSON managedSettings;

        home-manager.users."${user}" = { lib, ... }: {
          home.activation.claudeCodeBedrockAwsProfile =
            lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              if [ ! -x "${credentialProcess}" ]; then
                warnEcho "claude-code: ${credentialProcess} is missing."
                warnEcho "  Run install.sh from the IT-distributed claude-code-package to restore it."
              fi

              if ! grep -qs '^\[profile ${bcfg.profile}\]' "$HOME/.aws/config"; then
                $DRY_RUN_CMD mkdir -p "$HOME/.aws"
                $DRY_RUN_CMD sh -c 'cat ${awsProfileStanza} >> "$HOME/.aws/config"'
                $VERBOSE_ECHO "claude-code: added AWS profile ${bcfg.profile} to ~/.aws/config"
              fi
            '';
        };
      })
    ];
  }
