{ pkgs, pipewire-src }:

let
  ffado = pkgs.ffado.overrideAttrs (_old: rec {
    version = "2.5.0";
    src = pkgs.fetchurl {
      url = "https://www.ffado.org/files/libffado-${version}.tgz";
      hash = "sha256-JcEtk9U5iPPK+ZZSNu03nxZ6vePqTMYzsTTuYlTYfKE=";
    };
  });
in
(pkgs.pipewire.override { inherit ffado; }).overrideAttrs (old: {
  version = "1.7.0-unstable-2026-08-06";
  src = pipewire-src;
  patches = builtins.filter (patch: !pkgs.lib.hasSuffix "musl.patch" (toString patch)) (
    old.patches or [ ]
  );
  mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dbluez5-codec-lhdc=disabled" ];
})
