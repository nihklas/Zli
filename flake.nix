{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";

    zls.url = "github:zigtools/zls/0.14.0";
    zls.inputs.nixpkgs.follows = "nixpkgs";
    zls.inputs.zig-overlay.follows = "zig-overlay";
  };

  outputs = {
    nixpkgs,
    zig-overlay,
    zls,
    ...
  }: let
    systems = ["aarch64-darwin" "x86_64-linux"];
    eachSystem = function:
      nixpkgs.lib.genAttrs systems (system:
        function {
          inherit system;
          target = builtins.replaceStrings ["darwin"] ["macos"] system;
          pkgs = nixpkgs.legacyPackages.${system};
          zig = zig-overlay.packages.${system}.master;
        });
  in {
    devShells = eachSystem ({
      system,
      pkgs,
      zig,
      ...
    }: {
      default = pkgs.mkShellNoCC {
        packages = [
          pkgs.lua-language-server
          zls.packages.${system}.default
          zig
        ];
      };
    });
  };
}

