# Continix
This is home to a simple project to generate Docker images using Nix all the way, that means more declarative config, and less bash scripts.

It's a simple wrapper around eval-config and `dockerTools.buildImage`.

Right now it's very simple and just sets the contents, but there is potential for new experimentation using `sys.build.toplevel` init scripts (with SystemD, and hardware related tasks stripped), which will likely prove more accurate and reliable if it is possible to remove build-time dependencies from the final image.

The resulting filesystem will be the sum of included packages, so no symlinks in `/run`, just a simple `/bin`, so NixOS-dependent tools may not work if written wrong.

## Examples

```nix
rec {
  cont = continix.mkSystem {
    name = "hello";
    entrypoint = "${pkgs.hello}/bin/hello";
    cfg = {
      users = {
        users = [{
          name = "example";
          group = "example";
          home = "/data";
          createHome = true;
          uid = 1000;
        }];

        groups = [{
          name = "example";
          gid = 1000;
        }];
      };
    };
  };

  image = continix.mkDocker {
    inherit cont;

    tag = "latest";

    extraDockerConfig = {
      ExposedPorts = {
        "8080" = {};
      };
    };
  };
}
```