{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell {
  buildInputs = [
  ];

  shellHook = ''
    # Follow Ghostty's Darwin approach: use system Xcode tools,
    # not Nix-provided SDK/Xcode wrappers.
    unset SDKROOT
    unset DEVELOPER_DIR
    unset CC LD
  '';
}
