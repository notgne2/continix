{ nixpkgs ? <nixpkgs>, pkgs ? import nixpkgs { }, ... }:

{
  # Generate a Docker image from a system and some other props
  mkDocker = pkgs.callPackage ./docker.nix { inherit nixpkgs pkgs; };

  # Make a system from a NixOS-like config (think configuration.nix)
  mkSystem = pkgs.callPackage ./system.nix { inherit nixpkgs pkgs; };
}
