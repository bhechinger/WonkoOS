{
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # Stable Nixpkgs
    unstable-nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # Unstable Nixpkgs

    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/3"; # Determinate 3.*
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    auto-splice.url = "github:zenith-network/auto-splice";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spotify-midi-control.url = "github:bhechinger/spotify-midi-control";
  };

  outputs =
    {
      nixpkgs,
      unstable-nixpkgs,
      determinate,
      home-manager,
      auto-splice,
      sops-nix,
      spotify-midi-control,
      ...
    }:
    let
      #lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
      unstable-pkgs = import unstable-nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
        overlays = [
          (_final: prev: {
            # Codex's upstream Linux sandbox currently conflicts with this NixOS
            # setup, so the bwrap and landlock checks are patched out below. The
            # wrapper still drops Linux capabilities with setpriv, but Codex
            # subprocesses are intentionally not filesystem/network sandboxed here.
            codex = prev.codex.overrideAttrs (old: {
              env = (old.env or { }) // {
                RUST_MIN_STACK = "16777216";
              };
              postPatch = (old.postPatch or "") + ''
                substituteInPlace linux-sandbox/src/bwrap.rs \
                  --replace-fail '!matches!(self, Self::FullAccess)' 'false'
                substituteInPlace linux-sandbox/src/landlock.rs \
                  --replace-fail '!network_sandbox_policy.is_enabled() || allow_network_for_proxy' 'false'
              '';
              postFixup = (old.postFixup or "") + ''
                mv $out/bin/codex $out/bin/.codex-setpriv-target
                makeWrapper ${prev.util-linux}/bin/setpriv $out/bin/codex \
                  --set SSL_CERT_FILE "${prev.cacert}/etc/ssl/certs/ca-bundle.crt" \
                  --set NIX_SSL_CERT_FILE "${prev.cacert}/etc/ssl/certs/ca-bundle.crt" \
                  --add-flags "--inh-caps=-all" \
                  --add-flags "--ambient-caps=-all" \
                  --add-flags "$out/bin/.codex-setpriv-target"
              '';
            });
          })
        ];
      };
    in
    {
      homeConfigurations = {
        wonko = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit unstable-pkgs;
            inherit auto-splice;
            inherit sops-nix;
            inherit spotify-midi-control;
          };
          modules = [
            determinate.homeManagerModules.default
            spotify-midi-control.homeManagerModules.default
            ./home.nix
            ./zsh.nix
            ./atuin.nix
            ./audio.nix
            ./development.nix
            ./greptile.nix
            ./kubernetes.nix
            ./software.nix
            ./desktop.nix
            ./nix_tools.nix
            ./zenith.nix
            ./games.nix
            # ./circleci-runner.nix
            ./gamedev.nix
          ];
        };
      };
    };
}
