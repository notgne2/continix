{ config, lib, utils, pkgs, ... }:
{
  # The purpose of this is to disable everything that we won't need all the time
  # this can of course be overridden in your Continix config
  config = {
    # # You might want this if you expect normal things to exist
    # environment.systemPackages = [ pkgs.busybox ];

    # Hey its lightweight and you probably want one
    users.defaultUserShell = pkgs.dash;

    fonts.fontconfig.enable = lib.mkDefault false;
  };
}