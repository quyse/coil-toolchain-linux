{ pkgs ? import <nixpkgs> {}
, lib ? pkgs.lib
, toolchain
, fixedsFile ? ./fixeds.json
, fixeds ? lib.importJSON fixedsFile
}:

rec {
  debDistros = {
    ubuntu2204x86_64 = rec {
      name = "ubuntu-22.04-jammy-amd64";
      fullName = "Ubuntu 22.04 Jammy (amd64)";
      packagesLists = [
        (pkgs.fetchurl {
          inherit (fixeds.fetchurl."${urlPrefix}/dists/jammy/main/binary-amd64/Packages.xz") url name sha256;
        })
        (pkgs.fetchurl {
          inherit (fixeds.fetchurl."${urlPrefix}/dists/jammy-updates/main/binary-amd64/Packages.xz") url name sha256;
        })
        (pkgs.fetchurl {
          inherit (fixeds.fetchurl."${urlPrefix}/dists/jammy/universe/binary-amd64/Packages.xz") url name sha256;
        })
        (pkgs.fetchurl {
          inherit (fixeds.fetchurl."${urlPrefix}/dists/jammy-updates/universe/binary-amd64/Packages.xz") url name sha256;
        })
      ];
      urlPrefix = "http://archive.ubuntu.com/ubuntu";
      packages = pkgs.vmTools.commonDebPackages ++ [
        "diffutils"
        "libc-bin"
      ];
    };
  };

  diskImagesFuns = lib.mapAttrs (name: distro: extraPackages: pkgs.vmTools.makeImageFromDebDist (distro // {
    inherit extraPackages;
  })) debDistros;

  defaultDiskImages = lib.mapAttrs (name: f: f []) diskImagesFuns;

  touch = defaultDiskImages // {
    autoUpdateScript = toolchain.autoUpdateFixedsScript fixedsFile;
  };
}
