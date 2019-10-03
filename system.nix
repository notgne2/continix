{
  nixpkgs,
  pkgs,
  lib,
  stdenv,

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
        # Helper method to recursively gather a list of dependencies for a given service
        getRequiredBy = (serviceName:
          let
            # Get the service by name
            service = evaled.config.systemd.services.${serviceName};

            # Helper methods for looking for possibly non-existent field names containing a list of services or targets on the service
            # TODO: use better builtins for this?
            maybe = (name: if builtins.hasAttr name service then service.${name} else []);
            maybes = (names: builtins.concatLists (map maybe names));

            # Scrape the list of targets and services this service wants, and seperate into targets and services
            required = map (x: lib.splitString "." x) (maybes [ "after" "wants" "requires" ]);
            requiredTargets = map (x: builtins.elemAt x 0) (builtins.filter (x: (builtins.elemAt x 1) == "target") required);
            requiredServices = map (x: builtins.elemAt x 0) (builtins.filter (x: (builtins.elemAt x 1) == "service") required);

            # Filter over all other services, to find ones which want to run before this one
            reverseRequired = builtins.filter (aServiceName:
              let
                # Get the other service by name
                aService = evaled.config.systemd.services.${aServiceName};

                # Helper methods for looking for possibly non-existent field names containing a list of services or targets on the other service
                aMaybe = (name: if builtins.hasAttr name aService then aService.${name} else []);
                aMaybes = (names: builtins.concatLists (map aMaybe names));

                # Scrape the list of targets and services this other service wants to run before
                aServicePreceeds = map (x: lib.splitString "." x) (aMaybes [ "before" "wantedBy" ]);
                aServicePreceedsTargets = map (x: builtins.elemAt x 0) (builtins.filter (x: (builtins.elemAt x 1) == "target") aServicePreceeds);
                aServicePreceedsServices = map (x: builtins.elemAt x 0) (builtins.filter (x: (builtins.elemAt x 1) == "service") aServicePreceeds);
              in
              # If this other service wants to preceed the service, or if this other service wants to start before a target the service wants
              builtins.elem serviceName aServicePreceedsServices || (builtins.length (builtins.filter (t: builtins.elem t requiredTargets) aServicePreceedsTargets)) != 0
            ) (builtins.attrNames evaled.config.systemd.services);

            # Filtr down the list of required services to only those which exist
            existingRequiredServices = builtins.filter (n: builtins.hasAttr n evaled.config.systemd.services) requiredServices;

            # Make a semi-full list of requirements from the requirements that exist and the requirements found from iterating other services
            semiFullRequiredServices = existingRequiredServices ++ reverseRequired;
          in
          # Combine our semi-full list of requirements with the scraped requirements of those requirements
          semiFullRequiredServices ++ (builtins.concatLists (map getRequiredBy semiFullRequiredServices))
        );

        # Gather the requirements for the specified service
        requirements = getRequiredBy systemdService;
        # Filter down to only oneshot services
        shottableRequirements = builtins.filter (s: s.serviceConfig.Type == "oneshot") requirements;

        # Helper copied from the SystemD NixOS module (TODO: import it?)
        shellEscape = s: (lib.replaceChars [ "\\" ] [ "\\\\" ] s);
        makeJobScript = name: text:
          let mkScriptName =  s: "unit-script-" + (lib.replaceChars [ "\\" "@" ] [ "-" "_" ] (shellEscape s) );
          in  pkgs.writeTextFile { name = mkScriptName name; executable = true; inherit text; };

        # Convert a SystemD ExecStart into a bash line (they often begin with special operators that must be parsed)
        reparseExecStart = (x:
          let
            # Split the launch string by spaces (TODO: take (ba)sh? formatting into account, i.e. quotes)
            split = lib.splitString " " x;
            # Get the first component of the launch string
            first = builtins.elemAt split 0;

            # Helper to seperate prefix operators from the first part of the Exec command
            collectVood = (s:
              let
                # Define the actual function internally to expose a more reasonable API, while supporting recursion
                _collectVood = (ss: s:
                  # If the current string begins with one of the prefix operator symbols
                  if (builtins.elem (builtins.substring 0 1 s) [ "@" "-" ":" "!" ]) then
                    # Recurse this function with the first character (the operator) and the remainder
                    _collectVood (ss + (builtins.substring 0 1 s)) (builtins.substring 1 (builtins.stringLength s) s)
                  else
                    # Return the current string and remainder
                    [ ss s ]
                );
              in
              _collectVood "" s
            );

            # Use the helper above to seperate the prefix operators from the launch string
            vood = collectVood first;
            prefixParts = builtins.elemAt vood 0;
            firstParts = builtins.elemAt vood 1;

            # Make a string from the remainder of the ExecStart line (not including the first part, which was parsed)
            remainder = builtins.concatStringsSep " " (lib.drop 1 split);

            # Compile a simple program that will replace argv[0] with the 2nd provided arg
            modFirstArg = pkgs.runCommandCC "mod-first-arg" {} ''
              echo "int main(int c,char*v[]){execvp(v[1],&v[2]);perror(v[1]);return 127;}" > r.c
              gcc -o $out r.c
            '';
          in
          if (builtins.elem "@" (lib.stringToCharacters prefixParts)) then
            "${modFirstArg} ${firstParts} ${remainder}"
          else # TODO: support more operators
            "${firstParts} ${remainder}"
        );

        # Make a list of all the services which should be ran
        allServices = (shottableRequirements ++ [ systemdService ]);

        serviceLaunchScripts = map (serviceName:
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

            # Make a PATH variable for all the service's packages
            binPath = lib.makeBinPath (service.path ++ [
              pkgs.coreutils
              pkgs.findutils
              pkgs.gnugrep
              pkgs.gnused
            ]);

            # Convert the service's specified environment variables into an env-setting script snippet
            envLines = map (k:
              "${k}=${service.environment.${k}}"
            ) (builtins.attrNames service.environment);
          in
          pkgs.writeScript "service-launch-${serviceName}" ''
            #! ${pkgs.runtimeShell} -e
            PATH=${binPath}
            ${builtins.concatStringsSep "\n" envLines}
            ${preStart}
            ${start}
          '' + (if (service.serviceConfig.Type == "forking") then "\n" + ''
            # This will retry reading the PIDFile until success
            while true; do
              export PID=$(${pkgs.coreutils}/bin/cat ${service.serviceConfig.PIDFile})
              [ ! -z "$PID" ] && break
            done

            # This will end when the process exits
            ${pkgs.coreutils}/bin/tail -f /proc/$PID/fd/1 /proc/$PID/fd/2 --pid=$PID
          '' else "")
        ) allServices;
      in
      builtins.concatStringsSep "\n" serviceLaunchScripts
      else ""
    )
    else null;
  in
  # Only define an entrypoint if contents for it were provided
  if entrypointScriptContents != null then pkgs.writeScript "entrypoint.sh" entrypointScriptContents else null;
}