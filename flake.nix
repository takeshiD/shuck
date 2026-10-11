{
  description = "shuck: a fast shell script linter";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      rust-overlay,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };
        inherit (pkgs) lib;

        # Use the exact toolchain pinned in rust-toolchain.toml so that
        # `nix build` and a plain `cargo build` compile with the same compiler.
        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustToolchain;
          rustc = rustToolchain;
        };

        cargoToml = fromTOML (builtins.readFile ./Cargo.toml);

        # Only the files cargo needs. Keeps website/, scripts/ and other
        # non-Rust changes from invalidating the build. docs/rules and
        # contracts/ are read by crates/shuck-linter/build.rs through the
        # `rules` and `contracts` symlinks inside that crate.
        src = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [
            ./Cargo.toml
            ./Cargo.lock
            ./rust-toolchain.toml
            ./crates
            ./contracts
            ./docs/rules
          ];
        };

        shuck = rustPlatform.buildRustPackage {
          pname = "shuck";
          version = cargoToml.workspace.package.version;
          inherit src;

          cargoLock.lockFile = ./Cargo.lock;

          # Build only the CLI; the workspace also contains wasm bindings and
          # benchmark harnesses that are not part of the installed package.
          cargoBuildFlags = [
            "-p"
            "shuck-cli"
          ];
          # Mirror `make test`.
          cargoTestFlags = [
            "-p"
            "shuck-cli"
            "-p"
            "shuck-cache"
          ];

          meta = {
            description = cargoToml.workspace.package.description;
            homepage = cargoToml.workspace.package.repository;
            license = lib.licenses.mit;
            mainProgram = "shuck";
          };
        };
      in
      {
        packages = {
          inherit shuck;
          default = shuck;
        };

        apps.default = {
          type = "app";
          program = lib.getExe shuck;
          meta.description = "Run the shuck shell script linter";
        };

        devShells.default = pkgs.mkShell {
          packages = [
            rustToolchain
            pkgs.hyperfine
            pkgs.samply
            pkgs.neovim
            pkgs.python3
            pkgs.lua
            pkgs.shellcheck
            pkgs.shfmt
            pkgs.zsh
            pkgs.cargo-fuzz
            pkgs.cargo-shear
            pkgs.yq
          ];
        };
      }
    );
}
