{ config, lib, pkgs, ... }:
with lib;
{
  options.dev.shared.optimizations = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable system optimizations for development (inotify, etc)";
    };
  };

  config = mkIf config.dev.shared.optimizations.enable {
    boot.kernel.sysctl."fs.inotify.max_user_instances" = 524288;
    boot.kernel.sysctl."fs.inotify.max_user_watches" = 524288;
  };
}
