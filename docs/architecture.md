---
layout: page
title: CLI architecture
---

# CLI architecture

Start with [the executable](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/exe/irasutoya), which loads the CLI and starts
the Thor runner. [`Runner`](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/lib/irasutoya/cli.rb) defines the commands,
their arguments and options, and the output for search and random results.

- **Search and random** use the `irasutoya` gem to find and parse illustration
  pages. [`Illustration`](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/lib/irasutoya/cli/illustration.rb) adapts the gem's
  random-page fetch to use the same [`PageUrl`](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/lib/irasutoya/cli/page_url.rb)
  validation as search results and downloads. Page URL validation and image
  transfers use [`HttpsUrl`](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/lib/irasutoya/cli/https_url.rb) to normalize
  legacy HTTP URLs.
- **Output and previews** start in the runner. JSON Lines output takes an early
  return, while text output can include previews when standard output is a
  terminal. [`Preview`](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/lib/irasutoya/cli/preview.rb) selects the rendering
  path and uses [`PreviewPNG`](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/lib/irasutoya/cli/preview_png.rb) to decode
  PNG data for ANSI rendering.
- **Downloading** starts in
  [`DownloadCommand`](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/lib/irasutoya/cli/download_command.rb), which
  validates the `--output`/`--input` options and then either downloads one
  `PAGE_URL` or iterates a URL list from
  [`DownloadList`](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/lib/irasutoya/cli/download_list.rb). Each page goes to
  [`Download`](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/lib/irasutoya/cli/download.rb), which validates the
  illustration page URL, fetches its image URLs, and saves each image
  through a temporary file and a hard link that avoids overwriting an
  existing file.
- **Image transfers** for both previews and downloads go through
  [`ImageTransfer`](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/lib/irasutoya/cli/image_transfer.rb), which streams
  HTTPS responses and manages connections and redirects.

For examples of how each path is exercised, see the
[command specs](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/spec/irasutoya/cli_spec.rb),
[JSON Lines specs](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/spec/irasutoya/jsonl_spec.rb),
[preview specs](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/spec/irasutoya/ansi_preview_spec.rb), and
[download specs](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/spec/irasutoya/download_spec.rb).
