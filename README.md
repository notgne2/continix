# Continix
This is home to a simple project to generate Docker images using Nix all the way, that means more declarative config, and less bash scripts.

It's a simple wrapper around eval-config and `dockerTools.buildImage`.

By default there is a user created called `continix` which the entrypoint will be called from, for any root commands you can use `rootEntrypoint`. SystemD services will also currently all run as root, but this will soon be fixed.

Currently this is set up by using a few tweaks (like stripping some bloat and statically generating `/etc/passwd`) and simply reading the outputted files for a NixOS generation, this means there is no native NixOS activation logic (i.e. activation scripts) yet.

A few modified versions of NixOS modules are included, eventually I would like for these changes to be upstreamed or have upstream otherwise modified to make Continix possible, but as of now there isn't many, so maintaining isn't too much work.

There is also included logic for running a single ongoing SystemD service, and any amount of preceeding oneshot services (dependency/order resolution is complete and theoretically accurate). This is all done at build-time and will compile into a single bash entrypoint that will perform the actual execution. There are some missing features from this as of now, but these can eventually be patched in if we don't have a replacement service runtime soon enough.

In the future there will probably be included runtimes, and as a whole will work a lot more like a standard NixOS system or container, but for right now, this suffices for a majority of tasks.

The resulting _top level_ packages will just be mapped onto `/`, so for instance derivations producing a `/bin` will be put in `/bin`, so the only real difference here is there is no `/run` symlinks (which is not needed as there is no switching)

## Examples

```nix
rec {
  cont = continix.mkSystem {
    name = "hello";
    entrypoint = "${pkgs.hello}/bin/hello";
    rootEntrypoint = "mkdir /tmp/something";
    cfg = {};
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

```nix
rec {
  cont = continix.mkSystem {
    name = "hello";
    systemdService = "httpd"; # This must be the name of the systemd service, not neccesarily the name used for the NixOS service

    cfg = {
      services.httpd = {
        enable = true;
        virtualHosts = [
          { hostName = "example.local"; documentRoot = "${pkgs.some-web-thing}/html"; }
        ];
      };
    };
  };

  image = continix.mkDocker {
    inherit cont;

    tag = "latest";

    extraDockerConfig = {
      ExposedPorts = {
        "80" = {};
      };
    };
  };
}
```

```nix
rec {
  cont = continix.mkSystem {
    name = "hello";
    entrypoint = "${pkgs.hello}/bin/hello";
    user = "example";
    cfg = {
      users = {
        users = [{
          name = "example";
          group = "example";
          home = "/data";
          createHome = true; # TODO: make Continix actually do this, right now it only handles it for the built-in user
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
