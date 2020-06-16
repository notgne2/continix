{ nixpkgs, pkgs, lib, ... }:
let
  repeat = n: a: accum:
    if n == 0 then accum else repeat (n - 1) a (accum ++ [ a ]);
  r = n: a: repeat n a [ ];
in
(
  { cont
  , name ? cont.name
  , tag
  , cmd ? [ ]
  , workDir ? "/data"
  , enableLocale ? false
  , extraDockerConfig ? { }
  , env ? [ ]
  , maxLayers ? 120
  , perLayer ? 3
  , hints ? r (maxLayers - 1) perLayer
  }:
  let
    dockerTools = pkgs.callPackage (./dockertools/default.nix) { };
  in
  dockerTools.buildLayeredImage {
    inherit maxLayers name tag hints;

    contents = pkgs.symlinkJoin {
      name = "${name}-contents";
      paths = [ cont.sys.build.etc cont.sys.path ] ++ cont.contents;
    };

    config = {
      Entrypoint = cont.entrypoint;

      Cmd = cmd;
      WorkingDir = workDir;

      Env = cont.env;
    } // extraDockerConfig;
  }
)
