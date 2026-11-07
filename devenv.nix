{pkgs, ...}: {
  languages.dart.enable = true;
  packages = with pkgs; [
    flutter
  ];
}
