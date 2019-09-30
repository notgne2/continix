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

        shellEscape = s: (lib.replaceChars [ "\\" ] [ "\\\\" ] s);
        makeJobScript = name: text:
          let mkScriptName =  s: "unit-script-" + (lib.replaceChars [ "\\" "@" ] [ "-" "_" ] (shellEscape s) );
          in  pkgs.writeTextFile { name = mkScriptName name; executable = true; inherit text; };

        reparseExecStart = (x:
          let
            split = lib.splitString " " x;
            first = builtins.elemAt split 0;

            collectVood = (s:
              let
                _collectVood = (ss: s:
                  if (builtins.elem (builtins.substring 0 1 s) [ "@" "-" ":" "!" ]) then
                    _collectVood (ss + (builtins.substring 0 1 s)) (builtins.substring 1 (builtins.stringLength s) s)
                  else
                    [ ss s ]
                );
              in
              _collectVood "" s
            );

            vood = collectVood first;
            prefixParts = builtins.elemAt vood 0;
            firstParts = builtins.elemAt vood 1;

            remainder = builtins.concatStringsSep " " (lib.drop 1 split);
          in
          if (builtins.elem "@" (lib.stringToCharacters prefixParts)) then
            "${pkgs.perl}/bin/perl -e 'exec {shift} @ARGV' ${firstParts} ${remainder}"
          else # TODO support more operators
            "${firstParts} ${remainder}"
        );

        allServices = (shottableRequirements ++ [ systemdService ]);

        allServiceBinPaths = builtins.concatLists (map (serviceName:
          evaled.config.systemd.services.${serviceName}.path
        ) allServices);

        binPath = lib.makeBinPath (allServiceBinPaths ++ [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.gnused
        ]);

        gatherStone = (ss:
          builtins.concatLists (map (s:
            map (k:
              [ k s.${k} ]
            ) (builtins.attrNames s)
          ) ss)
        );

        allServiceEnvironments = gatherStone (map (serviceName:
          evaled.config.systemd.services.${serviceName}.environment
        ) allServices);

        envLines = map (x:
          "${builtins.elemAt x 0}=${builtins.elemAt x 1}"
        ) allServiceEnvironments;

        serviceLaunchLines = map (serviceName:
          let
            service = evaled.config.systemd.services.${serviceName};
            preStart =
              if builtins.hasAttr "preStart" service then
                makeJobScript "${serviceName}-pre-start" ''
                  #! ${pkgs.runtimeShell} -e
                  ${service.preStart}
                ''
              else if builtins.hasAttr "serviceConfig" service && builtins.hasAttr "ExecStartPre" service.serviceConfig then
                service.serviceConfig.ExecStartPre
              else
                "";

            start =
              if builtins.hasAttr "script" service then
                makeJobScript "${serviceName}-start" ''
                  #! ${pkgs.runtimeShell} -e
                  ${service.script}
                '' + " " + service.scriptArgs
              else if builtins.hasAttr "serviceConfig" service && builtins.hasAttr "ExecStart" service.serviceConfig then
                reparseExecStart service.serviceConfig.ExecStart
              else
                "";
          in
          ''
            #! ${pkgs.runtimeShell} -e
            PATH=${binPath}
            ${builtins.concatStringsSep "\n" envLines}
            ${preStart}
            ${start}
          '' + (if (service.serviceConfig.Type == "forking") then ''
            sleep 1 # This is an ugly hack fix for a race condition, TODO fix this asap
            PID=$(cat ${service.serviceConfig.PIDFile})
            ${pkgs.busybox}/bin/xargs ${pkgs.coreutils}/bin/tail -f /proc/$PID/fd/1 /proc/$PID/fd/2 --pid=$PID # this is a "just-in-case", since reptyr wont always work
          '' else "")
        ) allServices;
      in
      builtins.concatStringsSep "\n" serviceLaunchLines
      else ""
    )
    else null;
  in
  if entrypointScriptContents != null then pkgs.writeScript "entrypoint.sh" entrypointScriptContents else null;
}