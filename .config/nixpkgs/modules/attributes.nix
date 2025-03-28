{ lib, ... }:

with lib;

{
  options.attributes = {
    machine.name = mkOption {
      description = "Name of configuration under <config root>/machines";
      type = types.str;
    };
    mainUser.name = mkOption {
      description = "Main user to be granted various service-related rights to";
      type = types.str;
    };
    mainUser.fullName = mkOption {
      description = "Main user's full name";
      type = types.str;
    };
    mainUser.email = mkOption {
      description = "Main user's email";
      type = types.str;
    };
  };
}
