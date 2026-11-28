---
layout: page
title: FAQ and troubleshooting
---

# FAQ and troubleshooting

## Why does the installed gem reject `download` or `--jsonl`?

Version 1.0.1 does not include `download` or the `--jsonl` option for
`search` and `random`. Follow the
[checkout setup instructions](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/README.md#download-images-from-a-checkout)
and run `bundle exec exe/irasutoya help` from the repository directory to see
the checkout's commands. The [CLI reference](usage.md) uses that executable.

## Why do I see metadata without an inline preview?

In a checkout, `search` and `random` skip previews when standard output is
piped or redirected, or when `--jsonl` is set. Run the command directly in a
terminal to request previews.

If the ANSI fallback cannot preview a non-PNG image, make sure ImageMagick's
`magick` or `convert` executable is on your `PATH`. Use a terminal with
24-bit color support for the ANSI preview, or see the
[CLI reference](usage.md#search-and-browse-illustrations) for iTerm2 and Sixel
support.

## Why does a download fail even when the output directory is writable?

The checkout's `download` command uses hard links to save images. A writable
FAT32 directory still cannot support this operation. Set `--output` to a
writable directory on a filesystem that supports hard links.
