{
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system}; continix = import ./default.nix { inherit nixpkgs pkgs; }; in
      rec {
        lib = continix;
        packages = rec {
          cont = continix.mkSystem {
            inherit system;

            name = "hello";
            systemdService = "httpd";

            cfg = {
              services.httpd = {
                adminAddr = "example@example.com";
                enable = true;
                virtualHosts = {
                  "example.com" = { documentRoot = pkgs.runCommand "dumb-web" {} ''
                    mkdir $out
                    echo "hello world" > $out/index.html
                  ''; };
                };
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
        };
      }
    );
}
