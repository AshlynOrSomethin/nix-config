{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "ashlyn" ];
      MaxAuthTries = 5;
      PerSourcePenalties = "crash:3600s authfail:3600s max:86400s";
    };
  };
}
