# Thin layer that fixes IeumOffice's UI language without rebuilding the app:
# re-exports the package and wraps bin/ieumoffice and bin/ieumoffice-cli with
# GENOFFICE_LANG (upstream's "force the UI language" variable, read by every
# module). --set-default keeps GENOFFICE_LANG=... at run time in charge.
{
  lib,
  symlinkJoin,
  makeShellWrapper,
}:

uiLanguage: unwrapped:

if uiLanguage == null then
  unwrapped
else
  symlinkJoin {
    name = "${unwrapped.name}-${uiLanguage}";
    paths = [ unwrapped ];
    nativeBuildInputs = [ makeShellWrapper ];

    postBuild = ''
      for prog in ieumoffice ieumoffice-cli; do
        rm $out/bin/$prog
        makeShellWrapper ${unwrapped}/bin/$prog $out/bin/$prog \
          --set-default GENOFFICE_LANG ${lib.escapeShellArg uiLanguage}
      done

      # the desktop entry must start this wrapper, not the unwrapped app
      desktop=share/applications/ieumoffice.desktop
      rm $out/$desktop
      substitute ${unwrapped}/$desktop $out/$desktop \
        --replace-fail ${unwrapped}/bin/ieumoffice $out/bin/ieumoffice
    '';

    passthru = (unwrapped.passthru or { }) // {
      inherit unwrapped uiLanguage;
    };
    inherit (unwrapped) meta;
  }
