{ ... }:

{
  users = {
    users = {
      continix = {
        group = "continix";
        home = "/data";
        uid = 369;
      };
    };

    groups = { continix = { gid = 369; }; };
  };
}
