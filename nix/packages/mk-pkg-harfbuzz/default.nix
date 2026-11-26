{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  name = "harfbuzz";
  packageLock = (import ../../../packages.lock.nix).${name};
  inherit (packageLock) version;

  callPackage = pkgs.lib.callPackageWith { inherit pkgs os arch; };
  nativeFile = callPackage ../../utils/native-file/default.nix { };
  crossFile = callPackage ../../utils/cross-file/default.nix { };

  nativeBuildInputs = [
    pkgs.meson
    pkgs.ninja
    pkgs.pkg-config
    pkgs.python3
  ];

  pname = import ../../utils/name/package.nix name;
  src = callPackage ../../utils/fetch-tarball/default.nix {
    name = "${pname}-source-${version}";
    inherit (packageLock) url sha256;
  };
  patchedSource = callPackage ../../utils/patch-shebangs/default.nix {
    name = "${pname}-patched-source-${version}";
    inherit src;
    inherit nativeBuildInputs;
  };
  # Apple clang 21 declares __sincosf, not sincosf. HarfBuzz 8.1.1 still calls
  # sincosf when its configure check sets HAVE_SINCOSF.
  srcNoSincos = pkgs.runCommand "${pname}-no-sincos-${version}" { } ''
    cp -r ${patchedSource} $out
    chmod -R u+w $out
    sed -i.bak 's/#ifdef HAVE_SINCOSF/#if 0/' $out/src/OT/glyf/VarCompositeGlyph.hh
    rm -f $out/src/OT/glyf/VarCompositeGlyph.hh.bak
  '';
in

pkgs.stdenvNoCC.mkDerivation {
  name = "${pname}-${os}-${arch}-${version}";
  pname = pname;
  inherit version;
  src = srcNoSincos;
  dontUnpack = true;
  enableParallelBuilding = true;
  inherit nativeBuildInputs;
  configurePhase = ''
    meson setup build $src \
      --native-file ${nativeFile} \
      --cross-file ${crossFile} \
      --prefix=$out \
      -Dglib=disabled \
      -Dgobject=disabled \
      -Dcairo=disabled \
      -Dchafa=disabled \
      -Dicu=disabled \
      -Dgraphite=disabled \
      -Dgraphite2=disabled \
      -Dfreetype=disabled \
      -Dgdi=disabled \
      -Ddirectwrite=disabled \
      -Dcoretext=enabled \
      -Dtests=disabled \
      -Dintrospection=disabled \
      -Ddocs=disabled \
      -Dbenchmark=disabled \
      -Dicu_builtin=false \
      -Dexperimental_api=false \
      -Dragel_subproject=false \
      -Dfuzzer_ldflags=
  '';
  buildPhase = ''
    meson compile -vC build
  '';
  installPhase = ''
    meson install -C build
  '';
}
