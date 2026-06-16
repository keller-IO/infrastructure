{
  description = "keller.io — infrastructure dev shell (opentofu, talosctl, sops, age, kubectl)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          name = "keller.io-infra";

          # Tooling required by the justfile recipes and the deployment workflow.
          packages = with pkgs; [
            just # task runner
            opentofu # infrastructure as code
            talosctl # Talos Linux cluster management
            kubectl # cluster access
            sops # secret encryption
            age # age keys for SOPS (age + age-keygen)
          ];

          shellHook = ''
            echo "keller.io infra dev shell — run 'just' for available recipes."
          '';
        };
      }
    );
}
