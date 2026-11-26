# CLI reference

These examples use the current checkout. Follow the
[checkout setup instructions](../README.md#download-images-from-a-checkout)
before running them, or see [Getting started](getting-started.md) for a
guided first walkthrough.

## Search and browse illustrations

```sh
bundle exec exe/irasutoya search '白い猫'
bundle exec exe/irasutoya random
```

`search {query}` takes one query argument. Quote a query that contains spaces.
The command attempts to fetch up to three result pages, each of which can
contain multiple images. Search and random use the same page URL rules as
`download`: URLs must use HTTP or HTTPS, have the host `irasutoya.com` or
`www.irasutoya.com`, and have a path ending in `.html`. Search warns and skips
a result if its URL fails validation or the page fetch fails. `random` takes
no arguments and shows one randomly selected illustration page. It reports an
error if the selected URL fails validation.

Both commands print the page URL, title, description, and an image URL for
each image. When standard output is a terminal, the CLI also attempts to
render inline previews. The CLI fetches illustration pages and previews over
HTTPS, upgrading legacy HTTP URLs before fetching. Each preview has a 10 MiB limit. Redirect standard
output to a file or pipe it into another command to get the metadata
without fetching previews.

```sh
bundle exec exe/irasutoya search '白い猫' > results.txt
```

Image previews use [iTerm2](https://iterm2.com/index.html) when detected, or Sixel when the [libsixel](https://github.com/saitoha/libsixel) `img2sixel` command is on `PATH`. Otherwise, previews fall back to ANSI rendering and display in terminals that support 24-bit (true-color) ANSI colors. The ANSI fallback renders PNGs directly and requires ImageMagick (`magick` or `convert` on `PATH`) to convert other supported image formats to PNG.

### JSON Lines output

Use `--jsonl` with `search` or `random` to write one JSON object per
illustration page to standard output. This mode skips previews even in a
terminal. Each object has four fields:

| Field | Type | Contents |
| --- | --- | --- |
| `page_url` | string | Illustration page URL accepted by `download` |
| `title` | string | Illustration title |
| `description` | string | Illustration description |
| `image_urls` | array of strings | All image URLs on the page |

Search writes each result as it becomes available. An empty search writes
zero lines. If a result page returns an HTTP error or times out, search
warns on standard error and continues with its usual exit status.

```sh
bundle exec exe/irasutoya random --jsonl

page_url=$(bundle exec exe/irasutoya search '白い猫' --jsonl | jq -ser '.[0].page_url // empty') &&
  bundle exec exe/irasutoya download "$page_url" --output ./images
```

## Download images

```sh
bundle exec exe/irasutoya download 'PAGE_URL' --output ./images
```

Replace `PAGE_URL` with the value from the `Page URL` field in a search or
random result. The command accepts HTTP or HTTPS illustration page URLs on
`irasutoya.com` or `www.irasutoya.com` with paths ending in `.html`. The CLI upgrades legacy HTTP page and image
URLs to HTTPS before downloading and rejects redirects to HTTP.

`--output DIR` is required. The command creates the directory if needed,
saves images on the page in order, and prints a `Saved:` line for each file.
When a filename is already taken, the command adds a suffix such as
`-1` before the extension. If the page contains no images, the command
reports an error.

The command recognizes PNG, JPEG, GIF, and WebP images by their file
signature, independent of the URL's extension, and saves each file with the
extension that matches its detected format (for example, a PNG served from a
URL ending in `.jpg` is saved with a `.png` extension). If an image on the
page is in another format, such as SVG, the command reports an error and
stops downloading from that page. Images already saved from earlier in the
page are kept.

### Save illustration metadata

Add `--metadata` to also save a JSON file with the page URL, title,
description, and the filenames of the images saved from that page, reusing
the illustration already fetched to locate the images (no extra request).
The file is named after the page (for example `cat.json` for a page saved
as `cat.png`) and gets a numeric suffix such as `-1` if that name is
already taken, the same way image filenames do. The file is only written
after every image on the page saves successfully.

```sh
bundle exec exe/irasutoya download 'PAGE_URL' --output ./images --metadata
```

### Download from a URL list

Use `--input FILE` in place of `PAGE_URL` to download a saved list with
one illustration page URL per line. Use `--input -` to read from standard
input.

```sh
bundle exec exe/irasutoya download --input pages.txt --output ./images

bundle exec exe/irasutoya search '白い猫' --jsonl |
  jq -r '.page_url' |
  bundle exec exe/irasutoya download --input - --output ./images
```

The command trims surrounding whitespace, skips blank lines, and processes
URLs in order, including repeated entries. If a page fails, the command
reports the line on standard error and continues with the remaining pages.
It keeps saved images and exits with status 1 if any page failed.

## Get help

Use `bundle exec exe/irasutoya help` to list commands or
`bundle exec exe/irasutoya help COMMAND` to show arguments and options for a
specific command. Use `bundle exec exe/irasutoya tree` to display the command tree.
