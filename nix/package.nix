{
  lib,
  fetchFromGitHub,
  apple-sdk_26,
  darwinMinVersionHook,
  swift,
  swiftPackages,
  swiftpm,
}:

let
  tomlPin = lib.findFirst (pin: pin.identity == "tomldecoder") null
    (lib.importJSON ../Package.resolved).pins;
  tomlDecoder = fetchFromGitHub {
    owner = "dduan";
    repo = "TOMLDecoder";
    rev = tomlPin.state.revision;
    hash = "sha256-sazDC5JH+7v0S/ER0TeI5fAPpMj5tbyxYKiNxvsP5aE=";
  };
in
swiftPackages.stdenv.mkDerivation {
  pname = "mactilebar";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Package.swift
      ../Package.resolved
      ../config.example.toml
      ../Sources
      ../Tests
      ../scripts/Info.plist
      ../scripts/build-app.sh
    ];
  };

  nativeBuildInputs = [ swift swiftpm ];
  buildInputs = [
    apple-sdk_26
    (darwinMinVersionHook "26.0")
  ];

  postPatch = ''
    # Give SwiftPM the pinned source without another network fetch in the build.
    ln -s ${tomlDecoder} TOMLDecoder
    substituteInPlace Package.swift \
      --replace-fail '.package(url: "${tomlPin.location}", from: "${tomlPin.state.version}")' \
                     '.package(path: "TOMLDecoder")'
    substituteInPlace scripts/build-app.sh \
      --replace-fail '.build/checkouts/TOMLDecoder/LICENSE.md' 'TOMLDecoder/LICENSE.md' \
      --replace-fail 'codesign --' '/usr/bin/codesign --'
  '';

  buildPhase = ''
    runHook preBuild
    bash scripts/build-app.sh
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    dist/MacTileBar.app/Contents/MacOS/MacTileBar \
      --config "$PWD/config.example.toml" --check-config
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R dist/MacTileBar.app "$out/Applications/"
    runHook postInstall
  '';

  postFixup = ''
    bundle="$out/Applications/MacTileBar.app"
    /usr/bin/codesign --force --sign - "$bundle"
    /usr/bin/codesign --verify --strict "$bundle"
  '';

  meta = {
    description = "macOS window control bar for yabai";
    homepage = "https://github.com/Jacky-Lzx/MacTileBar";
    platforms = [ "aarch64-darwin" ];
  };
}
