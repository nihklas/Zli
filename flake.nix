{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
    zigscient.url = "gitlab:nihklas/zigscient-nix";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem
    (
      system: let
        overlays = [
          inputs.zig.overlays.default
          inputs.zigscient.overlays.default
        ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
      in
        with pkgs; {
          devShells.default = mkShell {
            packages = [
              zigpkgs.master
              zigscient
            ];
            shellHook = ''
              # We unset some NIX environment variables that might interfere with the zig compiler.
              # Issue: https://github.com/ziglang/zig/issues/18998
              unset NIX_CFLAGS_COMPILE
              unset NIX_LDFLAGS
              printf '\n'
              echo "Running Zig Version: $(zig version)"
            '';
          };
        }
    );
}
