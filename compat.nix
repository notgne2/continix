{ config, lib, utils, pkgs, ... }:
{
  # Some "fake" options for modules that dont exist to make other modules happy
  # some of these might be dinosaurs from past experiments
  options = {
    services.nscd.enable = lib.mkOption { default = false; };
    systemd.services = lib.mkOption {};
    security.pam = lib.mkOption {};
    security.wrappers = lib.mkOption {};
    system.activationScripts = lib.mkOption {};
    system.build = lib.mkOption {};
  };

  config = {
    # This is needed to make the patched users-groups.nix able to pregenerate /etc/passwd
    users.mutableUsers = false;
    users.enforceStaticIds = true;
  };
}