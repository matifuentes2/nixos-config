{
  fetchurl,
  runCommand,
  imagemagick,
}:

let
  source = fetchurl {
    name = "omarchy-tokyo-night-sunset-lake.png";
    url = "https://raw.githubusercontent.com/basecamp/omarchy/8fcc9d6048af4cb0e3af8512c78049857a3b53dd/themes/tokyo-night/backgrounds/1-sunset-lake.png";
    hash = "sha256-Bt+5/OAp7DWttA6jk5KWd3wrFA0SMrWhaXsVBS1XU2I=";
  };
in
# The original is 7680px wide; V3D on the Pi 4 supports textures up to 4096px.
# Use the same bounded image for the wallpaper and lock screen. Strip metadata
# and timestamps so the generated asset is reproducible and safe to share.
runCommand "tokyo-night-wallpaper.png"
  {
    nativeBuildInputs = [ imagemagick ];
  }
  ''
    magick ${source} -resize '3840x2160>' -strip \
      -define png:exclude-chunks=date,time PNG:"$out"
  ''
