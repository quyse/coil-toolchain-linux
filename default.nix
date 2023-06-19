{ pkgs ? import <nixpkgs> {}
, lib ? pkgs.lib
, toolchain
, fixedsFile ? ./fixeds.json
, fixeds ? lib.importJSON fixedsFile
}:

rec {
  # hacky wrapper around pkgs.vmTools.debClosureGenerator allowing multiple url prefixes
  # rewrites Packages* files, adds urls directly into Filename field
  generateDebClosure =
  { name
  , packagesLists
  , arch
  , packages
  }:
  pkgs.runCommand "${name}.closure.nix" {} ''
    sed -e 's#url = "URL/#url = "#' < ${pkgs.vmTools.debClosureGenerator {
      inherit name;
      packagesLists = map (
        { urlPrefix
        , suite
        , component
        , format
        }:
        pkgs.runCommand "${suite}_${component}_${arch}_PackagesUrlExpanded.xz" {} ''
          ${{
            xz = "${pkgs.xz}/bin/xz -d";
            bz2 = "${pkgs.bzip2}/bin/bunzip2";
            gz = "${pkgs.gzip}/bin/gunzip";
          }."${format}"} < ${pkgs.fetchurl {
            inherit (fixeds.fetchurl."${urlPrefix}dists/${suite}/${component}/binary-${arch}/Packages.${format}") url name sha256;
          }} | sed -e 's#^Filename: #Filename: '${lib.escapeShellArg urlPrefix}'#' | ${pkgs.xz}/bin/xz -0 > $out
        ''
      ) packagesLists;
      urlPrefix = "URL";
      packages = pkgs.vmTools.commonDebPackages ++ packages;
    }} > $out
  '';

  makeDebDistImage = { name, packagesLists, arch, packages }: let
    closure = generateDebClosure {
      inherit name packagesLists arch packages;
    };
  in pkgs.vmTools.fillDiskWithDebs {
    inherit name;
    fullName = name;
    debs = import closure {
      inherit (pkgs) fetchurl;
    };
    # reference closure in derivation so it's not GC'ed
    postInstall = ''
      echo ${closure}
    '';
  };

  diskImagesFuns = let
    ubuntuDistroFun = { name, suite, arch }: packages: makeDebDistImage {
      inherit name;
      packagesLists = [
        {
          urlPrefix = "http://archive.ubuntu.com/ubuntu/";
          inherit suite;
          component = "main";
          format = "xz";
        }
        {
          urlPrefix = "http://archive.ubuntu.com/ubuntu/";
          inherit suite;
          component = "universe";
          format = "xz";
        }
        {
          urlPrefix = "http://archive.ubuntu.com/ubuntu/";
          suite = "${suite}-updates";
          component = "main";
          format = "xz";
        }
        {
          urlPrefix = "http://archive.ubuntu.com/ubuntu/";
          suite = "${suite}-updates";
          component = "universe";
          format = "xz";
        }
        {
          urlPrefix = "https://apt.kitware.com/ubuntu/";
          inherit suite;
          component = "main";
          format = "gz";
        }
        {
          urlPrefix = "https://apt.llvm.org/${suite}/";
          suite = "llvm-toolchain-${suite}-${llvmVersion}";
          component = "main";
          format = "gz";
        }
      ];
      inherit arch packages;
    };
  in lib.listToAttrs (map (
    { version, suite, arch }: let
      name = "ubuntu_${version}_${arch}";
    in lib.nameValuePair name (ubuntuDistroFun {
      inherit name suite arch;
    })
  ) [
    {
      version = "2204";
      suite = "jammy";
      arch = "amd64";
    }
  ]);

  llvmVersion = "16";

  defaultDiskImages = lib.mapAttrs (name: distroFun: distroFun [
    "clang-${llvmVersion}"
  ]) diskImagesFuns;

  touch = defaultDiskImages // {
    autoUpdateScript = toolchain.autoUpdateFixedsScript fixedsFile;
  };
}
