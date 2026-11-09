{ lib, rustPlatform, buildNpmPackage, importNpmLock, pkg-config, pipewire, lilv, src }:

let
  web = buildNpmPackage {
    pname = "pipeweaver-web";
    version = "unstable-${src.shortRev}";
    inherit src;
    sourceRoot = "source/web";
    npmDeps = importNpmLock { npmRoot = "${src}/web"; };
    npmConfigHook = importNpmLock.npmConfigHook;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r dist/. "$out/"
      runHook postInstall
    '';
  };
in
rustPlatform.buildRustPackage {
  pname = "pipeweaver";
  version = "unstable-${src.shortRev}";
  inherit src;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    allowBuiltinFetchGit = true;
  };

  nativeBuildInputs = [ pkg-config rustPlatform.bindgenHook ];
  buildInputs = [ pipewire lilv ];
  cargoBuildFlags = [ "-p" "pipeweaver-daemon" "-p" "pipeweaver-client" ];
  cargoTestFlags = [ "-p" "pipeweaver-daemon" "-p" "pipeweaver-client" ];

  postPatch = ''
    # Build the UI separately so Cargo never runs npm or accesses the network.
    cat > daemon/build.rs <<'EOF'
    fn main() {
        println!("cargo:rustc-env=GIT_HASH=${src.shortRev}");
    }
    EOF
    mkdir -p daemon/web-content
    cp -r ${web}/. daemon/web-content/
  '';

  meta = {
    description = "PipeWire audio routing and mixing with a web interface";
    homepage = "https://github.com/pipeweaver/pipeweaver";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "pipeweaver-daemon";
  };
}
