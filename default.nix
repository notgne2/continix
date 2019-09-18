{
  ...
}:

rec {
  nixpkgs = <nixpkgs>;
  # it's a good idea not to use any of these, the top one breaks things iirc
  # pkgs = import nixpkgs { overlays = [ (self: super: { glibcLocales = super.glibcLocales.override { allLocales = false; }; }) ]; };
  # pkgs = (import nixpkgs {}).pkgsMusl;
  pkgs = import nixpkgs {};

  # Generate a Docker image from a system and some other props
  mkDocker = pkgs.callPackage ./docker.nix {
    inherit nixpkgs pkgs;
  };

  # Make a system from a NixOS-like config (think configuration.nix)
  mkSystem = pkgs.callPackage ./system.nix {
    inherit nixpkgs pkgs;
  };
}