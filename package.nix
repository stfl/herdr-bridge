{
  lib,
  stdenvNoCC,
  makeWrapper,
  bats,
  shellcheck,
  jq,
  gawk,
  gnugrep,
  coreutils,
  openssh,
  util-linux,
  python3,
}:
stdenvNoCC.mkDerivation {
  pname = "herdr-bridge";
  version = "0.0.1";
  src = ./.;

  # jq, gawk and util-linux (flock) are needed by the suite as well as at
  # runtime; python3 backs the stub ssh's socket creation.
  nativeBuildInputs = [makeWrapper shellcheck bats python3 jq gawk util-linux];

  # There is nothing to compile, and the default buildPhase would otherwise
  # run the Makefile's `all` target — lint and tests, before shebangs are
  # patched and outside the check phase.
  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    # The suite executes the script and its stub binaries directly, and the
    # sandbox has no /usr/bin/env to resolve their shebangs.
    patchShebangs bin test
    shellcheck --shell=bash bin/herdr-bridge \
      test/helpers/stub-herdr test/helpers/stub-ssh completions/herdr-bridge.bash
    bats test
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm0755 bin/herdr-bridge "$out/bin/herdr-bridge"
    install -Dm0644 completions/herdr-bridge.zsh \
      "$out/share/zsh/site-functions/_herdr-bridge"
    install -Dm0644 completions/herdr-bridge.bash \
      "$out/share/bash-completion/completions/herdr-bridge"

    # herdr itself is deliberately left to PATH: the bridge has to speak to
    # whichever herdr owns the session it runs inside, not to a copy pinned
    # here. Everything else it shells out to is pinned.
    wrapProgram "$out/bin/herdr-bridge" \
      --prefix PATH : ${lib.makeBinPath [jq gawk gnugrep coreutils openssh util-linux]}
    runHook postInstall
  '';

  meta = {
    description = "Show a remote herdr agent inside a local herdr pane";
    longDescription = ''
      herdr sessions are independent servers and its sidebar renders one of
      them, so agents on another machine stay outside the local agent panel.
      herdr-bridge forwards a remote session's sockets over SSH, streams one
      remote agent's terminal into the local pane it is run from, and
      republishes that agent's lifecycle state onto the pane, so it appears in
      the local sidebar alongside local agents.
    '';
    homepage = "https://github.com/stfl/herdr-bridge";
    license = lib.licenses.mit;
    mainProgram = "herdr-bridge";
    platforms = lib.platforms.unix;
  };
}
