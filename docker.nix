{
  nixpkgs,
  pkgs,
  lib,

  ...
}:

{
  cont,
  name ? cont.name,
  tag,
  cmd ? [],
  workDir ? "/data",
  enableLocale ? false,
  extraDockerConfig ? {},
  env ? [],
  maxLayers ? 120,
}:

pkgs.dockerTools.buildLayeredImage {
  inherit maxLayers name tag;

  contents = pkgs.symlinkJoin {
    name = "${name}-contents";
    paths = [
      cont.sys.build.etc
      cont.sys.path
    ] ++ cont.contents;
  };

  config = {
    Entrypoint = cont.entrypoint;

    Cmd = cmd;
    WorkingDir = workDir;

    Env = cont.env;
  } // extraDockerConfig;
}