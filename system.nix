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
  entrypoint ? null,
  rootEntrypoint ? null,
  systemdService ? null,
}:

let
  evaled = (import "${nixpkgs}/nixos/lib/eval-config.nix" {
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
      "config/fonts/fonts.nix"
      "config/fonts/fontconfig.nix"
      "config/fonts/fontconfig-penultimate.nix"
      "programs/environment.nix"
      "programs/shadow.nix"
      "services/web-servers/apache-httpd/default.nix"
    ]) ++ [
      # Custom system-path module for a lighter system
      ./custom-modules/system-path.nix

      # Custom users-groups that pregenerates passwd
      # TODO: use a git submodule pointing to the PR commit
      ./custom-modules/users-groups.nix

      # Bunch of stuff to make modules not complain so much
      ./compat.nix

      # Bunch of stuff to make stock Continix containers weight less
      ./lite.nix
    ];

    # We're sortof expected to _only_ supply modules, but we wanted to remove some things
    # so lets just put the user config here
    modules = [
      cfg
    ];
  });

  sys = evaled.config.system;

  userEntrypointScript = if entrypoint != null then (pkgs.writeScript "user-entrypoint.sh" ''
    #!${pkgs.dash}/bin/dash
    ${entrypoint}
  '') else null;

  rootEntrypointScript = if rootEntrypoint != null then (pkgs.writeScript "root-entrypoint.sh" ''
    #!${pkgs.dash}/bin/dash
    ${rootEntrypoint}
  '') else null;
in
{
  inherit sys cfg name env contents evaled;

  entrypoint =
  let
    entrypointScriptContents = if (rootEntrypointScript != null || userEntrypointScript != null || systemdService != null) then
    ''
      #!${pkgs.dash}/bin/dash
      ${if rootEntrypointScript != null then rootEntrypointScript else ""}
      ${if userEntrypointScript != null then "${pkgs.gosu}/bin/gosu ${user} ${userEntrypointScript}" else ""}
    '' + (
      if systemdService != null then
      let
        getRequiredBy = (serviceName:
          let
            service = evaled.config.systemd.services.${serviceName};

            maybe = (name: if builtins.hasAttr name service then service.${name} else []);
            # maybe = (name: if builtins.hasAttr name service then [] else ["a.b"]);
            maybes = (names: builtins.concatLists (map maybe names));

            required = map (x: lib.splitString "." x) (maybes [ "after" "wants" "requires" ]);
            requiredTargets = map (x: builtins.elemAt x 0) (builtins.filter (x: (builtins.elemAt x 1) == "target") required);
            requiredServices = map (x: builtins.elemAt x 0) (builtins.filter (x: (builtins.elemAt x 1) == "service") required);

            reverseRequired = builtins.filter (aServiceName:
              let
                aService = evaled.config.systemd.services.${aServiceName};

                aMaybe = (name: if builtins.hasAttr name aService then aService.${name} else []);
                aMaybes = (names: builtins.concatLists (map aMaybe names));

                aServicePreceeds = map (x: lib.splitString "." x) (aMaybes [ "before" "wantedBy" ]);
                aServicePreceedsTargets = map (x: builtins.elemAt x 0) (builtins.filter (x: (builtins.elemAt x 1) == "target") aServicePreceeds);
                aServicePreceedsServices = map (x: builtins.elemAt x 0) (builtins.filter (x: (builtins.elemAt x 1) == "service") aServicePreceeds);
              in
              builtins.elem serviceName aServicePreceedsServices || (builtins.length (builtins.filter (t: builtins.elem t requiredTargets) aServicePreceedsTargets)) != 0
            ) (builtins.attrNames evaled.config.systemd.services);

            existingRequiredServices = builtins.filter (n: builtins.hasAttr n evaled.config.systemd.services) requiredServices;

            semiFullRequiredServices = existingRequiredServices ++ reverseRequired;
          in
          semiFullRequiredServices ++ (builtins.concatLists (map getRequiredBy semiFullRequiredServices))
        );

        requirements = getRequiredBy systemdService;
        shottableRequirements = builtins.filter (s: s.serviceConfig.Type == "oneshot") requirements;

        serviceLaunchLines = map (service:
          ''
            ${service.preStart}
            ${service.serviceConfig.ExecStart}
          ''
        ) (shottableRequirements ++ [ evaled.config.systemd.services.${systemdService} ]);
      in
      builtins.concatStringsSep "" serviceLaunchLines
      else ""
    )
    else null;
  in
  if entrypointScriptContents != null then pkgs.writeScript "entrypoint.sh" entrypointScriptContents else null;
}