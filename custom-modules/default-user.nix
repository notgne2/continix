{ ... }:

{
  users = {
    users = {
      continix = {
        group = "continix";
        home = "/data";
        createHome = true;
        uid = 1000;
      };
    };

    groups = { continix = { gid = 1000; }; };
  };
}
