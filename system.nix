{
  nixpkgs,
  pkgs,
  lib,

  ...
}:

{
  name,
  cfg,
  env ? [],
  user ? "root",
  contents ? [],
  entrypoint ? "",
  rootEntrypoint ? "",
}:

let
  # Make a system thing
  sys = (import "${nixpkgs}/nixos/lib/eval-config.nix" {
    inherit pkgs;

    # Override the base modules with our own limited set of modules
    baseModules = (map (p: "${nixpkgs}/nixos/modules/${p}") [
      # Essential modules copied from clever's not-os
      "system/etc/etc.nix"
      "misc/nixpkgs.nix"
      "misc/assertions.nix"
      "misc/lib.nix"
      "config/sysctl.nix"

      # And these are included too for some reason
      "misc/extra-arguments.nix"
      "misc/ids.nix"
      "config/shells-environment.nix"
      "config/system-environment.nix"
      "programs/environment.nix"
      "programs/shadow.nix"
    ]) ++ [
      # Custom system-path module for a lighter system
      ./custom-modules/system-path.nix

      # Custom users-groups that pregenerates passwd
      # TODO: use a git submodule pointing to the PR commit
      ./custom-modules/users-groups.nix

      # Bunch of stuff to make modules not complain so much
      ./compat.nix
    ];

    # We're sortof expected to _only_ supply modules, but we wanted to remove some things
    # so lets just put the user config here
    modules = [
      cfg
    ];
  }).config.system;

  userEntrypointScript = if entrypoint != "" then (pkgs.writeScript "user-entrypoint.sh" ''
    #!${pkgs.dash}/bin/dash
    ${entrypoint}
  '') else null;

  rootEntrypointScript = if rootEntrypoint != "" then (pkgs.writeScript "root-entrypoint.sh" ''
    #!${pkgs.dash}/bin/dash
    ${rootEntrypoint}
  '') else null;
in
{
  inherit sys cfg name env contents;

  entrypoint = pkgs.writeScript "entrypoint.sh" ''
    #!${pkgs.dash}/bin/dash
    ${if rootEntrypointScript != null then rootEntrypointScript else ""}
    ${if userEntrypointScript != null then "${pkgs.gosu}/bin/gosu ${user} ${userEntrypointScript}" else ""}
  '';
}