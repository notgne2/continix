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
  }:
  pkgs.dockerTools.buildImage {
    inherit name tag;

    contents = pkgs.symlinkJoin {
      name = "${name}-contents";
      paths = [ cont.sys.build.etc cont.sys.path ] ++ cont.contents;
    };

    config = {
      Entrypoint = cont.entrypoint;

      Cmd = cmd;
      WorkingDir = workDir;

      Env = cont.env ++ env;
    } // extraDockerConfig;
  }
)
