# Getting started

## Requirements

Ruby 3.3 or newer.

## Install

```sh
$ gem install irasutoya-cli
```

## First walkthrough

### Show a random illustration

```sh
$ irasutoya random
```

This prints the page URL, title, description, and image URL for one randomly
selected illustration. When standard output is a terminal, the CLI also
attempts to render an inline preview of each image.

### Search for a topic

```sh
$ irasutoya search '猫'
```

`search` takes one query argument (quote it if it contains spaces) and
fetches up to three matching result pages, each of which can contain
multiple images. It prints the same fields as `random` for every image it
finds.

### Download the images from a page

The installed gem (version 1.0.1) does not include the `download` command
or the `--jsonl` option used below. To use them, run the CLI from a checkout
instead:

```sh
$ git clone https://github.com/irasutoya-tools/irasutoya-cli.git
$ cd irasutoya-cli
$ bundle install
```

Copy the `Page URL` printed by `random` or `search` and pass it to
`download`:

```sh
$ bundle exec exe/irasutoya download 'PAGE_URL' --output ./images
```

The command creates `./images` if needed and saves every image on the page
there.

### Chain search and download

In a checkout, add `--jsonl` to `search` or `random` to print one JSON
object per illustration page instead of text, then feed a `page_url` into
`download`:

```sh
$ page_url=$(bundle exec exe/irasutoya search '猫' --jsonl | jq -ser '.[0].page_url // empty')
$ bundle exec exe/irasutoya download "$page_url" --output ./images
```

## Next steps

- [CLI reference](usage.md) covers every command's arguments, options, and
  output in full, including `--jsonl` and `--input`.
- [FAQ and troubleshooting](troubleshooting.md) covers missing commands,
  previews, and download errors.
- [Architecture](architecture.md) is where contributors should start
  reading the code.
