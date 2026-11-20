# CLI reference

## Search and browse illustrations

```sh
irasutoya search '白い猫'
irasutoya random
```

`search QUERY` takes one query argument. Quote a query that contains spaces.
The command attempts to fetch up to three result pages, each of which can
contain multiple images. If fetching a result page returns an HTTP error,
the command warns and skips that page. `random` takes no arguments and
shows one randomly selected illustration page.

Both commands print the page URL, title, description, and an image URL for
each image. When standard output is a terminal, the CLI also attempts to
render inline previews. Each preview has a 10 MiB limit. Redirect standard
output to a file or pipe it into another command to get the metadata
without fetching previews.

```sh
irasutoya search '白い猫' > results.txt
```

See [Installation](../README.md#installation) for terminal and renderer
requirements.

## Download images

```sh
irasutoya download 'PAGE_URL' --output ./images
```

Replace `PAGE_URL` with the value from the `Page URL` field in a search or
random result. The command accepts HTTP or HTTPS illustration page URLs on
`irasutoya.com` or `www.irasutoya.com` with paths ending in `.html`.

`--output DIR` is required. The command creates the directory if needed,
saves all images on the page, and prints a `Saved:` line for each file.
When a filename is already taken, the command adds a suffix such as
`-1` before the extension. If the page contains no images, the command
reports an error.

## Get help

Use `irasutoya help` to list commands or `irasutoya help COMMAND` to show
arguments and options for a specific command. Use `irasutoya tree` to
display the command tree.
