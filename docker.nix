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
  cmd ? null,
  workDir ? "/data",
  enableLocale ? false,
  extraDockerConfig ? {},
  env ? [],
}:

pkgs.dockerTools.buildImage {
  name = name;
  tag = tag;

  contents = pkgs.symlinkJoin {
    name = "${name}-contents";
    paths = [
      cont.sys.build.etc
      cont.sys.path
    ];
  };

  config = {
    Entrypoint = cont.entrypoint;

    Cmd = if cmd != null then cmd else [];
    WorkingDir = workDir;

    Env = cont.env;
  } // extraDockerConfig;
}