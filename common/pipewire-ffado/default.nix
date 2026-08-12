{ pkgs }:

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
  patches = (old.patches or [ ]) ++ [ ./ffado-driver.patch ];
})
