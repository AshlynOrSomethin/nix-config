{ lib, ... }:
{
  xdg.mimeApps = {
    enable = true;
    defaultApplications = lib.genAttrs [
      "application/zip"
      "application/x-zip"
      "application/x-zip-compressed"
      "application/x-7z-compressed"
      "application/x-7z-compressed-tar"
      "application/vnd.rar"
      "application/x-rar"
      "application/x-rar-compressed"
      "application/x-tar"
      "application/x-gtar"
      "application/gzip"
      "application/x-gzip"
      "application/x-compressed-tar"
      "application/bzip2"
      "application/x-bzip"
      "application/x-bzip2"
      "application/x-bzip-compressed-tar"
      "application/x-bzip2-compressed-tar"
      "application/x-xz"
      "application/x-xz-compressed-tar"
      "application/x-lzma"
      "application/x-lzma-compressed-tar"
      "application/x-lzip"
      "application/x-lzip-compressed-tar"
      "application/x-lz4"
      "application/x-lz4-compressed-tar"
      "application/x-lzop"
      "application/x-tzo"
      "application/zstd"
      "application/x-zstd-compressed-tar"
      "application/x-compress"
      "application/x-tarz"
      "application/x-cpio"
      "application/x-ar"
      "application/x-archive"
      "application/x-arj"
      "application/x-ace"
      "application/x-lha"
      "application/x-lhz"
      "application/vnd.ms-cab-compressed"
      "application/x-cabinet"
      "application/java-archive"
      "application/x-java-archive"
      "application/x-cd-image"
    ] (_: "peazip.desktop") // {
      "inode/directory" = "dev.duxlabs.files.desktop";
      "x-scheme-handler/file" = "dev.duxlabs.files.desktop";
      "x-scheme-handler/sftp" = "dev.duxlabs.files.desktop";
      "x-scheme-handler/trash" = "dev.duxlabs.files.desktop";
      "application/xhtml+xml" = "firefox.desktop";
      "text/html" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/discord" = "vesktop.desktop";
      "x-scheme-handler/bitwarden" = "bitwarden.desktop";
      "x-scheme-handler/lunarclient" = "lunarclient.desktop";
    };
    associations.added = {
      "text/x-log" = "code.desktop";
    };
  };

  # Overwrite the pre-existing unmanaged mimeapps.list.
  xdg.configFile."mimeapps.list".force = true;
}
