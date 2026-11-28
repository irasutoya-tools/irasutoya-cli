---
layout: page
title: CLI architecture
---

# CLI architecture

Start with [the executable](../exe/irasutoya), which loads the CLI and starts
the Thor runner. [`Runner`](../lib/irasutoya/cli.rb) defines the commands,
their arguments and options, and the output for search and random results.

- **Search and random** use the `irasutoya` gem to find and parse illustration
  pages. [`Illustration`](../lib/irasutoya/cli/illustration.rb) adapts the gem's
  random-page fetch to use the same [`PageUrl`](../lib/irasutoya/cli/page_url.rb)
  validation as search results and downloads. Page URL validation and image
  transfers use [`HttpsUrl`](../lib/irasutoya/cli/https_url.rb) to normalize
  legacy HTTP URLs.
- **Categories and browse** work the same way. [`Category`](../lib/irasutoya/cli/category.rb)
  wraps the gem's category scraper so it fetches pages through the same secure
  fetcher as search and random, and
  [`CategoryCommand`](../lib/irasutoya/cli/category_command.rb) lists category
  titles and resolves a category title to its illustration links for `browse`,
  which the runner displays through the same pipeline as `search`.
- **Output and previews** are mixed into the runner from
  [`ResultPresenter`](../lib/irasutoya/cli/result_presenter.rb). JSON Lines
  output takes an early return, while text output can include previews when
  standard output is a terminal. [`Preview`](../lib/irasutoya/cli/preview.rb)
  selects the rendering path and uses
  [`PreviewPNG`](../lib/irasutoya/cli/preview_png.rb) to decode PNG data for
  ANSI rendering.
- **Downloading** starts in
  [`DownloadCommand`](../lib/irasutoya/cli/download_command.rb), which
  validates the `--output`/`--input` options and then either downloads one
  `PAGE_URL` or iterates a URL list from
  [`DownloadList`](../lib/irasutoya/cli/download_list.rb). Each page goes to
  [`Download`](../lib/irasutoya/cli/download.rb), which validates the
  illustration page URL, fetches its image URLs, and saves each image
  through a temporary file and a hard link that avoids overwriting an
  existing file.
- **Image transfers** for both previews and downloads go through
  [`ImageTransfer`](../lib/irasutoya/cli/image_transfer.rb), which streams
  HTTPS responses and manages connections and redirects.

For examples of how each path is exercised, see the
[command specs](../spec/irasutoya/cli_spec.rb),
[JSON Lines specs](../spec/irasutoya/jsonl_spec.rb),
[preview specs](../spec/irasutoya/ansi_preview_spec.rb), and
[download specs](../spec/irasutoya/download_spec.rb).
