# Irasutoya::Cli

[![CI](https://github.com/irasutoya-tools/irasutoya-cli/actions/workflows/test.yml/badge.svg?branch=master)](https://github.com/irasutoya-tools/irasutoya-cli/actions/workflows/test.yml)
[![Gem Version](https://badge.fury.io/rb/irasutoya-cli.svg)](https://badge.fury.io/rb/irasutoya-cli)
[![Code Climate](https://codeclimate.com/github/irasutoya-tools/irasutoya-cli/badges/gpa.svg)](https://codeclimate.com/github/irasutoya-tools/irasutoya-cli)
[![codecov](https://codecov.io/gh/irasutoya-tools/irasutoya-cli/branch/master/graph/badge.svg)](https://codecov.io/gh/irasutoya-tools/irasutoya-cli)
[![Libraries.io dependency status for GitHub repo](https://img.shields.io/librariesio/github/irasutoya-tools/irasutoya-cli.svg)](https://libraries.io/github/irasutoya-tools/irasutoya-cli)
![](http://ruby-gem-downloads-badge.herokuapp.com/irasutoya-cli?type=total)
![GitHub](https://img.shields.io/github/license/irasutoya-tools/irasutoya-cli.svg)

![](./images/example.png)

## Installation

Ruby 3.3 or newer is required.

```sh
$ gem install irasutoya-cli
```

Image previews use [iTerm2](https://iterm2.com/index.html) when detected, or Sixel when the [libsixel](https://github.com/saitoha/libsixel) `img2sixel` command is on `PATH`. Otherwise, previews fall back to ANSI rendering and display in terminals that support 24-bit (true-color) ANSI colors. The ANSI fallback renders PNGs directly and requires ImageMagick (`magick` or `convert` on `PATH`) to convert other supported image formats to PNG.

## Quick Start

After installing the gem, run a search with a single query argument:

```sh
$ irasutoya search '猫'
```

For each result, the CLI prints the illustration's page URL, title, description, and image URLs. Copy the `Page URL` from `search` or `random` and pass it to `download` with a destination directory:

```sh
$ irasutoya download 'PAGE_URL' --output ./images
```

The command creates the destination directory if needed, saves every image on the page, and prints each saved path. If a filename is already taken, the command adds a numeric suffix before the extension. Downloads work in terminals without inline preview support.

## Usage

```sh
$ irasutoya
Commands:
  irasutoya download PAGE_URL --output DIR  # Saves all images from an illustration page
  irasutoya help [COMMAND]  # Describe available commands or one specific command
  irasutoya random          # Gives you random irasutoya image
  irasutoya search {query}  # Shows images from up to three result pages. Each page can contain multiple images.
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/irasutoya-tools/irasutoya-cli. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Irasutoya::Cli project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/unhappychoice/irasutoya-cli/blob/master/CODE_OF_CONDUCT.md).

## Author

[@unhappychoice](https://unhappychoice.com)
