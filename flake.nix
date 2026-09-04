{
  description = "Show a remote herdr agent inside a local herdr pane";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forAllSystems (pkgs: rec {
      herdr-bridge = pkgs.callPackage ./package.nix {};
      default = herdr-bridge;
    });

    # `nix flake check` runs shellcheck and the bats suite via the package's
    # own check phase.
    checks = forAllSystems (pkgs: {
      herdr-bridge = self.packages.${pkgs.stdenv.hostPlatform.system}.herdr-bridge;
    });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        packages = with pkgs; [bats shellcheck shfmt jq openssh zsh];
      };
    });

    formatter = forAllSystems (pkgs: pkgs.alejandra);
  };
}
