{ config, lib, pkgs, ... }:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  imports = [
  ];

  wsl.enable = true;
  wsl.defaultUser = "nixos";

  system.stateVersion = "26.05";

  environment.systemPackages = with pkgs; [
  ];

  programs.git = {
    enable = true;
    config = {
      user.name = "Phuc X. Doan";
      user.email = "phucxdoan@gmail.com";
    };
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    configure = {
      customRC = ''
        luafile ~/configs/init.lua
      '';
    };
  };
}
